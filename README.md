# Lectigo

Lectigo is an iOS SwiftUI app that captures the display of another app via ScreenCaptureKit (iOS 27+), runs offline OCR on the subtitle area, and announces new caption lines with VoiceOver.

## Current State

The app has two tabs:

- `Capture` to start/stop screen capture and show the latest recognized caption
- `Settings` for OCR engine choice, subtitle crop area, capture interval, and announcement similarity threshold

Text recognition runs fully on device through one of two engines:

- `PaddleOCR` – a Swift/Objective-C pipeline executing bundled PP-OCRv5 ONNX models with the `onnxruntime-objc` pod, OpenCV, and the Clipper polygon offset library
- `iOS Vision (Built-in)` – Apple's `VNRecognizeTextRequest`

The PaddleOCR engine sources live in `Lectigo/Sources/PaddleOCR/` (Swift orchestration plus Objective-C++ OpenCV bridges in `PaddleOCR/CV/` and Clipper in `PaddleOCR/Clipper/`). ONNX models are bundled in `Lectigo/Models/det/` and `Lectigo/Models/rec/`.

`Lectigo/Sources/ScreenCapture/ScreenCaptureCaptionController.swift` presents the content sharing picker, streams `SCStreamOutput` frames, crops the configured region, and drives the selected recognizer.

## Dependencies

Install with CocoaPods (`pod install`) and build the `Lectigo.xcworkspace`:

- `onnxruntime-objc` ~> 1.24
- `OpenCV` ~> 4.3.0
- `Yams` ~> 5.0

The `Podfile` post-install hook pins every pod to deployment target 27.0 and disables `CLANG_WARN_QUOTED_INCLUDE_IN_FRAMEWORK_HEADER`.

## GitHub Actions Build

The workflow at `.github/workflows/build-unsigned-ios.yml` runs `pod install`, builds the unsigned `Release-iphoneos` app with `xcodebuild`, and packages `Lectigo-unsigned.ipa`.

## Background Mode

`Info.plist` includes the `screen-capture` background mode so screen capture can keep running while the app is in the background.