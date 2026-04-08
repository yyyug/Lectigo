# Lectigo

Lectigo is an iOS SwiftUI prototype that opens YouTube in a `WKWebView`, captures the caption area once per second while the page video is playing, sends the image to a PaddleOCR v5 bridge, and announces newly recognized text with `AVSpeechSynthesizer`.

## Current State

The app shell, web view capture loop, OCR pipeline boundary, speech output, and a usable on-device Vision OCR fallback are implemented.

The actual Paddle Lite iOS inference code and PP-OCRv5 model files are not present in this empty workspace yet. Add the Paddle Lite iOS runtime, optimized PP-OCRv5 `.nb` files, and replace `Lectigo/Sources/Native/PaddleOCRBridge.mm` with the detector/recognizer preprocessing, inference, and postprocessing. Until then, the app falls back to Apple's on-device Vision OCR so the IPA remains usable.

## GitHub Actions Build

The workflow at `.github/workflows/build-unsigned-ios.yml` builds an unsigned `Lectigo-unsigned.ipa` artifact on macOS.

## PaddleOCR v5 Files

Add these files to the app bundle:

- `PP-OCRv5_mobile_det.nb`
- `PP-OCRv5_mobile_rec.nb`
- `PP-OCRv5_mobile_cls.nb` if angle classification is enabled
- `ppocr_keys_ocrv5.txt`

## YouTube Note

This implementation captures rendered webpage images. Confirm the product and legal constraints before shipping a public app that extracts text from YouTube playback.
