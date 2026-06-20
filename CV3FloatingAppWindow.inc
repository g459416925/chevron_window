static void CV3CascadeUpdateSovereigntyAssertions(void) {
    if (!floatingWindows || floatingWindows.count == 0) return;
    NSArray *windowsSnapshot = [floatingWindows copy];
    for (id win in windowsSnapshot) {
        if ([win isKindOfClass:[CV3FloatingAppWindow class]] && ![win isClosing]) {
            [win updateSovereigntyAssertion];
        }
    }
}
static const CGFloat kCV3RotationCascadeStep = 20.0;
static const CGFloat kCV3StashIconSize = 44.0;
static const CGFloat kCV3StashIconInset = 4.0;

static CGRect CV3DisplayBoundsForWindow(UIWindow *window) {
    if (window.windowScene) {
        CGRect sceneBounds = window.windowScene.coordinateSpace.bounds;
        if (!CGRectIsEmpty(sceneBounds)) {
            return sceneBounds;
        }
    }
    if (window.screen) {
        CGRect screenBounds = window.screen.bounds;
        if (!CGRectIsEmpty(screenBounds)) {
            return screenBounds;
        }
    }
    return [UIScreen mainScreen].bounds;
}

static BOOL isGlobalExposeActive = NO;
static UIWindow *globalExposeBackdrop = nil;

void CV3ToggleExposeMode(void) {
    if (isGlobalExposeActive) {
        // Exit Exposé
        isGlobalExposeActive = NO;
        [UIView animateWithDuration:0.35 delay:0 usingSpringWithDamping:0.86 initialSpringVelocity:0.0 options:UIViewAnimationOptionCurveEaseInOut | UIViewAnimationOptionAllowUserInteraction animations:^{
            if (floatingWindows) {
                for (id obj in floatingWindows) {
                    if (![obj isKindOfClass:[CV3FloatingAppWindow class]]) continue;
                    CV3FloatingAppWindow *win = (CV3FloatingAppWindow *)obj;
                    if (!CGRectIsEmpty(win.preExposeFrame)) {
                        win.transform = win.preExposeTransform;
                        win.frame = win.preExposeFrame;
                        [win.exposeOverlayView removeFromSuperview];
                        win.exposeOverlayView = nil;
                    }
                }
            }
            if (globalExposeBackdrop) globalExposeBackdrop.alpha = 0.0;
        } completion:^(BOOL finished) {
            if (globalExposeBackdrop) {
                globalExposeBackdrop.hidden = YES;
                globalExposeBackdrop = nil;
            }
        }];
    } else {
        if (!floatingWindows || floatingWindows.count == 0) return;
        // Enter Exposé
        isGlobalExposeActive = YES;
        
        UIWindowScene *scene = nil;
        for (id obj in floatingWindows) {
            if ([obj isKindOfClass:[CV3FloatingAppWindow class]]) {
                scene = [(CV3FloatingAppWindow *)obj windowScene];
                if (scene) break;
            }
        }
        
        if (!globalExposeBackdrop) {
            if (scene) {
                globalExposeBackdrop = [[UIWindow alloc] initWithWindowScene:scene];
            } else {
                globalExposeBackdrop = [[UIWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
            }
            globalExposeBackdrop.windowLevel = CV3Style.floatingApp - 1;
            
            UIBlurEffect *blur = [UIBlurEffect effectWithStyle:UIBlurEffectStyleDark];
            UIVisualEffectView *bg = [[UIVisualEffectView alloc] initWithEffect:blur];
            bg.frame = globalExposeBackdrop.bounds;
            bg.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
            [globalExposeBackdrop addSubview:bg];
            
            UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:[CV3FloatingAppWindow class] action:@selector(handleExposeBackdropTap:)];
            [globalExposeBackdrop addGestureRecognizer:tap];
        }
        
        globalExposeBackdrop.alpha = 0.0;
        globalExposeBackdrop.hidden = NO;
        
        NSInteger count = floatingWindows.count;
        NSInteger cols = ceil(sqrt((double)count));
        NSInteger rows = ceil((double)count / cols);
        
        CGRect screenBounds = globalExposeBackdrop.bounds;
        CGFloat padding = 24.0;
        CGFloat availableW = screenBounds.size.width - padding * (cols + 1);
        CGFloat availableH = screenBounds.size.height - padding * (rows + 1);
        
        CGFloat cellW = availableW / cols;
        CGFloat cellH = availableH / rows;
        
        [UIView animateWithDuration:0.45 delay:0 usingSpringWithDamping:0.75 initialSpringVelocity:0.0 options:UIViewAnimationOptionCurveEaseInOut | UIViewAnimationOptionAllowUserInteraction animations:^{
            globalExposeBackdrop.alpha = 1.0;
            
            for (NSInteger i=0; i<count; i++) {
                id obj = floatingWindows[i];
                if (![obj isKindOfClass:[CV3FloatingAppWindow class]]) continue;
                CV3FloatingAppWindow *win = (CV3FloatingAppWindow *)obj;
                
                // 折叠浮窗的控制菜单（如果有展开的话）
                [win dismissMultitaskingMenu];
                
                win.preExposeFrame = win.frame;
                win.preExposeTransform = win.transform;
                
                // Add Overlay
                if (!win.exposeOverlayView) {
                    win.exposeOverlayView = [[UIView alloc] initWithFrame:win.bounds];
                    win.exposeOverlayView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
                    win.exposeOverlayView.backgroundColor = [UIColor clearColor];
                    UITapGestureRecognizer *winTap = [[UITapGestureRecognizer alloc] initWithTarget:win action:@selector(handleExposeSelectionTap:)];
                    [win.exposeOverlayView addGestureRecognizer:winTap];
                    [win addSubview:win.exposeOverlayView];
                }
                
                NSInteger r = i / cols;
                NSInteger c = i % cols;
                
                CGRect cellFrame = CGRectMake(padding + c * (cellW + padding), padding + r * (cellH + padding), cellW, cellH);
                
                CGFloat scaleX = cellW / win.bounds.size.width;
                CGFloat scaleY = cellH / win.bounds.size.height;
                CGFloat scale = MIN(scaleX, scaleY);
                
                CGPoint targetCenter = CGPointMake(CGRectGetMidX(cellFrame), CGRectGetMidY(cellFrame));
                
                win.transform = CGAffineTransformMakeScale(scale, scale);
                win.center = targetCenter;
            }
        } completion:nil];
    }
}

@implementation CV3FloatingAppWindow
- (UIEdgeInsets)currentSafeAreaInsets {
    UIEdgeInsets safeArea = self.safeAreaInsets;
    if (safeArea.top == 0 && safeArea.bottom == 0 && safeArea.left == 0 && safeArea.right == 0) {
        UIWindow *keyWindow = nil;
        if (@available(iOS 15.0, *)) {
            keyWindow = self.windowScene.keyWindow;
        } else {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
            keyWindow = [UIApplication sharedApplication].keyWindow;
#pragma clang diagnostic pop
        }
        safeArea = keyWindow ? keyWindow.safeAreaInsets : UIEdgeInsetsMake(47, 0, 34, 0);
    }
    return safeArea;
}
+ (void)handleExposeBackdropTap:(UITapGestureRecognizer *)sender {
    CV3ToggleExposeMode();
}

- (void)handleExposeSelectionTap:(UITapGestureRecognizer *)sender {
    CV3ToggleExposeMode();
    // 提升选中的窗口
    [self setWindowFocused:YES];
}

- (void)enforcePortraitWindowGeometry {
    if (self.isStashed || self.isClosing) return;

    self.transform = CGAffineTransformIdentity;
    UIInterfaceOrientation orientation = CV3TrustedInterfaceOrientation(self.windowScene);
    self.targetOrientation = orientation;
    CGAffineTransform targetRotation = CV3RotationTransformForInterfaceOrientation(orientation);
    self.baseRotationTransform = targetRotation;
    self.rootTransformContainer.transform = targetRotation;
}

- (void)applyInterfaceOrientation:(UIInterfaceOrientation)orientation force:(BOOL)force {
    if (!CV3IsValidInterfaceOrientation(orientation) || self.isClosing) return;

    CGAffineTransform targetRotation = CV3RotationTransformForInterfaceOrientation(orientation);
    BOOL orientationChanged = (self.lastLayoutOrientation != orientation);
    BOOL rotationChanged = !CGAffineTransformEqualToTransform(self.baseRotationTransform, targetRotation);
    BOOL targetIsLandscape = UIInterfaceOrientationIsLandscape(orientation);

    CV3LastTrustedInterfaceOrientation = orientation;
    self.targetOrientation = orientation;

    if (self.isStashed) {
        CGPoint preferredCenter = CGRectIsEmpty(self.preStashFrame) ? self.center : CGPointMake(CGRectGetMidX(self.preStashFrame), CGRectGetMidY(self.preStashFrame));
        self.preStashFrame = [self restorableFrameForOrientation:orientation preferredCenter:preferredCenter];
        self.baseRotationTransform = targetRotation;
        self.lastLayoutOrientation = orientation;
        self.rootTransformContainer.transform = CGAffineTransformIdentity;
        [self normalizeStashedGrabberLayout];
        return;
    }

    if (!force && !orientationChanged && !rotationChanged) {
        return;
    }

    CGPoint oldCenter = self.center;
    CGSize newSize;
    
    CGRect screenBounds = CV3DisplayBoundsForWindow(self);
    CGFloat portraitW = MIN(screenBounds.size.width, screenBounds.size.height);
    CGFloat portraitH = MAX(screenBounds.size.width, screenBounds.size.height);
    CGFloat screenScale = portraitH / portraitW; // 真机物理分辨率长宽比例

    if (targetIsLandscape) {
        // 横屏状态下：仍维持竖直窗口，仅以可用高度为上限做等比缩放。
        UIEdgeInsets safeArea = [self currentSafeAreaInsets];
        CGFloat breath = CV3Style.safeAreaBreath;
        CGFloat maxH = portraitW - safeArea.top - safeArea.bottom - breath * 2.0;
        CGFloat targetH = MAX(1.0, maxH);
        CGFloat targetW = targetH / MAX(screenScale, 1.0);
        newSize = CGSizeMake(targetW, targetH);
    } else {
        // 竖屏状态下：默认占屏幕宽度的 45%，高度按物理分辨率比例缩放
        CGFloat targetW = portraitW * 0.45;
        newSize = CGSizeMake(targetW, targetW * screenScale);
    }

    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    self.transform = CGAffineTransformIdentity;
    self.bounds = CGRectMake(0, 0, MAX(1.0, newSize.width), MAX(1.0, newSize.height));
    
    self.center = oldCenter;

    self.baseRotationTransform = targetRotation;
    self.rootTransformContainer.transform = targetRotation;
    
    [CATransaction commit];

    // 转屏时将窗口像果冻一样平滑弹跳居中，加入级联偏移防止多窗口重叠，并保证安全区域避让
    if (orientationChanged) {
        NSInteger index = 0;
        if (floatingWindows) {
            index = [floatingWindows indexOfObject:self];
            if (index == NSNotFound) index = 0;
        }
        CGFloat cascade = index * kCV3RotationCascadeStep;
        CGRect displayBounds = CV3DisplayBoundsForWindow(self);
        [UIView animateWithDuration:0.55
                              delay:0
             usingSpringWithDamping:0.48 // 果冻物理阻尼系数
              initialSpringVelocity:0.6
                            options:UIViewAnimationOptionCurveEaseInOut | UIViewAnimationOptionBeginFromCurrentState
                         animations:^{
            self.center = CGPointMake(CGRectGetMidX(displayBounds) + cascade, CGRectGetMidY(displayBounds) + cascade);
            [self clampToScreenBounds];
        } completion:nil];
    }

    self.lastLayoutOrientation = orientation;
    [self syncHostedSceneLayoutForce:YES];
    [self setNeedsLayout];
    [self layoutIfNeeded];
    [self clampToScreenBounds];
    [self syncWindowBoundsToClient];
}

- (void)applyTrustedOrientationNow {
    [self applyInterfaceOrientation:CV3TrustedInterfaceOrientation(self.windowScene) force:NO];
}

- (CGRect)restorableFrameForOrientation:(UIInterfaceOrientation)orientation preferredCenter:(CGPoint)preferredCenter {
    CGRect screenBounds = CV3DisplayBoundsForWindow(self);
    CGFloat portraitW = MIN(screenBounds.size.width, screenBounds.size.height);
    CGFloat portraitH = MAX(screenBounds.size.width, screenBounds.size.height);
    CGFloat screenScale = portraitH / MAX(portraitW, 1.0);

    CGSize targetSize;
    if (UIInterfaceOrientationIsLandscape(orientation)) {
        UIEdgeInsets safeArea = [self currentSafeAreaInsets];
        CGFloat breath = CV3Style.safeAreaBreath;
        CGFloat maxH = portraitW - safeArea.top - safeArea.bottom - breath * 2.0;
        CGFloat targetH = MAX(1.0, maxH);
        CGFloat targetW = targetH / MAX(screenScale, 1.0);
        targetSize = CGSizeMake(targetW, targetH);
    } else {
        CGFloat targetW = portraitW * 0.45;
        targetSize = CGSizeMake(targetW, targetW * screenScale);
    }

    CGRect targetFrame = CGRectMake(preferredCenter.x - targetSize.width * 0.5,
                                    preferredCenter.y - targetSize.height * 0.5,
                                    targetSize.width,
                                    targetSize.height);
    UIEdgeInsets safeArea = [self currentSafeAreaInsets];
    CGFloat breath = CV3Style.safeAreaBreath;
    CGFloat minX = safeArea.left + breath;
    CGFloat minY = safeArea.top + breath;
    CGFloat maxX = screenBounds.size.width - safeArea.right - breath - targetFrame.size.width;
    CGFloat maxY = screenBounds.size.height - safeArea.bottom - breath - targetFrame.size.height;
    if (maxX < minX) maxX = minX;
    if (maxY < minY) maxY = minY;
    targetFrame.origin.x = MIN(MAX(targetFrame.origin.x, minX), maxX);
    targetFrame.origin.y = MIN(MAX(targetFrame.origin.y, minY), maxY);
    return targetFrame;
}

- (CGRect)visiblePortraitContentFrame {
    if (self.rootTransformContainer && !CGRectIsEmpty(self.rootTransformContainer.bounds)) {
        return self.rootTransformContainer.bounds;
    }
    return self.bounds;
}

- (CGRect)currentHostedSceneBounds {
    CGRect rawScreenBounds = [UIScreen mainScreen].bounds;
    CGFloat portraitW = MIN(rawScreenBounds.size.width, rawScreenBounds.size.height);
    CGFloat portraitH = MAX(rawScreenBounds.size.width, rawScreenBounds.size.height);
    return CGRectMake(0, 0, portraitW, portraitH);
}

- (BOOL)applyHostedSceneLayoutToSettings:(id)settings force:(BOOL)force {
    if (!settings) return NO;

    BOOL modified = NO;
    CGRect targetFrame = [self currentHostedSceneBounds];
    // 宿主 App 始终按手机竖屏物理分辨率渲染，外层分屏窗口再统一负责视觉旋转。
    UIInterfaceOrientation targetOrientation = UIInterfaceOrientationPortrait;

    @try {
        if (force ||
            fabs(((FBSMutableSceneSettings *)settings).frame.size.width - targetFrame.size.width) > 0.1 ||
            fabs(((FBSMutableSceneSettings *)settings).frame.size.height - targetFrame.size.height) > 0.1) {
            if ([settings respondsToSelector:@selector(setFrame:)]) {
                [(FBSMutableSceneSettings *)settings setFrame:targetFrame];
                modified = YES;
            }
        }
    } @catch (NSException *e) {}

    NSInteger orientationValue = (NSInteger)targetOrientation;
    modified |= CV3SetIntegerSetting(settings,
                                     @selector(interfaceOrientation),
                                     @selector(setInterfaceOrientation:),
                                     @"interfaceOrientation",
                                     orientationValue,
                                     force);

    UIDeviceOrientation deviceOrientation = UIDeviceOrientationPortrait;
    if (deviceOrientation != UIDeviceOrientationUnknown) {
        modified |= CV3SetIntegerSetting(settings,
                                         @selector(deviceOrientation),
                                         @selector(setDeviceOrientation:),
                                         @"deviceOrientation",
                                         (NSInteger)deviceOrientation,
                                         force);
    }

    modified |= CV3ApplyLockedOrientationTraitsToSettings(settings, targetOrientation, force);

    return modified;
}

- (BOOL)syncHostedSceneLayoutForce:(BOOL)force {
    if (!self.targetScene || self.isClosing || self.isStashed) return NO;

    BOOL didUpdate = NO;
    @try {
        FBSMutableSceneSettings *settings = [[self.targetScene settings] mutableCopy];
        didUpdate = [self applyForegroundSovereigntyToSettings:settings clearDeactivation:YES forceLayout:force];
        if (didUpdate) {
            [CATransaction begin];
            [CATransaction setDisableActions:YES];
            [self.targetScene updateSettings:settings withTransitionContext:nil];
            [CATransaction commit];
            CV3LogToFile(@"[Layout] 已同步托管 Scene 方向=%ld frame=%@", (long)self.targetOrientation, NSStringFromCGRect(((FBSMutableSceneSettings *)settings).frame));
        }
    } @catch (NSException *e) {
        CV3LogToFile(@"[Error] syncHostedSceneLayoutForce 异常: %@", e);
    }

    return didUpdate;
}

- (BOOL)applyForegroundSovereigntyToSettings:(id)settings clearDeactivation:(BOOL)clearDeactivation forceLayout:(BOOL)forceLayout {
    if (!settings) return NO;

    BOOL modified = NO;
    modified |= CV3SetBoolSettingIfNeeded(settings, @selector(setForeground:), @"foreground", YES);
    modified |= CV3SetBoolSettingIfNeeded(settings, @selector(setBackgrounded:), @"backgrounded", NO);
    modified |= CV3SetBoolSettingIfNeeded(settings, NSSelectorFromString(@"setOccluded:"), @"occluded", NO);
    modified |= CV3SetIntegerSettingIfNeeded(settings, NSSelectorFromString(@"setVisibility:"), @"visibility", 2);
    modified |= CV3SetBoolSettingIfNeeded(settings, NSSelectorFromString(@"setIdleTimerDisabled:"), @"idleTimerDisabled", YES);
    modified |= CV3SetIntegerSettingIfNeeded(settings,
                                             @selector(setInterruptionPolicy:),
                                             @"interruptionPolicy",
                                             1);

    if (clearDeactivation) {
        modified |= CV3SetIntegerSettingIfNeeded(settings,
                                                 @selector(setDeactivationReasons:),
                                                 @"deactivationReasons",
                                                 0);
    }

    modified |= [self applyHostedSceneLayoutToSettings:settings force:forceLayout];
    return modified;
}

- (void)stabilizeForegroundForWorkspaceTransition:(NSString *)reason {
    if (!self.targetScene || self.isClosing || self.isStashed) return;

    @try {
        FBSMutableSceneSettings *settings = [[self.targetScene settings] mutableCopy];
        BOOL modified = [self applyForegroundSovereigntyToSettings:settings clearDeactivation:YES forceLayout:NO];
        if (modified) {
            [self.targetScene updateSettings:settings withTransitionContext:nil];
            CV3LogToFile(@"[Continuity] 已稳定分屏前台状态(%@): %@", reason ?: @"Unknown", self.bundleID);
        }

        if ([self.targetScene respondsToSelector:@selector(_setContentState:)]) {
            [self.targetScene _setContentState:2];
        }

        self.hostView.hidden = NO;
        self.hostView.alpha = 1.0;
        if (!self.rbsAssertion) {
            [self updateSovereigntyAssertion];
        }
    } @catch (NSException *e) {
        CV3LogToFile(@"[Error] stabilizeForegroundForWorkspaceTransition 异常: %@", e);
    }
}

- (UIButton *)chromeButtonWithTitle:(NSString *)title action:(SEL)action {
    UIButton *button = [UIButton buttonWithType:UIButtonTypeCustom];
    (void)title;
    button.tintColor = [UIColor clearColor];
    [button setTitle:nil forState:UIControlStateNormal];
    [button setImage:nil forState:UIControlStateNormal];
    button.clipsToBounds = NO;
    
    // 视觉圆点作为子视图居中
    UIView *visualDot = [[UIView alloc] initWithFrame:CGRectZero];
    visualDot.tag = 999;
    visualDot.backgroundColor = [UIColor secondaryLabelColor];
    visualDot.layer.cornerRadius = CV3Style.floatingChromeControlSize / 2.0;
    visualDot.layer.masksToBounds = YES;
    visualDot.layer.borderWidth = 0.5 / [UIScreen mainScreen].scale;
    visualDot.layer.borderColor = [[UIColor blackColor] colorWithAlphaComponent:0.18].CGColor;
    visualDot.userInteractionEnabled = NO;
    [button addSubview:visualDot];
    
    // macOS 交通灯内部图标符号
    NSString *symbolName = nil;
    if (action == @selector(handleChromeCloseAction:)) {
        symbolName = @"xmark";
    } else if (action == @selector(handleChromeMinimizeAction:)) {
        symbolName = @"minus";
    } else if (action == @selector(handleChromeModeAction:)) {
        symbolName = @"plus";
    }
    
    if (symbolName) {
        UIImageView *symbolView = [[UIImageView alloc] initWithFrame:CGRectZero];
        symbolView.tag = 998;
        if (@available(iOS 13.0, *)) {
            UIImageSymbolConfiguration *config = [UIImageSymbolConfiguration configurationWithPointSize:6.0 weight:UIImageSymbolWeightBold scale:UIImageSymbolScaleSmall];
            symbolView.image = [[UIImage systemImageNamed:symbolName withConfiguration:config] imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
        }
        symbolView.tintColor = [[UIColor blackColor] colorWithAlphaComponent:0.55];
        symbolView.contentMode = UIViewContentModeScaleAspectFit;
        symbolView.userInteractionEnabled = NO;
        symbolView.alpha = 0.0; // 默认隐藏，在 touch down 或悬停时显现
        [visualDot addSubview:symbolView];
    }
    
    [button addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];
    return button;
}

- (void)updateFloatingChromeAppearance {
    self.windowChromeView.backgroundColor = [UIColor clearColor];
    self.windowChromeView.layer.cornerRadius = 0;
    self.chromeModeButton.hidden = NO;
    self.chromeMinimizeButton.hidden = NO;
    self.chromeCloseButton.hidden = NO;

    // 去掉药丸把手的视觉背景和描边（使其透明，仅保留手势物理拦截区）
    self.chromeDragHandle.backgroundColor = [UIColor clearColor];
    self.chromeDragHandle.layer.borderColor = [UIColor clearColor].CGColor;
    self.chromeDragHandle.layer.borderWidth = 0.0;
    self.chromeDragHandle.layer.cornerRadius = self.chromeDragHandle.bounds.size.height / 2.0;
    self.chromeDragHandle.clipsToBounds = NO; // 不裁切子圆点的物理缩放交互边界
    
    // 取消生硬投影
    self.chromeDragHandle.layer.shadowColor = [UIColor clearColor].CGColor;
    self.chromeDragHandle.layer.shadowOpacity = 0.0;

    // 默认常态显示经典的交通灯配色 (若窗口失焦则显示置灰颜色)
    NSArray<UIButton *> *buttons = @[self.chromeCloseButton, self.chromeMinimizeButton, self.chromeModeButton];
    for (UIButton *btn in buttons) {
        btn.backgroundColor = [UIColor clearColor]; // 物理按钮自身透明
        btn.layer.borderWidth = 0;
        btn.alpha = 1.0;
        
        UIView *vDot = [btn viewWithTag:999];
        if (vDot) {
            vDot.transform = CGAffineTransformIdentity;
            vDot.layer.borderWidth = 0.5 / [UIScreen mainScreen].scale;
            vDot.layer.borderColor = [[UIColor blackColor] colorWithAlphaComponent:0.12].CGColor;
            
            if (self.isFocused) {
                // 经典交通灯配色
                if (btn == self.chromeCloseButton) {
                    vDot.backgroundColor = [UIColor colorWithRed:1.00 green:0.37 blue:0.33 alpha:1.0]; // macOS 红
                } else if (btn == self.chromeMinimizeButton) {
                    vDot.backgroundColor = [UIColor colorWithRed:1.00 green:0.75 blue:0.18 alpha:1.0]; // macOS 黄
                } else if (btn == self.chromeModeButton) {
                    vDot.backgroundColor = [UIColor colorWithRed:0.15 green:0.79 blue:0.25 alpha:1.0]; // macOS 绿
                }
            } else {
                // 失焦时使用全局样式中定义的灰色
                vDot.backgroundColor = [UIColor colorWithWhite:CV3Style.trafficLightInactiveGray alpha:CV3Style.trafficLightInactiveAlpha];
            }
        }
    }

    [self.windowChromeView sendSubviewToBack:self.chromeDragHandle];
    [self.windowChromeView bringSubviewToFront:self.chromeCloseButton];
    [self.windowChromeView bringSubviewToFront:self.chromeMinimizeButton];
    [self.windowChromeView bringSubviewToFront:self.chromeModeButton];
}

- (void)layoutFloatingChromeForSize:(CGSize)size {
    CGFloat chromeScale = MIN(1.25, MAX(0.72, MIN(size.width, size.height) / 390.0));
    CGFloat chromeH = MIN(44.0 * chromeScale, MAX(0.0, size.height));
    self.windowChromeView.frame = CGRectMake(0, 0, size.width, chromeH);

    // 恒定使用完美的展开比例，取消折叠尺寸
    CGFloat capsuleX = 9.0 * chromeScale;
    CGFloat capsuleY = 6.0 * chromeScale;
    CGFloat capsuleW = CV3Style.windowHandleW * chromeScale;
    CGFloat capsuleH = CV3Style.windowHandleH * chromeScale;
    CGFloat dot = CV3Style.floatingChromeControlSize * chromeScale;

    self.chromeDragHandle.frame = CGRectMake(capsuleX, capsuleY, capsuleW, capsuleH);
    
    // 物理热区进一步放大：按钮高度提升到 54pt，宽度平分胶囊宽度 (capsuleW / 3)
    CGFloat btnW = capsuleW / 3.0;
    CGFloat btnH = 54.0;
    CGFloat btnY = capsuleY + (capsuleH - btnH) / 2.0;
    
    self.chromeCloseButton.frame = CGRectMake(capsuleX + 0 * btnW, btnY, btnW, btnH);
    self.chromeMinimizeButton.frame = CGRectMake(capsuleX + 1 * btnW, btnY, btnW, btnH);
    self.chromeModeButton.frame = CGRectMake(capsuleX + 2 * btnW, btnY, btnW, btnH);
    
    // 重新排列内部的视觉圆点
    NSArray<UIButton *> *buttons = @[self.chromeCloseButton, self.chromeMinimizeButton, self.chromeModeButton];
    for (UIButton *btn in buttons) {
        UIView *vDot = [btn viewWithTag:999];
        if (vDot) {
            // 采用 bounds 和 center 安全定位，规避 transform 状态下赋值 frame 的未定义错乱
            vDot.bounds = CGRectMake(0, 0, dot, dot);
            vDot.center = CGPointMake(btnW / 2.0, btnH / 2.0);
            vDot.layer.cornerRadius = dot / 2.0;
            
            UIView *symbolView = [vDot viewWithTag:998];
            if (symbolView) {
                CGFloat symbolSize = dot * 0.55;
                symbolView.bounds = CGRectMake(0, 0, symbolSize, symbolSize);
                symbolView.center = CGPointMake(dot / 2.0, dot / 2.0);
            }
        }
    }
    
    [self updateFloatingChromeAppearance];
}

- (void)setChromeControlsExpanded:(BOOL)expanded animated:(BOOL)animated {
    self.chromeControlsExpanded = expanded;
    void (^changes)(void) = ^{
        [self layoutFloatingChromeForSize:self.bounds.size];
        [self updateFloatingChromeAppearance];
    };
    if (animated) {
        [UIView animateWithDuration:0.18 delay:0 options:UIViewAnimationOptionCurveEaseOut animations:changes completion:nil];
    } else {
        changes();
    }
}

- (void)scheduleChromeControlsCollapse {
    // 长驻无需折叠
}

- (void)collapseChromeControlsTimerFired:(NSTimer *)timer {
    // 长驻无需折叠
}

- (void)handleChromeControlTouchDown:(id)sender {
    // 长驻无需折叠
}

- (void)handleChromeControlTap:(id)sender {
    // 恒定展开，无需操作
}

- (void)attachMoveLongPressToChromeButton:(UIButton *)button {
    if (!button) return;

    UILongPressGestureRecognizer *moveLongPress = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(handleMoveLongPress:)];
    moveLongPress.minimumPressDuration = 0.22;
    moveLongPress.delegate = self;
    [button addGestureRecognizer:moveLongPress];
}

- (void)handleChromeCloseAction:(id)sender {
    // 隐藏窗口：触发中等关闭震动
    [[[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleMedium] impactOccurred];
    [self closeWindow];
}

- (void)handleChromeMinimizeAction:(id)sender {
    // 隐藏窗口：触发中等关闭震动
    [[[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleMedium] impactOccurred];
    [self handleHideAction];
}

- (void)handleChromeModeAction:(id)sender {
    // 绿色按钮点击时弹出多任务菜单（全屏/所有浮窗/关闭）
    CV3LogToFile(@"[MultitaskingMenu] handleChromeModeAction clicked!");
    [[[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleLight] impactOccurred];
    [self toggleMultitaskingMenu];
}

- (void)chromeBtnTouchDown:(UIButton *)sender {
    // 触发微弱选择震动
    [[[UISelectionFeedbackGenerator alloc] init] selectionChanged];
    [UIView animateWithDuration:0.2 delay:0 options:UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionAllowUserInteraction animations:^{
        UIView *dot = [sender viewWithTag:999];
        if (dot) {
            dot.transform = CGAffineTransformMakeScale(0.82, 0.82);
        }
        
        NSArray<UIButton *> *buttons = @[self.chromeCloseButton, self.chromeMinimizeButton, self.chromeModeButton];
        for (UIButton *btn in buttons) {
            UIView *vDot = [btn viewWithTag:999];
            if (vDot) {
                UIView *sym = [vDot viewWithTag:998];
                if (sym) sym.alpha = 1.0;
            }
        }
    } completion:nil];
}

- (void)chromeBtnTouchUp:(UIButton *)sender {
    [UIView animateWithDuration:0.35 delay:0 usingSpringWithDamping:0.6 initialSpringVelocity:0.5 options:UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionAllowUserInteraction animations:^{
        UIView *dot = [sender viewWithTag:999];
        if (dot) {
            dot.transform = CGAffineTransformIdentity;
        }
        
        NSArray<UIButton *> *buttons = @[self.chromeCloseButton, self.chromeMinimizeButton, self.chromeModeButton];
        for (UIButton *btn in buttons) {
            UIView *vDot = [btn viewWithTag:999];
            if (vDot) {
                UIView *sym = [vDot viewWithTag:998];
                if (sym) sym.alpha = 0.0;
            }
        }
    } completion:nil];
}

- (void)menuBtnTouchDown:(UIButton *)sender {
    [[[UISelectionFeedbackGenerator alloc] init] selectionChanged];
    [UIView animateWithDuration:CV3Style.durationShort delay:0 options:UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionAllowUserInteraction animations:^{
        sender.transform = CGAffineTransformMakeScale(CV3Style.menuBtnScale, CV3Style.menuBtnScale);
        sender.alpha = 0.85;
        
        UIView *hoverBg = [sender viewWithTag:990];
        if (hoverBg) {
            hoverBg.alpha = 1.0;
            
            CAGradientLayer *specular = nil;
            if (hoverBg.layer.sublayers) {
                for (CALayer *sub in hoverBg.layer.sublayers) {
                    if ([[sub valueForKey:@"name"] isEqualToString:@"specular"]) {
                        specular = (CAGradientLayer *)sub;
                        break;
                    }
                }
            }
            if (specular) {
                [specular removeAnimationForKey:@"flow"];
                
                CABasicAnimation *startAnim = [CABasicAnimation animationWithKeyPath:@"startPoint"];
                startAnim.fromValue = [NSValue valueWithCGPoint:CGPointMake(-0.5, -0.5)];
                startAnim.toValue = [NSValue valueWithCGPoint:CGPointMake(1.0, 1.0)];
                
                CABasicAnimation *endAnim = [CABasicAnimation animationWithKeyPath:@"endPoint"];
                endAnim.fromValue = [NSValue valueWithCGPoint:CGPointMake(0.0, 0.0)];
                endAnim.toValue = [NSValue valueWithCGPoint:CGPointMake(1.5, 1.5)];
                
                CAAnimationGroup *group = [CAAnimationGroup animation];
                group.animations = @[startAnim, endAnim];
                group.duration = CV3Style.menuAnimDuration;
                group.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut];
                group.fillMode = kCAFillModeForwards;
                group.removedOnCompletion = NO;
                [specular addAnimation:group forKey:@"flow"];
            }
        }
    } completion:nil];
}

- (void)menuBtnTouchUp:(UIButton *)sender {
    [UIView animateWithDuration:CV3Style.durationMedium delay:0 usingSpringWithDamping:CV3Style.springDamping initialSpringVelocity:CV3Style.springVelocity options:UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionAllowUserInteraction animations:^{
        sender.transform = CGAffineTransformIdentity;
        sender.alpha = 1.0;
        
        UIView *hoverBg = [sender viewWithTag:990];
        if (hoverBg) {
            hoverBg.alpha = 0.0;
            
            if (hoverBg.layer.sublayers) {
                for (CALayer *sub in hoverBg.layer.sublayers) {
                    if ([[sub valueForKey:@"name"] isEqualToString:@"specular"]) {
                        [sub removeAnimationForKey:@"flow"];
                        break;
                    }
                }
            }
        }
    } completion:nil];
}

- (void)createFloatingHomeBarIfNeeded {
    if (self.homeBarView) return;

    UIView *bar = [[UIView alloc] initWithFrame:CGRectZero];
    bar.userInteractionEnabled = YES;
    bar.backgroundColor = [UIColor clearColor];
    bar.layer.shadowColor = [UIColor blackColor].CGColor;
    bar.layer.shadowOffset = CGSizeMake(0, 6);
    bar.layer.shadowOpacity = 0.16;
    bar.layer.shadowRadius = 14.0;

    UIVisualEffectView *blurView = [[UIVisualEffectView alloc] initWithEffect:[UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemChromeMaterial]];
    blurView.userInteractionEnabled = NO;
    blurView.clipsToBounds = YES;
    [bar addSubview:blurView];

    CAGradientLayer *glow = [CAGradientLayer layer];
    glow.startPoint = CGPointMake(0.0, 0.5);
    glow.endPoint = CGPointMake(1.0, 0.5);
    [bar.layer insertSublayer:glow atIndex:0];

    UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handleHomeBarTap:)];
    UILongPressGestureRecognizer *move = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(handleMoveLongPress:)];
    move.minimumPressDuration = 0.22;
    move.allowableMovement = 24.0;
    move.delegate = self;
    UIPanGestureRecognizer *resizePan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handleHomeBarResizePan:)];
    resizePan.delegate = self;

    [tap requireGestureRecognizerToFail:move];
    [tap requireGestureRecognizerToFail:resizePan];
    [bar addGestureRecognizer:tap];
    [bar addGestureRecognizer:move];
    [bar addGestureRecognizer:resizePan];

    self.homeBarView = bar;
    self.homeBarBlurView = blurView;
    self.homeBarGlowLayer = glow;
    self.homeBarPlacement = 0;
    UIView *homeBarContainer = self.appContentWrapper ?: self;
    [homeBarContainer addSubview:self.homeBarView];
    [self updateFloatingHomeBarAppearance];
}

