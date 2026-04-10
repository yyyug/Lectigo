#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface PaddleOCRBridge : NSObject
+ (BOOL)prepareWithError:(NSError * _Nullable * _Nullable)error;
+ (NSString *)recognizeTextInImage:(UIImage *)image error:(NSError * _Nullable * _Nullable)error;
@end

NS_ASSUME_NONNULL_END
