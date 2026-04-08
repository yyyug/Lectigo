# Lectigo

Lectigo is an iOS SwiftUI prototype that opens YouTube in a `WKWebView`, captures the caption area once per second while the page video is playing, sends the image to a PaddleOCR v5 bridge, and announces newly recognized text with `AVSpeechSynthesizer`.

## Current State

The app shell, web view capture loop, OCR pipeline boundary, speech output, and a usable on-device Vision OCR fallback are implemented.

The repository now includes the official Paddle Lite iOS arm64 runtime in `ThirdParty/PaddleLite/inference_lite_lib.ios64.armv8` and bundles the official `PP-OCRv5_mobile_det.nb`, `PP-OCRv5_mobile_rec.nb`, and `ppocr_keys_ocrv5.txt` model assets.

`Lectigo/Sources/Native/PaddleOCRBridge.mm` now links against the real Paddle Lite headers/library and validates that the bundled predictors can be created. The actual detector preprocessing, box decoding, crop extraction, recognizer tensor feed, and OCR postprocessing are still not implemented there, so the app falls back to Apple's on-device Vision OCR for usable recognition.

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