- (NSInteger)preferredHomeBarPlacementForScreenFrame:(CGRect)frame {
    UIEdgeInsets safeArea = [self currentSafeAreaInsets];
    CGRect screenBounds = CV3DisplayBoundsForWindow(self);

    NSInteger bestScreenPlacement = 0;
    CGFloat clearances[4] = {
        MAX(0.0, screenBounds.size.height - safeArea.bottom - CGRectGetMaxY(frame)),
        MAX(0.0, CGRectGetMinY(frame) - safeArea.top),
        MAX(0.0, screenBounds.size.width - safeArea.right - CGRectGetMaxX(frame)),
        MAX(0.0, CGRectGetMinX(frame) - safeArea.left)
    };
    CGFloat largestClearance = clearances[0];
    for (NSInteger i = 1; i < 4; i++) {
        if (clearances[i] > largestClearance) {
            largestClearance = clearances[i];
            bestScreenPlacement = i;
        }
    }

    UIInterfaceOrientation orientation = self.targetOrientation;
    if (!CV3IsValidInterfaceOrientation(orientation)) {
        orientation = CV3TrustedInterfaceOrientation(self.windowScene);
    }

    // Placement ids are local to appContentWrapper:
    // 0 bottom, 1 top, 2 right, 3 left. The clearance calculation above is in
    // screen space, so rotate the selected screen edge back into local space.
    switch (orientation) {
        case UIInterfaceOrientationLandscapeLeft: {
            static const NSInteger map[4] = {3, 2, 0, 1};
            return map[bestScreenPlacement];
        }
        case UIInterfaceOrientationLandscapeRight: {
            static const NSInteger map[4] = {2, 3, 1, 0};
            return map[bestScreenPlacement];
        }
        case UIInterfaceOrientationPortraitUpsideDown: {
            static const NSInteger map[4] = {1, 0, 3, 2};
            return map[bestScreenPlacement];
        }
        case UIInterfaceOrientationPortrait:
        default:
            return bestScreenPlacement;
    }
}

- (CGRect)orientedDisplayBoundsForCurrentOrientation {
    CGRect screenBounds = CV3DisplayBoundsForWindow(self);
    CGFloat shortSide = MIN(screenBounds.size.width, screenBounds.size.height);
    CGFloat longSide = MAX(screenBounds.size.width, screenBounds.size.height);
    UIInterfaceOrientation orientation = self.targetOrientation;
    if (!CV3IsValidInterfaceOrientation(orientation)) {
        orientation = CV3TrustedInterfaceOrientation(self.windowScene);
    }

    CGSize orientedSize = UIInterfaceOrientationIsLandscape(orientation)
        ? CGSizeMake(longSide, shortSide)
        : CGSizeMake(shortSide, longSide);
    return CGRectMake(0, 0, orientedSize.width, orientedSize.height);
}

- (void)homeBarResizeLimitsForAspect:(CGFloat)aspect minWidth:(CGFloat *)minWidth maxWidth:(CGFloat *)maxWidth {
    CGRect screenBounds = [self orientedDisplayBoundsForCurrentOrientation];
    UIEdgeInsets safeArea = [self currentSafeAreaInsets];
    CGFloat breath = CV3Style.safeAreaBreath;
    CGFloat shortSide = MIN(screenBounds.size.width, screenBounds.size.height);
    CGFloat visibleWidth = MAX(1.0, screenBounds.size.width - safeArea.left - safeArea.right - breath * 2.0);
    CGFloat visibleHeight = MAX(1.0, screenBounds.size.height - safeArea.top - safeArea.bottom - breath * 2.0);
    CGFloat minW = shortSide * 0.4;
    CGFloat maxW = shortSide * 0.75;

    maxW = MIN(maxW, visibleWidth);
    maxW = MIN(maxW, visibleHeight / MAX(aspect, 1.0));
    if (maxW < minW) minW = maxW;

    if (minWidth) *minWidth = MAX(1.0, minW);
    if (maxWidth) *maxWidth = MAX(1.0, maxW);
}

- (CGRect)constrainedFloatingFrameForSize:(CGSize)size preferredCenter:(CGPoint)center {
    CGRect screenBounds = [self orientedDisplayBoundsForCurrentOrientation];
    UIEdgeInsets safeArea = [self currentSafeAreaInsets];
    CGFloat breath = CV3Style.safeAreaBreath;
    CGRect frame = CGRectMake(center.x - size.width * 0.5,
                              center.y - size.height * 0.5,
                              size.width,
                              size.height);
    CGFloat minX = safeArea.left + breath;
    CGFloat minY = safeArea.top + breath;
    CGFloat maxX = screenBounds.size.width - safeArea.right - breath - size.width;
    CGFloat maxY = screenBounds.size.height - safeArea.bottom - breath - size.height;

    if (maxX < minX) maxX = minX;
    if (maxY < minY) maxY = minY;
    frame.origin.x = MIN(MAX(frame.origin.x, minX), maxX);
    frame.origin.y = MIN(MAX(frame.origin.y, minY), maxY);
    return frame;
}

- (void)startHomeBarResizeSessionIfNeeded {
    if (self.isLiveResizing) return;

    UIImpactFeedbackGenerator *gen = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleLight];
    [gen impactOccurred];

    self.isLiveResizing = YES;
    [self visualShadowLayer].shadowPath = nil;
    [self startLiquidMotion];
    [UIView animateWithDuration:0.2 animations:^{
        [self visualShadowLayer].shadowOpacity = CV3Style.shadowOpacityUnfocused * 0.5;
        self.glassBackdrop.effect = nil;
        self.glassBackdrop.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.2];
    }];

    if (self.hostView) {
        self.liveResizeSnapshotView = [self.hostView snapshotViewAfterScreenUpdates:NO];
        if (self.liveResizeSnapshotView) {
            self.liveResizeSnapshotView.frame = self.hostContainerProxy.bounds;
            self.liveResizeSnapshotView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
            [self.hostContainerProxy addSubview:self.liveResizeSnapshotView];
            self.hostView.alpha = 0;
        }
    }

    if (self.targetScene) {
        @try {
            FBSMutableSceneSettings *settings = [[self.targetScene settings] mutableCopy];
            if ([settings respondsToSelector:@selector(setInLiveResize:)]) {
                [(UIMutableApplicationSceneSettings *)settings setInLiveResize:YES];
                [self.targetScene updateSettings:settings withTransitionContext:nil];
            }
        } @catch (NSException *e) {
            CV3LogToFile(@"[Critical] Failed to set home bar live resize state: %@", e);
        }
    }
}

- (void)updateFloatingHomeBarAppearance {
    if (!self.homeBarView || !self.homeBarBlurView) return;

    CGFloat alpha = self.isFocused ? 1.0 : 0.84;
    self.homeBarView.alpha = (self.isStashed || self.isClosing) ? 0.0 : alpha;

    UIColor *tintColor = self.adaptiveAppColor ?: [UIColor labelColor];
    CGFloat hue = 0, saturation = 0, brightness = 0, componentAlpha = 0;
    if ([tintColor getHue:&hue saturation:&saturation brightness:&brightness alpha:&componentAlpha]) {
        saturation = MIN(0.58, MAX(0.16, saturation));
        brightness = self.isFocused ? MIN(0.92, MAX(0.60, brightness)) : MIN(0.72, MAX(0.42, brightness));
        tintColor = [UIColor colorWithHue:hue saturation:saturation brightness:brightness alpha:1.0];
    }

    self.homeBarView.layer.shadowOpacity = self.isFocused ? 0.18 : 0.10;
    self.homeBarView.layer.shadowRadius = self.isFocused ? 16.0 : 10.0;
    self.homeBarBlurView.contentView.backgroundColor = [[UIColor whiteColor] colorWithAlphaComponent:self.isFocused ? 0.08 : 0.04];
    self.homeBarGlowLayer.colors = @[
        (id)[tintColor colorWithAlphaComponent:0.00].CGColor,
        (id)[tintColor colorWithAlphaComponent:self.isFocused ? 0.32 : 0.18].CGColor,
        (id)[tintColor colorWithAlphaComponent:0.00].CGColor
    ];
}

- (void)layoutFloatingHomeBarForBounds:(CGRect)bounds {
    [self createFloatingHomeBarIfNeeded];
    if (!self.homeBarView) return;

    CGFloat minEdge = MIN(bounds.size.width, bounds.size.height);
    CGFloat scale = MIN(1.18, MAX(0.82, minEdge / 390.0));
    CGFloat barLength = 56.0 * scale;
    CGFloat barThickness = 18.0 * scale;
    CGFloat protrusion = MAX(4.0, barThickness * 0.42);

    self.homeBarPlacement = [self preferredHomeBarPlacementForScreenFrame:self.frame];
    self.homeBarView.bounds = CGRectMake(0, 0, barLength, barThickness);
    self.homeBarBlurView.frame = self.homeBarView.bounds;
    self.homeBarBlurView.layer.cornerRadius = barThickness / 2.0;
    self.homeBarGlowLayer.frame = self.homeBarView.bounds;
    self.homeBarGlowLayer.cornerRadius = barThickness / 2.0;

    CGPoint center = CGPointMake(CGRectGetMidX(bounds), CGRectGetMaxY(bounds) - barThickness * 0.5 + protrusion);
    CGAffineTransform orientationTransform = CGAffineTransformIdentity;
    if (self.homeBarPlacement == 1) {
        center = CGPointMake(CGRectGetMidX(bounds), barThickness * 0.5 - protrusion);
    } else if (self.homeBarPlacement == 2) {
        center = CGPointMake(CGRectGetMaxX(bounds) - barThickness * 0.5 + protrusion, CGRectGetMidY(bounds));
        orientationTransform = CGAffineTransformMakeRotation((CGFloat)(M_PI_2));
    } else if (self.homeBarPlacement == 3) {
        center = CGPointMake(barThickness * 0.5 - protrusion, CGRectGetMidY(bounds));
        orientationTransform = CGAffineTransformMakeRotation((CGFloat)(M_PI_2));
    }

    self.homeBarView.center = center;
    self.homeBarView.transform = orientationTransform;
    [self updateFloatingHomeBarAppearance];
    [self.homeBarView.superview bringSubviewToFront:self.homeBarView];
}

