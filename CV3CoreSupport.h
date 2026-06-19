#import <Foundation/Foundation.h>
#include <fcntl.h>
#include <sys/mman.h>
#include <sys/stat.h>

typedef struct {
    uint32_t magic;
    uint32_t isHosted;
    float width;
    float height;
} CV3SharedGeometry;

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

    NSMutableDictionary *registry = CV3SharedGeometryRegistry();
    NSMutableDictionary *existingEntry = registry[bundleID];
    if (existingEntry) {
        return [existingEntry[@"pointer"] pointerValue];
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
        if (fd < 0) return NULL;

        if (ftruncate(fd, sizeof(CV3SharedGeometry)) != 0) {
            close(fd);
            return NULL;
        }
        chmod([path UTF8String], 0644);

        void *addr = mmap(NULL, sizeof(CV3SharedGeometry), PROT_READ | PROT_WRITE, MAP_SHARED, fd, 0);
        if (addr == MAP_FAILED) {
            close(fd);
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
        return geometry;
    } @catch (NSException *e) {
        return NULL;
    }
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
