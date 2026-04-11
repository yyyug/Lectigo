#import "ToolRunnerBridge.h"

#import <dispatch/dispatch.h>
#import <spawn.h>
#import <sys/stat.h>
#import <sys/wait.h>
#import <unistd.h>
#import <cstring>
#import <vector>

extern char **environ;

static NSString * const LectigoToolRunnerErrorDomain = @"Lectigo.ToolRunnerBridge";

@implementation ToolRunnerBridge

+ (void)downloadVideo:(NSString *)urlString
     outputDirectory:(NSString *)outputDirectory
            progress:(LectigoToolRunnerProgressBlock)progress
          completion:(LectigoToolRunnerCompletionBlock)completion {
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSError *setupError = nil;
        if (![self ensureDirectoryAtPath:outputDirectory error:&setupError]) {
            [self completeOnMainWithFilePath:nil error:setupError completion:completion];
            return;
        }

        NSString *pythonPath = [self firstExistingPathNamed:@[@"python3", @"python"] executable:YES];
        NSString *ytDlpPath = [self firstExistingPathNamed:@[@"yt-dlp", @"yt-dlp.pyz"] executable:NO];
        NSString *ffmpegPath = [self firstExistingPathNamed:@[@"ffmpeg"] executable:YES];

        if (pythonPath.length == 0 || ytDlpPath.length == 0 || ffmpegPath.length == 0) {
            NSString *message = @"Bundled downloader toolchain is incomplete. Add python3, yt-dlp, and ffmpeg to the app bundle resources before using on-device downloads.";
            NSError *error = [NSError errorWithDomain:LectigoToolRunnerErrorDomain
                                                 code:1001
                                             userInfo:@{NSLocalizedDescriptionKey: message}];
            [self completeOnMainWithFilePath:nil error:error completion:completion];
            return;
        }

        NSString *outputTemplate = [outputDirectory stringByAppendingPathComponent:@"%(title)s-%(id)s.%(ext)s"];
        NSArray<NSString *> *arguments = @[
            pythonPath,
            ytDlpPath,
            @"--no-playlist",
            @"--newline",
            @"--restrict-filenames",
            @"--merge-output-format", @"mp4",
            @"--remux-video", @"mp4",
            @"--ffmpeg-location", ffmpegPath,
            @"-f", @"bestvideo*+bestaudio/best",
            @"-o", outputTemplate,
            urlString
        ];

        [self postProgress:@"Starting bundled yt-dlp" progress:progress];
        int terminationStatus = 0;
        NSError *runError = nil;
        BOOL succeeded = [self runProcess:arguments
                                 progress:progress
                        terminationStatus:&terminationStatus
                                    error:&runError];
        if (!succeeded) {
            [self completeOnMainWithFilePath:nil error:runError completion:completion];
            return;
        }

        if (terminationStatus != 0) {
            NSString *message = [NSString stringWithFormat:@"yt-dlp exited with status %d.", terminationStatus];
            NSError *error = [NSError errorWithDomain:LectigoToolRunnerErrorDomain
                                                 code:1002
                                             userInfo:@{NSLocalizedDescriptionKey: message}];
            [self completeOnMainWithFilePath:nil error:error completion:completion];
            return;
        }

        NSString *resultPath = [self newestPlayableFileInDirectory:outputDirectory];
        if (resultPath.length == 0) {
            NSError *error = [NSError errorWithDomain:LectigoToolRunnerErrorDomain
                                                 code:1003
                                             userInfo:@{NSLocalizedDescriptionKey: @"yt-dlp finished but no playable local video file was found in the output directory."}];
            [self completeOnMainWithFilePath:nil error:error completion:completion];
            return;
        }

        [self completeOnMainWithFilePath:resultPath error:nil completion:completion];
    });
}

+ (BOOL)ensureDirectoryAtPath:(NSString *)path error:(NSError **)error {
    return [[NSFileManager defaultManager] createDirectoryAtPath:path
                                     withIntermediateDirectories:YES
                                                      attributes:nil
                                                           error:error];
}

