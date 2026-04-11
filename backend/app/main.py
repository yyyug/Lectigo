from __future__ import annotations

import asyncio
import hmac
import json
import os
import threading
from contextlib import asynccontextmanager
from datetime import UTC, datetime, timedelta
from pathlib import Path
from typing import Any, Literal
from uuid import uuid4

import jwt
from fastapi import Depends, FastAPI, HTTPException, status
from fastapi.responses import FileResponse
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from pydantic import BaseModel
from yt_dlp import YoutubeDL


def utc_now() -> datetime:
    return datetime.now(UTC)


class Settings(BaseModel):
    host: str = os.getenv("LECTIGO_HOST", "0.0.0.0")
    port: int = int(os.getenv("LECTIGO_PORT", "8000"))
    base_url: str = os.getenv("LECTIGO_BASE_URL", "http://127.0.0.1:8000").rstrip("/")
    jwt_secret: str = os.getenv("LECTIGO_JWT_SECRET", "change-this-secret")
    default_username: str = os.getenv("LECTIGO_DEFAULT_USERNAME", "lectigo")
    default_password: str = os.getenv("LECTIGO_DEFAULT_PASSWORD", "change-this-password")
    retention_hours: int = int(os.getenv("LECTIGO_RETENTION_HOURS", "24"))
    storage_dir: Path = Path(os.getenv("LECTIGO_STORAGE_DIR", "./storage")).resolve()
    ffmpeg_location: str = os.getenv("LECTIGO_FFMPEG_LOCATION", "").strip()


settings = Settings()
security = HTTPBearer(auto_error=False)


class LoginRequest(BaseModel):
    usernameOrEmail: str
    password: str


class LoginResponse(BaseModel):
    accessToken: str
    username: str


class CreateDownloadRequest(BaseModel):
    sourceURL: str


class CreateDownloadResponse(BaseModel):
    jobID: str
    status: str


class JobRecord(BaseModel):
    jobID: str
    owner: str
    sourceURL: str
    status: Literal["queued", "downloading", "processing", "ready", "failed", "expired"]
    title: str | None = None
    progressText: str | None = None
    durationSeconds: float | None = None
    errorMessage: str | None = None
    downloadURL: str | None = None
    expiresAt: datetime | None = None
    fileID: str | None = None
    fileName: str | None = None
    outputPath: str | None = None
    createdAt: datetime
    updatedAt: datetime


class JobStatusResponse(BaseModel):
    jobID: str
    status: Literal["queued", "downloading", "processing", "ready", "failed", "expired"]
    title: str | None = None
    progressText: str | None = None
    durationSeconds: float | None = None
    errorMessage: str | None = None
    downloadURL: str | None = None
    expiresAt: datetime | None = None
    fileID: str | None = None
    fileName: str | None = None