- (void)handleHomeBarTap:(UITapGestureRecognizer *)gesture {
    if (gesture.state != UIGestureRecognizerStateEnded || self.isClosing || self.isStashed) return;
    [[[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleLight] impactOccurred];
    [self handleHideAction];
}

- (void)handleHomeBarResizePan:(UIPanGestureRecognizer *)gesture {
    static CGFloat lastHapticOvershoot = 0;
    static BOOL hasTriggeredTopHaptic = NO;
    static BOOL hasTriggeredBottomHaptic = NO;
    static BOOL hasTriggeredSideHaptic = NO;

    if (self.isClosing || self.isStashed) return;

    if (gesture.state == UIGestureRecognizerStateBegan) {
        self.isFullscreenMode = NO;
        self.isCompactMode = NO;
        self.initialResizeFrame = self.frame;
        self.homeBarResizeStartPlacement = self.homeBarPlacement;
        CGPoint axis = CGPointMake(1.0, 0.0);
        if (self.homeBarView) {
            CGRect barBounds = self.homeBarView.bounds;
            CGPoint left = [self.homeBarView convertPoint:CGPointMake(CGRectGetMinX(barBounds), CGRectGetMidY(barBounds)) toView:nil];
            CGPoint right = [self.homeBarView convertPoint:CGPointMake(CGRectGetMaxX(barBounds), CGRectGetMidY(barBounds)) toView:nil];
            axis = CGPointMake(right.x - left.x, right.y - left.y);
            CGFloat length = sqrt(axis.x * axis.x + axis.y * axis.y);
            if (length > 0.1) {
                axis.x /= length;
                axis.y /= length;
            } else {
                axis = CGPointMake(1.0, 0.0);
            }
        }
        if (self.homeBarResizeStartPlacement == 2 || self.homeBarResizeStartPlacement == 3) {
            axis.x = -axis.x;
            axis.y = -axis.y;
        }
        self.homeBarResizeAxis = axis;
        CGPoint commandAxis = CGPointMake(-axis.y, axis.x);
        if (self.homeBarView) {
            UIView *container = self.homeBarView.superview ?: self.appContentWrapper ?: self;
            CGPoint contentCenter = [container convertPoint:CGPointMake(CGRectGetMidX(container.bounds), CGRectGetMidY(container.bounds)) toView:nil];
            CGPoint barCenter = [self.homeBarView convertPoint:CGPointMake(CGRectGetMidX(self.homeBarView.bounds), CGRectGetMidY(self.homeBarView.bounds)) toView:nil];
            commandAxis = CGPointMake(barCenter.x - contentCenter.x, barCenter.y - contentCenter.y);
            CGFloat commandLength = sqrt(commandAxis.x * commandAxis.x + commandAxis.y * commandAxis.y);
            if (commandLength > 0.1) {
                commandAxis.x /= commandLength;
                commandAxis.y /= commandLength;
            } else {
                commandAxis = CGPointMake(-axis.y, axis.x);
            }
        }
        CGFloat dot = commandAxis.x * axis.x + commandAxis.y * axis.y;
        commandAxis = CGPointMake(commandAxis.x - axis.x * dot, commandAxis.y - axis.y * dot);
        CGFloat commandAxisLength = sqrt(commandAxis.x * commandAxis.x + commandAxis.y * commandAxis.y);
        if (commandAxisLength > 0.1) {
            commandAxis.x /= commandAxisLength;
            commandAxis.y /= commandAxisLength;
        } else {
            commandAxis = CGPointMake(-axis.y, axis.x);
        }
        self.homeBarCommandAxis = commandAxis;
        [gesture setTranslation:CGPointZero inView:nil];
        lastHapticOvershoot = 0;
        hasTriggeredTopHaptic = NO;
        hasTriggeredBottomHaptic = NO;
        hasTriggeredSideHaptic = NO;
        self.homeBarPanMode = 0;
        self.homeBarCommandProjection = 0.0;
    }

    CGPoint translation = [gesture translationInView:nil];

    if (gesture.state == UIGestureRecognizerStateChanged) {
        CGRect screenBounds = [self orientedDisplayBoundsForCurrentOrientation];
        CGFloat shortSide = MIN(screenBounds.size.width, screenBounds.size.height);
        CGFloat longSide = MAX(screenBounds.size.width, screenBounds.size.height);
        CGFloat aspect = longSide / MAX(shortSide, 1.0);
        CGFloat minAllowedWidth = 1.0;
        CGFloat maxAllowedWidth = 1.0;
        [self homeBarResizeLimitsForAspect:aspect minWidth:&minAllowedWidth maxWidth:&maxAllowedWidth];

        CGPoint axis = self.homeBarResizeAxis;
        CGFloat axisLength = sqrt(axis.x * axis.x + axis.y * axis.y);
        if (axisLength < 0.1) {
            axis = CGPointMake(1.0, 0.0);
        }
        CGFloat dominantTranslation = translation.x * axis.x + translation.y * axis.y;
        CGPoint commandAxis = self.homeBarCommandAxis;
        CGFloat commandAxisLength = sqrt(commandAxis.x * commandAxis.x + commandAxis.y * commandAxis.y);
        if (commandAxisLength < 0.1) {
            commandAxis = CGPointMake(-axis.y, axis.x);
        }
        CGFloat commandTranslation = translation.x * commandAxis.x + translation.y * commandAxis.y;

        if (self.homeBarPanMode == 0) {
            CGFloat movement = sqrt(translation.x * translation.x + translation.y * translation.y);
            if (movement < 8.0) return;

            if (fabs(commandTranslation) > fabs(dominantTranslation) * 1.15) {
                self.homeBarPanMode = 2;
                self.homeBarCommandProjection = commandTranslation;
                UIImpactFeedbackGenerator *gen = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleLight];
                [gen impactOccurred];
                return;
            }

            self.homeBarPanMode = 1;
            [self startHomeBarResizeSessionIfNeeded];
        }

        if (self.homeBarPanMode == 2) {
            self.homeBarCommandProjection = commandTranslation;
            return;
        }

        CGFloat initialLogicalWidth = self.initialResizeFrame.size.width;
        CGFloat targetWidth = initialLogicalWidth + dominantTranslation * 0.9;

        CGFloat overshoot = 0;
        if (targetWidth < minAllowedWidth) overshoot = (minAllowedWidth - targetWidth) / (minAllowedWidth * 0.2);
        else if (targetWidth > maxAllowedWidth) overshoot = (targetWidth - maxAllowedWidth) / (maxAllowedWidth * 0.2);

        if (overshoot > 0.05 && fabs(overshoot - lastHapticOvershoot) > 0.1) {
            UIImpactFeedbackGenerator *gradientGen = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleLight];
            [gradientGen impactOccurredWithIntensity:MIN(1.0, overshoot)];
            lastHapticOvershoot = overshoot;
        } else if (overshoot <= 0.05) {
            lastHapticOvershoot = 0;
        }

        NSArray *windowsSnapshot = [floatingWindows copy];
        for (CV3FloatingAppWindow *other in windowsSnapshot) {
            if (other == self || other.isStashed || ![other isKindOfClass:[CV3FloatingAppWindow class]]) continue;

            CGFloat distance = sqrt(pow(self.center.x - other.center.x, 2) + pow(self.center.y - other.center.y, 2));
            CGFloat minGap = (self.bounds.size.width + other.bounds.size.width) / 2.0 + 20.0;
            if (distance < minGap) {
                targetWidth *= (0.8 + 0.2 * (distance / minGap));
            }
        }

        CGFloat finalWidth = MIN(MAX(targetWidth, minAllowedWidth), maxAllowedWidth);

        CGFloat finalHeight = finalWidth * aspect;
        CGPoint preferredCenter = CGPointMake(CGRectGetMidX(self.initialResizeFrame), CGRectGetMidY(self.initialResizeFrame));
        CGRect newFrame = [self constrainedFloatingFrameForSize:CGSizeMake(finalWidth, finalHeight) preferredCenter:preferredCenter];

        UIEdgeInsets safeArea = [self currentSafeAreaInsets];
        if (newFrame.origin.y < safeArea.top && !hasTriggeredTopHaptic) {
            [[[UISelectionFeedbackGenerator alloc] init] selectionChanged];
            hasTriggeredTopHaptic = YES;
        } else if (newFrame.origin.y >= safeArea.top) {
            hasTriggeredTopHaptic = NO;
        }

        if (CGRectGetMaxY(newFrame) > screenBounds.size.height - safeArea.bottom && !hasTriggeredBottomHaptic) {
            [[[UISelectionFeedbackGenerator alloc] init] selectionChanged];
            hasTriggeredBottomHaptic = YES;
        } else if (CGRectGetMaxY(newFrame) <= screenBounds.size.height - safeArea.bottom) {
            hasTriggeredBottomHaptic = NO;
        }

        BOOL hitSide = (newFrame.origin.x < safeArea.left || CGRectGetMaxX(newFrame) > screenBounds.size.width - safeArea.right);
        if (hitSide && !hasTriggeredSideHaptic) {
            [[[UISelectionFeedbackGenerator alloc] init] selectionChanged];
            hasTriggeredSideHaptic = YES;
        } else if (!hitSide) {
            hasTriggeredSideHaptic = NO;
        }

        [CATransaction begin];
        [CATransaction setDisableActions:YES];
        self.bounds = CGRectMake(0, 0, newFrame.size.width, newFrame.size.height);
        self.center = CGPointMake(CGRectGetMidX(newFrame), CGRectGetMidY(newFrame));
        [self layoutFloatingHomeBarForBounds:self.appContentWrapper.bounds];
        [CATransaction commit];
        [self syncWindowBoundsToClientAndNotify:NO];
    }

    if (gesture.state == UIGestureRecognizerStateEnded ||
        gesture.state == UIGestureRecognizerStateCancelled ||
        gesture.state == UIGestureRecognizerStateFailed) {
        if (self.homeBarPanMode == 2) {
            CGPoint velocity = [gesture velocityInView:nil];
            CGPoint commandAxis = self.homeBarCommandAxis;
            CGFloat commandAxisLength = sqrt(commandAxis.x * commandAxis.x + commandAxis.y * commandAxis.y);
            if (commandAxisLength < 0.1) {
                CGPoint axis = self.homeBarResizeAxis;
                CGFloat axisLength = sqrt(axis.x * axis.x + axis.y * axis.y);
                if (axisLength < 0.1) axis = CGPointMake(1.0, 0.0);
                commandAxis = CGPointMake(-axis.y, axis.x);
            }
            CGFloat commandVelocity = velocity.x * commandAxis.x + velocity.y * commandAxis.y;
            CGFloat commandProjection = self.homeBarCommandProjection;
            self.homeBarPanMode = 0;
            self.homeBarCommandProjection = 0.0;

            if (gesture.state == UIGestureRecognizerStateEnded &&
                (fabs(commandProjection) > 42.0 || fabs(commandVelocity) > 520.0)) {
                CGFloat commandSignal = fabs(commandVelocity) > 520.0 ? commandVelocity : commandProjection;
                [[[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleMedium] impactOccurred];
                if (commandSignal > 0.0) {
                    [self activateHostedAppFullscreenAndClose];
                } else {
                    CV3ToggleExposeMode();
                }
            }
            return;
        }

        if (self.homeBarPanMode == 0 || !self.isLiveResizing) {
            self.homeBarPanMode = 0;
            self.homeBarCommandProjection = 0.0;
            return;
        }

        self.homeBarPanMode = 0;
        self.homeBarCommandProjection = 0.0;
        [self stopLiquidMotion];

        if (gesture.state != UIGestureRecognizerStateEnded) {
            self.isLiveResizing = NO;
            CGFloat minEdge = MIN(self.bounds.size.width, self.bounds.size.height);
            CGFloat finalRadius = MAX(CV3Style.adaptiveCornerRadiusMin, MIN(CV3Style.adaptiveCornerRadiusMax, minEdge * CV3Style.adaptiveCornerRadiusRatio));
            [self visualShadowLayer].shadowPath = [UIBezierPath bezierPathWithRoundedRect:[self currentVisualShadowFrame] cornerRadius:finalRadius].CGPath;
            [self animateFocusShadow:self.isFocused];
            [UIView animateWithDuration:0.4 delay:0 options:UIViewAnimationOptionCurveEaseInOut animations:^{
                self.glassBackdrop.effect = [UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemThinMaterial];
                self.glassBackdrop.backgroundColor = [UIColor clearColor];
            } completion:nil];
        }

        CGRect screenBounds = [self orientedDisplayBoundsForCurrentOrientation];
        CGFloat shortSide = MIN(screenBounds.size.width, screenBounds.size.height);
        CGFloat longSide = MAX(screenBounds.size.width, screenBounds.size.height);
        CGFloat aspect = longSide / MAX(shortSide, 1.0);
        CGPoint initialCenter = CGPointMake(CGRectGetMidX(self.frame), CGRectGetMidY(self.frame));
        UIEdgeInsets safeArea = [self currentSafeAreaInsets];

        if (self.targetScene) {
            @try {
                FBSMutableSceneSettings *settings = [[self.targetScene settings] mutableCopy];
                if ([settings respondsToSelector:@selector(setInLiveResize:)]) {
                    [(UIMutableApplicationSceneSettings *)settings setInLiveResize:NO];
                    [self.targetScene updateSettings:settings withTransitionContext:nil];
                }
                [self setNeedsLayout];
                [self layoutIfNeeded];
            } @catch (NSException *e) {}
        }

        UIView *snapshot = self.liveResizeSnapshotView;
        self.liveResizeSnapshotView = nil;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.15 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [UIView animateWithDuration:0.4 delay:0 options:UIViewAnimationOptionCurveEaseInOut animations:^{
                self.hostView.alpha = 1.0;
                if (snapshot) snapshot.alpha = 0;
            } completion:^(BOOL finished) {
                [snapshot removeFromSuperview];
            }];
        });

        if (gesture.state == UIGestureRecognizerStateEnded) {
            CGFloat finalWidth = self.bounds.size.width;
            CGPoint velocity = [gesture velocityInView:nil];
            CGPoint axis = self.homeBarResizeAxis;
            CGFloat axisLength = sqrt(axis.x * axis.x + axis.y * axis.y);
            if (axisLength < 0.1) axis = CGPointMake(1.0, 0.0);
            CGFloat axisVelocity = velocity.x * axis.x + velocity.y * axis.y;
            if (fabs(axisVelocity) > 300.0) {
                finalWidth += axisVelocity * 0.015;
            }

            CGFloat minAllowedWidth = 1.0;
            CGFloat maxAllowedWidth = 1.0;
            [self homeBarResizeLimitsForAspect:aspect minWidth:&minAllowedWidth maxWidth:&maxAllowedWidth];
            finalWidth = MAX(minAllowedWidth, MIN(maxAllowedWidth, finalWidth));

            CGFloat previousLogicalWidth = finalWidth;
            CGRect snapFrame = self.frame;
            CGFloat snapThreshold = 25.0;
            if (fabs(snapFrame.origin.y - safeArea.top) < snapThreshold) {
                snapFrame.origin.y = safeArea.top;
                [[[UISelectionFeedbackGenerator alloc] init] selectionChanged];
            }

            CGFloat currentRatio = finalWidth / shortSide;
            if (fabs(currentRatio - 0.5) < 0.03) finalWidth = shortSide * 0.5;
            else if (fabs(currentRatio - 0.75) < 0.03) finalWidth = shortSide * 0.75;
            finalWidth = MAX(minAllowedWidth, MIN(maxAllowedWidth, finalWidth));

            CGFloat finalHeight = finalWidth * aspect;
            CGSize finalSize = CGSizeMake(finalWidth, finalHeight);
            snapFrame.size = finalSize;

            if (fabs(finalWidth - previousLogicalWidth) > 0.1) {
                snapFrame.origin.x = initialCenter.x - finalWidth / 2.0;
                snapFrame.origin.y = initialCenter.y - finalHeight / 2.0;
                [[[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleMedium] impactOccurred];
            }

            snapFrame = [self constrainedFloatingFrameForSize:finalSize preferredCenter:CGPointMake(CGRectGetMidX(snapFrame), CGRectGetMidY(snapFrame))];

            CGFloat springVelocity = MIN(4.0, MAX(0.5, fabs(axisVelocity) / 800.0));
            [UIView animateWithDuration:0.5 delay:0 usingSpringWithDamping:0.75 initialSpringVelocity:springVelocity options:0 animations:^{
                self.bounds = CGRectMake(0, 0, snapFrame.size.width, snapFrame.size.height);
                self.center = CGPointMake(CGRectGetMidX(snapFrame), CGRectGetMidY(snapFrame));
                [self setNeedsLayout];
                [self layoutIfNeeded];
                [self layoutFloatingHomeBarForBounds:self.appContentWrapper.bounds];
            } completion:^(BOOL finished) {
                self.isLiveResizing = NO;
                CGFloat minEdge = MIN(self.bounds.size.width, self.bounds.size.height);
                CGFloat finalRadius = MAX(CV3Style.adaptiveCornerRadiusMin, MIN(CV3Style.adaptiveCornerRadiusMax, minEdge * CV3Style.adaptiveCornerRadiusRatio));
                [self visualShadowLayer].shadowPath = [UIBezierPath bezierPathWithRoundedRect:[self currentVisualShadowFrame] cornerRadius:finalRadius].CGPath;
                [UIView animateWithDuration:0.4 delay:0 options:UIViewAnimationOptionCurveEaseInOut animations:^{
                    self.glassBackdrop.effect = [UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemThinMaterial];
                    self.glassBackdrop.backgroundColor = [UIColor clearColor];
                } completion:nil];
                [self syncWindowBoundsToClientAndNotify:YES];
                [self syncWindowShadowForCurrentState];
            }];

            [self animateFocusShadow:self.isFocused];
        }
    }
}

- (void)activateHostedAppFullscreenAndClose {
    if (self.isClosing || self.bundleID.length == 0) return;

    NSString *bundleID = [self.bundleID copy];
    [self closeWindow];

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0), ^{
        @try {
            if ([[UIApplication sharedApplication] respondsToSelector:@selector(launchApplicationWithIdentifier:suspended:)]) {
                [[UIApplication sharedApplication] launchApplicationWithIdentifier:bundleID suspended:NO];
            } else {
                [[CV3ClassNamed(@"LSApplicationWorkspace") defaultWorkspace] openApplicationWithBundleID:bundleID];
            }
        } @catch (NSException *e) {
            CV3LogToFile(@"[HomeBar] 打开全屏应用失败 %@: %@", bundleID, e);
            [[CV3ClassNamed(@"LSApplicationWorkspace") defaultWorkspace] openApplicationWithBundleID:bundleID];
        }
    });
}

- (UIButton *)multitaskingMenuButtonWithTitle:(NSString *)title symbol:(NSString *)symbol action:(SEL)action {
    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    button.tintColor = [UIColor labelColor];
    button.titleLabel.font = [UIFont systemFontOfSize:CV3Style.multitaskingMenuFontSize weight:UIFontWeightSemibold];
    button.titleLabel.numberOfLines = 1;
    button.backgroundColor = [UIColor clearColor];
    button.layer.cornerRadius = 10.0;
    
    // 增加精致的半透明圆角选项背景层（Hover/Touch 高亮跟随）
    UIView *hoverBg = [[UIView alloc] initWithFrame:CGRectZero];
    hoverBg.tag = 990;
    hoverBg.backgroundColor = [[UIColor labelColor] colorWithAlphaComponent:0.07];
    hoverBg.layer.cornerRadius = 8.0;
    if (@available(iOS 13.0, *)) {
        hoverBg.layer.cornerCurve = kCACornerCurveContinuous;
    }
    hoverBg.userInteractionEnabled = NO;
    hoverBg.alpha = 0.0;
    [button addSubview:hoverBg];
    
    // 增加金属反射流光层 (Metallic Specular Flow)
    CAGradientLayer *specular = [CAGradientLayer layer];
    [specular setValue:@"specular" forKey:@"name"];
    specular.colors = @[(id)[UIColor clearColor].CGColor,
                        (id)[[UIColor whiteColor] colorWithAlphaComponent:CV3Style.menuSpecularAlpha].CGColor,
                        (id)[UIColor clearColor].CGColor];
    specular.startPoint = CGPointMake(-0.5, -0.5);
    specular.endPoint = CGPointMake(0.0, 0.0);
    specular.locations = @[@0.0, @0.5, @1.0];
    [hoverBg.layer addSublayer:specular];
    
    if (@available(iOS 13.0, *)) {
        // 使用配置好的 icon 尺寸，防止大尺寸 SF Symbol 挤占或遮挡文字
        UIImageSymbolConfiguration *config = [UIImageSymbolConfiguration configurationWithPointSize:CV3Style.multitaskingMenuIconSize weight:UIImageSymbolWeightMedium scale:UIImageSymbolScaleSmall];
        UIImage *image = [UIImage systemImageNamed:symbol withConfiguration:config];
        [button setImage:image forState:UIControlStateNormal];
    }
    [button setTitle:[NSString stringWithFormat:@" %@", title] forState:UIControlStateNormal];
    [button setTitleColor:[UIColor labelColor] forState:UIControlStateNormal];
    [button addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];
    
    // 连接触控物理收缩反馈
    [button addTarget:self action:@selector(menuBtnTouchDown:) forControlEvents:UIControlEventTouchDown | UIControlEventTouchDragEnter];
    [button addTarget:self action:@selector(menuBtnTouchUp:) forControlEvents:UIControlEventTouchUpInside | UIControlEventTouchUpOutside | UIControlEventTouchCancel | UIControlEventTouchDragExit];
    
    return button;
}

- (void)toggleMultitaskingMenu {
    CV3LogToFile(@"[MultitaskingMenu] toggleMultitaskingMenu entered. menuView = %@, hidden = %d", self.multitaskingMenuView, self.multitaskingMenuView ? self.multitaskingMenuView.hidden : -1);
    if (self.multitaskingMenuView && !self.multitaskingMenuView.hidden) {
        CV3LogToFile(@"[MultitaskingMenu] menuView already visible, dismissing");
        [self dismissMultitaskingMenu];
        return;
    }

    if (!self.multitaskingMenuView) {
        CV3LogToFile(@"[MultitaskingMenu] Creating multitaskingMenuView...");
        UIBlurEffect *effect = [UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemMaterial];
        self.multitaskingMenuView = [[UIVisualEffectView alloc] initWithEffect:effect];
        self.multitaskingMenuView.clipsToBounds = YES;
        self.multitaskingMenuView.layer.cornerRadius = 16.0;
        if (@available(iOS 13.0, *)) {
            self.multitaskingMenuView.layer.cornerCurve = kCACornerCurveContinuous;
        }
        self.multitaskingMenuView.layer.shadowColor = [UIColor blackColor].CGColor;
        self.multitaskingMenuView.layer.shadowOffset = CGSizeMake(0, 8);
        self.multitaskingMenuView.layer.shadowOpacity = 0.18;
        self.multitaskingMenuView.layer.shadowRadius = 18.0;

        // 冰川蓝注入层 (Ice Tint) 增强毛玻璃通透感与极致美学
        UIView *tintView = [[UIView alloc] initWithFrame:self.multitaskingMenuView.bounds];
        tintView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        tintView.backgroundColor = [UIColor colorWithRed:CV3Style.menuTintR green:CV3Style.menuTintG blue:CV3Style.menuTintB alpha:CV3Style.menuTintA];
        tintView.userInteractionEnabled = NO;
        [self.multitaskingMenuView.contentView addSubview:tintView];

        // 多任务菜单三棱镜色散层 (Prism Dispersion for Menu)
        CALayer *menuCyan = [CALayer layer];
        [menuCyan setValue:@"menuCyan" forKey:@"name"];
        menuCyan.borderColor = [[UIColor cyanColor] colorWithAlphaComponent:0.12].CGColor;
        menuCyan.borderWidth = 0.3;
        menuCyan.cornerRadius = 16.0;
        if (@available(iOS 13.0, *)) {
            menuCyan.cornerCurve = kCACornerCurveContinuous;
        }
        [self.multitaskingMenuView.layer addSublayer:menuCyan];
        
        CALayer *menuMagenta = [CALayer layer];
        [menuMagenta setValue:@"menuMagenta" forKey:@"name"];
        menuMagenta.borderColor = [[UIColor magentaColor] colorWithAlphaComponent:0.12].CGColor;
        menuMagenta.borderWidth = 0.3;
        menuMagenta.cornerRadius = 16.0;
        if (@available(iOS 13.0, *)) {
            menuMagenta.cornerCurve = kCACornerCurveContinuous;
        }
        [self.multitaskingMenuView.layer addSublayer:menuMagenta];

        UIButton *fullscreen = [self multitaskingMenuButtonWithTitle:@"全屏" symbol:@"rectangle.fill" action:@selector(handleFullscreenMenuAction:)];
        UIButton *expose = [self multitaskingMenuButtonWithTitle:@"所有浮窗" symbol:@"square.grid.2x2" action:@selector(handleExposeMenuAction:)];
        UIButton *close = [self multitaskingMenuButtonWithTitle:@"关闭" symbol:@"xmark" action:@selector(handleCloseMenuAction:)];
        fullscreen.tag = 101;
        expose.tag = 102;
        close.tag = 103;
        [self.multitaskingMenuView.contentView addSubview:fullscreen];
        [self.multitaskingMenuView.contentView addSubview:expose];
        [self.multitaskingMenuView.contentView addSubview:close];
        [self.rootTransformContainer addSubview:self.multitaskingMenuView];
    }

    CGFloat logicalW = self.rootTransformContainer.bounds.size.width;
    CGFloat menuW = MIN(320.0, MAX(280.0, logicalW - 24.0));
    CGFloat menuH = 54.0;
    self.multitaskingMenuView.frame = CGRectMake((logicalW - menuW) / 2.0, 24.0, menuW, menuH);
    CV3LogToFile(@"[MultitaskingMenu] menuView frame = %@", NSStringFromCGRect(self.multitaskingMenuView.frame));
    
    // 动态调整多任务菜单的色散边缘图层
    CGRect menuBounds = self.multitaskingMenuView.bounds;
    if (self.multitaskingMenuView.layer.sublayers) {
        for (CALayer *sub in self.multitaskingMenuView.layer.sublayers) {
            if ([[sub valueForKey:@"name"] isEqualToString:@"menuCyan"]) {
                sub.frame = CGRectInset(menuBounds, -0.3, -0.3);
            } else if ([[sub valueForKey:@"name"] isEqualToString:@"menuMagenta"]) {
                sub.frame = CGRectInset(menuBounds, 0.3, 0.3);
            }
        }
    }
    
    CGFloat itemW = menuW / 3.0;
    for (UIButton *button in self.multitaskingMenuView.contentView.subviews) {
        if (![button isKindOfClass:[UIButton class]]) continue;
        NSInteger idx = button.tag - 101;
        button.frame = CGRectMake(itemW * idx, 0, itemW, menuH);
        
        UIView *hoverBg = [button viewWithTag:990];
        if (hoverBg) {
            hoverBg.frame = CGRectInset(button.bounds, 4, 4); // 四周内缩，呈现精致悬浮边框
            
            // 同步调整金属反射流光层的尺寸
            if (hoverBg.layer.sublayers) {
                for (CALayer *sub in hoverBg.layer.sublayers) {
                    if ([[sub valueForKey:@"name"] isEqualToString:@"specular"]) {
                        sub.frame = hoverBg.bounds;
                        break;
                    }
                }
            }
        }
    }

    // 级联水滴滑入动效 (Cascade Slide Animation) - 从绿色的多任务按钮正下方喷射展开
    CGPoint startCenter = [self.windowChromeView convertPoint:self.chromeModeButton.center toView:self.rootTransformContainer];
    CGPoint targetCenter = CGPointMake(logicalW / 2.0, 24.0 + menuH / 2.0);
    
    self.multitaskingMenuView.center = startCenter;
    self.multitaskingMenuView.transform = CGAffineTransformMakeScale(CV3Style.menuStartScale, CV3Style.menuStartScale);
    self.multitaskingMenuView.alpha = 0.0;
    self.multitaskingMenuView.hidden = NO;
    [self.rootTransformContainer bringSubviewToFront:self.multitaskingMenuView];
    
    // 水滴抛物线飞行动画 (Parabolic Flight trajectory)
    CGMutablePathRef curvedPath = CGPathCreateMutable();
    CGPathMoveToPoint(curvedPath, NULL, startCenter.x, startCenter.y);
    CGFloat cx = startCenter.x + (targetCenter.x - startCenter.x) * 0.4;
    CGFloat cy = startCenter.y + CV3Style.menuParabolicOffset;
    CGPathAddQuadCurveToPoint(curvedPath, NULL, cx, cy, targetCenter.x, targetCenter.y);
    
    CAKeyframeAnimation *pathAnimation = [CAKeyframeAnimation animationWithKeyPath:@"position"];
    pathAnimation.duration = CV3Style.menuAnimDuration;
    pathAnimation.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut];
    pathAnimation.path = curvedPath;
    CGPathRelease(curvedPath);
    
    [self.multitaskingMenuView.layer addAnimation:pathAnimation forKey:@"position"];
    
    CV3LogToFile(@"[MultitaskingMenu] Performing cascade spring animation...");
    [UIView animateWithDuration:CV3Style.menuAnimDuration
                          delay:0
         usingSpringWithDamping:CV3Style.menuAnimDamping
          initialSpringVelocity:0.2
                        options:UIViewAnimationOptionCurveEaseInOut | UIViewAnimationOptionAllowUserInteraction
                     animations:^{
        self.multitaskingMenuView.center = targetCenter;
        self.multitaskingMenuView.transform = CGAffineTransformIdentity;
        self.multitaskingMenuView.alpha = 1.0;
    } completion:nil];
}

