# Lectigo

Lectigo is an iOS SwiftUI prototype that opens YouTube in a `WKWebView`, captures the caption area once per second while the page video is playing, sends the image to a PaddleOCR v5 bridge, and announces newly recognized text with `AVSpeechSynthesizer`.

## Current State

The app shell, web view capture loop, OCR pipeline boundary, speech output, and a usable on-device Vision OCR fallback are implemented.

The repository includes the official Paddle Lite iOS arm64 runtime in `ThirdParty/PaddleLite/inference_lite_lib.ios64.armv8`, the PP-OCRv5 detector/recognizer/classifier `.nb` model assets, the OCR dictionary, config file, and the native Paddle OCR C++ pipeline adapted from the official iOS demo.

`Lectigo/Sources/Native/PaddleOCRBridge.mm` now converts each `UIImage` snapshot to an OpenCV matrix, runs the real Paddle OCR detector/classifier/recognizer pipeline, and returns recognized caption text to Swift. If Paddle returns no text or fails on a frame, the app falls back to Apple's on-device Vision OCR.

## GitHub Actions Build

The workflow at `.github/workflows/build-unsigned-ios.yml` builds an unsigned `Lectigo-unsigned.ipa` artifact on macOS. It downloads the official `opencv2.framework` during CI because that framework binary is larger than GitHub's per-file repository limit.

## PaddleOCR v5 Files

Add these files to the app bundle:

- `PP-OCRv5_mobile_det.nb`
- `PP-OCRv5_mobile_rec.nb`
- `PP-OCRv5_mobile_cls.nb` if angle classification is enabled
- `ppocr_keys_ocrv5.txt`

## YouTube Note

This implementation captures rendered webpage images. Confirm the product and legal constraints before shipping a public app that extracts text from YouTube playback.
