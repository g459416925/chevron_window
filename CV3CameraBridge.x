#import <Foundation/Foundation.h>
#import <mach-o/dyld.h>
#import <objc/message.h>
#import <objc/runtime.h>
#import <substrate.h>
#include <stdarg.h>
#import "CV3CameraSupport.h"

typedef BOOL (*CV3CameraAccessGetterIMP)(id, SEL);

static CV3CameraAccessGetterIMP CV3OriginalApplicationStateMonitorHasBackgroundCameraAccess;
static CV3CameraAccessGetterIMP CV3OriginalSessionMonitorClientHasBackgroundCameraAccess;
static BOOL CV3ApplicationStateMonitorHookInstalled;
static BOOL CV3SessionMonitorClientHookInstalled;
static NSMutableDictionary<NSString *, NSNumber *> *CV3CachedCameraGrantStates;
static CFAbsoluteTime CV3LastHostedCameraAccessNotificationTimestamp;

static void CV3CameraProbe(NSString *format, ...) {
    va_list args;
    va_start(args, format);
    NSString *message = [[NSString alloc] initWithFormat:format arguments:args];
    va_end(args);
    NSLog(@"[ChevronProbe][CameraBridge] pid=%d process=%@ %@",
          NSProcessInfo.processInfo.processIdentifier,
          NSProcessInfo.processInfo.processName, message ?: @"<nil>");
    @try {
        NSString *path = @"/rootfs/var/mobile/Library/Logs/ChevronV3_Logs.txt";
        NSString *line = [NSString stringWithFormat:@"[%@][ChevronProbe][CameraBridge] pid=%d process=%@ %@\n",
                          NSDate.date, NSProcessInfo.processInfo.processIdentifier,
                          NSProcessInfo.processInfo.processName, message ?: @"<nil>"];
        NSFileManager *manager = NSFileManager.defaultManager;
        [manager createDirectoryAtPath:[path stringByDeletingLastPathComponent] withIntermediateDirectories:YES attributes:nil error:nil];
        if (![manager fileExistsAtPath:path]) [manager createFileAtPath:path contents:nil attributes:nil];
        NSFileHandle *handle = [NSFileHandle fileHandleForWritingAtPath:path];
        if (handle) { [handle seekToEndOfFile]; [handle writeData:[line dataUsingEncoding:NSUTF8StringEncoding]]; [handle closeFile]; }
    } @catch (__unused NSException *exception) {}
}

static void CV3InvalidateCameraGrantCache(void) {
    @synchronized (CV3CameraGrantDomain) {
        CV3CachedCameraGrantStates = nil;
    }
    CV3CameraProbe(@"grant-cache invalidated");
}

static void CV3CameraGrantStateDidChange(CFNotificationCenterRef center,
                                          void *observer,
                                          CFStringRef name,
                                          const void *object,
                                          CFDictionaryRef userInfo) {
    CV3InvalidateCameraGrantCache();
}

static BOOL CV3CurrentCameraGrantForBundleID(NSString *bundleID) {
    if (bundleID.length == 0) return NO;
    @synchronized (CV3CameraGrantDomain) {
        if (!CV3CachedCameraGrantStates) {
            CV3CachedCameraGrantStates = [NSMutableDictionary dictionary];
        }
        NSNumber *cached = CV3CachedCameraGrantStates[bundleID];
        if (cached) return cached.boolValue;
        BOOL granted = CV3CameraForegroundGrantIsGranted(bundleID);
        CV3CachedCameraGrantStates[bundleID] = @(granted);
        return granted;
    }
}

static BOOL CV3IsTargetCameraDaemon(void) {
    NSString *processName = NSProcessInfo.processInfo.processName.lowercaseString;
    NSString *bundleIdentifier = NSBundle.mainBundle.bundleIdentifier.lowercaseString;
    return [processName isEqualToString:@"mediaserverd"] ||
        [processName containsString:@"cameracaptured"] ||
        [bundleIdentifier isEqualToString:@"com.apple.cameracaptured"];
}

static NSString *CV3CameraClientApplicationIdentifier(id object) {
    SEL selector = @selector(applicationID);
    if (!object || ![object respondsToSelector:selector]) return nil;
    id value = ((id (*)(id, SEL))objc_msgSend)(object, selector);
    return [value isKindOfClass:NSString.class] ? value : nil;
}

