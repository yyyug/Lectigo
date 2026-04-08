#import "PaddleOCRBridge.h"

static NSString * const PaddleOCRBridgeErrorDomain = @"Lectigo.PaddleOCRBridge";

@implementation PaddleOCRBridge

+ (NSString *)recognizeTextInImage:(UIImage *)image error:(NSError * _Nullable * _Nullable)error {
    NSBundle *bundle = NSBundle.mainBundle;
    BOOL hasDet = [bundle pathForResource:@"PP-OCRv5_mobile_det" ofType:@"nb"] != nil;
    BOOL hasRec = [bundle pathForResource:@"PP-OCRv5_mobile_rec" ofType:@"nb"] != nil;
    BOOL hasKeys = [bundle pathForResource:@"ppocr_keys_ocrv5" ofType:@"txt"] != nil;

    if (!hasDet || !hasRec || !hasKeys) {
        if (error != nil) {
            NSString *message = @"PaddleOCR v5 model files are missing. Add PP-OCRv5_mobile_det.nb, PP-OCRv5_mobile_rec.nb, and ppocr_keys_ocrv5.txt to the app bundle.";
            *error = [NSError errorWithDomain:PaddleOCRBridgeErrorDomain
                                         code:1
                                     userInfo:@{NSLocalizedDescriptionKey: message}];
        }
        return @"";
    }

    if (error != nil) {
        NSString *message = @"Paddle Lite inference is not linked yet. Add the Paddle Lite iOS library and replace this bridge stub with PP-OCRv5 preprocessing, inference, and postprocessing.";
        *error = [NSError errorWithDomain:PaddleOCRBridgeErrorDomain
                                     code:2
                                 userInfo:@{NSLocalizedDescriptionKey: message}];
    }
    return @"";
}

@end