- (void)dismissMultitaskingMenu {
    CV3LogToFile(@"[MultitaskingMenu] dismissMultitaskingMenu called.");
    if (!self.multitaskingMenuView || self.multitaskingMenuView.hidden) return;
    
    CGPoint startCenter = [self.windowChromeView convertPoint:self.chromeModeButton.center toView:self.rootTransformContainer];
    CGPoint currentCenter = self.multitaskingMenuView.center;
    
    // 原路收缩，吸回绿色的多任务按钮中
    CGMutablePathRef curvedPath = CGPathCreateMutable();
    CGPathMoveToPoint(curvedPath, NULL, currentCenter.x, currentCenter.y);
    CGFloat cx = startCenter.x + (currentCenter.x - startCenter.x) * 0.4;
    CGFloat cy = currentCenter.y + CV3Style.menuParabolicOffset;
    CGPathAddQuadCurveToPoint(curvedPath, NULL, cx, cy, startCenter.x, startCenter.y);
    
    CAKeyframeAnimation *pathAnimation = [CAKeyframeAnimation animationWithKeyPath:@"position"];
    pathAnimation.duration = CV3Style.durationMedium;
    pathAnimation.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut];
    pathAnimation.path = curvedPath;
    CGPathRelease(curvedPath);
    
    [self.multitaskingMenuView.layer addAnimation:pathAnimation forKey:@"position"];
    
    [UIView animateWithDuration:CV3Style.durationMedium
                          delay:0
                        options:UIViewAnimationOptionCurveEaseIn | UIViewAnimationOptionAllowUserInteraction
                     animations:^{
        self.multitaskingMenuView.alpha = 0;
        self.multitaskingMenuView.center = startCenter;
        self.multitaskingMenuView.transform = CGAffineTransformMakeScale(CV3Style.menuStartScale, CV3Style.menuStartScale);
    } completion:^(BOOL finished) {
        self.multitaskingMenuView.hidden = YES;
        self.multitaskingMenuView.transform = CGAffineTransformIdentity;
        CV3LogToFile(@"[MultitaskingMenu] dismiss completed.");
    }];
}

- (void)handleFullscreenMenuAction:(id)sender {
    [self dismissMultitaskingMenu];

    if (self.isFullscreenMode && !CGRectIsEmpty(self.preFullscreenFrame)) {
        CGRect restoreFrame = self.preFullscreenFrame;
        self.isFullscreenMode = NO;
        self.isCompactMode = NO;
        
        // 视窗变小，初态注入扩张视差 1.05x
        self.appContentWrapper.transform = CGAffineTransformMakeScale(CV3Style.transitionParallaxShrink, CV3Style.transitionParallaxShrink);
        
        [UIView animateWithDuration:0.35 delay:0 usingSpringWithDamping:0.86 initialSpringVelocity:0.0 options:UIViewAnimationOptionCurveEaseInOut animations:^{
            self.frame = restoreFrame;
            [self setNeedsLayout];
            [self layoutIfNeeded];
            
            // 视差过渡至标准物理尺寸
            self.appContentWrapper.transform = CGAffineTransformIdentity;
        } completion:^(BOOL finished) {
            [self syncHostedSceneLayoutForce:YES];
            [self syncWindowBoundsToClient];
        }];
        return;
    }

    if (!self.isFullscreenMode) {
        self.preFullscreenFrame = self.frame;
        self.isFullscreenMode = YES;
        self.isCompactMode = NO;
    }

    CGRect targetFrame = self.windowScene ? self.windowScene.coordinateSpace.bounds : [UIScreen mainScreen].bounds;
    
    // 视窗变大，初态注入收缩视差 0.93x
    self.appContentWrapper.transform = CGAffineTransformMakeScale(CV3Style.transitionParallaxExpand, CV3Style.transitionParallaxExpand);
    
    [UIView animateWithDuration:0.35 delay:0 usingSpringWithDamping:0.86 initialSpringVelocity:0.0 options:UIViewAnimationOptionCurveEaseInOut animations:^{
        self.transform = CGAffineTransformIdentity;
        self.frame = targetFrame;
        [self setNeedsLayout];
        [self layoutIfNeeded];
        
        // 视差过渡至标准物理尺寸
        self.appContentWrapper.transform = CGAffineTransformIdentity;
    } completion:^(BOOL finished) {
        [self syncHostedSceneLayoutForce:YES];
        [self syncWindowBoundsToClient];
    }];
}

- (void)handleCloseMenuAction:(id)sender {
    [self dismissMultitaskingMenu];
    [self closeWindow];
}

- (void)handleExposeMenuAction:(id)sender {
    [self dismissMultitaskingMenu];
    CV3ToggleExposeMode();
}

- (instancetype)initWithBundleID:(NSString *)bundleID center:(CGPoint)center windowScene:(UIWindowScene *)windowScene {
    if (windowScene) {
        self = [super initWithWindowScene:windowScene];
    } else {
        self = [super initWithFrame:CGRectMake(0, 0, 300, 500)];
    }
    
    if (self) {
        CGRect screen = CV3DisplayBoundsForWindow(self);
        // 始终获取竖屏比例作为基准计算，确保弹出的窗口比例正确
        CGFloat portraitW = MIN(screen.size.width, screen.size.height);
        CGFloat portraitH = MAX(screen.size.width, screen.size.height);
        
        // 默认逻辑尺寸：宽占屏幕 45%，高按屏幕比例缩放
        CGFloat logicalW = portraitW * 0.45;
        CGFloat logicalH = logicalW * (portraitH / portraitW);
        
        UIInterfaceOrientation currentOrientation = CV3TrustedInterfaceOrientation(windowScene);
        
        // 外层 UIWindow 使用当前可信方向坐标；横屏创建时直接使用宽屏窗口，不再退回竖屏尺寸。
        CGFloat physicalW = logicalW;
        CGFloat physicalH = logicalH;
        
        self.frame = CGRectMake(0, 0, physicalW, physicalH);
        self.lastLayoutOrientation = currentOrientation;
        self.targetOrientation = currentOrientation;
        
        self.bundleID = bundleID;
        self.allowProcessTerminationOnClose = NO;
        self.center = center;
        [self enforcePortraitWindowGeometry];
        self.windowLevel = CV3Style.floatingApp; // 高于普通 App，但低于通知栏/控制中心
        self.backgroundColor = [UIColor clearColor];
        self.alpha = 1.0;
        
        [self visualShadowLayer].shadowColor = [UIColor blackColor].CGColor;
        [self visualShadowLayer].shadowOffset = CGSizeMake(0, 10);
        [self visualShadowLayer].shadowOpacity = 0.16;
        [self visualShadowLayer].shadowRadius = 24.0;
        self.layer.cornerRadius = CV3Style.floatingChromeCornerRadius;
        if (@available(iOS 13.0, *)) {
            self.layer.cornerCurve = kCACornerCurveContinuous;
        }
        
        // 核心修复：引入旋转根容器 (Root Transform Container)
        // 该容器用于隔离系统 UIWindow 的 Transform 问题，承载全方位的视觉旋转
        self.rootTransformContainer = [[UIView alloc] initWithFrame:self.bounds];
        self.rootTransformContainer.backgroundColor = [UIColor clearColor];
        [self addSubview:self.rootTransformContainer];

        // 核心修复：引入内容包装层 (App Content Wrapper)
        // 该层用于统一缩放动画，确保主内容与把手 (Home Bar) 同步缩放至图标
        self.appContentWrapper = [[UIView alloc] initWithFrame:self.rootTransformContainer.bounds];
        self.appContentWrapper.backgroundColor = [UIColor clearColor];
        [self.rootTransformContainer addSubview:self.appContentWrapper];
        [self clearOuterWindowShadow];
        [self syncWindowShadowForCurrentState];

        [self createFloatingHomeBarIfNeeded];

        // 核心修复：引入非缩放裁剪层 (Clipping Container)
        // 该层的大小始终等于窗口大小，负责强制执行圆角裁剪，不受内部缩放影响
        self.clippingContainer = [[UIView alloc] initWithFrame:self.bounds];
        self.clippingContainer.layer.cornerRadius = CV3Style.floatingChromeCornerRadius;
        if (@available(iOS 13.0, *)) {
            self.clippingContainer.layer.cornerCurve = kCACornerCurveContinuous;
        }
        self.clippingContainer.layer.masksToBounds = YES;
        self.clippingContainer.layer.borderWidth = 1.0 / [UIScreen mainScreen].scale;
        self.clippingContainer.backgroundColor = [UIColor clearColor];
        [self.appContentWrapper addSubview:self.clippingContainer];

        self.glassBackdrop = [[UIVisualEffectView alloc] initWithEffect:[UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemThinMaterial]];
        self.glassBackdrop.frame = self.clippingContainer.bounds;
        self.glassBackdrop.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        [self.clippingContainer insertSubview:self.glassBackdrop atIndex:0];

        CGFloat initialRadius = CV3Style.floatingChromeCornerRadius;
        
        self.cyanLayer = [CALayer layer];
        self.cyanLayer.frame = self.clippingContainer.bounds;
        self.cyanLayer.borderColor = [[UIColor cyanColor] colorWithAlphaComponent:0.12].CGColor;
        self.cyanLayer.borderWidth = 0.3;
        self.cyanLayer.cornerRadius = initialRadius;
        [self.clippingContainer.layer addSublayer:self.cyanLayer];

        self.magentaLayer = [CALayer layer];
        self.magentaLayer.frame = self.clippingContainer.bounds;
        self.magentaLayer.borderColor = [[UIColor magentaColor] colorWithAlphaComponent:0.12].CGColor;
        self.magentaLayer.borderWidth = 0.3;
        self.magentaLayer.cornerRadius = initialRadius;
        [self.clippingContainer.layer addSublayer:self.magentaLayer];

        self.innerGlowLayer = [CALayer layer];
        self.innerGlowLayer.frame = self.clippingContainer.bounds;
        self.innerGlowLayer.borderColor = [[UIColor labelColor] colorWithAlphaComponent:0.45].CGColor;
        self.innerGlowLayer.borderWidth = 0.3;
        self.innerGlowLayer.cornerRadius = initialRadius;
        [self.clippingContainer.layer addSublayer:self.innerGlowLayer];

        self.specularHighlight = [CAGradientLayer layer];
        self.specularHighlight.frame = self.clippingContainer.bounds;
        self.specularHighlight.colors = @[
            (id)[[UIColor whiteColor] colorWithAlphaComponent:0.0].CGColor,
            (id)[[UIColor whiteColor] colorWithAlphaComponent:0.15].CGColor,
            (id)[[UIColor whiteColor] colorWithAlphaComponent:0.0].CGColor
        ];
        self.specularHighlight.startPoint = CGPointMake(0.0, 0.0);
        self.specularHighlight.endPoint = CGPointMake(1.0, 1.0);
        self.specularHighlight.cornerRadius = initialRadius;
        [self.clippingContainer.layer addSublayer:self.specularHighlight];

        // 代理容器：用来隔离系统的布局覆盖，承载真实的缩放和裁剪
        self.hostContainerProxy = [[UIView alloc] initWithFrame:self.bounds];
        self.hostContainerProxy.backgroundColor = [UIColor clearColor];
        // 核心修复：应用三线性过滤 (Trilinear Filtering)
        // 在非整数缩放比下，三线性过滤能显著减少文本和细线的锯齿，提升渲染清晰度
        self.hostContainerProxy.layer.magnificationFilter = kCAFilterTrilinear;
        self.hostContainerProxy.layer.minificationFilter = kCAFilterTrilinear;
        
        [self.clippingContainer addSubview:self.hostContainerProxy];
        [self ensureLaunchSplashVisible];
        
        // 侧边隐藏拉手 (Grabber -> Prism Switcher)
        self.stashGrabber = [[UIView alloc] initWithFrame:CGRectMake(0, 0, kCV3StashIconSize, kCV3StashIconSize)];
        self.stashGrabber.backgroundColor = [UIColor clearColor];
        self.stashGrabber.layer.cornerRadius = 0;
        self.stashGrabber.layer.borderWidth = 0;
        self.stashGrabber.alpha = 0; // 初始隐藏
        [self addSubview:self.stashGrabber];

        self.appIconMiniView = [[UIImageView alloc] initWithFrame:CGRectMake(kCV3StashIconInset, kCV3StashIconInset, kCV3StashIconSize - kCV3StashIconInset * 2.0, kCV3StashIconSize - kCV3StashIconInset * 2.0)];
        self.appIconMiniView.layer.cornerRadius = 8;
        self.appIconMiniView.clipsToBounds = YES;
        [self.stashGrabber addSubview:self.appIconMiniView];

        UITapGestureRecognizer *restoreTap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handleRestoreTap:)];
        [self.stashGrabber addGestureRecognizer:restoreTap];

        UIPanGestureRecognizer *restorePan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handleStashPan:)];
        [self.stashGrabber addGestureRecognizer:restorePan];

        // 核心功能：长按结束分屏
        UILongPressGestureRecognizer *stashClose = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(handleStashLongPress:)];
        stashClose.minimumPressDuration = 0.8; 
        [self.stashGrabber addGestureRecognizer:stashClose];

        self.stashGrabber.userInteractionEnabled = YES;

        [self clampToScreenBounds];
        [self layoutFloatingHomeBarForBounds:self.appContentWrapper.bounds];
        [self updateAdaptiveColor];

        [self loadAppScene];
        
        // Auto-focus on creation
        [self setWindowFocused:YES];

        // 核心修复：监听 Scene 变更与系统通知，确保窗口持久存在
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(attachToCurrentActiveScene) name:UISceneDidActivateNotification object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(enforceSceneForegroundState) name:UISceneDidEnterBackgroundNotification object:nil];

        // 启动主动保活断言看门狗定时器
        self.assertionWatchdogTimer = [NSTimer scheduledTimerWithTimeInterval:5.0 target:self selector:@selector(assertionWatchdogTick:) userInfo:nil repeats:YES];
        
        // [SHM Lazy Unmapping] 持有共享内存引用计数
        CV3RetainSharedGeometry(self.bundleID);
    }
    return self;
}

- (void)setHidden:(BOOL)hidden {
    // 核心修复：禁止系统强制隐藏窗口（除非是明确的关闭操作或 Stash）
    if (hidden && !self.isStashed && !self.isClosing) {
        CV3LogToFile(@"[Visibility] 拦截系统隐藏请求: %@", self.bundleID);
        [super setHidden:NO];
        [self attachToCurrentActiveScene];
        return;
    }
    CV3LogToFile(@"[Visibility] 窗口 Hidden 状态变更 -> %d: %@", hidden, self.bundleID);
    [super setHidden:hidden];
}

- (void)attachToCurrentActiveScene {
    CV3LogToFile(@"[Scene] 开始尝试同步挂载场景: %@", self.bundleID);
    @try {
        UIWindowScene *targetScene = nil;
        
        // 1. 终极优先：获取 SpringBoard 核心主场景 (SBWindowSceneSessionRoleMain)
        targetScene = CV3InvokeObject(CV3ClassNamed(@"SBWindowScene"), @selector(mainDisplayWindowScene));
        
        // 2. 备选方案：遍历场景并严格过滤非显示角色
        if (!targetScene) {
            for (UIScene *scene in [[UIApplication sharedApplication].connectedScenes allObjects]) {
                if ([scene isKindOfClass:[UIWindowScene class]]) {
                    UIWindowScene *ws = (UIWindowScene *)scene;
                    NSString *role = ws.session.role;
                    
                    // 核心修正：严格排除灵动岛相关的幕帘场景
                    // 这些场景在上滑 Home 条时会活跃，但会导致我们的窗口被系统优化掉
                    if ([role containsString:@"Aperture"] || [role containsString:@"Curtain"]) {
                        continue;
                    }
                    
                    if (ws.activationState == UISceneActivationStateForegroundActive) {
                        targetScene = ws;
                        break;
                    }
                }
            }
        }
        
        // 3. 强制同步场景挂载。
        if (targetScene && (self.windowScene != targetScene || !self.windowScene)) {
            NSString *role = targetScene.session.role ?: @"Unknown";
            CV3LogToFile(@"[Scene] 成功将窗口 (%@) 挂载至主场景: %@ (Role: %@)", self.bundleID, targetScene, role);
            self.windowScene = targetScene;
            [self setHidden:NO];
            [self setNeedsLayout];
            [self layoutIfNeeded];
        } else if (!targetScene) {
            CV3LogToFile(@"[Scene] 警告：未能找到可用的显示级 targetScene: %@", self.bundleID);
        }
        
        // 4. 无论如何，强制维持内部 App 场景的活跃状态
        [self enforceSceneForegroundState];
    } @catch (NSException *e) {
        CV3LogToFile(@"[Error] attachToCurrentActiveScene 异常: %@", e);
    }
}

- (void)refreshHostViewPresentation {
    if (!self.targetScene || !self.hostView) {
        return;
    }
    
    @try {
        // [Safety Restore] 恢复至 7 (1|2|4)，确保键盘可弹出。
        // 由于已解决布局死锁，恢复 2(Keyboard) 和 4(KeyboardBg) 是安全的。
        UIScenePresentationContext *context = [[CV3ClassNamed(@"UIScenePresentationContext") alloc] _initWithDefaultValues];
        if ([context respondsToSelector:@selector(setPresentedLayerTypes:)]) {
            [context setPresentedLayerTypes:7];
        }
        if ([context respondsToSelector:@selector(setAppearanceStyle:)]) {
            BOOL previousSuppress = CV3SuppressPresentationContextFanout;
            CV3SuppressPresentationContextFanout = YES;
            @try {
                [context setAppearanceStyle:2];
            } @finally {
                CV3SuppressPresentationContextFanout = previousSuppress;
            }
        }
        if ([context respondsToSelector:@selector(setClipsToBounds:)]) {
            [context setClipsToBounds:YES];
        }
        
        CV3InvokeObject1(self.hostView, @selector(_setPresentationContext:), context);
        
        self.hostView.alpha = 1.0;
        self.hostView.hidden = NO;
        
    } @catch (NSException *e) {
        CV3LogToFile(@"[Error] 热刷新渲染失败: %@", e);
    }
}

- (void)ensureLaunchSplashVisible {
    if (!self.hostContainerProxy) return;

    if (!self.splashView) {
        UIBlurEffectStyle blurStyle = UIBlurEffectStyleSystemThinMaterial;
        if (@available(iOS 13.0, *)) {
            blurStyle = UIBlurEffectStyleSystemMaterial;
        }

        UIVisualEffectView *splash = [[UIVisualEffectView alloc] initWithEffect:[UIBlurEffect effectWithStyle:blurStyle]];
        splash.frame = self.hostContainerProxy.bounds;
        splash.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        splash.userInteractionEnabled = NO;
        splash.alpha = 1.0;

        UIView *tintView = [[UIView alloc] initWithFrame:splash.contentView.bounds];
        tintView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        UIColor *tintColor = self.adaptiveAppColor ?: [UIColor colorWithWhite:0.12 alpha:1.0];
        tintView.backgroundColor = [tintColor colorWithAlphaComponent:0.24];
        [splash.contentView addSubview:tintView];

        UIImageView *iconView = [[UIImageView alloc] initWithFrame:CGRectMake(0, 0, 76, 76)];
        iconView.center = CGPointMake(CGRectGetMidX(splash.contentView.bounds), CGRectGetMidY(splash.contentView.bounds));
        iconView.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleRightMargin | UIViewAutoresizingFlexibleTopMargin | UIViewAutoresizingFlexibleBottomMargin;
        iconView.layer.cornerRadius = 17.0;
        iconView.layer.masksToBounds = YES;
        iconView.contentMode = UIViewContentModeScaleAspectFill;
        iconView.backgroundColor = [[UIColor whiteColor] colorWithAlphaComponent:0.18];
        if (self.appIconMiniView.image) {
            iconView.image = self.appIconMiniView.image;
        }
        [splash.contentView addSubview:iconView];

        self.splashView = splash;
        self.largeSplashIcon = iconView;
        [self.hostContainerProxy addSubview:self.splashView];
    }

    self.splashView.hidden = NO;
    self.splashView.alpha = 1.0;
    self.splashView.frame = self.hostContainerProxy.bounds;
    [self.hostContainerProxy bringSubviewToFront:self.splashView];
    if (self.largeSplashIcon && self.appIconMiniView.image) {
        self.largeSplashIcon.image = self.appIconMiniView.image;
    }
}

