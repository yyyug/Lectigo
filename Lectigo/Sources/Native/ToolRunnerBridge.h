#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef void (^LectigoToolRunnerProgressBlock)(NSString *line);
typedef void (^LectigoToolRunnerCompletionBlock)(NSString * _Nullable filePath, NSError * _Nullable error);

@interface ToolRunnerBridge : NSObject

+ (void)downloadVideo:(NSString *)urlString
     outputDirectory:(NSString *)outputDirectory
            progress:(LectigoToolRunnerProgressBlock _Nullable)progress
          completion:(LectigoToolRunnerCompletionBlock)completion;

@end

NS_ASSUME_NONNULL_END
