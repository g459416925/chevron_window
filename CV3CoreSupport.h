#import <Foundation/Foundation.h>
#include <fcntl.h>
#include <sys/mman.h>
#include <sys/stat.h>
#include <pthread.h>

typedef struct {
    uint32_t magic;
    uint32_t isHosted;
    float width;
    float height;
} CV3SharedGeometry;

static pthread_mutex_t *CV3SharedGeometryLock(void) {
    static pthread_mutex_t lock;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        pthread_mutexattr_t attributes;
        pthread_mutexattr_init(&attributes);
        pthread_mutexattr_settype(&attributes, PTHREAD_MUTEX_RECURSIVE);
        pthread_mutex_init(&lock, &attributes);
        pthread_mutexattr_destroy(&attributes);
    });
    return &lock;
}

static NSMutableDictionary<NSString *, NSMutableDictionary *> *CV3SharedGeometryRegistry(void) {
    static NSMutableDictionary<NSString *, NSMutableDictionary *> *registry = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        registry = [NSMutableDictionary dictionary];
    });
    return registry;
}

static NSString *CV3SanitizedGeometryIdentifier(NSString *bundleID) {
    if (bundleID.length == 0) return @"default";

    NSMutableCharacterSet *allowed = [NSMutableCharacterSet alphanumericCharacterSet];
    [allowed addCharactersInString:@"._-"];

    NSMutableString *sanitized = [NSMutableString stringWithCapacity:bundleID.length];
    for (NSUInteger i = 0; i < bundleID.length; i++) {
        unichar ch = [bundleID characterAtIndex:i];
        if ([allowed characterIsMember:ch]) {
            [sanitized appendFormat:@"%C", ch];
        } else {
            [sanitized appendString:@"_"];
        }
    }

    return sanitized.length > 0 ? sanitized : @"default";
}

static CV3SharedGeometry *CV3SharedGeometryForBundleID(NSString *bundleID) {
    if (bundleID.length == 0) return NULL;

    pthread_mutex_t *lock = CV3SharedGeometryLock();
    pthread_mutex_lock(lock);

    NSMutableDictionary *registry = CV3SharedGeometryRegistry();
    NSMutableDictionary *existingEntry = registry[bundleID];
    if (existingEntry) {
        CV3SharedGeometry *existingGeometry = [existingEntry[@"pointer"] pointerValue];
        pthread_mutex_unlock(lock);
        return existingGeometry;
    }

    NSString *sanitizedBundleID = CV3SanitizedGeometryIdentifier(bundleID);
    NSString *path = [@"/var/mobile/Library/Preferences" stringByAppendingPathComponent:
                      [NSString stringWithFormat:@"com.xu.chevronv3.%@.shm", sanitizedBundleID]];
    NSFileManager *fm = [NSFileManager defaultManager];
    NSString *parentDir = [path stringByDeletingLastPathComponent];

    @try {
        if (![fm fileExistsAtPath:parentDir]) {
            [fm createDirectoryAtPath:parentDir withIntermediateDirectories:YES attributes:nil error:nil];
        }

        int fd = open([path UTF8String], O_RDWR | O_CREAT, 0644);
        if (fd < 0) {
            pthread_mutex_unlock(lock);
            return NULL;
        }

        if (ftruncate(fd, sizeof(CV3SharedGeometry)) != 0) {
            close(fd);
            pthread_mutex_unlock(lock);
            return NULL;
        }
        chmod([path UTF8String], 0644);

        void *addr = mmap(NULL, sizeof(CV3SharedGeometry), PROT_READ | PROT_WRITE, MAP_SHARED, fd, 0);
        if (addr == MAP_FAILED) {
            close(fd);
            pthread_mutex_unlock(lock);
            return NULL;
        }

        CV3SharedGeometry *geometry = (CV3SharedGeometry *)addr;
        geometry->magic = 0x43563353;

        registry[bundleID] = [@{
            @"pointer": [NSValue valueWithPointer:geometry],
            @"fd": @(fd),
            @"path": path
        } mutableCopy];

        NSLog(@"[ChevronV3] [SHM] %@ geometry initialized at %p", bundleID, geometry);
        pthread_mutex_unlock(lock);
        return geometry;
    } @catch (NSException *e) {
        pthread_mutex_unlock(lock);
        return NULL;
    }
}

static inline void CV3RetainSharedGeometry(NSString *bundleID) {
    if (bundleID.length == 0) return;
    pthread_mutex_t *lock = CV3SharedGeometryLock();
    pthread_mutex_lock(lock);
    NSMutableDictionary *registry = CV3SharedGeometryRegistry();
    NSMutableDictionary *entry = registry[bundleID];
    if (entry) {
        NSInteger ref = [entry[@"refCount"] integerValue];
        entry[@"refCount"] = @(ref + 1);
    } else {
        CV3SharedGeometryForBundleID(bundleID);
        entry = registry[bundleID];
        if (entry) {
            entry[@"refCount"] = @(1);
        }
    }
    pthread_mutex_unlock(lock);
}

static inline void CV3ReleaseSharedGeometry(NSString *bundleID) {
    if (bundleID.length == 0) return;
    pthread_mutex_t *lock = CV3SharedGeometryLock();
    pthread_mutex_lock(lock);
    NSMutableDictionary *registry = CV3SharedGeometryRegistry();
    NSMutableDictionary *entry = registry[bundleID];
    if (entry) {
        NSInteger ref = [entry[@"refCount"] integerValue] - 1;
        if (ref <= 0) {
            CV3SharedGeometry *geometry = [entry[@"pointer"] pointerValue];
            int fd = [entry[@"fd"] intValue];
            if (geometry) {
                munmap(geometry, sizeof(CV3SharedGeometry));
            }
            if (fd >= 0) {
                close(fd);
            }
            [registry removeObjectForKey:bundleID];
            NSLog(@"[ChevronV3] [SHM] Released geometry for %@", bundleID);
        } else {
            entry[@"refCount"] = @(ref);
        }
    }
    pthread_mutex_unlock(lock);
}

static inline BOOL CV3WriteSharedGeometryForBundleID(NSString *bundleID, float w, float h, int isHosted) {
    if (bundleID.length == 0) return NO;

    pthread_mutex_t *lock = CV3SharedGeometryLock();
    pthread_mutex_lock(lock);
    CV3SharedGeometry *geometry = CV3SharedGeometryForBundleID(bundleID);
    if (geometry) {
        geometry->width = w;
        geometry->height = h;
        geometry->isHosted = (uint32_t)isHosted;
    }
    pthread_mutex_unlock(lock);
    return geometry != NULL;
}

static dispatch_queue_t CV3LogQueue(void) {
    static dispatch_queue_t queue;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        queue = dispatch_queue_create("com.xu.chevronv3.log", DISPATCH_QUEUE_SERIAL);
    });
    return queue;
}

static dispatch_queue_t CV3AppLoadQueue(void) {
    static dispatch_queue_t queue;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        queue = dispatch_queue_create("com.xu.chevronv3.appload", DISPATCH_QUEUE_SERIAL);
    });
    return queue;
}

static inline CGFloat CV3ConcentricCornerRadius(CGFloat outerRadius, CGFloat padding) {
    return MAX(4.0, outerRadius - padding);
}

