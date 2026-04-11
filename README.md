# Lectigo

Lectigo is an iOS SwiftUI app that lets users browse YouTube in a `WKWebView`, request a backend download for the current page URL, fetch a temporary MP4 from a server-backed `yt-dlp` service, play the video locally, and run PaddleOCR v5 on local video frames with VoiceOver accessibility announcements.

## Current State

The app now has three tabs:

- `Browse` for YouTube navigation and authenticated download requests
- `Library` for backend job progress, downloaded local videos, and local playback
- `Settings` for OCR settings plus backend login and base URL configuration

The repository includes the official Paddle Lite iOS arm64 runtime in `ThirdParty/PaddleLite/inference_lite_lib.ios64.armv8`, the PP-OCRv5 detector/recognizer/classifier `.nb` model assets, the OCR dictionary, config file, and the native Paddle OCR C++ pipeline adapted from the official iOS demo.

`Lectigo/Sources/Native/PaddleOCRBridge.mm` converts each local video frame image to an OpenCV matrix, runs the Paddle OCR detector/classifier/recognizer pipeline, and returns recognized caption text to Swift. The app is configured to use Paddle OCR only.

## Backend

The `backend/` folder contains a FastAPI service that:

- authenticates the app with bearer tokens
- runs `yt-dlp` plus system `ffmpeg`
- stores temporary MP4 output files
- exposes download job polling and file fetch endpoints
- cleans up expired files

See `backend/README.md` for setup and deployment.

## GitHub Actions Build

The workflow at `.github/workflows/build-unsigned-ios.yml` builds an unsigned `Lectigo-unsigned.ipa` artifact on macOS. It downloads the official `opencv2.framework` during CI because that framework binary is larger than GitHub's per-file repository limit.

## PaddleOCR v5 Files

Add these files to the app bundle:

- `PP-OCRv5_mobile_det.nb`
- `PP-OCRv5_mobile_rec.nb`
- `PP-OCRv5_mobile_cls.nb` if angle classification is enabled
- `ppocr_keys_ocrv5.txt`

## YouTube Note

The app still uses a YouTube webpage for browsing, but OCR runs only on locally downloaded playback, not on webpage snapshots. Confirm the product and legal constraints before shipping a public app that downloads and processes YouTube content.
