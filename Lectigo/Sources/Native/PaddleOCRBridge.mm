#import "PaddleOCRBridge.h"
#import "paddle_api.h"

using paddle::lite_api::MobileConfig;
using paddle::lite_api::PaddlePredictor;
using paddle::lite_api::CreatePaddlePredictor;

static NSString * const PaddleOCRBridgeErrorDomain = @"Lectigo.PaddleOCRBridge";

namespace {
std::shared_ptr<PaddlePredictor> CreatePredictorFromBundleFile(NSString *name) {
    NSString *path = [[NSBundle mainBundle] pathForResource:name ofType:@"nb"];
    if (path.length == 0) {
        return nullptr;
    }

    MobileConfig config;
    config.set_model_from_file(path.UTF8String);
    config.set_threads(1);
    return CreatePaddlePredictor(config);
}
}

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

    @try {
        static std::shared_ptr<PaddlePredictor> detector = CreatePredictorFromBundleFile(@"PP-OCRv5_mobile_det");
        static std::shared_ptr<PaddlePredictor> recognizer = CreatePredictorFromBundleFile(@"PP-OCRv5_mobile_rec");
        if (!detector || !recognizer) {
            if (error != nil) {
                NSString *message = @"Paddle Lite runtime is linked, but the PP-OCRv5 predictors could not be created from the bundled .nb files.";
                *error = [NSError errorWithDomain:PaddleOCRBridgeErrorDomain
                                             code:2
                                         userInfo:@{NSLocalizedDescriptionKey: message}];
            }
            return @"";
        }
    } @catch (NSException *exception) {
        if (error != nil) {
            NSString *message = [NSString stringWithFormat:@"Paddle Lite predictor initialization failed: %@", exception.reason ?: @"Unknown exception"];
            *error = [NSError errorWithDomain:PaddleOCRBridgeErrorDomain
                                         code:3
                                     userInfo:@{NSLocalizedDescriptionKey: message}];
        }
        return @"";
    }

    if (error != nil) {
        NSString *message = @"Paddle Lite runtime and PP-OCRv5 model files are bundled, but OCR preprocessing/postprocessing is still stubbed. The app falls back to Vision OCR for usable recognition.";
        *error = [NSError errorWithDomain:PaddleOCRBridgeErrorDomain
                                     code:4
                                 userInfo:@{NSLocalizedDescriptionKey: message}];
    }
    return @"";
}

@end
