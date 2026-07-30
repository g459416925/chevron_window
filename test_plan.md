# ChevronV3 device regression plan

Target: iPhone 14 Pro Max, iOS 16.5.1, RootHide.

## Build and package

- Run `make clean`, `make`, and `make package`.
- Verify the deb contains both tweak dylibs and both filter plists.
- Confirm SpringBoard restarts without a crash after installation.

## Floating-window lifecycle

- Open, focus, drag, resize, stash, restore and close one floating App.
- Repeat with three simultaneous floating Apps and enter/exit Expose mode.
- Kill a hosted App and confirm its Scene reconnects without a stale snapshot.
- Lock with one or more windows active and verify hosted content and controls are hidden. Unlock and verify only non-stashed windows return without restarting their hosted Scenes.
- Open Control Center and enter/exit App Switcher with windows active.
- With an App hosted, tap its Home Screen, Dock, Spotlight and App Library icon; verify the existing floating window receives focus and no fullscreen transition or dim overlay begins.
- Deliver a new notification while unlocked and verify the top/Dynamic Island banner appears without opening a hosted window. Tap the live banner and verify it opens exactly one split-screen window.
- While locked, deliver and tap a lock-screen notification. Verify the system opens the App normally and Chevron does not create or focus a split-screen window.
- Enter App Switcher with one and three hosted Apps. Verify hosted cards are invisible, unrelated cards remain visible and horizontally scroll without delayed touches.
- Compare portrait and landscape App Switcher layouts. Verify all unrelated cards use one consistent size and the invisible hosted card does not collapse surrounding geometry.
- Repeatedly enter and leave App Switcher 20 times; verify no floating window becomes the key window while the switcher is visible and SpringBoard does not enter Safe Mode.

## Identity isolation

- Install or use two Apps whose bundle identifiers have a prefix relationship, such as `com.example.app` and `com.example.app.pro`.
- Host both and verify Scene destruction, interruption and foreground updates affect only the exact App.

## App list and keyboard

- Install or uninstall an App while repeatedly opening the launcher panel.
- Confirm the list refreshes, remains sorted and SpringBoard does not crash.
- Search with the keyboard in portrait and landscape, then dismiss via background tap and scrolling.
- Wake the launcher with its edge gesture, dismiss it by tapping outside, and confirm no Spotlight blur remains or requires a Home gesture to clear.
- Confirm the panel excludes non-launchable system records such as Lookup, Coverage Details and TV Provider while retaining normal Apple system Apps.
- Dismiss the panel by background tap, traffic-light close and App launch; verify the settle, fade and edge-directed shrink complete without an abrupt cut or stale blur.
- Generate unread notifications for Messages, Mail and a third-party App; verify each launcher icon shows the same badge count as SpringBoard and counts above 99 display as `99+`.
- Disable notification permission for an App while it still has a stale system badge; verify the launcher does not show its badge, then re-enable permission and verify the badge can return.
- While the panel remains open, add and clear notifications; verify visible badges update within one second without changing the scroll position or restarting the panel.
- Scroll badge-bearing cells offscreen and back, then switch search/category filters; verify badges stay attached to the correct App and reused cells do not retain stale counts or animations.
- Enable Reduce Motion and reopen the panel; verify unread badges remain visible while the attention pulse is disabled.

## System-wide icon sizing

- Compare Apple and third-party App icons on the Home Screen, Dock, inside folders and in App Library; verify every App image renders at 95% while labels, badges, grid spacing and touch targets retain their original size.
- Verify App icons are also 95% in Spotlight/Search, Share Sheet, Open In/Jump targets, notification-related App rows and Settings App lists.
- Open Share Sheet and Search from several Apple and third-party Apps; verify the global icon module loads consistently outside SpringBoard and does not resize unrelated thumbnails, contact avatars or action glyphs.
- In Douyin, open the Share Sheet repeatedly from a video and profile, dismiss it, and select several share targets; verify the App and Share Sheet remain stable and target App icons stay at 95%.
- Repeat Douyin sharing both normally and while Chevron-hosted; verify orientation observation is inactive in the normal App and never accesses a controller after its dismissal.
- Enter and leave icon editing mode, open and close folders, rotate the device and trigger an icon launch; verify the 95% scale does not compound, jump or interfere with SpringBoard press/launch animations.
- Verify folder icons, widgets and non-App SpringBoard controls are not scaled as application icons.

## Video orientation

- In a hosted App, enter fullscreen video in landscape-left and landscape-right.
- Confirm only that App's hosted content changes orientation.
- Dismiss fullscreen video and verify the content returns to portrait.
- Repeat while rotating the physical device and while another floating App remains visible.

## System aperture appearance

- Start a Live Activity or live stream and confirm the compact Dynamic Island has no outer border or halo.
- Let the Live Activity update repeatedly and confirm the border does not return.
- Expand and collapse the Dynamic Island; verify its background, app icon and expanded content remain intact.
- Stop the Live Activity and confirm the inactive island and status-bar content are unaffected.

## Resource and failure checks

- Repeat open/resize/close for at least 30 cycles and inspect memory growth.
- Exercise Low Power Mode and a memory warning.
- Inspect SpringBoard crash logs, RunningBoard messages and `ChevronV3_Logs.txt` for errors.
- If an RBS attribute is unavailable, verify retries stop after five failures and resume only after the window changes between visible and stashed priority.
- Respring or deliberately terminate SpringBoard while an App is hosted; after SpringBoard returns, verify the client does not retain stale hosted/audio-protection state.
- While hosted but outside a workspace transition, pause playback and deactivate the App audio session; verify those explicit App actions are not suppressed.