static BOOL CV3CameraGrantMatchesClient(id object) {
    NSString *bundleID = CV3CameraClientApplicationIdentifier(object);
    BOOL matched = CV3CurrentCameraGrantForBundleID(bundleID);
    CV3CameraProbe(@"grant-check bundle=%@ matched=%d", bundleID ?: @"<nil>", matched);
    if (!matched) return NO;

    @synchronized (CV3CameraGrantDomain) {
        CFAbsoluteTime now = CFAbsoluteTimeGetCurrent();
        if (now - CV3LastHostedCameraAccessNotificationTimestamp >= 0.25) {
            CV3LastHostedCameraAccessNotificationTimestamp = now;
            CFNotificationCenterPostNotification(
                CFNotificationCenterGetDarwinNotifyCenter(),
                (__bridge CFStringRef)CV3HostedCameraAccessGrantedNotification,
                NULL, NULL, true);
        }
    }
    return YES;
}

static BOOL CV3ApplicationStateMonitorHasBackgroundCameraAccess(id self, SEL selector) {
    if (CV3CameraGrantMatchesClient(self)) return YES;
    return CV3OriginalApplicationStateMonitorHasBackgroundCameraAccess
        ? CV3OriginalApplicationStateMonitorHasBackgroundCameraAccess(self, selector)
        : NO;
}

static BOOL CV3SessionMonitorClientHasBackgroundCameraAccess(id self, SEL selector) {
    if (CV3CameraGrantMatchesClient(self)) return YES;
    return CV3OriginalSessionMonitorClientHasBackgroundCameraAccess
        ? CV3OriginalSessionMonitorClientHasBackgroundCameraAccess(self, selector)
        : NO;
}

static BOOL CV3CanHookCameraMethod(Class targetClass, SEL selector) {
    Method method = targetClass ? class_getInstanceMethod(targetClass, selector) : NULL;
    return method && method_getNumberOfArguments(method) == 2;
}

static void CV3InstallCameraCompatibilityHooks(void) {
    if (!CV3IsTargetCameraDaemon()) return;

    @synchronized (NSProcessInfo.class) {
        SEL selector = @selector(hasBackgroundCameraAccess);
        if (!CV3ApplicationStateMonitorHookInstalled) {
            Class targetClass = objc_getClass("FigCaptureClientApplicationStateMonitorClient");
            if (CV3CanHookCameraMethod(targetClass, selector)) {
                MSHookMessageEx(targetClass, selector,
                    (IMP)CV3ApplicationStateMonitorHasBackgroundCameraAccess,
                    (IMP *)&CV3OriginalApplicationStateMonitorHasBackgroundCameraAccess);
                CV3ApplicationStateMonitorHookInstalled = YES;
                NSLog(@"[ChevronV3Camera] application-state monitor hook installed");
            }
        }

        if (!CV3SessionMonitorClientHookInstalled) {
            Class targetClass = objc_getClass("FigCaptureClientSessionMonitorClient");
            if (CV3CanHookCameraMethod(targetClass, selector)) {
                MSHookMessageEx(targetClass, selector,
                    (IMP)CV3SessionMonitorClientHasBackgroundCameraAccess,
                    (IMP *)&CV3OriginalSessionMonitorClientHasBackgroundCameraAccess);
                CV3SessionMonitorClientHookInstalled = YES;
                NSLog(@"[ChevronV3Camera] session monitor hook installed");
            }
        }
    }
}

static void CV3CameraImageDidLoad(const struct mach_header *header, intptr_t slide) {
    CV3InstallCameraCompatibilityHooks();
}

%ctor {
    if (!CV3IsTargetCameraDaemon()) return;
    CV3CameraProbe(@"camera.ctor");
    CFNotificationCenterAddObserver(
        CFNotificationCenterGetDarwinNotifyCenter(), NULL,
        CV3CameraGrantStateDidChange,
        (__bridge CFStringRef)CV3CameraGrantStateChangedNotification,
        NULL, CFNotificationSuspensionBehaviorDeliverImmediately);
    _dyld_register_func_for_add_image(CV3CameraImageDidLoad);
    CV3InstallCameraCompatibilityHooks();
}
