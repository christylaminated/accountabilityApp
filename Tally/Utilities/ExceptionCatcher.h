//
//  ExceptionCatcher.h
//  Tally
//
//  ⚠️ DO NOT DELETE AS "UNUSED" ⚠️
//  This is referenced from Swift through the bridging header
//  (Tally-Bridging-Header.h), not by a symbol you can grep for in `.swift`.
//
//  WHY THIS EXISTS
//  ---------------
//  `CKShare.removeParticipant(_:)` raises an Objective-C
//  `NSInternalInconsistencyException` on iOS 26 under certain share states
//  (corrupt participant role / acceptance status — see
//  `PersonalRepository.leaveFriendShare`). Swift's `try`/`catch` CANNOT catch
//  Objective-C exceptions: they unwind straight past Swift frames and abort
//  the process. The ONLY way to survive that call is to wrap it in an
//  Objective-C `@try/@catch`. This shim does exactly that — convert a raised
//  NSException into a thrown NSError — and nothing else.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface ExceptionCatcher : NSObject

/// Runs @c block, converting any Objective-C @c NSException it raises into a
/// returned NSError so Swift `try` can handle it instead of crashing.
/// Returns YES if the block completed without raising, NO otherwise.
+ (BOOL)catchExceptionIn:(NS_NOESCAPE void (^)(void))block
                   error:(NSError * _Nullable * _Nullable)error;

@end

NS_ASSUME_NONNULL_END
