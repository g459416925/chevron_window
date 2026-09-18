#import <Foundation/Foundation.h>
#import <CoreFoundation/CoreFoundation.h>

static NSString * const CV3CameraGrantDomain = @"com.xu.chevronv3";
static NSString * const CV3CameraGrantBundleIDsKey = @"HostedCameraGrantBundleIDs";
static NSString * const CV3CameraGrantStateChangedNotification = @"com.xu.chevronv3.camera-state-changed";

NS_INLINE NSSet<NSString *> *CV3CameraForegroundGrantBundleIDs(void) {
    CFPreferencesAppSynchronize((__bridge CFStringRef)CV3CameraGrantDomain);
    CFPropertyListRef value = CFPreferencesCopyAppValue(
        (__bridge CFStringRef)CV3CameraGrantBundleIDsKey,
        (__bridge CFStringRef)CV3CameraGrantDomain);
    NSSet<NSString *> *bundleIDs = nil;
    if (value && CFGetTypeID(value) == CFArrayGetTypeID()) {
        bundleIDs = [NSSet setWithArray:(__bridge NSArray *)value];
    }
    if (value) CFRelease(value);
    return bundleIDs ?: [NSSet set];
}

NS_INLINE void CV3SetCameraForegroundGrant(NSString *bundleID, BOOL granted) {
    if (bundleID.length == 0) return;

    NSMutableSet<NSString *> *bundleIDs = [CV3CameraForegroundGrantBundleIDs() mutableCopy];
    if (granted) {
        [bundleIDs addObject:bundleID];
    } else {
        [bundleIDs removeObject:bundleID];
    }
    NSArray<NSString *> *storedBundleIDs = [[bundleIDs allObjects]
        sortedArrayUsingSelector:@selector(compare:)];
    CFPreferencesSetAppValue(
        (__bridge CFStringRef)CV3CameraGrantBundleIDsKey,
        (__bridge CFArrayRef)storedBundleIDs,
        (__bridge CFStringRef)CV3CameraGrantDomain);
    CFPreferencesAppSynchronize((__bridge CFStringRef)CV3CameraGrantDomain);
    CFNotificationCenterPostNotification(
        CFNotificationCenterGetDarwinNotifyCenter(),
        (__bridge CFStringRef)CV3CameraGrantStateChangedNotification,
        NULL, NULL, true);
}

NS_INLINE void CV3ResetCameraForegroundGrants(void) {
    CFPreferencesSetAppValue(
        (__bridge CFStringRef)CV3CameraGrantBundleIDsKey,
        NULL,
        (__bridge CFStringRef)CV3CameraGrantDomain);
    CFPreferencesAppSynchronize((__bridge CFStringRef)CV3CameraGrantDomain);
    CFNotificationCenterPostNotification(
        CFNotificationCenterGetDarwinNotifyCenter(),
        (__bridge CFStringRef)CV3CameraGrantStateChangedNotification,
        NULL, NULL, true);
}