+ (NSString *)firstExistingPathNamed:(NSArray<NSString *> *)names executable:(BOOL)executable {
    NSURL *resourceURL = [[NSBundle mainBundle] resourceURL];
    if (resourceURL == nil) {
        return @"";
    }

    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSDirectoryEnumerator *enumerator = [fileManager enumeratorAtURL:resourceURL
                                          includingPropertiesForKeys:@[NSURLNameKey, NSURLIsRegularFileKey, NSURLIsExecutableKey]
                                                             options:0
                                                        errorHandler:nil];
    for (NSURL *candidateURL in enumerator) {
        NSNumber *isRegularFile = nil;
        [candidateURL getResourceValue:&isRegularFile forKey:NSURLIsRegularFileKey error:nil];
        if (![isRegularFile boolValue]) {
            continue;
        }

        NSString *fileName = candidateURL.lastPathComponent;
        if (![names containsObject:fileName]) {
            continue;
        }

        if (executable) {
            NSNumber *isExecutable = nil;
            [candidateURL getResourceValue:&isExecutable forKey:NSURLIsExecutableKey error:nil];
            if (![isExecutable boolValue]) {
                continue;
            }
        }

        return candidateURL.path;
    }

    return @"";
}

+ (BOOL)runProcess:(NSArray<NSString *> *)arguments
          progress:(LectigoToolRunnerProgressBlock)progress
 terminationStatus:(int *)terminationStatus
             error:(NSError **)error {
    if (arguments.count == 0) {
        if (error != NULL) {
            *error = [NSError errorWithDomain:LectigoToolRunnerErrorDomain
                                         code:1004
                                     userInfo:@{NSLocalizedDescriptionKey: @"No executable arguments were provided to the downloader."}];
        }
        return NO;
    }

    int outputPipe[2];
    if (pipe(outputPipe) != 0) {
        if (error != NULL) {
            *error = [NSError errorWithDomain:NSPOSIXErrorDomain
                                         code:errno
                                     userInfo:@{NSLocalizedDescriptionKey: @"Could not create the downloader output pipe."}];
        }
        return NO;
    }

    posix_spawn_file_actions_t fileActions;
    posix_spawn_file_actions_init(&fileActions);
    posix_spawn_file_actions_adddup2(&fileActions, outputPipe[1], STDOUT_FILENO);
    posix_spawn_file_actions_adddup2(&fileActions, outputPipe[1], STDERR_FILENO);
    posix_spawn_file_actions_addclose(&fileActions, outputPipe[0]);
    posix_spawn_file_actions_addclose(&fileActions, outputPipe[1]);

    std::vector<char *> argv;
    argv.reserve(arguments.count + 1);
    for (NSString *argument in arguments) {
        argv.push_back(const_cast<char *>(argument.UTF8String));
    }
    argv.push_back(nullptr);

    pid_t pid = 0;
    int spawnStatus = posix_spawn(&pid, argv[0], &fileActions, nullptr, argv.data(), environ);
    posix_spawn_file_actions_destroy(&fileActions);
    close(outputPipe[1]);

    if (spawnStatus != 0) {
        close(outputPipe[0]);
        if (error != NULL) {
            NSString *message = [NSString stringWithFormat:@"Could not launch bundled downloader executable at %@.", arguments.firstObject];
            *error = [NSError errorWithDomain:NSPOSIXErrorDomain
                                         code:spawnStatus
                                     userInfo:@{NSLocalizedDescriptionKey: message}];
        }
        return NO;
    }

    [self readProgressFromFileDescriptor:outputPipe[0] progress:progress];
    close(outputPipe[0]);

    int waitStatus = 0;
    if (waitpid(pid, &waitStatus, 0) < 0) {
        if (error != NULL) {
            *error = [NSError errorWithDomain:NSPOSIXErrorDomain
                                         code:errno
                                     userInfo:@{NSLocalizedDescriptionKey: @"Downloader process launched but waitpid failed."}];
        }
        return NO;
    }

    if (terminationStatus != NULL) {
        if (WIFEXITED(waitStatus)) {
            *terminationStatus = WEXITSTATUS(waitStatus);
        } else if (WIFSIGNALED(waitStatus)) {
            *terminationStatus = 128 + WTERMSIG(waitStatus);
        } else {
            *terminationStatus = waitStatus;
        }
    }
    return YES;
}

