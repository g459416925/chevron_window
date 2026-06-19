#import <Foundation/Foundation.h>
#import <objc/message.h>

static inline Class CV3ClassNamed(NSString *className) {
    return className.length > 0 ? NSClassFromString(className) : Nil;
}

static inline BOOL CV3TargetRespondsToSelector(id target, SEL selector) {
    return target && selector && [target respondsToSelector:selector];
}

static inline id CV3InvokeObject(id target, SEL selector) {
    if (!CV3TargetRespondsToSelector(target, selector)) return nil;

    @try {
        return ((id (*)(id, SEL))objc_msgSend)(target, selector);
    } @catch (NSException *e) {
        return nil;
    }
}

static inline id CV3InvokeObject1(id target, SEL selector, id arg1) {
    if (!CV3TargetRespondsToSelector(target, selector)) return nil;

    @try {
        return ((id (*)(id, SEL, id))objc_msgSend)(target, selector, arg1);
    } @catch (NSException *e) {
        return nil;
    }
}

static inline id CV3InvokeObject2(id target, SEL selector, id arg1, id arg2) {
    if (!CV3TargetRespondsToSelector(target, selector)) return nil;

    @try {
        return ((id (*)(id, SEL, id, id))objc_msgSend)(target, selector, arg1, arg2);
    } @catch (NSException *e) {
        return nil;
    }
}

static inline BOOL CV3InvokeBool(id target, SEL selector, BOOL fallbackValue) {
    if (!CV3TargetRespondsToSelector(target, selector)) return fallbackValue;

    @try {
        return ((BOOL (*)(id, SEL))objc_msgSend)(target, selector);
    } @catch (NSException *e) {
        return fallbackValue;
    }
}

static inline NSInteger CV3InvokeInteger(id target, SEL selector, NSInteger fallbackValue) {
    if (!CV3TargetRespondsToSelector(target, selector)) return fallbackValue;

    @try {
        return ((NSInteger (*)(id, SEL))objc_msgSend)(target, selector);
    } @catch (NSException *e) {
        return fallbackValue;
    }
}
