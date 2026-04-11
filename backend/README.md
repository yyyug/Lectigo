# Lectigo Backend

This backend receives YouTube URLs from the iOS app, runs `yt-dlp` plus system `ffmpeg`, stores a temporary MP4, and lets the app fetch that MP4 over an authenticated API.

## Features

- login endpoint with bearer-token auth
- serial download worker
- job status polling
- temporary file download endpoint
- automatic retention cleanup

## Quick Start

1. Create and activate a Python virtual environment.
2. Install dependencies:

   ```bash
   pip install -r requirements.txt
   ```

3. Copy `.env.example` to `.env` and set:
   - `LECTIGO_BASE_URL`
   - `LECTIGO_JWT_SECRET`
   - `LECTIGO_DEFAULT_USERNAME`
   - `LECTIGO_DEFAULT_PASSWORD`

4. Ensure `ffmpeg` is installed on the host and available on `PATH`, or set `LECTIGO_FFMPEG_LOCATION`.
5. Start the server:

   ```bash
   ./scripts/run_dev.sh
   ```

## API

- `POST /auth/login`
- `POST /downloads`
- `GET /downloads/{job_id}`
- `GET /files/{file_id}`
- `DELETE /downloads/{job_id}`

All download endpoints require `Authorization: Bearer <token>`.

## Notes

- The worker is intentionally serial to reduce VPS contention.
- Completed files expire after `LECTIGO_RETENTION_HOURS`.
- The app should download finished MP4 files promptly; backend storage is temporary.
