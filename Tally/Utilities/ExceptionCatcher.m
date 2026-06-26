//
//  ExceptionCatcher.m
//  Tally
//
//  See ExceptionCatcher.h for why this shim exists. Keep it minimal: its only
//  job is to run a block inside an Objective-C @try/@catch so a raised
//  NSException becomes a thrown NSError instead of crashing the process.
//

#import "ExceptionCatcher.h"

@implementation ExceptionCatcher

+ (BOOL)catchExceptionIn:(NS_NOESCAPE void (^)(void))block
                   error:(NSError * _Nullable * _Nullable)error {
    @try {
        block();
        return YES;
    } @catch (NSException *exception) {
        if (error) {
            NSMutableDictionary *info = [NSMutableDictionary dictionary];
            info[NSLocalizedDescriptionKey] = exception.reason ?: @"Objective-C exception";
            if (exception.name) {
                info[@"ExceptionName"] = exception.name;
            }
            *error = [NSError errorWithDomain:@"TallyExceptionCatcher"
                                         code:0
                                     userInfo:info];
        }
        return NO;
    }
}

@end