+ (void)readProgressFromFileDescriptor:(int)fileDescriptor progress:(LectigoToolRunnerProgressBlock)progress {
    if (fileDescriptor < 0) {
        return;
    }

    NSMutableData *buffer = [NSMutableData data];
    char chunk[1024];
    ssize_t bytesRead = 0;
    while ((bytesRead = read(fileDescriptor, chunk, sizeof(chunk))) > 0) {
        [buffer appendBytes:chunk length:(NSUInteger)bytesRead];
        [self emitCompleteLinesFromBuffer:buffer progress:progress];
    }

    if (buffer.length > 0) {
        NSString *remaining = [[NSString alloc] initWithData:buffer encoding:NSUTF8StringEncoding];
        if (remaining.length > 0) {
            [self postProgress:[remaining stringByTrimmingCharactersInSet:[NSCharacterSet newlineCharacterSet]]
                      progress:progress];
        }
    }
}

+ (void)emitCompleteLinesFromBuffer:(NSMutableData *)buffer progress:(LectigoToolRunnerProgressBlock)progress {
    while (true) {
        const void *bytes = buffer.bytes;
        NSUInteger length = buffer.length;
        const void *newline = memchr(bytes, '\n', length);
        if (newline == nullptr) {
            return;
        }

        NSUInteger lineLength = (const char *)newline - (const char *)bytes;
        NSData *lineData = [buffer subdataWithRange:NSMakeRange(0, lineLength)];
        NSString *line = [[NSString alloc] initWithData:lineData encoding:NSUTF8StringEncoding];
        if (line.length > 0) {
            [self postProgress:line progress:progress];
        }

        NSUInteger bytesToRemove = MIN(length, lineLength + 1);
        [buffer replaceBytesInRange:NSMakeRange(0, bytesToRemove) withBytes:nullptr length:0];
    }
}

+ (void)postProgress:(NSString *)line progress:(LectigoToolRunnerProgressBlock)progress {
    if (progress == nil || line.length == 0) {
        return;
    }
    dispatch_async(dispatch_get_main_queue(), ^{
        progress(line);
    });
}

+ (NSString *)newestPlayableFileInDirectory:(NSString *)directoryPath {
    NSArray<NSString *> *extensions = @[@"mp4", @"m4v", @"mov", @"webm", @"mkv"];
    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSArray<NSURL *> *children = [fileManager contentsOfDirectoryAtURL:[NSURL fileURLWithPath:directoryPath]
                                            includingPropertiesForKeys:@[NSURLContentModificationDateKey, NSURLIsRegularFileKey]
                                                               options:0
                                                                 error:nil];

    NSURL *bestURL = nil;
    NSDate *bestDate = nil;
    for (NSURL *childURL in children) {
        NSNumber *isRegularFile = nil;
        [childURL getResourceValue:&isRegularFile forKey:NSURLIsRegularFileKey error:nil];
        if (![isRegularFile boolValue]) {
            continue;
        }

        if (![extensions containsObject:childURL.pathExtension.lowercaseString]) {
            continue;
        }

        NSDate *modifiedDate = nil;
        [childURL getResourceValue:&modifiedDate forKey:NSURLContentModificationDateKey error:nil];
        if (bestURL == nil || [bestDate compare:modifiedDate] == NSOrderedAscending) {
            bestURL = childURL;
            bestDate = modifiedDate;
        }
    }

    return bestURL.path ?: @"";
}

+ (void)completeOnMainWithFilePath:(NSString *)filePath
                             error:(NSError *)error
                        completion:(LectigoToolRunnerCompletionBlock)completion {
    dispatch_async(dispatch_get_main_queue(), ^{
        completion(filePath, error);
    });
}

@end
