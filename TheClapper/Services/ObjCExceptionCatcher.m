#import "ObjCExceptionCatcher.h"

@implementation ObjCExceptionCatcher

+ (BOOL)tryBlock:(void (^)(void))block error:(NSError *_Nullable *)error {
    @try {
        block();
        return YES;
    } @catch (NSException *exception) {
        if (error) {
            *error = [NSError errorWithDomain:@"com.edgeless.theclapper.objc"
                                         code:-1
                                     userInfo:@{
                NSLocalizedDescriptionKey: exception.reason ?: @"Unknown ObjC exception",
                @"ExceptionName": exception.name
            }];
        }
        return NO;
    }
}

@end