- (void)dismissLaunchSplashAnimated {
    if (!self.splashView) return;

    UIView *splash = self.splashView;
    UIImageView *icon = self.largeSplashIcon;
    self.splashView = nil;
    self.largeSplashIcon = nil;

    [UIView animateWithDuration:0.35
                          delay:0.05
                        options:UIViewAnimationOptionCurveEaseOut | UIViewAnimationOptionBeginFromCurrentState
                     animations:^{
        splash.alpha = 0;
        icon.transform = CGAffineTransformMakeScale(1.08, 1.08);
    } completion:^(BOOL finished) {
        [splash removeFromSuperview];
    }];
}

- (void)enforceSceneForegroundState {
    if (!self.targetScene) {
        CV3LogToFile(@"[Recovery] enforceSceneForegroundState 缺失 targetScene，触发冷启动: %@", self.bundleID);
        [self ensureLaunchSplashVisible];
        [self loadAppScene];
        return;
    }
    
    @try {
        // 核心增强：除了检查 isValid，还检查是否还在连接状态
        BOOL sceneValid = CV3InvokeBool(self.targetScene, @selector(isValid), YES);
        
        if (!sceneValid) {
            CV3LogToFile(@"[Recovery] 场景失效，触发重连机制: %@", self.bundleID);
            [self ensureLaunchSplashVisible];
            if (self.hostView) {
                [self.hostView removeFromSuperview];
                self.hostView = nil;
            }
            [self loadAppScene];
            return;
        }

        // 预防性重置：如果检测到 HostView 存在但可能已“冻结”，强制触发层级重新同步
        if (self.hostView && self.hostView.superview) {
            // 通过检查渲染层级是否还具备 Presentation Context 来判断冻结
            if (CV3TargetRespondsToSelector(self.hostView, @selector(presentationContext)) &&
                !CV3InvokeObject(self.hostView, @selector(presentationContext))) {
                CV3LogToFile(@"[Recovery] 检测到 HostView 渲染层断连，强制修复: %@", self.bundleID);
                [self ensureLaunchSplashVisible];
                [self.hostView removeFromSuperview];
                [self attemptToHostSceneWithRetries:1 delay:0]; // 快速尝试重建
                return;
            }
        }

        FBSMutableSceneSettings *settings = [[self.targetScene settings] mutableCopy];
        BOOL needsUpdate = [self applyForegroundSovereigntyToSettings:settings clearDeactivation:YES forceLayout:NO];
        
        if (needsUpdate) {
            [self.targetScene updateSettings:settings withTransitionContext:nil];
            
            // 确保内容状态强制为前台
            if ([self.targetScene respondsToSelector:@selector(_setContentState:)]) {
                [self.targetScene _setContentState:2]; 
            }
            
            // 立即实施层级重刷，而非等待主循环
            [self refreshHostViewPresentation];
            CV3LogToFile(@"[Lifecycle] 已强制更新 %@ 场景设置与渲染上下文", self.bundleID);
        }
    } @catch (NSException *e) {
        CV3LogToFile(@"[Error] enforceSceneForegroundState 异常: %@", e);
    }
}

- (void)updateSovereigntyAssertion {
    if (!self.bundleID || self.isClosing) return;

    @try {
        if (self.rbsAssertion) {
            [self.rbsAssertion invalidate];
            self.rbsAssertion = nil;
        }

        RBSProcessIdentity *identity = [CV3ClassNamed(@"RBSProcessIdentity") identityForEmbeddedApplicationIdentifier:self.bundleID];
        RBSTarget *target = [CV3ClassNamed(@"RBSTarget") targetWithProcessIdentity:identity];
        
        // Z-Order 能效调度算法：
        // 1. 如果窗口被 Stash，直接为 UserInitiated
        // 2. 如果窗口可见且未 Stash：
        //    - 如果是 Focused (聚焦窗口) 或处于数组末尾的最顶层 2 个可见窗口之一，为 UserInteractive
        //    - 其他更底层的窗口降级为 UserInitiated，配合系统能耗优化并防止 CPU 抢占
        BOOL isTopWindow = YES;
        if (!self.isStashed && floatingWindows && floatingWindows.count > 2) {
            NSMutableArray *activeWindows = [NSMutableArray array];
            for (CV3FloatingAppWindow *win in floatingWindows) {
                if ([win isKindOfClass:[CV3FloatingAppWindow class]] && !win.isStashed && !win.isClosing) {
                    [activeWindows addObject:win];
                }
            }
            NSInteger myIdx = [activeWindows indexOfObject:self];
            if (myIdx != NSNotFound && activeWindows.count - myIdx > 2) {
                isTopWindow = NO;
            }
        }

        NSString *attributeName = @"UserInteractive";
        if (self.isStashed) {
            attributeName = @"UserInitiated";
        } else if (!self.isFocused && !isTopWindow) {
            attributeName = @"UserInitiated";
        }
        
        RBSDomainAttribute *attr = [CV3ClassNamed(@"RBSDomainAttribute") attributeWithDomain:@"com.apple.common" name:attributeName];
        
        self.rbsAssertion = [[CV3ClassNamed(@"RBSAssertion") alloc] initWithExplanation:[NSString stringWithFormat:@"ChevronV3 Sovereignty (%@) for %@", attributeName, self.bundleID] 
                                                                   target:target 
                                                               attributes:@[attr]];
        
        NSError *error = nil;
        if ([self.rbsAssertion acquireWithError:&error]) {
            CV3LogToFile(@"[Immortality] 已动态更新 %@ 优先级断言 -> %@", self.bundleID, attributeName);
        } else {
            CV3LogToFile(@"[Error] RBSAssertion (%@) 更新失败: %@", attributeName, error);
        }
    } @catch (NSException *e) {
        CV3LogToFile(@"[Error] updateSovereigntyAssertion 异常: %@", e);
    }
}

- (void)animateFocusShadow:(BOOL)focused {
    if (self.isStashed) {
        [self syncWindowShadowForCurrentState];
        return;
    }

    CALayer *shadowLayer = [self visualShadowLayer];
    [self clearOuterWindowShadow];
    shadowLayer.shadowColor = [UIColor blackColor].CGColor;
    [shadowLayer removeAnimationForKey:@"shadowRadius"];
    [shadowLayer removeAnimationForKey:@"shadowOpacity"];
    [shadowLayer removeAnimationForKey:@"shadowOffset"];
    
    CGFloat startRadius = focused ? CV3Style.shadowRadiusUnfocused : CV3Style.shadowRadiusFocused;
    CGFloat peakRadius = focused ? CV3Style.shadowRadiusPeak : (CV3Style.shadowRadiusUnfocused - 4.0);
    CGFloat endRadius = focused ? CV3Style.shadowRadiusFocused : CV3Style.shadowRadiusUnfocused;
    
    CGFloat startOpacity = focused ? CV3Style.shadowOpacityUnfocused : CV3Style.shadowOpacityFocused;
    CGFloat peakOpacity = focused ? CV3Style.shadowOpacityPeak : (CV3Style.shadowOpacityUnfocused - 0.04);
    CGFloat endOpacity = focused ? CV3Style.shadowOpacityFocused : CV3Style.shadowOpacityUnfocused;
    
    CGFloat startOffsetY = focused ? CV3Style.shadowOffsetUnfocusedY : CV3Style.shadowOffsetFocusedY;
    CGFloat peakOffsetY = focused ? CV3Style.shadowOffsetPeakY : (CV3Style.shadowOffsetUnfocusedY - 2.0);
    CGFloat endOffsetY = focused ? CV3Style.shadowOffsetFocusedY : CV3Style.shadowOffsetUnfocusedY;
    
    CAKeyframeAnimation *radiusAnim = [CAKeyframeAnimation animationWithKeyPath:@"shadowRadius"];
    radiusAnim.values = @[@(startRadius), @(peakRadius), @(endRadius)];
    radiusAnim.keyTimes = @[@0.0, @0.4, @1.0];
    radiusAnim.duration = CV3Style.durationMedium;
    radiusAnim.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut];
    [shadowLayer addAnimation:radiusAnim forKey:@"shadowRadius"];
    shadowLayer.shadowRadius = endRadius;
    
    CAKeyframeAnimation *opacityAnim = [CAKeyframeAnimation animationWithKeyPath:@"shadowOpacity"];
    opacityAnim.values = @[@(startOpacity), @(peakOpacity), @(endOpacity)];
    opacityAnim.keyTimes = @[@0.0, @0.4, @1.0];
    opacityAnim.duration = CV3Style.durationMedium;
    opacityAnim.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut];
    [shadowLayer addAnimation:opacityAnim forKey:@"shadowOpacity"];
    shadowLayer.shadowOpacity = endOpacity;
    
    CAKeyframeAnimation *offsetAnim = [CAKeyframeAnimation animationWithKeyPath:@"shadowOffset"];
    offsetAnim.values = @[
        [NSValue valueWithCGSize:CGSizeMake(0, startOffsetY)],
        [NSValue valueWithCGSize:CGSizeMake(0, peakOffsetY)],
        [NSValue valueWithCGSize:CGSizeMake(0, endOffsetY)]
    ];
    offsetAnim.keyTimes = @[@0.0, @0.4, @1.0];
    offsetAnim.duration = CV3Style.durationMedium;
    offsetAnim.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut];
    [shadowLayer addAnimation:offsetAnim forKey:@"shadowOffset"];
    shadowLayer.shadowOffset = CGSizeMake(0, endOffsetY);
}

- (void)setWindowFocused:(BOOL)focused {
    if (self.isFocused == focused) return;
    self.isFocused = focused;
    
    [self updateSovereigntyAssertion]; // 同步更新优先级
    [self applyCurrentTransformWithScale:1.0];
    
    [self animateFocusShadow:focused]; // 触发三维物理回弹阴影
    
    self.hostContainerProxy.alpha = 1.0;
    
    [self updateFloatingHomeBarAppearance];
    
    if (focused) {
        [self makeKeyAndVisible];
        self.windowLevel = CV3Style.floatingApp;
        
        // Z-order 层级重排：将聚焦窗口移至 floatingWindows 数组末尾，以提升其层级与转屏级联偏移优先级
        if (floatingWindows && [floatingWindows containsObject:self]) {
            [floatingWindows removeObject:self];
            [floatingWindows addObject:self];
        }
        
        // Dim other windows
        for (CV3FloatingAppWindow *win in floatingWindows) {
            if (win != self && [win isKindOfClass:[CV3FloatingAppWindow class]]) [win setWindowFocused:NO];
        }

        // Z-Order 发生变化，级联刷新所有窗口前台优先级断言
        CV3CascadeUpdateSovereigntyAssertions();
    }
}

- (void)updateResizeHandleAppearance {
    BOOL darkStyle = NO;
    if (@available(iOS 12.0, *)) {
        darkStyle = self.traitCollection.userInterfaceStyle == UIUserInterfaceStyleDark;
    }
    
    UIColor *borderColor = darkStyle ? [[UIColor whiteColor] colorWithAlphaComponent:0.18] : [[UIColor blackColor] colorWithAlphaComponent:0.16];
    
    UIColor *baseColor = self.adaptiveAppColor ?: (darkStyle ? [UIColor systemGrayColor] : [UIColor whiteColor]);
    CGFloat hue = 0, saturation = 0, brightness = 0, alpha = 0;
    if ([baseColor getHue:&hue saturation:&saturation brightness:&brightness alpha:&alpha]) {
        saturation = MIN(0.55, MAX(0.18, saturation));
        brightness = darkStyle ? MIN(0.82, MAX(0.36, brightness)) : MIN(0.98, MAX(0.72, brightness));
        baseColor = [UIColor colorWithHue:hue saturation:saturation brightness:brightness alpha:1.0];
    }

    self.resizeHandle.backgroundColor = [UIColor clearColor];
    self.resizeHandle.layer.borderWidth = 0;
    self.resizeHandle.layer.shadowOpacity = 0;

    CGSize visualSize = self.resizeHandleVisualSize;
    if (visualSize.width <= 0 || visualSize.height <= 0) {
        visualSize = CGSizeMake(MIN(26.0, CGRectGetWidth(self.resizeHandle.bounds)),
                                MIN(26.0, CGRectGetHeight(self.resizeHandle.bounds)));
    }
    CGRect b = CGRectMake(CGRectGetWidth(self.resizeHandle.bounds) - visualSize.width,
                          CGRectGetHeight(self.resizeHandle.bounds) - visualSize.height,
                          visualSize.width,
                          visualSize.height);
    if (!CGRectIsEmpty(b)) {
        self.resizeHandleLayer.frame = b;
        UIBezierPath *path = [UIBezierPath bezierPath];

        CGRect localBounds = self.resizeHandleLayer.bounds;
        CGPoint cornerCenter = CGPointMake(CGRectGetMinX(localBounds), CGRectGetMinY(localBounds));
        CGFloat windowScale = MIN(1.35, MAX(0.78, MIN(self.bounds.size.width, self.bounds.size.height) / 390.0));
        CGFloat arcRadius = MAX(10.0, MIN(localBounds.size.width - 4.0, (CV3Style.floatingChromeCornerRadius + 4.0) * windowScale));
        CGFloat startAngle = (CGFloat)(M_PI_4 * 0.18);
        CGFloat endAngle = (CGFloat)(M_PI_4 * 1.52);
        [path addArcWithCenter:cornerCenter radius:arcRadius startAngle:startAngle endAngle:endAngle clockwise:YES];

        UIColor *strokeColor = baseColor;
        CGFloat strokeHue = 0, strokeSaturation = 0, strokeBrightness = 0, strokeAlpha = 0;
        if ([strokeColor getHue:&strokeHue saturation:&strokeSaturation brightness:&strokeBrightness alpha:&strokeAlpha]) {
            BOOL sourceIsBright = strokeBrightness > 0.62;
            strokeSaturation = sourceIsBright ? MIN(0.42, MAX(0.10, strokeSaturation * 0.65)) : MIN(0.62, MAX(0.20, strokeSaturation + 0.10));
            strokeBrightness = darkStyle ? MIN(0.92, MAX(0.68, strokeBrightness + 0.22)) : (sourceIsBright ? 0.30 : 0.78);
            strokeColor = [UIColor colorWithHue:strokeHue saturation:strokeSaturation brightness:strokeBrightness alpha:1.0];
        }
        self.resizeHandleLayer.path = path.CGPath;
        self.resizeHandleLayer.strokeColor = [strokeColor colorWithAlphaComponent:(darkStyle ? 0.72 : 0.58)].CGColor;
        self.resizeHandleLayer.fillColor = [UIColor clearColor].CGColor;
        self.resizeHandleLayer.lineWidth = MAX(2.0, MIN(3.0, 2.35 * windowScale));
        self.resizeHandleLayer.lineCap = kCALineCapRound;
    }

    self.clippingContainer.layer.borderColor = borderColor.CGColor;
}

- (void)traitCollectionDidChange:(UITraitCollection *)previousTraitCollection {
    [super traitCollectionDidChange:previousTraitCollection];
    [self updateResizeHandleAppearance];
}

- (void)handleGrabberLongPress:(UILongPressGestureRecognizer *)gesture {
    if (gesture.state == UIGestureRecognizerStateBegan) {
        UIImpactFeedbackGenerator *gen = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleHeavy];
        [gen impactOccurred];
    }
}

- (void)handleHideAction {
    [self dismissMultitaskingMenu];
    UIImpactFeedbackGenerator *gen = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleLight];
    [gen impactOccurred];

    CGRect screen = CV3DisplayBoundsForWindow(self);
    BOOL isNearLeft = (self.center.x < screen.size.width / 2.0);
    CGRect initialFrame = self.frame;
    UIEdgeInsets safeArea = [self currentSafeAreaInsets];
    CGFloat breath = CV3Style.safeAreaBreath;
    CGFloat stashHalf = kCV3StashIconSize * 0.5;
    CGPoint stashCenter = CGPointMake(CGRectGetMidX(initialFrame), CGRectGetMidY(initialFrame));
    CGFloat minCenterX = safeArea.left + breath + stashHalf;
    CGFloat maxCenterX = screen.size.width - safeArea.right - breath - stashHalf;
    CGFloat minCenterY = safeArea.top + breath + stashHalf;
    CGFloat maxCenterY = screen.size.height - safeArea.bottom - breath - stashHalf;
    if (maxCenterX < minCenterX) maxCenterX = minCenterX;
    if (maxCenterY < minCenterY) maxCenterY = minCenterY;
    stashCenter.x = MIN(MAX(stashCenter.x, minCenterX), maxCenterX);
    stashCenter.y = MIN(MAX(stashCenter.y, minCenterY), maxCenterY);
    CGRect targetFrame = CGRectMake(stashCenter.x - stashHalf, stashCenter.y - stashHalf, kCV3StashIconSize, kCV3StashIconSize);
    CGRect targetFrameInWindow = CGRectOffset(targetFrame, -initialFrame.origin.x, -initialFrame.origin.y);
    CGRect snapshotStartFrame = [self convertRect:self.appContentWrapper.bounds fromView:self.appContentWrapper];
    UIView *minimizeSnapshot = [self.appContentWrapper snapshotViewAfterScreenUpdates:NO];

    self.preStashFrame = self.frame;
    self.isStashed = YES;
    self.stashedSide = isNearLeft ? 1 : 2;
    CV3CascadeUpdateSovereigntyAssertions(); // 级联刷新所有窗口前台优先级断言

    if (!minimizeSnapshot) {
        self.frame = targetFrame;
        self.appContentWrapper.alpha = 0.0;
        self.resizeHandle.alpha = 0.0;
        self.homeBarView.alpha = 0.0;
        [self normalizeStashedGrabberLayout];
        CV3UpdateFloatingBackdrop(self.windowScene);
        return;
    }

    UIView *minimizeContainer = [[UIView alloc] initWithFrame:snapshotStartFrame];
    minimizeContainer.backgroundColor = [UIColor clearColor];
    minimizeContainer.layer.shadowColor = [UIColor blackColor].CGColor;
    minimizeContainer.layer.shadowOffset = [self visualShadowLayer].shadowOffset;
    minimizeContainer.layer.shadowOpacity = MIN(0.14, MAX(0.08, [self visualShadowLayer].shadowOpacity));
    minimizeContainer.layer.shadowRadius = MIN(18.0, MAX(10.0, [self visualShadowLayer].shadowRadius * 0.65));
    minimizeContainer.layer.shadowPath = [UIBezierPath bezierPathWithRoundedRect:minimizeContainer.bounds cornerRadius:self.clippingContainer.layer.cornerRadius].CGPath;
    minimizeContainer.layer.shouldRasterize = YES;
    minimizeContainer.layer.rasterizationScale = [UIScreen mainScreen].scale;

    minimizeSnapshot.frame = minimizeContainer.bounds;
    minimizeSnapshot.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    minimizeSnapshot.layer.cornerRadius = self.clippingContainer.layer.cornerRadius;
    minimizeSnapshot.layer.masksToBounds = YES;
    [minimizeContainer addSubview:minimizeSnapshot];
    [self addSubview:minimizeContainer];
    [self syncWindowShadowForCurrentState];

    CGPoint startCenter = minimizeContainer.center;
    CGPoint finalCenter = CGPointMake(CGRectGetMidX(targetFrameInWindow), CGRectGetMidY(targetFrameInWindow));
    CGPoint stageCenter = CGPointMake(startCenter.x + (finalCenter.x - startCenter.x) * 0.58,
                                      startCenter.y - MIN(18.0, initialFrame.size.height * 0.04));
    CGFloat finalScaleX = targetFrame.size.width / MAX(snapshotStartFrame.size.width, 1.0);
    CGFloat finalScaleY = targetFrame.size.height / MAX(snapshotStartFrame.size.height, 1.0);
    CGFloat stageScaleX = MAX(finalScaleX * 3.4, 0.42);
    CGFloat stageScaleY = MAX(finalScaleY * 5.0, 0.82);
    CGFloat finalCornerRadius = CV3Style.iconCornerRadius / MAX(MIN(finalScaleX, finalScaleY), 0.01);

    self.stashGrabber.alpha = 0.0;
    self.stashGrabber.bounds = CGRectMake(0, 0, kCV3StashIconSize, kCV3StashIconSize);
    self.stashGrabber.center = CGPointMake(CGRectGetMidX(targetFrameInWindow), CGRectGetMidY(targetFrameInWindow));
    [self applyStashedGrabberOrientation];
    self.appIconMiniView.frame = CGRectInset(self.stashGrabber.bounds, kCV3StashIconInset, kCV3StashIconInset);
    self.appIconMiniView.transform = CGAffineTransformMakeScale(0.82, 0.82);
    self.appContentWrapper.alpha = 0.0;
    self.resizeHandle.alpha = 0.0;
    self.homeBarView.alpha = 0.0;

    [UIView animateKeyframesWithDuration:0.42 delay:0 options:UIViewKeyframeAnimationOptionCalculationModeCubic | UIViewAnimationOptionBeginFromCurrentState animations:^{
        // Animate a visual proxy only; the UIWindow itself moves after the animation completes.
        [UIView addKeyframeWithRelativeStartTime:0.0 relativeDuration:0.42 animations:^{
            minimizeContainer.center = stageCenter;
            minimizeContainer.transform = CGAffineTransformMakeScale(stageScaleX, stageScaleY);
            minimizeContainer.alpha = 0.94;
            minimizeContainer.layer.shadowOpacity = 0.08;
            minimizeContainer.layer.shadowRadius = 10.0;
            minimizeContainer.layer.shadowPath = [UIBezierPath bezierPathWithRoundedRect:minimizeContainer.bounds cornerRadius:self.clippingContainer.layer.cornerRadius * 1.8].CGPath;
            minimizeSnapshot.layer.cornerRadius = self.clippingContainer.layer.cornerRadius * 1.8;
        }];

        [UIView addKeyframeWithRelativeStartTime:0.22 relativeDuration:0.48 animations:^{
            minimizeContainer.center = finalCenter;
            minimizeContainer.transform = CGAffineTransformMakeScale(finalScaleX, finalScaleY);
            minimizeContainer.alpha = 0.0;
            minimizeContainer.layer.shadowOpacity = 0.0;
            minimizeContainer.layer.shadowPath = [UIBezierPath bezierPathWithRoundedRect:minimizeContainer.bounds cornerRadius:finalCornerRadius].CGPath;
            minimizeSnapshot.layer.cornerRadius = finalCornerRadius;
        }];

        [UIView addKeyframeWithRelativeStartTime:0.45 relativeDuration:0.20 animations:^{
            self.stashGrabber.alpha = 0.72;
            self.appIconMiniView.transform = CGAffineTransformMakeScale(0.88, 0.88);
        }];
        [UIView addKeyframeWithRelativeStartTime:0.62 relativeDuration:0.38 animations:^{
            self.stashGrabber.alpha = 1.0;
            self.stashGrabber.bounds = CGRectMake(0, 0, kCV3StashIconSize, kCV3StashIconSize);
            self.stashGrabber.center = CGPointMake(CGRectGetMidX(targetFrameInWindow), CGRectGetMidY(targetFrameInWindow));
            [self applyStashedGrabberOrientation];
            self.appIconMiniView.frame = CGRectInset(self.stashGrabber.bounds, kCV3StashIconInset, kCV3StashIconInset);
            self.appIconMiniView.transform = CGAffineTransformIdentity;
        }];
    } completion:^(BOOL finished) {
        [minimizeContainer removeFromSuperview];
        self.frame = targetFrame;
        [self visualShadowLayer].shadowOpacity = 0.0;
        [self visualShadowLayer].shadowRadius = 0.0;
        [self visualShadowLayer].shadowOffset = CGSizeZero;
        [self visualShadowLayer].shadowPath = nil;
        self.appContentWrapper.transform = CGAffineTransformIdentity;
        self.appContentWrapper.alpha = 0.0;
        [self.hostView removeFromSuperview];
        [self normalizeStashedGrabberLayout];
        CV3UpdateFloatingBackdrop(self.windowScene);
    }];
}

- (void)applyStashedGrabberOrientation {
    self.stashGrabber.transform = self.baseRotationTransform;
}

