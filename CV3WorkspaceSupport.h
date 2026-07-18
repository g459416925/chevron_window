@interface SBWorkspaceEntity : NSObject
- (id)applicationSceneEntity;
@end

static NSString *CV3BundleIdentifierFromWorkspaceObject(id object) {
    if (!object) return nil;

    NSArray *selectors = @[
        @"bundleIdentifier",
        @"applicationBundleIdentifier",
        @"applicationBundleID",
        @"displayIdentifier",
        @"bundleID",
        @"identifier"
    ];

    for (NSString *selectorName in selectors) {
        NSString *value = CV3InvokeObject(object, NSSelectorFromString(selectorName));
        if ([value isKindOfClass:[NSString class]] && value.length > 0) {
            return value;
        }
    }

    NSArray *nestedSelectors = @[
        @"applicationSceneEntity",
        @"displayItem",
        @"sceneHandle",
        @"application",
        @"app",
        @"process",
        @"bundle",
        @"entity"
    ];

    for (NSString *selectorName in nestedSelectors) {
        id nestedObject = CV3InvokeObject(object, NSSelectorFromString(selectorName));
        if (nestedObject && nestedObject != object) {
            NSString *bundleID = CV3BundleIdentifierFromWorkspaceObject(nestedObject);
            if (bundleID.length > 0) return bundleID;
        }
    }

    return nil;
}

static BOOL CV3WorkspaceEntityMatchesFloatingWindow(id entity, NSString **matchedBundleID) {
    if (!entity || !floatingWindows || floatingWindows.count == 0) return NO;

    NSString *entityBundleID = CV3BundleIdentifierFromWorkspaceObject(entity);
    NSString *entityDescription = nil;
    if (!entityBundleID) {
        @try {
            entityDescription = [entity description];
        } @catch (NSException *e) {}
    }

    for (CV3FloatingAppWindow *win in floatingWindows) {
        if (![win isKindOfClass:[CV3FloatingAppWindow class]] || win.isClosing || win.isStashed) continue;

        BOOL matches = [entityBundleID isEqualToString:win.bundleID];
        if (!matches && entityDescription.length > 0) {
            matches = CV3IdentifierContainsExactBundleID(entityDescription, win.bundleID);
        }

        if (matches) {
            if (matchedBundleID) *matchedBundleID = win.bundleID;
            return YES;
        }
    }

    return NO;
}