class AppState:
    def __init__(self) -> None:
        self.storage_dir = settings.storage_dir
        self.jobs_file = self.storage_dir / "jobs.json"
        self.downloads_dir = self.storage_dir / "downloads"
        self.queue: asyncio.Queue[str] = asyncio.Queue()
        self.lock = threading.Lock()
        self.jobs: dict[str, JobRecord] = {}
        self.active_job_id: str | None = None
        self.worker_task: asyncio.Task[None] | None = None
        self.cleanup_task: asyncio.Task[None] | None = None
        self._ensure_storage()
        self._load_jobs()

    def _ensure_storage(self) -> None:
        self.storage_dir.mkdir(parents=True, exist_ok=True)
        self.downloads_dir.mkdir(parents=True, exist_ok=True)
        if not self.jobs_file.exists():
            self.jobs_file.write_text("[]", encoding="utf-8")

    def _load_jobs(self) -> None:
        try:
            raw_items = json.loads(self.jobs_file.read_text(encoding="utf-8"))
            for raw_item in raw_items:
                job = JobRecord.model_validate(raw_item)
                if job.status in {"downloading", "processing"}:
                    job.status = "queued"
                    job.progressText = "Queued after server restart"
                self.jobs[job.jobID] = job
        except Exception:
            self.jobs = {}

    def persist_jobs(self) -> None:
        with self.lock:
            serialized = [job.model_dump(mode="json") for job in self.jobs.values()]
            self.jobs_file.write_text(json.dumps(serialized, indent=2), encoding="utf-8")

    def create_job(self, owner: str, source_url: str) -> JobRecord:
        job_id = uuid4().hex
        job = JobRecord(
            jobID=job_id,
            owner=owner,
            sourceURL=source_url,
            status="queued",
            progressText="Queued",
            createdAt=utc_now(),
            updatedAt=utc_now(),
        )
        with self.lock:
            self.jobs[job_id] = job
        self.persist_jobs()
        return job

    def get_job(self, job_id: str) -> JobRecord:
        with self.lock:
            job = self.jobs.get(job_id)
        if job is None:
            raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Download job not found.")
        return job

    def save_job(self, job: JobRecord) -> None:
        job.updatedAt = utc_now()
        with self.lock:
            self.jobs[job.jobID] = job
        self.persist_jobs()

    def queue_pending_jobs(self) -> None:
        for job in sorted(self.jobs.values(), key=lambda current: current.createdAt):
            if job.status == "queued":
                self.queue.put_nowait(job.jobID)

    def enqueue_job(self, job_id: str) -> None:
        self.queue.put_nowait(job_id)

    def cleanup_expired_jobs(self) -> None:
        now = utc_now()
        dirty = False
        with self.lock:
            jobs = list(self.jobs.values())
        for job in jobs:
            if job.expiresAt and job.expiresAt <= now:
                output_path = Path(job.outputPath) if job.outputPath else None
                if output_path and output_path.exists():
                    output_path.unlink(missing_ok=True)
                if output_path and output_path.parent.exists():
                    try:
                        output_path.parent.rmdir()
                    except OSError:
                        pass
                job.status = "expired"
                job.downloadURL = None
                job.fileID = None
                job.progressText = "Expired"
                dirty = True
                self.save_job(job)
        if dirty:
            self.persist_jobs()

    async def start(self) -> None:
        self.queue_pending_jobs()
        self.worker_task = asyncio.create_task(self.worker_loop())
        self.cleanup_task = asyncio.create_task(self.cleanup_loop())

    async def stop(self) -> None:
        for task in (self.worker_task, self.cleanup_task):
            if task is not None:
                task.cancel()
        for task in (self.worker_task, self.cleanup_task):
            if task is not None:
                try:
                    await task
                except asyncio.CancelledError:
                    pass

    async def cleanup_loop(self) -> None:
        while True:
            self.cleanup_expired_jobs()
            await asyncio.sleep(300)

    async def worker_loop(self) -> None:
        while True:
            job_id = await self.queue.get()
            try:
                await asyncio.to_thread(self.process_job, job_id)
            finally:
                self.queue.task_done()

    def process_job(self, job_id: str) -> None:
        try:
            job = self.get_job(job_id)
        except HTTPException:
            return
        if job.status not in {"queued", "failed"}:
            return

        self.active_job_id = job_id
        download_dir = self.downloads_dir / job_id
        download_dir.mkdir(parents=True, exist_ok=True)

        def hook(update: dict[str, Any]) -> None:
            current = self.get_job(job_id)
            status_value = update.get("status")
            if status_value == "downloading":
                current.status = "downloading"
                current.progressText = update.get("_percent_str", "").strip() or "Downloading source media"
                current.title = current.title or update.get("filename")
                self.save_job(current)
            elif status_value == "finished":
                current.status = "processing"
                current.progressText = "Merging and preparing MP4"
                self.save_job(current)

        options: dict[str, Any] = {
            "outtmpl": str(download_dir / "%(title)s-%(id)s.%(ext)s"),
            "format": "bestvideo*+bestaudio/best",
            "noplaylist": True,
            "merge_output_format": "mp4",
            "remuxvideo": "mp4",
            "quiet": True,
            "no_warnings": True,
            "progress_hooks": [hook],
        }
        if settings.ffmpeg_location:
            options["ffmpeg_location"] = settings.ffmpeg_location

        try:
            with YoutubeDL(options) as ydl:
                info = ydl.extract_info(job.sourceURL, download=True)
            current = self.get_job(job_id)
            output_path = self._resolve_output_path(info, download_dir)
            file_name = output_path.name
            current.status = "ready"
            current.title = info.get("title") or current.title or file_name
            current.durationSeconds = float(info["duration"]) if info.get("duration") else None
            current.progressText = "Ready"
            current.fileID = job_id
            current.fileName = file_name
            current.outputPath = str(output_path)
            current.expiresAt = utc_now() + timedelta(hours=settings.retention_hours)
            current.downloadURL = f"{settings.base_url}/files/{job_id}"
            current.errorMessage = None
            self.save_job(current)
        except Exception as error:
            current = self.get_job(job_id)
            current.status = "failed"
            current.errorMessage = str(error)
            current.progressText = "Failed"
            self.save_job(current)
        finally:
            self.active_job_id = None

    def _resolve_output_path(self, info: dict[str, Any], download_dir: Path) -> Path:
        candidates: list[Path] = []
        direct_path = info.get("filepath") or info.get("_filename")
        if direct_path:
            direct = Path(direct_path)
            if direct.exists():
                return direct

        for extension in ("mp4", "m4v", "mov", "mkv", "webm"):
            candidates.extend(download_dir.glob(f"*.{extension}"))
        if not candidates:
            raise RuntimeError("yt-dlp finished but no playable local file was found.")
        return max(candidates, key=lambda path: path.stat().st_mtime)


