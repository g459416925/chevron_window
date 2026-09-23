#import <Foundation/Foundation.h>
#import <CoreFoundation/CoreFoundation.h>

static NSString * const CV3CameraGrantDomain = @"com.xu.chevronv3";
static NSString * const CV3CameraGrantGenerationKey = @"HostedCameraGrantGeneration";
static NSString * const CV3CameraGrantBundleKeyPrefix = @"HostedCameraGrant.";
static NSString * const CV3CameraGrantStateChangedNotification = @"com.xu.chevronv3.camera-state-changed";
static NSString * const CV3HostedCameraAccessGrantedNotification = @"com.xu.chevronv3.hosted-camera-access-granted";
typedef void (*CV3CameraGrantMutationLogger)(NSString *message);
static CV3CameraGrantMutationLogger CV3CameraGrantLogger = NULL;

NS_INLINE void CV3SetCameraGrantMutationLogger(CV3CameraGrantMutationLogger logger) {
    CV3CameraGrantLogger = logger;
}

NS_INLINE NSString *CV3CameraGrantKeyForBundleID(NSString *bundleID) {
    if (bundleID.length == 0) return nil;
    NSData *data = [bundleID dataUsingEncoding:NSUTF8StringEncoding];
    return [CV3CameraGrantBundleKeyPrefix stringByAppendingString:
        [data base64EncodedStringWithOptions:0]];
}

NS_INLINE NSNumber *CV3CameraGrantCopyNumber(NSString *key) {
    if (key.length == 0) return nil;
    CFPreferencesAppSynchronize((__bridge CFStringRef)CV3CameraGrantDomain);
    CFPropertyListRef value = CFPreferencesCopyAppValue(
        (__bridge CFStringRef)key,
        (__bridge CFStringRef)CV3CameraGrantDomain);
    NSNumber *number = nil;
    if (value && CFGetTypeID(value) == CFNumberGetTypeID()) {
        number = [(__bridge NSNumber *)value copy];
    }
    if (value) CFRelease(value);
    return number;
}

NS_INLINE uint64_t CV3CameraGrantCurrentGeneration(void) {
    return CV3CameraGrantCopyNumber(CV3CameraGrantGenerationKey).unsignedLongLongValue;
}

NS_INLINE BOOL CV3CameraForegroundGrantIsGranted(NSString *bundleID) {
    uint64_t generation = CV3CameraGrantCurrentGeneration();
    if (generation == 0) return NO;
    NSNumber *bundleGeneration = CV3CameraGrantCopyNumber(
        CV3CameraGrantKeyForBundleID(bundleID));
    return bundleGeneration.unsignedLongLongValue == generation;
}

NS_INLINE void CV3CameraGrantMutationProbe(NSString *operation,
                                           NSString *bundleID,
                                           uint64_t generation,
                                           BOOL before,
                                           BOOL after,
                                           BOOL synchronized) {
    NSString *line = [NSString stringWithFormat:
        @"[ChevronProbe][CameraGrant] operation=%@ bundle=%@ strategy=per-bundle-generation generation=%llu sync=%d before=%d after=%d",
        operation ?: @"<nil>", bundleID ?: @"<nil>", generation,
        synchronized, before, after];
    if (CV3CameraGrantLogger) CV3CameraGrantLogger(line);
    else NSLog(@"%@", line);
}

NS_INLINE void CV3SetCameraForegroundGrant(NSString *bundleID, BOOL granted) {
    NSString *bundleKey = CV3CameraGrantKeyForBundleID(bundleID);
    if (bundleKey.length == 0) return;

    uint64_t generation = CV3CameraGrantCurrentGeneration();
    BOOL before = CV3CameraForegroundGrantIsGranted(bundleID);
    NSNumber *storedGeneration = granted && generation > 0 ? @(generation) : nil;
    CFPreferencesSetAppValue(
        (__bridge CFStringRef)bundleKey,
        (__bridge CFPropertyListRef)storedGeneration,
        (__bridge CFStringRef)CV3CameraGrantDomain);
    BOOL synchronized = CFPreferencesAppSynchronize(
        (__bridge CFStringRef)CV3CameraGrantDomain);
    CV3CameraGrantMutationProbe(granted ? @"grant" : @"revoke", bundleID,
                                generation, before,
                                granted && generation > 0, synchronized);
    CFNotificationCenterPostNotification(
        CFNotificationCenterGetDarwinNotifyCenter(),
        (__bridge CFStringRef)CV3CameraGrantStateChangedNotification,
        NULL, NULL, true);
}

NS_INLINE void CV3ResetCameraForegroundGrants(void) {
    uint64_t previousGeneration = CV3CameraGrantCurrentGeneration();
    uint64_t generation = previousGeneration + 1;
    if (generation == 0) generation = 1;
    CFPreferencesSetAppValue(
        (__bridge CFStringRef)CV3CameraGrantGenerationKey,
        (__bridge CFNumberRef)@(generation),
        (__bridge CFStringRef)CV3CameraGrantDomain);
    CFPreferencesSetAppValue(
        CFSTR("HostedCameraGrantBundleIDs"), NULL,
        (__bridge CFStringRef)CV3CameraGrantDomain);
    BOOL synchronized = CFPreferencesAppSynchronize(
        (__bridge CFStringRef)CV3CameraGrantDomain);
    CV3CameraGrantMutationProbe(@"reset", nil, generation,
                                previousGeneration > 0, NO, synchronized);
    CFNotificationCenterPostNotification(
        CFNotificationCenterGetDarwinNotifyCenter(),
        (__bridge CFStringRef)CV3CameraGrantStateChangedNotification,
        NULL, NULL, true);
}
