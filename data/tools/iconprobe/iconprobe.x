// iconprobe.x v7 —— 回主屏 API 探针（纯只读）
//
// 背景：155 复测 returnHome.noCandidate（SBUIController/UIApplication 的
//       returnToHomeScreen/_returnToHomeScreen/_dismissToHomeScreen/goHome 全不存在）。
// 目标：dump 相关类族中含 home/present/activate 关键字的真实方法名与签名，
//       为"App 场景 → 回主屏 → 复刻"找到可用入口。
//
// 纯只读：不 hook、不调用、不改状态。输出：/var/mobile/Documents/iconprobe.log

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>
#include <stdio.h>

static void ipLog(NSString *fmt, ...) {
    va_list ap;
    va_start(ap, fmt);
    NSString *s = [[NSString alloc] initWithFormat:fmt arguments:ap];
    va_end(ap);
    FILE *f = fopen("/var/mobile/Documents/iconprobe.log", "a");
    if (!f) return;
    fprintf(f, "%s\n", s.UTF8String);
    fclose(f);
}

static void ipDumpFiltered(NSString *className, NSArray<NSString *> *keys) {
    Class rootCls = NSClassFromString(className);
    if (!rootCls) { ipLog(@"[ICONPROBE] class %@ NOT FOUND", className); return; }
    ipLog(@"[ICONPROBE] ---- %@ (exists) ----", className);
    for (Class cls = rootCls; cls != Nil; cls = class_getSuperclass(cls)) {
        unsigned int count = 0;
        Method *methods = class_copyMethodList(cls, &count);
        for (unsigned i = 0; i < count; i++) {
            NSString *name = NSStringFromSelector(method_getName(methods[i]));
            NSString *lower = name.lowercaseString;
            BOOL hit = NO;
            for (NSString *k in keys) { if ([lower containsString:k]) { hit = YES; break; } }
            if (!hit) continue;
            ipLog(@"[ICONPROBE]   <%@> - %@ types=%s", NSStringFromClass(cls), name,
                  method_getTypeEncoding(methods[i]) ?: "?");
        }
        free(methods);
        Class superCls = class_getSuperclass(cls);
        if (!superCls || superCls == cls) break;
    }
}

__attribute__((constructor)) static void iconprobe_ctor(void) {
    @autoreleasepool {
        dispatch_async(dispatch_get_main_queue(), ^{
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(4 * NSEC_PER_SEC)),
                           dispatch_get_main_queue(), ^{
                ipLog(@"[ICONPROBE] ===== v7 home-api probe start %@ pid=%d =====", [NSDate date], getpid());
                NSArray<NSString *> *keys = @[ @"returnhome", @"gohome", @"showhome", @"presenthome",
                                               @"homescreen", @"dismiss", @"activatehome", @"homebutton" ];
                ipDumpFiltered(@"SBHomeScreenController", keys);
                ipDumpFiltered(@"SBUIController", keys);
                ipDumpFiltered(@"SBHomeHardwareButton", keys);
                ipDumpFiltered(@"SBMainWorkspace", keys);
                ipDumpFiltered(@"SBMainSwitcherControllerCoordinator", keys);
                ipLog(@"[ICONPROBE] ===== v7 probe done =====");
            });
        });
    }
}
