# PaddleOCR v5 Models

Add the optimized Paddle Lite `.nb` files and dictionary here, then include them in the Xcode target resources:

- `PP-OCRv5_mobile_det.nb`
- `PP-OCRv5_mobile_rec.nb`
- `PP-OCRv5_mobile_cls.nb` if you enable angle classification
- `ppocr_keys_ocrv5.txt`

The bridge currently checks for the detector, recognizer, and dictionary in the app bundle.
