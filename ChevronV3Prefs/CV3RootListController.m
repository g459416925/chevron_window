#import <UIKit/UIKit.h>
#import <Preferences/PSListController.h>
#import <Preferences/PSSpecifier.h>
#import <notify.h>

@interface ChevronV3RootListController : PSListController
@end

static PSSpecifier *CV3Group(NSString *name, NSString *footer) {
    PSSpecifier *specifier = [PSSpecifier preferenceSpecifierNamed:name
                                                              target:nil
                                                                 set:nil
                                                                 get:nil
                                                              detail:nil
                                                                cell:PSGroupCell
                                                                edit:nil];
    if (footer.length > 0) [specifier setProperty:footer forKey:@"footerText"];
    return specifier;
}

@implementation ChevronV3RootListController

- (NSArray *)specifiers {
    if (_specifiers) return _specifiers;

    PSSpecifier *group = CV3Group(@"通知分屏测试", @"通过 SpringBoard 的原生通知链路发布测试通知；默认使用“短信”。");

    PSSpecifier *bundleID = [PSSpecifier preferenceSpecifierNamed:@"测试应用 Bundle ID"
                                                             target:self
                                                                set:@selector(setPreferenceValue:specifier:)
                                                                get:@selector(readPreferenceValue:)
                                                             detail:nil
                                                               cell:PSEditTextCell
                                                               edit:nil];
    [bundleID setProperty:@"com.xu.chevronv3" forKey:@"defaults"];
    [bundleID setProperty:@"CV3TestNotificationBundleID" forKey:@"key"];
    [bundleID setProperty:@"com.apple.MobileSMS" forKey:@"default"];
    [bundleID setProperty:@"com.apple.MobileSMS" forKey:@"placeholder"];
    [bundleID setProperty:@YES forKey:@"noAutoCorrect"];
    [bundleID setProperty:@YES forKey:@"noAutoCaps"];

    PSSpecifier *send = [PSSpecifier preferenceSpecifierNamed:@"发送原生系统通知"
                                                         target:self
                                                            set:nil
                                                            get:nil
                                                         detail:nil
                                                           cell:PSButtonCell
                                                           edit:nil];
    send->action = @selector(sendSimulatedNotification:);

    _specifiers = [@[group, bundleID, send] mutableCopy];
    return _specifiers;
}

- (id)readPreferenceValue:(PSSpecifier *)specifier {
    NSString *key = [specifier propertyForKey:@"key"];
    CFPropertyListRef value = key.length > 0
        ? CFPreferencesCopyAppValue((__bridge CFStringRef)key, CFSTR("com.xu.chevronv3"))
        : NULL;
    return value ? CFBridgingRelease(value) : [specifier propertyForKey:@"default"];
}

- (void)setPreferenceValue:(id)value specifier:(PSSpecifier *)specifier {
    NSString *key = [specifier propertyForKey:@"key"];
    if (key.length == 0) return;
    CFPreferencesSetAppValue((__bridge CFStringRef)key,
                             (__bridge CFPropertyListRef)value,
                             CFSTR("com.xu.chevronv3"));
    CFPreferencesAppSynchronize(CFSTR("com.xu.chevronv3"));
}

- (void)sendSimulatedNotification:(PSSpecifier *)specifier {
    [self.view endEditing:YES];
    CFPreferencesAppSynchronize(CFSTR("com.xu.chevronv3"));
    notify_post("com.xu.chevronv3.simulate-notification");
    UINotificationFeedbackGenerator *feedback = [[UINotificationFeedbackGenerator alloc] init];
    [feedback notificationOccurred:UINotificationFeedbackTypeSuccess];
}

@end