app_state = AppState()


def create_access_token(username: str) -> str:
    payload = {
        "sub": username,
        "exp": utc_now() + timedelta(days=30),
    }
    return jwt.encode(payload, settings.jwt_secret, algorithm="HS256")


def authenticate(credentials: HTTPAuthorizationCredentials | None = Depends(security)) -> str:
    if credentials is None or credentials.scheme.lower() != "bearer":
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Missing bearer token.")
    try:
        payload = jwt.decode(credentials.credentials, settings.jwt_secret, algorithms=["HS256"])
    except jwt.InvalidTokenError as error:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Invalid bearer token.") from error
    username = payload.get("sub")
    if username != settings.default_username:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Token user is not allowed.")
    return username


def public_job_response(job: JobRecord) -> JobStatusResponse:
    return JobStatusResponse(
        jobID=job.jobID,
        status=job.status,
        title=job.title,
        progressText=job.progressText,
        durationSeconds=job.durationSeconds,
        errorMessage=job.errorMessage,
        downloadURL=job.downloadURL,
        expiresAt=job.expiresAt,
        fileID=job.fileID,
        fileName=job.fileName,
    )


@asynccontextmanager
async def lifespan(_: FastAPI):
    await app_state.start()
    try:
        yield
    finally:
        await app_state.stop()


app = FastAPI(title="Lectigo Backend", lifespan=lifespan)


@app.post("/auth/login", response_model=LoginResponse)
async def login(request: LoginRequest) -> LoginResponse:
    if request.usernameOrEmail != settings.default_username or not hmac.compare_digest(request.password, settings.default_password):
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Invalid username or password.")
    return LoginResponse(accessToken=create_access_token(settings.default_username), username=settings.default_username)


@app.post("/downloads", response_model=CreateDownloadResponse)
async def create_download(request: CreateDownloadRequest, username: str = Depends(authenticate)) -> CreateDownloadResponse:
    job = app_state.create_job(username, request.sourceURL)
    app_state.enqueue_job(job.jobID)
    return CreateDownloadResponse(jobID=job.jobID, status=job.status)


@app.get("/downloads/{job_id}", response_model=JobStatusResponse)
async def get_download(job_id: str, username: str = Depends(authenticate)) -> JobStatusResponse:
    job = app_state.get_job(job_id)
    if job.owner != username:
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="You do not own this download job.")
    return public_job_response(job)


@app.get("/files/{file_id}")
async def get_file(file_id: str, username: str = Depends(authenticate)) -> FileResponse:
    job = app_state.get_job(file_id)
    if job.owner != username:
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="You do not own this file.")
    if job.status == "expired" or (job.expiresAt and job.expiresAt <= utc_now()):
        raise HTTPException(status_code=status.HTTP_410_GONE, detail="The temporary MP4 has expired.")
    if job.outputPath is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="No output file was produced for this job.")
    path = Path(job.outputPath)
    if not path.exists():
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="The temporary MP4 file is missing.")
    return FileResponse(path, filename=job.fileName or path.name, media_type="video/mp4")


@app.delete("/downloads/{job_id}")
async def delete_download(job_id: str, username: str = Depends(authenticate)) -> dict[str, str]:
    job = app_state.get_job(job_id)
    if job.owner != username:
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="You do not own this download job.")
    if app_state.active_job_id == job_id:
        raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail="This job is currently running and cannot be deleted.")

    if job.outputPath:
        path = Path(job.outputPath)
        path.unlink(missing_ok=True)
        if path.parent.exists():
            try:
                path.parent.rmdir()
            except OSError:
                pass

    with app_state.lock:
        app_state.jobs.pop(job_id, None)
    app_state.persist_jobs()
    return {"status": "deleted"}
