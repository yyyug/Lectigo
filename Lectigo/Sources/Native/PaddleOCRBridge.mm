#import "PaddleOCRBridge.h"
#import <opencv2/imgcodecs/ios.h>
#include "pipeline.h"
#import "paddle_api.h"
#import "paddle_use_kernels.h"
#import "paddle_use_ops.h"

#include <mutex>

using paddle::lite_api::MobileConfig;
using paddle::lite_api::PaddlePredictor;
using paddle::lite_api::CreatePaddlePredictor;

static NSString * const PaddleOCRBridgeErrorDomain = @"Lectigo.PaddleOCRBridge";

namespace {
std::mutex gPipelineMutex;
std::unique_ptr<Pipeline> gPipeline;

NSString *BundlePath(NSString *name, NSString *ext) {
    return [[NSBundle mainBundle] pathForResource:name ofType:ext];
}

std::string UTF8Path(NSString *path) {
    return path != nil ? std::string(path.UTF8String) : std::string();
}

Pipeline *SharedPipeline(NSError * _Nullable * _Nullable error) {
    std::lock_guard<std::mutex> lock(gPipelineMutex);
    if (gPipeline) {
        return gPipeline.get();
    }

    NSString *detPath = BundlePath(@"PP-OCRv5_mobile_det", @"nb");
    NSString *recPath = BundlePath(@"PP-OCRv5_mobile_rec", @"nb");
    NSString *clsPath = BundlePath(@"PP-LCNet_x0_25_textline_ori", @"nb");
    NSString *dictPath = BundlePath(@"ppocr_keys_ocrv5", @"txt");
    NSString *configPath = BundlePath(@"config", @"txt");

    if (detPath.length == 0 || recPath.length == 0 || clsPath.length == 0 ||
        dictPath.length == 0 || configPath.length == 0) {
        if (error != nil) {
            NSString *message = @"PaddleOCR bundled resources are incomplete. Expected detector, recognizer, classifier, config, and dictionary files.";
            *error = [NSError errorWithDomain:PaddleOCRBridgeErrorDomain
                                         code:10
                                     userInfo:@{NSLocalizedDescriptionKey: message}];
        }
        return nullptr;
    }

    try {
        gPipeline = std::make_unique<Pipeline>(
            UTF8Path(detPath),
            UTF8Path(clsPath),
            UTF8Path(recPath),
            "LITE_POWER_HIGH",
            1,
            UTF8Path(configPath),
            UTF8Path(dictPath)
        );
    } catch (const std::exception &exception) {
        if (error != nil) {
            NSString *message = [NSString stringWithFormat:@"Paddle OCR pipeline initialization failed: %s", exception.what()];
            *error = [NSError errorWithDomain:PaddleOCRBridgeErrorDomain
                                         code:11
                                     userInfo:@{NSLocalizedDescriptionKey: message}];
        }
        return nullptr;
    }

    return gPipeline.get();
}

cv::Mat PrepareMatFromUIImage(UIImage *image) {
    cv::Mat rgbaMat;
    UIImageToMat(image, rgbaMat, true);

    if (rgbaMat.empty()) {
        return rgbaMat;
    }

    cv::Mat rgbMat;
    if (rgbaMat.channels() == 4) {
        cv::cvtColor(rgbaMat, rgbMat, cv::COLOR_RGBA2RGB);
    } else if (rgbaMat.channels() == 3) {
        cv::cvtColor(rgbaMat, rgbMat, cv::COLOR_BGR2RGB);
    } else {
        cv::cvtColor(rgbaMat, rgbMat, cv::COLOR_GRAY2RGB);
    }
    return rgbMat;
}
}

@implementation PaddleOCRBridge

+ (BOOL)prepareWithError:(NSError * _Nullable * _Nullable)error {
    return SharedPipeline(error) != nullptr;
}

+ (NSString *)recognizeTextInImage:(UIImage *)image error:(NSError * _Nullable * _Nullable)error {
    NSBundle *bundle = NSBundle.mainBundle;
    BOOL hasDet = [bundle pathForResource:@"PP-OCRv5_mobile_det" ofType:@"nb"] != nil;
    BOOL hasRec = [bundle pathForResource:@"PP-OCRv5_mobile_rec" ofType:@"nb"] != nil;
    BOOL hasCls = [bundle pathForResource:@"PP-LCNet_x0_25_textline_ori" ofType:@"nb"] != nil;
    BOOL hasKeys = [bundle pathForResource:@"ppocr_keys_ocrv5" ofType:@"txt"] != nil;
    BOOL hasConfig = [bundle pathForResource:@"config" ofType:@"txt"] != nil;

    if (!hasDet || !hasRec || !hasCls || !hasKeys || !hasConfig) {
        if (error != nil) {
            NSString *message = @"PaddleOCR v5 model files are missing. Add detector, recognizer, classifier, config, and dictionary resources to the app bundle.";
            *error = [NSError errorWithDomain:PaddleOCRBridgeErrorDomain
                                         code:1
                                     userInfo:@{NSLocalizedDescriptionKey: message}];
        }
        return @"";
    }

    if (image == nil) {
        if (error != nil) {
            *error = [NSError errorWithDomain:PaddleOCRBridgeErrorDomain
                                         code:2
                                     userInfo:@{NSLocalizedDescriptionKey: @"No image was provided for OCR."}];
        }
        return @"";
    }

    NSError *pipelineError = nil;
    Pipeline *pipeline = SharedPipeline(&pipelineError);
    if (pipeline == nullptr) {
        if (error != nil) {
            *error = pipelineError;
        }
        return @"";
    }

    cv::Mat inputMat = PrepareMatFromUIImage(image);
    if (inputMat.empty()) {
        if (error != nil) {
            *error = [NSError errorWithDomain:PaddleOCRBridgeErrorDomain
                                         code:3
                                     userInfo:@{NSLocalizedDescriptionKey: @"Could not convert the image into an OpenCV matrix."}];
        }
        return @"";
    }

    std::vector<std::string> results;
    cv::Mat visualized;
    try {
        visualized = pipeline->Process(inputMat, "", results);
    } catch (const std::exception &exception) {
        if (error != nil) {
            NSString *message = [NSString stringWithFormat:@"Paddle OCR inference failed: %s", exception.what()];
            *error = [NSError errorWithDomain:PaddleOCRBridgeErrorDomain
                                         code:4
                                     userInfo:@{NSLocalizedDescriptionKey: message}];
        }
        return @"";
    }

    NSMutableArray<NSString *> *lines = [NSMutableArray array];
    for (size_t index = 0; index + 1 < results.size(); index += 2) {
        std::string value = results[index];
        if (!value.empty()) {
            [lines addObject:[NSString stringWithUTF8String:value.c_str()]];
        }
    }

    if (lines.count == 0) {
        return @"";
    }
    return [lines componentsJoinedByString:@" "];
}

@end