- (void)normalizeStashedGrabberLayout {
    if (!self.isStashed) return;
    self.rootTransformContainer.transform = CGAffineTransformIdentity;
    self.rootTransformContainer.frame = self.bounds;
    self.stashGrabber.bounds = CGRectMake(0, 0, kCV3StashIconSize, kCV3StashIconSize);
    self.stashGrabber.center = CGPointMake(CGRectGetMidX(self.bounds), CGRectGetMidY(self.bounds));
    [self applyStashedGrabberOrientation];
    self.stashGrabber.alpha = 1.0;
    self.stashGrabber.userInteractionEnabled = YES;
    self.appIconMiniView.frame = CGRectInset(self.stashGrabber.bounds, kCV3StashIconInset, kCV3StashIconInset);
    self.appIconMiniView.transform = CGAffineTransformIdentity;
    [self bringSubviewToFront:self.stashGrabber];
    [self syncWindowShadowForCurrentState];
}

- (void)updateAdaptiveColor {
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        UIImage *icon = [UIImage _applicationIconImageForBundleIdentifier:self.bundleID format:10 scale:[UIScreen mainScreen].scale];
        UIColor *avgColor = CV3AverageColorFromImage(icon);
        dispatch_async(dispatch_get_main_queue(), ^{
            self.adaptiveAppColor = avgColor ?: [UIColor labelColor];
            self.appIconMiniView.image = icon;
            if (self.largeSplashIcon) {
                self.largeSplashIcon.image = icon;
            }
            [self updateResizeHandleAppearance];
            [self updateFloatingHomeBarAppearance];
        });
    });
}
- (void)triggerCollisionImpulseAtPoint:(CGPoint)point {
    UIImpactFeedbackGenerator *rigid = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleRigid];
    [rigid impactOccurredWithIntensity:1.0];
}

- (UIImage *)sparkImageWithColor:(UIColor *)color {
    CGFloat size = 20.0;
    UIGraphicsBeginImageContextWithOptions(CGSizeMake(size, size), NO, 0);
    CGContextRef context = UIGraphicsGetCurrentContext();
    CGContextAddEllipseInRect(context, CGRectMake(0, 0, size, size));
    [color setFill];
    CGContextFillPath(context);
    UIImage *image = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return image;
}

- (void)triggerCollisionImpulse {
    [self triggerCollisionImpulseAtPoint:self.center];
}

- (void)applyCurrentTransformWithScale:(CGFloat)scale {
    CGAffineTransform transform = self.baseRotationTransform;
    if (scale != 1.0) {
        transform = CGAffineTransformScale(transform, scale, scale);
    }
    self.transform = CGAffineTransformIdentity; // Keep physical upright
    self.rootTransformContainer.transform = transform;
}

- (CALayer *)visualShadowLayer {
    return self.appContentWrapper ? self.appContentWrapper.layer : self.layer;
}

- (void)clearOuterWindowShadow {
    self.layer.shadowPath = nil;
    self.layer.shadowOpacity = 0.0;
    self.layer.shadowRadius = 0.0;
    self.layer.shadowOffset = CGSizeZero;
}

- (CGRect)currentVisualShadowFrame {
    return self.appContentWrapper ? self.appContentWrapper.bounds : self.bounds;
}

- (void)syncWindowShadowForCurrentState {
    CALayer *shadowLayer = [self visualShadowLayer];
    [self clearOuterWindowShadow];
    [shadowLayer removeAnimationForKey:@"shadowRadius"];
    [shadowLayer removeAnimationForKey:@"shadowOpacity"];
    [shadowLayer removeAnimationForKey:@"shadowOffset"];
    shadowLayer.shadowColor = [UIColor blackColor].CGColor;

    if (self.isStashed) {
        shadowLayer.shadowPath = nil;
        shadowLayer.shadowOpacity = 0.0;
        shadowLayer.shadowRadius = 0.0;
        shadowLayer.shadowOffset = CGSizeZero;
        return;
    }

    CGFloat minEdge = MIN(self.bounds.size.width, self.bounds.size.height);
    CGFloat adaptiveRadius = MAX(CV3Style.adaptiveCornerRadiusMin, MIN(CV3Style.adaptiveCornerRadiusMax, minEdge * CV3Style.adaptiveCornerRadiusRatio));
    shadowLayer.shadowPath = [UIBezierPath bezierPathWithRoundedRect:[self currentVisualShadowFrame] cornerRadius:adaptiveRadius].CGPath;
    shadowLayer.shadowOpacity = self.isFocused ? CV3Style.shadowOpacityFocused : CV3Style.shadowOpacityUnfocused;
    shadowLayer.shadowRadius = self.isFocused ? CV3Style.shadowRadiusFocused : CV3Style.shadowRadiusUnfocused;
    shadowLayer.shadowOffset = CGSizeMake(0, self.isFocused ? CV3Style.shadowOffsetFocusedY : CV3Style.shadowOffsetUnfocusedY);
}

- (void)layoutSubviews {
    if (self.isStashed || self.isInLayout) return; 
    self.isInLayout = YES;

    UIInterfaceOrientation activeOrientation = CV3TrustedInterfaceOrientation(self.windowScene);
    self.targetOrientation = activeOrientation;
    [self enforcePortraitWindowGeometry];
    
    // [Safety] 移除在 layoutSubviews 中直接修改 bounds 的逻辑，该逻辑已移至 setTargetOrientation 或全局同步 Hook。
    // 直接调用 super 进行基础布局。
    [super layoutSubviews];
    
    CGRect physicalFrame = self.bounds;
    CGFloat fullW = physicalFrame.size.width;
    CGFloat fullH = physicalFrame.size.height;
    
    BOOL isLandscape = UIInterfaceOrientationIsLandscape(activeOrientation);
    CGFloat logicalW, logicalH;
    if (isLandscape) {
        logicalW = MIN(fullW, fullH);
        logicalH = MAX(fullW, fullH);
    } else {
        logicalW = fullW;
        logicalH = fullH;
    }

    self.rootTransformContainer.bounds = CGRectMake(0, 0, logicalW, logicalH);
    self.rootTransformContainer.center = CGPointMake(fullW / 2.0, fullH / 2.0);
    [self applyCurrentTransformWithScale:1.0];

    self.appContentWrapper.bounds = CGRectMake(0, 0, logicalW, logicalH);
    self.appContentWrapper.center = CGPointMake(logicalW / 2.0, logicalH / 2.0);

    [self layoutFloatingHomeBarForBounds:self.appContentWrapper.bounds];

    CGAffineTransform jellyTransform = CGAffineTransformIdentity;
    CGFloat pushFactor = 0;
    NSInteger pushAxis = 0; // 1: X, 2: Y
    if (floatingWindows && floatingWindows.count > 1) {
        for (CV3FloatingAppWindow *other in floatingWindows) {
            if (other == self || other.isStashed || ![other isKindOfClass:[CV3FloatingAppWindow class]]) continue;
            
            CGFloat dx = self.center.x - other.center.x;
            CGFloat dy = self.center.y - other.center.y;
            CGFloat distance = sqrt(dx * dx + dy * dy);
            
            CGFloat threshold = (self.bounds.size.width + other.bounds.size.width) / 2.0 + 15.0;
            if (distance < threshold && distance > 0.1) {
                CGFloat overlap = threshold - distance;
                pushFactor = MIN(0.07, (overlap / threshold) * 0.25);
                pushAxis = (fabs(dx) > fabs(dy)) ? 1 : 2;
                break; // 每次只对最贴近的一个进行判定
            }
        }
    }
    
    if (pushFactor > 0.001) {
        self.collisionReleaseValue = pushFactor;
        self.collisionReleaseAxis = pushAxis;
        self.collisionReleaseTime = 0;
        
        CGFloat scaleX = (pushAxis == 1) ? (1.0 - pushFactor) : 1.0;
        CGFloat scaleY = (pushAxis == 2) ? (1.0 - pushFactor) : 1.0;
        jellyTransform = CGAffineTransformMakeScale(scaleX, scaleY);
    } else {
        if (self.collisionReleaseValue > 0.001) {
            if (self.collisionReleaseTime == 0) {
                self.collisionReleaseTime = CACurrentMediaTime();
            }
            NSTimeInterval elapsed = CACurrentMediaTime() - self.collisionReleaseTime;
            if (elapsed < 0.4) {
                CGFloat decay = exp(-elapsed * 10.0);
                CGFloat overshoot = self.collisionReleaseValue * decay * sin(elapsed * 25.0);
                
                CGFloat scaleX = (self.collisionReleaseAxis == 1) ? (1.0 + overshoot) : 1.0;
                CGFloat scaleY = (self.collisionReleaseAxis == 2) ? (1.0 + overshoot) : 1.0;
                jellyTransform = CGAffineTransformMakeScale(scaleX, scaleY);
                [self setNeedsLayout];
            } else {
                self.collisionReleaseValue = 0;
                self.collisionReleaseTime = 0;
            }
        }
    }
    self.rootTransformContainer.transform = CGAffineTransformConcat(self.rootTransformContainer.transform, jellyTransform);

    // 4. 更新子组件布局 (基于直立的逻辑坐标系)
    self.clippingContainer.bounds = CGRectMake(0, 0, logicalW, logicalH);
    self.clippingContainer.center = CGPointMake(logicalW / 2.0, logicalH / 2.0);
    
    CGFloat minEdge = MIN(logicalW, logicalH);
    CGFloat adaptiveRadius = MAX(CV3Style.adaptiveCornerRadiusMin, MIN(CV3Style.adaptiveCornerRadiusMax, minEdge * CV3Style.adaptiveCornerRadiusRatio));
    self.layer.cornerRadius = adaptiveRadius;
    self.clippingContainer.layer.cornerRadius = adaptiveRadius;
    self.clippingContainer.layer.borderWidth = 1.0 / [UIScreen mainScreen].scale;

    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    self.cyanLayer.frame = self.clippingContainer.bounds;
    self.cyanLayer.cornerRadius = adaptiveRadius;
    
    self.magentaLayer.frame = self.clippingContainer.bounds;
    self.magentaLayer.cornerRadius = adaptiveRadius;
    
    self.innerGlowLayer.frame = self.clippingContainer.bounds;
    self.innerGlowLayer.cornerRadius = adaptiveRadius;
    
    self.specularHighlight.frame = self.clippingContainer.bounds;
    self.specularHighlight.cornerRadius = adaptiveRadius;
    [CATransaction commit];

    // 5. 更新内部 App 场景 (等比铺满算法：基于直立窗口比例动态映射虚拟画布)
    if (self.hostContainerProxy) {
        CGRect virtualBounds = [self currentHostedSceneBounds];
        CGFloat scaleX = logicalW / MAX(virtualBounds.size.width, 1.0);
        CGFloat scaleY = logicalH / MAX(virtualBounds.size.height, 1.0);
        CGFloat uniformScale = MIN(scaleX, scaleY);
        
        if (!self.liveResizeSnapshotView) {
            [self syncHostedSceneLayoutForce:NO];
        }

        self.hostContainerProxy.transform = CGAffineTransformIdentity;
        self.hostContainerProxy.bounds = virtualBounds; 
        if (self.hostView) {
            self.hostView.transform = CGAffineTransformIdentity;
            self.hostView.frame = virtualBounds;
        }
        self.hostContainerProxy.layer.anchorPoint = CGPointMake(0.5, 0.5);
        self.hostContainerProxy.center = CGPointMake(logicalW / 2.0, logicalH / 2.0);
        self.hostContainerProxy.transform = CGAffineTransformMakeScale(uniformScale, uniformScale);
    }
    if (self.homeBarView && self.homeBarView.superview) {
        [self.homeBarView.superview bringSubviewToFront:self.homeBarView];
    }
    
    if (!self.isLiveResizing) {
        [self visualShadowLayer].shadowPath = [UIBezierPath bezierPathWithRoundedRect:[self currentVisualShadowFrame] cornerRadius:adaptiveRadius].CGPath;
    }
    
    self.isInLayout = NO;
}

- (void)clampToScreenBounds {
    if (self.isStashed) return; // 隐藏状态下跳过钳位，允许 origin.x 超出屏幕
    
    UIEdgeInsets safeArea = [self currentSafeAreaInsets];
    CGRect screenBounds = CV3DisplayBoundsForWindow(self);
    
    CGRect frame = self.frame;
    CGFloat breath = CV3Style.safeAreaBreath;
    if (frame.origin.x < safeArea.left + breath) frame.origin.x = safeArea.left + breath;
    if (frame.origin.y < safeArea.top + breath) frame.origin.y = safeArea.top + breath;
    if (CGRectGetMaxX(frame) > screenBounds.size.width - safeArea.right - breath) frame.origin.x = screenBounds.size.width - safeArea.right - breath - frame.size.width;
    if (CGRectGetMaxY(frame) > screenBounds.size.height - safeArea.bottom - breath) frame.origin.y = screenBounds.size.height - safeArea.bottom - breath - frame.size.height;
    
    // 核心修复：严禁在有 Transform (如缩放/旋转) 的情况下直接设置 frame。
    // 使用 center 进行平移钳位，确保不会触发无限抖动。
    self.center = CGPointMake(CGRectGetMidX(frame), CGRectGetMidY(frame));
}

- (FBScene *)getSceneForBundleID:(NSString *)bundleID {
    @try {
        SBApplication *app = [[CV3ClassNamed(@"SBApplicationController") sharedInstance] applicationWithBundleIdentifier:bundleID];
        if ([app respondsToSelector:@selector(mainScene)]) {
            FBScene *scene = [app mainScene];
            // 核心修复：严禁返回已失效或正在销毁的场景，强制触发重试逻辑等待新场景创建
            if (scene && !CV3InvokeBool(scene, @selector(isValid), YES)) {
                CV3LogToFile(@"[Debug] 忽略无效的旧场景: %@", bundleID);
            } else if (scene) {
                return scene;
            }
        }
        
        FBSceneManager *manager = [CV3ClassNamed(@"FBSceneManager") sharedInstance];
        
        // iOS 16 fallback: check if 'scenes' property exists (returns NSSet)
        if ([manager respondsToSelector:@selector(scenes)]) {
            id scenesSet = [manager valueForKey:@"scenes"];
            if ([scenesSet isKindOfClass:[NSSet class]]) {
                for (FBScene *scene in scenesSet) {
                    if ([scene.identifier containsString:bundleID]) {
                        if (!CV3InvokeBool(scene, @selector(isValid), YES)) continue;
                        return scene;
                    }
                }
            }
        }
        
        NSDictionary *scenes = nil;
        
        @try {
            id workspace = [manager valueForKey:@"_workspace"];
            scenes = [workspace valueForKey:@"_allScenesByID"];
        } @catch (NSException *e) {
            scenes = nil;
        }
        
        if (!scenes) {
            @try {
                scenes = [manager valueForKey:@"_scenesByID"];
            } @catch (NSException *e) {
                scenes = nil;
            }
        }
        
        for (NSString *key in scenes.allKeys) {
            if ([key containsString:bundleID]) {
                FBScene *scene = scenes[key];
                if (!CV3InvokeBool(scene, @selector(isValid), YES)) continue;
                return scene;
            }
        }
    } @catch (NSException *e) {
        CV3LogToFile(@"[Error] getSceneForBundleID failed: %@", e);
    }
    return nil;
}

- (void)attemptToHostSceneWithRetries:(int)retries delay:(double)delay {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        @try {
            FBScene *targetScene = [self getSceneForBundleID:self.bundleID];
            
            if (targetScene) {
                self.targetScene = targetScene;
                CV3LogToFile(@"[Debug] 找到场景: %@ (retries left: %d)", self.bundleID, retries);
                
                // Step 1: 确保 Scene 已准备好被托管
                FBSMutableSceneSettings *settings = [[targetScene settings] mutableCopy];
                [self applyForegroundSovereigntyToSettings:settings clearDeactivation:YES forceLayout:YES];

                [targetScene updateSettings:settings withTransitionContext:nil];
                
                if ([targetScene respondsToSelector:@selector(_setContentState:)]) {
                    [targetScene _setContentState:2]; // Ready
                }
                
                // Step 2: 优先重用已有的渲染视图，避免在 Scene 尚未完全就绪前重建引发死视图黑屏
                @try {
                    _UISceneLayerHostContainerView *hostedView = (_UISceneLayerHostContainerView *)self.hostView;
                    BOOL isReused = (hostedView != nil);
                    if (!hostedView) {
                        hostedView = [[CV3ClassNamed(@"_UISceneLayerHostContainerView") alloc] initWithScene:targetScene debugDescription:@"ChevronV3Host"];
                    }
                    
                    UIScenePresentationContext *context = [[CV3ClassNamed(@"UIScenePresentationContext") alloc] _initWithDefaultValues];
                    if ([context respondsToSelector:@selector(setPresentedLayerTypes:)]) {
                        // [Safety Restore] 恢复至 7 (1|2|4)，确保键盘可弹出。
                        [context setPresentedLayerTypes:7]; 
                    }
                    if ([context respondsToSelector:@selector(setAppearanceStyle:)]) {
                        [context setAppearanceStyle:2];
                    }
                    if ([context respondsToSelector:@selector(setClipsToBounds:)]) {
                        [context setClipsToBounds:YES];
                    }
                    
                    CV3InvokeObject1(hostedView, @selector(_setPresentationContext:), context);
                    
                    if (hostedView) {
                        hostedView.layer.cornerRadius = 0;
                        hostedView.layer.masksToBounds = YES;
                        
                        self.hostView = hostedView;
                        self.hostView.accessibilityIdentifier = @"ChevronV3Host";
                        
                        // 核心：将真实画面插入 Splash 之下，确保过渡动画淡出时能自然显露内容
                        if (!hostedView.superview) {
                            if (self.splashView) {
                                [self.hostContainerProxy insertSubview:hostedView belowSubview:self.splashView];
                            } else {
                                [self.hostContainerProxy addSubview:hostedView];
                            }
                        }
                        
                        CV3LogToFile(isReused ? @"[Debug] 成功重用已有的 _UISceneLayerHostContainerView" : @"[Debug] 成功通过 _UISceneLayerHostContainerView 创建渲染视图");
                        
                        [self syncWindowBoundsToClient];
                        [self dismissLaunchSplashAnimated];
                    } else {
                        CV3LogToFile(@"[Error] _UISceneLayerHostContainerView 创建/重用失败");
                    }
                } @catch (NSException *e) {
                    CV3LogToFile(@"[Error] 获取 SceneContainerView 失败: %@", e);
                }
            } else {
                CV3LogToFile(@"[Debug] 未找到场景: %@", self.bundleID);
                if (retries > 0) {
                    [self attemptToHostSceneWithRetries:retries - 1 delay:delay * 1.2];
                } else {
                    CV3LogToFile(@"[Error] targetScene not found after launch for %@", self.bundleID);
                }
            }
        } @catch (NSException *e) {
            CV3LogToFile(@"[Error] Floating window load scene failed: %@", e);
        }
    });
}

- (void)loadAppScene {
    dispatch_async(dispatch_get_main_queue(), ^{
        @try {
            [self ensureLaunchSplashVisible];
            [[UIApplication sharedApplication] launchApplicationWithIdentifier:self.bundleID suspended:YES];
            
            // [Foreground Sovereignty] Inject RunningBoard assertion to prevent process suspension
            if (self.rbsAssertion) {
                [self.rbsAssertion invalidate];
                self.rbsAssertion = nil;
            }
            
            @try {
                RBSProcessIdentity *identity = [CV3ClassNamed(@"RBSProcessIdentity") identityForEmbeddedApplicationIdentifier:self.bundleID];
                RBSTarget *target = [CV3ClassNamed(@"RBSTarget") targetWithProcessIdentity:identity];
                
                // 使用 UserInteractive 域和 Foreground 属性，模拟原生前台 App 的优先级
                RBSDomainAttribute *foregroundAttr = [CV3ClassNamed(@"RBSDomainAttribute") attributeWithDomain:@"com.apple.common" name:@"UserInteractive"];
                
                self.rbsAssertion = [[CV3ClassNamed(@"RBSAssertion") alloc] initWithExplanation:[NSString stringWithFormat:@"ChevronV3 Sovereignty for %@", self.bundleID] 
                                                                           target:target 
                                                                       attributes:@[foregroundAttr]];
                
                NSError *error = nil;
                if ([self.rbsAssertion acquireWithError:&error]) {
                    CV3LogToFile(@"[Immortality] 成功为 %@ 注入前台优先级断连 (RBSAssertion)", self.bundleID);
                } else {
                    CV3LogToFile(@"[Error] RBSAssertion 注入失败: %@", error);
                }
            } @catch (NSException *e) {
                CV3LogToFile(@"[Error] RBSAssertion 流程异常: %@", e);
            }

            // Start polling with initial delay of 0.3s, up to 10 retries (more resilient for cold starts)
            [self attemptToHostSceneWithRetries:10 delay:0.3];
            
            // [Safety] 增加全局超时保护：如果 12 秒后还没进入内容，强制移除 Splash，防止界面永久卡死
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(12.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                if (self.splashView) {
                    CV3LogToFile(@"[Safety] 触发启动超时强制恢复: %@", self.bundleID);
                    [self dismissLaunchSplashAnimated];
                }
            });
        } @catch (NSException *e) {
            CV3LogToFile(@"[Error] Floating window launch failed: %@", e);
        }
    });
}

