#import <UIKit/UIKit.h>
#import <Preferences/PSListController.h>
#import <Preferences/PSSpecifier.h>
#import <notify.h>

@interface ChevronV3RootListController : PSListController
@end

@implementation ChevronV3RootListController

- (NSArray *)specifiers {
    if (_specifiers) return _specifiers;

    PSSpecifier *group = [PSSpecifier preferenceSpecifierNamed:@"通知分屏测试"
                                                         target:nil
                                                            set:nil
                                                            get:nil
                                                         detail:nil
                                                           cell:PSGroupCell
                                                           edit:nil];
    [group setProperty:@"通过 SpringBoard 的 NCBulletinNotificationSource 发布系统原生通知，完整经过 NCNotificationDispatcher、系统横幅与默认点击响应；默认使用“短信”。"
                 forKey:@"footerText"];

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

- (void)sendSimulatedNotification:(PSSpecifier *)specifier {
    [self.view endEditing:YES];
    CFPreferencesAppSynchronize(CFSTR("com.xu.chevronv3"));
    notify_post("com.xu.chevronv3.simulate-notification");
    UINotificationFeedbackGenerator *feedback = [[UINotificationFeedbackGenerator alloc] init];
    [feedback notificationOccurred:UINotificationFeedbackTypeSuccess];
}

@end
