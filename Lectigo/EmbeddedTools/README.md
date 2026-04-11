Place the on-device downloader toolchain here before building a sideloaded app bundle.

Expected bundle contents:
- `python3` or `python`
- `yt-dlp` or `yt-dlp.pyz`
- `ffmpeg`

The native downloader bridge scans the app bundle recursively for those filenames.

This repository does not include those executables. They must be added separately for private distribution if you want Browse -> Download to work on-device.