- (void)handleMoveLongPress:(UIGestureRecognizer *)gesture {
    static CGPoint initialTouchOffset;
    static CGPoint lastVelocity;
    static NSTimeInterval lastTime;
    
    CGPoint currentPoint = [gesture locationInView:nil];
    CGRect screen = CV3DisplayBoundsForWindow(self);
    
    if (gesture.state == UIGestureRecognizerStateBegan) {
        CV3LogToFile(@"[MoveGesture] handleMoveLongPress state began. Dismissing multitaskingMenu");
        [self dismissMultitaskingMenu];
        if (!self.isStashed) {
            self.stashGrabber.alpha = 0;
            self.clippingContainer.alpha = 1.0;
            self.appContentWrapper.alpha = 1.0;
            self.appContentWrapper.transform = CGAffineTransformIdentity;
            self.resizeHandle.alpha = 1.0;
            self.homeBarView.alpha = 1.0;
        }
        self.isFullscreenMode = NO;
        self.isCompactMode = NO;
        [self setWindowFocused:YES];
        CGPoint centerInWindow = self.center;
        initialTouchOffset = CGPointMake(currentPoint.x - centerInWindow.x, currentPoint.y - centerInWindow.y);
        
        self.windowLevel = CV3Style.floatingApp + 10;
        [self startLiquidMotion];
        
        CGFloat minEdge = MIN(self.bounds.size.width, self.bounds.size.height);
        CGFloat adaptiveRadius = MAX(CV3Style.adaptiveCornerRadiusMin, MIN(CV3Style.adaptiveCornerRadiusMax, minEdge * CV3Style.adaptiveCornerRadiusRatio));
        [self visualShadowLayer].shadowPath = [UIBezierPath bezierPathWithRoundedRect:[self currentVisualShadowFrame] cornerRadius:adaptiveRadius].CGPath;
        [UIView animateWithDuration:0.3 animations:^{
            [self visualShadowLayer].shadowOpacity = CV3Style.shadowOpacityPeak;
            [self visualShadowLayer].shadowRadius = CV3Style.shadowRadiusPeak;
            [self applyCurrentTransformWithScale:1.05];
        }];
        
        self.lastTargetSnapFrame = CGRectZero;
        lastTime = CACurrentMediaTime();
        lastVelocity = CGPointZero;
        
        UIImpactFeedbackGenerator *gen = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleMedium];
        [gen impactOccurred];
    }
    
    if (gesture.state == UIGestureRecognizerStateChanged) {
        NSTimeInterval now = CACurrentMediaTime();
        CGFloat dt = now - lastTime;
        if (dt > 0) {
            lastVelocity = CGPointMake((currentPoint.x - (self.center.x + initialTouchOffset.x)) / dt, (currentPoint.y - (self.center.y + initialTouchOffset.y)) / dt);
        }
        lastTime = now;

        // 1. 更新位置
        self.center = CGPointMake(currentPoint.x - initialTouchOffset.x, currentPoint.y - initialTouchOffset.y);
        
        // 2. 更新惯性拉伸阴影与高度抬起
        CGFloat speed = sqrt(lastVelocity.x * lastVelocity.x + lastVelocity.y * lastVelocity.y);
        CGFloat elevationBoost = MIN(CV3Style.dragLagShadowElevationMax, speed * CV3Style.dragLagShadowElevationFactor);
        
        CGFloat dx = -lastVelocity.x * CV3Style.dragLagShadowFactor;
        CGFloat dy = -lastVelocity.y * CV3Style.dragLagShadowFactor + CV3Style.shadowOffsetPeakY + elevationBoost;
        CGFloat maxOffset = CV3Style.dragLagShadowMaxOffset;
        dx = MAX(-maxOffset, MIN(maxOffset, dx));
        dy = MAX(-maxOffset + CV3Style.shadowOffsetPeakY + elevationBoost, MIN(maxOffset + CV3Style.shadowOffsetPeakY + elevationBoost, dy));
        
        [CATransaction begin];
        [CATransaction setDisableActions:YES];
        [self visualShadowLayer].shadowRadius = CV3Style.shadowRadiusPeak + elevationBoost;
        [self visualShadowLayer].shadowOpacity = CV3Style.shadowOpacityPeak - elevationBoost * 0.005;
        [self visualShadowLayer].shadowOffset = CGSizeMake(dx, dy);
        [CATransaction commit];
        
        // --- Magnetic Window Alignment ---
        CGFloat magnetThreshold = 30.0;
        for (CV3FloatingAppWindow *other in floatingWindows) {
            if (other == self || other.isStashed || ![other isKindOfClass:[CV3FloatingAppWindow class]]) continue;
            CGRect otherFrame = other.frame;
            if (fabs(CGRectGetMaxX(self.frame) - otherFrame.origin.x) < magnetThreshold) {
                self.center = CGPointMake(otherFrame.origin.x - self.frame.size.width / 2.0 - 5.0, self.center.y);
            } else if (fabs(self.frame.origin.x - CGRectGetMaxX(otherFrame)) < magnetThreshold) {
                self.center = CGPointMake(CGRectGetMaxX(otherFrame) + self.frame.size.width / 2.0 + 5.0, self.center.y);
            }
        }
    }
    
    if (gesture.state == UIGestureRecognizerStateEnded || gesture.state == UIGestureRecognizerStateCancelled) {
        [self stopLiquidMotion];
        CGFloat velMag = sqrt(lastVelocity.x * lastVelocity.x + lastVelocity.y * lastVelocity.y);
        if (velMag > 2500.0) {
            BOOL towardLeft = (lastVelocity.x < -1800 && self.center.x < 150);
            BOOL towardRight = (lastVelocity.x > 1800 && self.center.x > screen.size.width - 150);
            BOOL towardTop = (lastVelocity.y < -1800 && self.center.y < 150);
            
            if (towardLeft || towardRight || towardTop) {
                [[[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleMedium] impactOccurred];
                [UIView animateWithDuration:0.45 delay:0 options:UIViewAnimationOptionCurveEaseIn animations:^{
                    self.center = CGPointMake(self.center.x + lastVelocity.x * 0.15, self.center.y + lastVelocity.y * 0.15);
                    self.transform = CGAffineTransformScale(self.transform, 0.01, 0.01);
                    self.alpha = 0;
                } completion:^(BOOL finished) {
                    [self closeWindow];
                }];
                return;
            }
        }

            [UIView animateWithDuration:0.5 delay:0 usingSpringWithDamping:0.7 initialSpringVelocity:0.5 options:UIViewAnimationOptionCurveEaseInOut animations:^{
                [self applyCurrentTransformWithScale:1.0];
                self.windowLevel = CV3Style.floatingApp;
            
            self.isStashed = NO;
            self.stashedSide = 0;
            self.stashGrabber.alpha = 0;
            self.clippingContainer.alpha = 1.0;
            self.appContentWrapper.alpha = 1.0;
            self.appContentWrapper.transform = CGAffineTransformIdentity;
            self.resizeHandle.alpha = 1.0;

            CGRect targetFrame = self.frame;
            UIEdgeInsets safeArea = [self currentSafeAreaInsets];
            CGFloat breath = CV3Style.safeAreaBreath;
            CGFloat minX = safeArea.left + breath;
            CGFloat minY = safeArea.top + breath;
            CGFloat maxX = screen.size.width - safeArea.right - breath - targetFrame.size.width;
            CGFloat maxY = screen.size.height - safeArea.bottom - breath - targetFrame.size.height;

            if (maxX < minX) maxX = minX;
            if (maxY < minY) maxY = minY;

            targetFrame.origin.x = MIN(MAX(targetFrame.origin.x, minX), maxX);
            targetFrame.origin.y = MIN(MAX(targetFrame.origin.y, minY), maxY);
            
            if (!CGRectEqualToRect(targetFrame, self.frame)) {
                self.frame = targetFrame;
            }
        } completion:^(BOOL finished) {
            [self enforceSceneForegroundState];
            [self refreshHostViewPresentation];
            [self syncWindowBoundsToClient];
            CV3UpdateFloatingBackdrop(self.windowScene);
        }];
        
        [self animateFocusShadow:self.isFocused];
    }
}

- (void)updateGrabberStack {
    // 移除旧的堆叠视觉
    for (UIView *sub in self.stashGrabber.subviews) {
        if (sub.tag == 99) [sub removeFromSuperview];
    }
    
    int stashedCount = 0;
    NSMutableArray *otherStashedWindows = [NSMutableArray array];
    for (CV3FloatingAppWindow *win in floatingWindows) {
        if (win.isStashed && win.stashedSide == self.stashedSide && win != self) {
            stashedCount++;
            [otherStashedWindows addObject:win];
        }
    }
    
    if (stashedCount > 0) {
        // 建议：Prism Stacking (棱镜堆叠视觉)
        // ... (保持原有的图标堆叠视觉逻辑) ...
    }

    // 核心修复：由于窗口本身已缩小为图标，堆叠时需要移动整个窗口的位置
    CGFloat stackOffset = 48.0; // 每个图标之间的垂直间距
    CGRect currentFrame = self.frame;
    currentFrame.origin.y = self.preStashFrame.origin.y + self.preStashFrame.size.height / 2.0 - (kCV3StashIconSize * 0.5) + (stashedCount * stackOffset);

    [UIView animateWithDuration:0.4 delay:0 usingSpringWithDamping:0.8 initialSpringVelocity:0 options:0 animations:^{
        self.frame = currentFrame;
    } completion:nil];
    }
- (void)handleRestoreTap:(UITapGestureRecognizer *)gesture {
    [self restoreFromStash];
}

- (void)restoreFromStash {
    [self dismissMultitaskingMenu];
    // 恢复为普通 App 之上的浮窗层级，保留系统通知栏/控制中心在上方
    self.windowLevel = CV3Style.floatingApp; 
    [self makeKeyAndVisible];
    self.windowLevel = CV3Style.floatingApp;
    [self setWindowFocused:YES];

    if (self.isStashed) {
        UIImpactFeedbackGenerator *gen = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleLight];
        [gen impactOccurred];

        CGRect iconFrame = self.frame;
        UIView *iconProxy = [self.stashGrabber snapshotViewAfterScreenUpdates:NO];
        CGPoint preferredCenter = CGRectIsEmpty(self.preStashFrame) ? self.center : CGPointMake(CGRectGetMidX(self.preStashFrame), CGRectGetMidY(self.preStashFrame));
        CGRect targetFrame = [self restorableFrameForOrientation:self.targetOrientation preferredCenter:preferredCenter];
        self.preStashFrame = targetFrame;
        self.stashGrabber.alpha = 0.0;

        self.isStashed = NO; // 先解除 Stash 标志，以便下面 updateSettings 时能被识别为前台
        CV3CascadeUpdateSovereigntyAssertions(); // 级联刷新所有窗口前台优先级断言

        // 核心修复：如果已有的 hostView 存在，立即加回层级中并设为可见，避免黑屏/渲染延迟
        if (self.hostView && !self.hostView.superview) {
            if (self.splashView) {
                [self.hostContainerProxy insertSubview:self.hostView belowSubview:self.splashView];
            } else {
                [self.hostContainerProxy addSubview:self.hostView];
            }
            self.hostView.hidden = NO;
            self.hostView.alpha = 1.0;
        }

        self.frame = targetFrame;
        [self enforcePortraitWindowGeometry];
        self.stashedSide = 0;
        [self syncHostedSceneLayoutForce:YES];
        [self setNeedsLayout];
        [self layoutIfNeeded];

        [self enforceSceneForegroundState]; // 立即通知 SpringBoard 将 FBScene 拉回前台
        [self attemptToHostSceneWithRetries:10 delay:0.05]; // 异步拉回渲染视图，50ms 延迟足够让 Scene 状态生效并挂载

        self.stashGrabber.alpha = 0.0;
        self.appContentWrapper.transform = CGAffineTransformIdentity;
        self.appContentWrapper.alpha = 1.0;
        self.clippingContainer.alpha = 1.0;
        self.clippingContainer.transform = CGAffineTransformIdentity;
        self.resizeHandle.alpha = 1.0;
        self.homeBarView.alpha = 1.0;

        CGRect endFrameInWindow = [self convertRect:self.appContentWrapper.bounds fromView:self.appContentWrapper];
        CGRect startFrameInWindow = CGRectOffset(iconFrame, -targetFrame.origin.x, -targetFrame.origin.y);
        UIView *restoreSnapshot = [self.appContentWrapper snapshotViewAfterScreenUpdates:YES];
        if (!restoreSnapshot) {
            restoreSnapshot = [self.appContentWrapper snapshotViewAfterScreenUpdates:NO];
        }
        if (!restoreSnapshot) {
            restoreSnapshot = [self.hostContainerProxy snapshotViewAfterScreenUpdates:YES];
        }
        if (!restoreSnapshot) {
            restoreSnapshot = [self.hostContainerProxy snapshotViewAfterScreenUpdates:NO];
        }

        self.appContentWrapper.alpha = 0.0;
        self.resizeHandle.alpha = 0.0;
        self.homeBarView.alpha = 0.0;
        [self syncWindowShadowForCurrentState];
        [self visualShadowLayer].shadowOpacity = 0.0;
        [self visualShadowLayer].shadowRadius = 0.0;
        [self visualShadowLayer].shadowOffset = CGSizeZero;
        [self visualShadowLayer].shadowPath = nil;

        if (!restoreSnapshot) {
            self.appContentWrapper.alpha = 1.0;
            self.resizeHandle.alpha = 1.0;
            self.homeBarView.alpha = 1.0;
            [self syncWindowShadowForCurrentState];
            [self animateFocusShadow:self.isFocused];
            CV3UpdateFloatingBackdrop(self.windowScene);
            for (CV3FloatingAppWindow *win in floatingWindows) {
                if (win.isStashed) [win updateGrabberStack];
            }
            return;
        }

        UIView *restoreContainer = [[UIView alloc] initWithFrame:endFrameInWindow];
        restoreContainer.backgroundColor = [UIColor clearColor];

        UIView *restoreRotatedContent = [[UIView alloc] initWithFrame:CGRectMake(0, 0, self.appContentWrapper.bounds.size.width, self.appContentWrapper.bounds.size.height)];
        restoreRotatedContent.backgroundColor = [UIColor clearColor];
        restoreRotatedContent.center = CGPointMake(CGRectGetMidX(restoreContainer.bounds), CGRectGetMidY(restoreContainer.bounds));
        restoreRotatedContent.transform = self.baseRotationTransform;

        restoreSnapshot.frame = restoreRotatedContent.bounds;
        restoreSnapshot.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        restoreSnapshot.layer.cornerRadius = self.clippingContainer.layer.cornerRadius;
        restoreSnapshot.layer.masksToBounds = YES;
        [restoreRotatedContent addSubview:restoreSnapshot];
        [restoreContainer addSubview:restoreRotatedContent];
        [self addSubview:restoreContainer];

        if (!iconProxy) {
            UIImageView *fallbackIconProxy = [[UIImageView alloc] initWithFrame:CGRectInset(startFrameInWindow, 4, 4)];
            fallbackIconProxy.image = self.appIconMiniView.image;
            fallbackIconProxy.layer.cornerRadius = CV3Style.iconCornerRadius;
            fallbackIconProxy.layer.masksToBounds = YES;
            fallbackIconProxy.contentMode = UIViewContentModeScaleAspectFill;
            fallbackIconProxy.transform = self.baseRotationTransform;
            iconProxy = fallbackIconProxy;
        } else {
            iconProxy.frame = startFrameInWindow;
        }
        [self addSubview:iconProxy];

        CGPoint startCenter = CGPointMake(CGRectGetMidX(startFrameInWindow), CGRectGetMidY(startFrameInWindow));
        CGPoint endCenter = restoreContainer.center;
        CGPoint stageCenter = CGPointMake(endCenter.x + (startCenter.x - endCenter.x) * 0.58,
                                          endCenter.y - MIN(18.0, targetFrame.size.height * 0.04));
        CGFloat startScaleX = startFrameInWindow.size.width / MAX(endFrameInWindow.size.width, 1.0);
        CGFloat startScaleY = startFrameInWindow.size.height / MAX(endFrameInWindow.size.height, 1.0);
        CGFloat stageScaleX = MAX(startScaleX * 3.4, 0.42);
        CGFloat stageScaleY = MAX(startScaleY * 5.0, 0.82);
        CGFloat startCornerRadius = CV3Style.iconCornerRadius / MAX(MIN(startScaleX, startScaleY), 0.01);

        restoreContainer.center = startCenter;
        restoreContainer.transform = CGAffineTransformMakeScale(startScaleX, startScaleY);
        restoreContainer.alpha = 0.0;
        restoreSnapshot.layer.cornerRadius = startCornerRadius;

        [UIView animateKeyframesWithDuration:0.42 delay:0 options:UIViewKeyframeAnimationOptionCalculationModeCubic | UIViewAnimationOptionBeginFromCurrentState animations:^{
            [UIView addKeyframeWithRelativeStartTime:0.0 relativeDuration:0.22 animations:^{
                iconProxy.alpha = 0.0;
                iconProxy.transform = CGAffineTransformMakeScale(0.86, 0.86);
                restoreContainer.alpha = 0.34;
            }];

            [UIView addKeyframeWithRelativeStartTime:0.18 relativeDuration:0.48 animations:^{
                restoreContainer.center = stageCenter;
                restoreContainer.transform = CGAffineTransformMakeScale(stageScaleX, stageScaleY);
                restoreContainer.alpha = 0.92;
                restoreSnapshot.layer.cornerRadius = self.clippingContainer.layer.cornerRadius * 1.8;
            }];

            [UIView addKeyframeWithRelativeStartTime:0.48 relativeDuration:0.52 animations:^{
                restoreContainer.center = endCenter;
                restoreContainer.transform = CGAffineTransformIdentity;
                restoreContainer.alpha = 1.0;
                restoreSnapshot.layer.cornerRadius = self.clippingContainer.layer.cornerRadius;
            }];
        } completion:^(BOOL finished) {
            [iconProxy removeFromSuperview];
            [restoreContainer removeFromSuperview];
            self.appContentWrapper.alpha = 1.0;
            self.resizeHandle.alpha = 1.0;
            self.homeBarView.alpha = 1.0;
            [self syncWindowShadowForCurrentState];
            [self animateFocusShadow:self.isFocused];
            CV3UpdateFloatingBackdrop(self.windowScene);
            // 通知其他窗口更新堆叠状态
            for (CV3FloatingAppWindow *win in floatingWindows) {
                if (win.isStashed) [win updateGrabberStack];
            }
        }];
    } else {
        // 如果没有被隐藏，则执行轻微的脉冲动画提醒用户它已置顶
        [self triggerCollisionImpulse];
    }
}

- (void)handleStashLongPress:(UILongPressGestureRecognizer *)gesture {
    if (!self.isStashed) return;
    if (gesture.state == UIGestureRecognizerStateBegan) {
        UIImpactFeedbackGenerator *gen = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleHeavy];
        [gen impactOccurred];
        
        [UIView animateWithDuration:0.4 delay:0 usingSpringWithDamping:0.8 initialSpringVelocity:0.5 options:0 animations:^{
            self.transform = CGAffineTransformMakeScale(0.01, 0.01);
            self.alpha = 0;
        } completion:^(BOOL finished) {
            [self closeWindow];
        }];
    }
}

- (void)handleStashPan:(UIPanGestureRecognizer *)gesture {
    if (!self.isStashed) return;
    
    CGPoint translation = [gesture translationInView:nil];
    CGRect screen = CV3DisplayBoundsForWindow(self);
    
    if (gesture.state == UIGestureRecognizerStateBegan) {
        [UIView animateWithDuration:0.2 animations:^{
            [self applyCurrentTransformWithScale:1.0];
            [self visualShadowLayer].shadowOpacity = 0;
            [self visualShadowLayer].shadowRadius = 0;
        }];
        UIImpactFeedbackGenerator *gen = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleMedium];
        [gen impactOccurred];
    } else if (gesture.state == UIGestureRecognizerStateChanged) {
        // 核心修复：使用增量平移 (Incremental Translation) 替代绝对位置设置，解决“跳动”问题
        self.center = CGPointMake(self.center.x + translation.x, self.center.y + translation.y);
        [gesture setTranslation:CGPointZero inView:nil];
    } else if (gesture.state == UIGestureRecognizerStateEnded || gesture.state == UIGestureRecognizerStateCancelled) {
        [UIView animateWithDuration:0.5 delay:0 usingSpringWithDamping:0.7 initialSpringVelocity:0.5 options:0 animations:^{
            [self applyCurrentTransformWithScale:1.0];
            [self visualShadowLayer].shadowOpacity = 0;
            [self visualShadowLayer].shadowRadius = 0;
            
            // 自由拖动位置：保持在安全区域内，但不强制吸附至侧边
            UIEdgeInsets safeArea = [self currentSafeAreaInsets];
            
            CGRect frame = self.frame;
            if (frame.origin.x < safeArea.left) frame.origin.x = safeArea.left;
            if (frame.origin.y < safeArea.top) frame.origin.y = safeArea.top;
            if (CGRectGetMaxX(frame) > screen.size.width - safeArea.right) frame.origin.x = screen.size.width - safeArea.right - frame.size.width;
            if (CGRectGetMaxY(frame) > screen.size.height - safeArea.bottom) frame.origin.y = screen.size.height - safeArea.bottom - frame.size.height;
            self.frame = frame;
            
            // 重要：更新 preStashFrame，确保从当前图标位置还原
            CGRect psf = self.preStashFrame;
            psf.origin.x = self.frame.origin.x + (kCV3StashIconSize * 0.5) - psf.size.width / 2.0;
            psf.origin.y = self.frame.origin.y + (kCV3StashIconSize * 0.5) - psf.size.height / 2.0;
            self.preStashFrame = psf;
            
            // 重新判定 stashedSide 以便堆叠逻辑参考 (以中线为界)
            self.stashedSide = (self.center.x < screen.size.width / 2.0) ? 1 : 2;
            [self updateSovereigntyAssertion]; // 确保 Stash 态优先级同步
            
        } completion:^(BOOL finished) {
            UIImpactFeedbackGenerator *gen = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleLight];
            [gen impactOccurred];
            
            for (CV3FloatingAppWindow *win in floatingWindows) {
                if (win.isStashed) [win updateGrabberStack];
            }
        }];
    }
}

- (void)syncWindowBoundsToClient {
    [self syncWindowBoundsToClientAndNotify:YES];
}

- (void)syncWindowBoundsToClientAndNotify:(BOOL)notify {
    if (self.bundleID) {
        CGRect contentFrame = [self visiblePortraitContentFrame];
        
        CV3SharedGeometry *geometry = CV3SharedGeometryForBundleID(self.bundleID);
        if (geometry) {
            CV3WriteSharedGeometry(geometry, (float)contentFrame.size.width, (float)contentFrame.size.height, self.hidden ? 0 : 1);
        }
        
        // 2. 仅在需要通知的静态时刻，才落盘 Plist 提供持久化记录和兼容性
        if (notify) {
            NSString *path = @"/var/mobile/Library/Preferences/com.xu.chevronv3.plist";
            NSMutableDictionary *dict = [NSMutableDictionary dictionaryWithContentsOfFile:path] ?: [NSMutableDictionary dictionary];
            
            dict[[NSString stringWithFormat:@"isHosted_%@", self.bundleID]] = @(!self.hidden);
            dict[[NSString stringWithFormat:@"currentWidth_%@", self.bundleID]] = @(contentFrame.size.width);
            dict[[NSString stringWithFormat:@"currentHeight_%@", self.bundleID]] = @(contentFrame.size.height);
            
            [dict writeToFile:path atomically:YES];
            chmod([path UTF8String], 0644);
            
            CV3LogToFile(@"宿主窗口 (%@) 最终尺寸已同步并发送 Darwin 通知: 宽度=%.1f, 高度=%.1f", self.bundleID, contentFrame.size.width, contentFrame.size.height);
            CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(), (CFStringRef)@"com.xu.chevronv3/SizeChanged", NULL, NULL, YES);
        } else {
            // 节流状态下，由于共享内存已更新，在此处我们完全省去 Plist 磁盘操作
            CV3LogToFile(@"[Throttled] 仅共享内存同步（零磁盘 IO）: %@ -> 宽度=%.1f, 高度=%.1f", self.bundleID, contentFrame.size.width, contentFrame.size.height);
        }
    }
}

- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    if (self.isClosing || self.isStashed) return [super hitTest:point withEvent:event];

    if (self.homeBarView && !self.homeBarView.hidden && self.homeBarView.alpha > 0.01) {
        CGRect homeBarFrame = CGRectInset([self convertRect:self.homeBarView.bounds fromView:self.homeBarView], -18.0, -18.0);
        if (CGRectContainsPoint(homeBarFrame, point)) {
            CGPoint pInHomeBar = [self convertPoint:point toView:self.homeBarView];
            UIView *homeBarHit = [self.homeBarView hitTest:pInHomeBar withEvent:event];
            return homeBarHit ?: self.homeBarView;
        }
    }
    
    CGRect visibleFrame = [self visiblePortraitContentFrame];
    if (!CGRectContainsPoint(visibleFrame, point)) return nil;

    // 2. 检查侧边 Stash 区域 (仅在 Stashed 时，但此处主要处理 Active 状态)
    if (self.stashGrabber.alpha > 0.5) {
        CGPoint pInGrabber = [self convertPoint:point toView:self.stashGrabber];
        if ([self.stashGrabber pointInside:pInGrabber withEvent:event]) {
            return self.stashGrabber;
        }
    }

    CGPoint pInRoot = [self convertPoint:point toView:self.rootTransformContainer];
    UIView *rootHit = [self.rootTransformContainer hitTest:pInRoot withEvent:event];
    if (rootHit) return rootHit;

    UIView *hit = [super hitTest:point withEvent:event];
    return hit ?: (self.clippingContainer ?: self.rootTransformContainer ?: self);
}

- (BOOL)gestureRecognizerShouldBegin:(UIGestureRecognizer *)gesture {
    return YES;
}

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer shouldReceiveTouch:(UITouch *)touch {
    return YES;
}

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer shouldBeRequiredToFailByGestureRecognizer:(UIGestureRecognizer *)otherGestureRecognizer {
    // 强制要求其他手势（即来自宿主 App 内部的手势）在我们自己的控制手势面前失败
    // 这可以防止拖拽或缩放/位移窗口时，底下的 App 还在疯狂滚动
    if (gestureRecognizer.view == self.homeBarView) {
        return NO;
    }
    return NO;
}

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer shouldRequireFailureOfGestureRecognizer:(UIGestureRecognizer *)otherGestureRecognizer {
    return NO;
}

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer shouldRecognizeSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer *)otherGestureRecognizer {
    return NO;
}

