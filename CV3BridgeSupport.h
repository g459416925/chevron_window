#import <Foundation/Foundation.h>

// Shared Darwin-notification protocol used by the SpringBoard host and the
// injected client bridge. Keep identifiers and hashing in one place so both
// processes always derive the same channel names.
static const char * const CV3VideoOrientationNotification = "com.xu.chevronv3.video-orientation";
static const char * const CV3PlaybackTraceNotification = "com.xu.chevronv3.playback-trace";
static const char * const CV3HostedInteractionNotification = "com.xu.chevronv3.hosted-interaction";
static const char * const CV3HostGenerationNotification = "com.xu.chevronv3.host-generation";
// Per-bundle Darwin state where an injected app publishes the orientation it
// last requested. The value outlives the floating window, so SpringBoard can
// still read the app's real canvas direction when it re-hosts an app whose
// window was already closed (for example a video that is still fullscreen).
static const char * const CV3RealContentOrientationNotificationPrefix = "com.xu.chevronv3.real-content-orientation";

static inline uint64_t CV3StableBundleHash(NSString *bundleID) {
    const unsigned char *bytes = (const unsigned char *)bundleID.UTF8String;
    uint64_t hash = 1469598103934665603ULL;
    if (!bytes) return hash;
    while (*bytes) {
        hash ^= (uint64_t)*bytes++;
        hash *= 1099511628211ULL;
    }
    return hash & 0x00FFFFFFFFFFFFFFULL;
}

static inline NSString *CV3BundleScopedNotificationName(NSString *prefix,
                                                         NSString *bundleID) {
    if (prefix.length == 0 || bundleID.length == 0) return nil;
    return [NSString stringWithFormat:@"%@.%014llx",
                                      prefix,
                                      (unsigned long long)CV3StableBundleHash(bundleID)];
}

// Injected by the build from the Debian Version field in control. Runtime logs
// must report the actually installed build instead of a hand-edited string:
// the host and the injected client ship as one package, and a mismatched pair
// is the first thing to rule out when the two halves stop agreeing.
#ifndef CV3_PACKAGE_VERSION
#define CV3_PACKAGE_VERSION "unknown"
#endif
#define CV3_VERSION_STRING @CV3_PACKAGE_VERSION
