#import <Foundation/Foundation.h>
#import <mach-o/dyld.h>
#import <objc/message.h>
#import <objc/runtime.h>
#import <substrate.h>
#import "CV3CameraSupport.h"

typedef BOOL (*CV3CameraAccessGetterIMP)(id, SEL);

static CV3CameraAccessGetterIMP CV3OriginalApplicationStateMonitorHasBackgroundCameraAccess;
static CV3CameraAccessGetterIMP CV3OriginalSessionMonitorClientHasBackgroundCameraAccess;
static BOOL CV3ApplicationStateMonitorHookInstalled;
static BOOL CV3SessionMonitorClientHookInstalled;
static NSSet<NSString *> *CV3CachedCameraGrantBundleIDs;
static CFAbsoluteTime CV3CameraGrantCacheTimestamp;

static void CV3InvalidateCameraGrantCache(void) {
    @synchronized (CV3CameraGrantDomain) {
        CV3CachedCameraGrantBundleIDs = nil;
        CV3CameraGrantCacheTimestamp = 0;
    }
}

static void CV3CameraGrantStateDidChange(CFNotificationCenterRef center,
                                          void *observer,
                                          CFStringRef name,
                                          const void *object,
                                          CFDictionaryRef userInfo) {
    CV3InvalidateCameraGrantCache();
}

static NSSet<NSString *> *CV3CurrentCameraGrantBundleIDs(void) {
    @synchronized (CV3CameraGrantDomain) {
        CFAbsoluteTime now = CFAbsoluteTimeGetCurrent();
        if (CV3CachedCameraGrantBundleIDs && now - CV3CameraGrantCacheTimestamp < 0.25) {
            return CV3CachedCameraGrantBundleIDs;
        }
        CV3CachedCameraGrantBundleIDs = CV3CameraForegroundGrantBundleIDs();
        CV3CameraGrantCacheTimestamp = now;
        return CV3CachedCameraGrantBundleIDs;
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
    return bundleID.length > 0 && [CV3CurrentCameraGrantBundleIDs() containsObject:bundleID];
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
    CFNotificationCenterAddObserver(
        CFNotificationCenterGetDarwinNotifyCenter(), NULL,
        CV3CameraGrantStateDidChange,
        (__bridge CFStringRef)CV3CameraGrantStateChangedNotification,
        NULL, CFNotificationSuspensionBehaviorDeliverImmediately);
    _dyld_register_func_for_add_image(CV3CameraImageDidLoad);
    CV3InstallCameraCompatibilityHooks();
}