- (void)handleResizePan:(UIPanGestureRecognizer *)gesture {
    static BOOL hasTriggeredTopHaptic = NO;
    static BOOL hasTriggeredBottomHaptic = NO;
    static BOOL hasTriggeredSideHaptic = NO;

    if (gesture.state == UIGestureRecognizerStateBegan) {
        [self dismissMultitaskingMenu];
        self.isFullscreenMode = NO;
        self.isCompactMode = NO;
        self.initialResizeFrame = self.frame;
        [gesture setTranslation:CGPointZero inView:nil];
        hasTriggeredTopHaptic = NO;
        hasTriggeredBottomHaptic = NO;
        hasTriggeredSideHaptic = NO;
        
        UIImpactFeedbackGenerator *gen = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleLight];
        [gen impactOccurred];

        self.isLiveResizing = YES;
        [self visualShadowLayer].shadowPath = nil;
        [self startLiquidMotion];
        [UIView animateWithDuration:0.2 animations:^{
            [self visualShadowLayer].shadowOpacity = CV3Style.shadowOpacityUnfocused * 0.5;
            self.glassBackdrop.effect = nil;
            self.glassBackdrop.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.2];
        }];

        if (self.hostView) {
            self.liveResizeSnapshotView = [self.hostView snapshotViewAfterScreenUpdates:NO];
            if (self.liveResizeSnapshotView) {
                self.liveResizeSnapshotView.frame = self.hostContainerProxy.bounds;
                self.liveResizeSnapshotView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
                [self.hostContainerProxy addSubview:self.liveResizeSnapshotView];
                self.hostView.alpha = 0;
            }
        }

        if (self.targetScene) {
            @try {
                FBSMutableSceneSettings *settings = [[self.targetScene settings] mutableCopy];
                if ([settings respondsToSelector:@selector(setInLiveResize:)]) {
                    [(UIMutableApplicationSceneSettings *)settings setInLiveResize:YES];
                    [self.targetScene updateSettings:settings withTransitionContext:nil];
                }
            } @catch (NSException *e) {
                CV3LogToFile(@"[Critical] Failed to set live resize state: %@", e);
            }
        }

    }
    
    CGPoint translation = [gesture translationInView:nil];
    
    if (gesture.state == UIGestureRecognizerStateChanged) {
        CGRect screenBounds = CV3DisplayBoundsForWindow(self);
        CGFloat shortSide = MIN(screenBounds.size.width, screenBounds.size.height);
        CGFloat longSide = MAX(screenBounds.size.width, screenBounds.size.height);
        CGFloat aspect = longSide / MAX(shortSide, 1.0);
        
        CGFloat minAllowedWidth = shortSide * 0.4;
        CGFloat maxAllowedWidth = shortSide * 0.75;
        
        CGPoint initialCenter = CGPointMake(CGRectGetMidX(self.initialResizeFrame), CGRectGetMidY(self.initialResizeFrame));
        CGPoint initialHandlePos = CGPointMake(CGRectGetMaxX(self.initialResizeFrame), CGRectGetMaxY(self.initialResizeFrame));
        CGPoint currentHandlePos = CGPointMake(initialHandlePos.x + translation.x, initialHandlePos.y + translation.y);
        
        CGFloat initialDist = sqrt(pow(initialHandlePos.x - initialCenter.x, 2) + pow(initialHandlePos.y - initialCenter.y, 2));
        CGFloat currentDist = sqrt(pow(currentHandlePos.x - initialCenter.x, 2) + pow(currentHandlePos.y - initialCenter.y, 2));
        
        CGFloat rawScaleFactor = initialDist > 0 ? (currentDist / initialDist) : 1.0;
        CGFloat scaleFactor = 1.0 + (rawScaleFactor - 1.0) * 1.25; 
        
        CGFloat initialLogicalWidth = self.initialResizeFrame.size.width;
        CGFloat targetWidth = initialLogicalWidth * scaleFactor;
        
        // --- [Geek Advice] Haptic Gradient Implementation ---
        static CGFloat lastHapticOvershoot = 0;
        CGFloat overshoot = 0;
        if (targetWidth < minAllowedWidth) overshoot = (minAllowedWidth - targetWidth) / (minAllowedWidth * 0.2);
        else if (targetWidth > maxAllowedWidth) overshoot = (targetWidth - maxAllowedWidth) / (maxAllowedWidth * 0.2);
        
        if (overshoot > 0.05 && fabs(overshoot - lastHapticOvershoot) > 0.1) {
            UIImpactFeedbackGenerator *gradientGen = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleLight];
            [gradientGen impactOccurredWithIntensity:MIN(1.0, overshoot)];
            lastHapticOvershoot = overshoot;
        } else if (overshoot <= 0.05) {
            lastHapticOvershoot = 0;
        }

        // Use copy to avoid mutation during enumeration
        NSArray *windowsSnapshot = [floatingWindows copy];
        for (CV3FloatingAppWindow *other in windowsSnapshot) {
            if (other == self || other.isStashed || ![other isKindOfClass:[CV3FloatingAppWindow class]]) continue;
            
            CGFloat distance = sqrt(pow(self.center.x - other.center.x, 2) + pow(self.center.y - other.center.y, 2));
            CGFloat minGap = (self.bounds.size.width + other.bounds.size.width) / 2.0 + 20.0;
            
            if (distance < minGap) {
                targetWidth *= (0.8 + 0.2 * (distance / minGap));
            }
        }

        CGFloat finalWidth = targetWidth;
        if (targetWidth < minAllowedWidth) {
            finalWidth = minAllowedWidth - (minAllowedWidth - targetWidth) * 0.3;
        } else if (targetWidth > maxAllowedWidth) {
            finalWidth = maxAllowedWidth + (targetWidth - maxAllowedWidth) * 0.3;
        }
        
        CGFloat finalHeight = finalWidth * aspect;
        CGFloat outerWidth = finalWidth;
        CGFloat outerHeight = finalHeight;
        
        CGRect newFrame;
        newFrame.size = CGSizeMake(outerWidth, outerHeight);
        newFrame.origin.x = initialCenter.x - outerWidth / 2.0;
        newFrame.origin.y = initialCenter.y - outerHeight / 2.0;
        
        UIEdgeInsets safeArea = [self currentSafeAreaInsets];
        
        if (newFrame.origin.y < safeArea.top && !hasTriggeredTopHaptic) {
            [[[UISelectionFeedbackGenerator alloc] init] selectionChanged];
            hasTriggeredTopHaptic = YES;
        } else if (newFrame.origin.y >= safeArea.top) {
            hasTriggeredTopHaptic = NO;
        }

        if (CGRectGetMaxY(newFrame) > screenBounds.size.height - safeArea.bottom && !hasTriggeredBottomHaptic) {
            [[[UISelectionFeedbackGenerator alloc] init] selectionChanged];
            hasTriggeredBottomHaptic = YES;
        } else if (CGRectGetMaxY(newFrame) <= screenBounds.size.height - safeArea.bottom) {
            hasTriggeredBottomHaptic = NO;
        }

        BOOL hitSide = (newFrame.origin.x < safeArea.left || CGRectGetMaxX(newFrame) > screenBounds.size.width - safeArea.right);
        if (hitSide && !hasTriggeredSideHaptic) {
            [[[UISelectionFeedbackGenerator alloc] init] selectionChanged];
            hasTriggeredSideHaptic = YES;
        } else if (!hitSide) {
            hasTriggeredSideHaptic = NO;
        }
            
        [CATransaction begin];
        [CATransaction setDisableActions:YES];
        
        self.bounds = CGRectMake(0, 0, outerWidth, outerHeight);
        self.center = CGPointMake(CGRectGetMidX(newFrame), CGRectGetMidY(newFrame));
        [CATransaction commit];
        
        // 拖动期间：仅同步 Plist 数据，节流静默 Darwin 广播通知
        [self syncWindowBoundsToClientAndNotify:NO];
    }
    
    if (gesture.state == UIGestureRecognizerStateEnded || 
        gesture.state == UIGestureRecognizerStateCancelled || 
        gesture.state == UIGestureRecognizerStateFailed) {
        
        [self stopLiquidMotion];
        
        if (gesture.state != UIGestureRecognizerStateEnded) {
            self.isLiveResizing = NO;
            CGFloat minEdge = MIN(self.bounds.size.width, self.bounds.size.height);
            CGFloat finalRadius = MAX(CV3Style.adaptiveCornerRadiusMin, MIN(CV3Style.adaptiveCornerRadiusMax, minEdge * CV3Style.adaptiveCornerRadiusRatio));
            [self visualShadowLayer].shadowPath = [UIBezierPath bezierPathWithRoundedRect:[self currentVisualShadowFrame] cornerRadius:finalRadius].CGPath;
            [self animateFocusShadow:self.isFocused];
            
            [UIView animateWithDuration:0.4 delay:0 options:UIViewAnimationOptionCurveEaseInOut animations:^{
                self.glassBackdrop.effect = [UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemThinMaterial];
                self.glassBackdrop.backgroundColor = [UIColor clearColor];
            } completion:nil];
        }
        
        CGRect screenBounds = CV3DisplayBoundsForWindow(self);
        CGFloat shortSide = MIN(screenBounds.size.width, screenBounds.size.height);
        CGFloat longSide = MAX(screenBounds.size.width, screenBounds.size.height);
        CGFloat aspect = longSide / MAX(shortSide, 1.0);
        CGPoint initialCenter = CGPointMake(CGRectGetMidX(self.frame), CGRectGetMidY(self.frame));

        UIEdgeInsets safeArea = [self currentSafeAreaInsets];

        // --- [Geek Advice] Asynchronous Frame Pipelining ---
        // Step 1: Immediately update scene settings to final frame and release live resize lock
        if (self.targetScene) {
            @try {
                FBSMutableSceneSettings *settings = [[self.targetScene settings] mutableCopy];
                if ([settings respondsToSelector:@selector(setInLiveResize:)]) {
                    [(UIMutableApplicationSceneSettings *)settings setInLiveResize:NO];
                    [self.targetScene updateSettings:settings withTransitionContext:nil];
                }
                
                // Force an immediate layout update for the new size
                [self setNeedsLayout];
                [self layoutIfNeeded]; 
                
                CV3LogToFile(@"[Pipelining] 已提交最终场景布局请求: %@", self.bundleID);
            } @catch (NSException *e) {}
        }

        // Cleanup visuals with staged fade
        UIView *snapshot = self.liveResizeSnapshotView;
        self.liveResizeSnapshotView = nil; // Clear state immediately to allow layoutSubviews to update the final scene frame

        // Step 2: Delay the transition slightly to give the remote process time to render its first frame at the new size
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.15 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [UIView animateWithDuration:0.4 delay:0 options:UIViewAnimationOptionCurveEaseInOut animations:^{
                self.hostView.alpha = 1.0;
                if (snapshot) snapshot.alpha = 0;
            } completion:^(BOOL finished) {
                [snapshot removeFromSuperview];
            }];
        });

        // Snapping and constraints for Ended state
        if (gesture.state == UIGestureRecognizerStateEnded) {
            CGFloat finalWidth = self.bounds.size.width;
            
            // 惯性滑行动量优化
            CGPoint gestureVel = [gesture velocityInView:nil];
            CGFloat speed = sqrt(gestureVel.x * gestureVel.x + gestureVel.y * gestureVel.y);
            CGFloat widthMomentum = 0;
            if (speed > 300.0) {
                // 计算对角线上的滑动速度分量
                CGFloat diagVelocity = (gestureVel.x + gestureVel.y) / sqrt(2.0);
                // 3000px/s 的速度映射为 45pt 的尺寸滑行动量
                widthMomentum = diagVelocity * 0.015;
            }
            finalWidth += widthMomentum;

            // 限制惯性后的宽度范围，避免拉伸越界
            CGFloat minAllowedWidth = shortSide * 0.4;
            CGFloat maxAllowedWidth = shortSide * 0.75;
            if (finalWidth < minAllowedWidth) finalWidth = minAllowedWidth;
            if (finalWidth > maxAllowedWidth) finalWidth = maxAllowedWidth;

            CGFloat previousLogicalWidth = finalWidth;
            
            // Island Snapping
            CGRect snapFrame = self.frame;
            CGFloat snapThreshold = 25.0;
            if (fabs(snapFrame.origin.y - safeArea.top) < snapThreshold) {
                snapFrame.origin.y = safeArea.top;
                [[[UISelectionFeedbackGenerator alloc] init] selectionChanged];
            }

            // Ratio Snapping
            CGFloat currentRatio = finalWidth / shortSide;
            if (fabs(currentRatio - 0.5) < 0.03) finalWidth = shortSide * 0.5;
            else if (fabs(currentRatio - 0.75) < 0.03) finalWidth = shortSide * 0.75;

            CGFloat finalHeight = finalWidth * aspect;
            CGFloat outerWidth = finalWidth;
            CGFloat outerHeight = finalHeight;
            snapFrame.size = CGSizeMake(outerWidth, outerHeight);
            
            // Re-center if ratio snapped
            if (fabs(finalWidth - previousLogicalWidth) > 0.1) {
                snapFrame.origin.x = initialCenter.x - outerWidth / 2.0;
                snapFrame.origin.y = initialCenter.y - outerHeight / 2.0;
                [[[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleMedium] impactOccurred];
            }

            // Safety clamp with breath padding to enforce Safe Area Constraint
            CGFloat breath = CV3Style.safeAreaBreath;
            if (snapFrame.origin.x < safeArea.left + breath) snapFrame.origin.x = safeArea.left + breath;
            if (snapFrame.origin.y < safeArea.top + breath) snapFrame.origin.y = safeArea.top + breath;
            if (CGRectGetMaxX(snapFrame) > screenBounds.size.width - safeArea.right - breath) 
                snapFrame.origin.x = screenBounds.size.width - safeArea.right - breath - outerWidth;
            if (CGRectGetMaxY(snapFrame) > screenBounds.size.height - safeArea.bottom - breath) 
                snapFrame.origin.y = screenBounds.size.height - safeArea.bottom - breath - outerHeight;

            // Final bounce animation with dynamic spring velocity matching gesture release speed
            CGFloat springVelocity = MIN(4.0, MAX(0.5, speed / 800.0));
            [UIView animateWithDuration:0.5 delay:0 usingSpringWithDamping:0.75 initialSpringVelocity:springVelocity options:0 animations:^{
                self.bounds = CGRectMake(0, 0, snapFrame.size.width, snapFrame.size.height);
                self.center = CGPointMake(CGRectGetMidX(snapFrame), CGRectGetMidY(snapFrame));
            } completion:^(BOOL finished) {
                self.isLiveResizing = NO;
                CGFloat minEdge = MIN(self.bounds.size.width, self.bounds.size.height);
                CGFloat finalRadius = MAX(CV3Style.adaptiveCornerRadiusMin, MIN(CV3Style.adaptiveCornerRadiusMax, minEdge * CV3Style.adaptiveCornerRadiusRatio));
                [self visualShadowLayer].shadowPath = [UIBezierPath bezierPathWithRoundedRect:[self currentVisualShadowFrame] cornerRadius:finalRadius].CGPath;
                
                [UIView animateWithDuration:0.4 delay:0 options:UIViewAnimationOptionCurveEaseInOut animations:^{
                    self.glassBackdrop.effect = [UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemThinMaterial];
                    self.glassBackdrop.backgroundColor = [UIColor clearColor];
                } completion:nil];

                // 动画静止后，发出一次最终的 Darwin 通知，通知客户端刷新其 UI
                [self syncWindowBoundsToClientAndNotify:YES];
            }];
            
            [self animateFocusShadow:self.isFocused];
        }
    }
}

- (void)handleTransitionGhosting {
    if (self.isClosing || !self.hostView) return;
    
    UIView *ghostShield = [self.hostView snapshotViewAfterScreenUpdates:NO];
    if (ghostShield) {
        ghostShield.frame = self.hostContainerProxy.bounds;
        [self.hostContainerProxy addSubview:ghostShield];
        
        self.hostView.alpha = 0;
        [self refreshHostViewPresentation];
        
        [UIView animateWithDuration:0.25 delay:0.05 options:UIViewAnimationOptionCurveEaseOut animations:^{
            ghostShield.alpha = 0;
            self.hostView.alpha = 1.0;
        } completion:^(BOOL finished) {
            [ghostShield removeFromSuperview];
        }];
    }
}

- (void)closeWindow {
    if (self.isClosing) return;
    self.isClosing = YES;
    
    if (self.assertionWatchdogTimer) {
        [self.assertionWatchdogTimer invalidate];
        self.assertionWatchdogTimer = nil;
    }
    
    CV3LogToFile(@"[Lifecycle] 正在关闭窗口(默认仅分离宿主，不强杀应用): %@", self.bundleID);
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    self.hidden = YES;
    [self syncWindowBoundsToClient];
    if (self.rbsAssertion) {
        [self.rbsAssertion invalidate];
        self.rbsAssertion = nil;
        CV3LogToFile(@"[Immortality] 已释放 %@ 的前台优先级断连", self.bundleID);
    }

    if (self.hostView) {
        // [Geek Advice] Explicitly disable hosting for the requester to release FBScene resources
        @try {
            if (self.targetScene && [self.targetScene respondsToSelector:@selector(hostManager)]) {
                id hm = CV3InvokeObject(self.targetScene, @selector(hostManager));
                if ([hm respondsToSelector:@selector(enableHostingForRequester:priority:)]) {
                    // 禁用托管，释放资源
                    CV3InvokeObject2(hm, @selector(enableHostingForRequester:priority:), nil, (id)0);
                }
            }
        } @catch (NSException *e) {
            CV3LogToFile(@"[Error] Failed to disable hosting during closeWindow: %@", e);
        }

        // [New] Reset Scene Settings to Background before destroying
        if (self.targetScene) {
            @try {
                FBSMutableSceneSettings *settings = [[self.targetScene settings] mutableCopy];
                if ([settings respondsToSelector:@selector(setForeground:)]) [settings setForeground:NO];
                if ([settings respondsToSelector:@selector(setBackgrounded:)]) [settings setBackgrounded:YES];
                [self.targetScene updateSettings:settings withTransitionContext:nil];
                CV3LogToFile(@"[Aggressive] 已将 Scene 设置为后台状态: %@", self.bundleID);
            } @catch (NSException *e) {
                CV3LogToFile(@"[Error] Reset scene settings failed: %@", e);
            }
        }

        // [Geek Advice] Use explicit invalidate to release backboardd resources
        if ([self.hostView respondsToSelector:@selector(invalidate)]) {
            CV3InvokeObject(self.hostView, @selector(invalidate));
        }
        [self.hostView removeFromSuperview];
        self.hostView = nil;
    }

    self.targetScene = nil;
    if (self.allowProcessTerminationOnClose) {
        CV3LogToFile(@"[Warning] allowProcessTerminationOnClose 已启用，但当前默认关闭路径不执行 kill: %@", self.bundleID);
    }
    
    self.windowScene = nil; // Clear scene attachment
    [floatingWindows removeObject:self];

    // 如果没有剩下活跃的分屏窗口，且 Expose 模式处于开启状态，自动退出 Expose 模式
    if (isGlobalExposeActive) {
        BOOL hasActiveExpose = NO;
        for (CV3FloatingAppWindow *win in floatingWindows) {
            if (!win.isClosing) {
                hasActiveExpose = YES;
                break;
            }
        }
        if (!hasActiveExpose) {
            CV3ToggleExposeMode();
        }
    }

    CV3CascadeUpdateSovereigntyAssertions(); // 级联刷新剩下的窗口前台优先级断言
    CV3UpdateFloatingBackdrop(nil);
    
    // [SHM Lazy Unmapping] 释放当前窗口对 SHM 的引用计数，若归零则60秒后回收
    CV3ReleaseSharedGeometry(self.bundleID);
}

- (void)assertionWatchdogTick:(NSTimer *)timer {
    if (self.isClosing) return;
    
    // 低电量模式：放宽保活强度，节省后台唤醒开销
    BOOL isLowPower = [NSProcessInfo processInfo].isLowPowerModeEnabled;

    if (self.isStashed) {
        // Stash + 低电量 -> 允许完全挂起，无需断言刷新
        if (isLowPower) return;
    }
    if (self.hidden) return;
    
    // 定时器触发，重新校验并刷新前台运行断言，防止断言在未知状态下失效或被系统回收
    @try {
        [self updateSovereigntyAssertion];
    } @catch (NSException *e) {}
    
    // 动态调整定时间隔：低电量下退避至 15s 减少唤醒
    NSTimeInterval targetInterval = isLowPower ? 15.0 : 5.0;
    if (fabs(timer.timeInterval - targetInterval) > 0.1) {
        [self.assertionWatchdogTimer invalidate];
        self.assertionWatchdogTimer = [NSTimer scheduledTimerWithTimeInterval:targetInterval
                                                                       target:self
                                                                     selector:@selector(assertionWatchdogTick:)
                                                                     userInfo:nil
                                                                      repeats:YES];
    }
}

- (void)dealloc {
    CV3LogToFile(@"[Lifecycle] CV3FloatingAppWindow Dealloc: %@", self.bundleID);
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    
    [self stopLiquidMotion];
    
    if (self.assertionWatchdogTimer) {
        [self.assertionWatchdogTimer invalidate];
        self.assertionWatchdogTimer = nil;
    }
    
    if (self.rbsAssertion) {
        [self.rbsAssertion invalidate];
        self.rbsAssertion = nil;
    }
    if ([self.hostView respondsToSelector:@selector(invalidate)]) {
        CV3InvokeObject(self.hostView, @selector(invalidate));
    }
}

+ (CMMotionManager *)sharedMotionManager {
    static CMMotionManager *sharedMotionManager = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedMotionManager = [[CMMotionManager alloc] init];
        sharedMotionManager.deviceMotionUpdateInterval = 1.0 / 120.0;
    });
    return sharedMotionManager;
}

- (void)startLiquidMotion {
    CMMotionManager *mgr = [[self class] sharedMotionManager];
    if (!mgr.isDeviceMotionAvailable) return;
    
    self.hasCapturedBaseline = NO;
    [mgr startDeviceMotionUpdates];
    if (self.liquidDisplayLink) {
        [self.liquidDisplayLink invalidate];
    }
    self.liquidDisplayLink = [CADisplayLink displayLinkWithTarget:self selector:@selector(updateLiquidMotion:)];
    [self.liquidDisplayLink addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];
}

- (void)updateLiquidMotion:(CADisplayLink *)sender {
    CMMotionManager *mgr = [[self class] sharedMotionManager];
    CMDeviceMotion *m = mgr.deviceMotion;
    if (!m) return;
    
    if (!self.hasCapturedBaseline) {
        self.baseRoll = m.attitude.roll;
        self.basePitch = m.attitude.pitch;
        self.hasCapturedBaseline = YES;
    }
    
    CGFloat deltaRoll = m.attitude.roll - self.baseRoll;
    CGFloat deltaPitch = m.attitude.pitch - self.basePitch;
    
    CGFloat tilt = sqrt(deltaRoll * deltaRoll + deltaPitch * deltaPitch);
    CGFloat dynamicBorderWidth = MIN(0.8, 0.3 + tilt * 0.5);
    
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    // 1. 镜面高光流动
    self.specularHighlight.startPoint = CGPointMake(0.0 - deltaRoll * 1.5, 0.0 - deltaPitch * 1.5);
    self.specularHighlight.endPoint = CGPointMake(1.0 - deltaRoll * 1.5, 1.0 - deltaPitch * 1.5);
    
    // 2. 青红分光折射与厚度动态色散
    CGFloat dx = deltaRoll * 1.2;
    CGFloat dy = deltaPitch * 1.2;
    self.cyanLayer.transform = CATransform3DMakeTranslation(-dx, -dy, 0);
    self.magentaLayer.transform = CATransform3DMakeTranslation(dx, dy, 0);
    
    self.cyanLayer.borderWidth = dynamicBorderWidth;
    self.magentaLayer.borderWidth = dynamicBorderWidth;
    [CATransaction commit];
}

- (void)stopLiquidMotion {
    if (self.liquidDisplayLink) {
        [self.liquidDisplayLink invalidate];
        self.liquidDisplayLink = nil;
    }
    
    BOOL anyActive = NO;
    if (floatingWindows) {
        for (CV3FloatingAppWindow *win in floatingWindows) {
            if (win != self && [win isKindOfClass:[CV3FloatingAppWindow class]] && win.liquidDisplayLink) {
                anyActive = YES;
                break;
            }
        }
    }
    if (!anyActive) {
        [[[self class] sharedMotionManager] stopDeviceMotionUpdates];
    }
}

@end
