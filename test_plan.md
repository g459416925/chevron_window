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
- Lock/unlock, open Control Center and enter/exit App Switcher with windows active.
- With an App hosted, tap its Home Screen, Dock, Spotlight and App Library icon; verify the existing floating window receives focus and no fullscreen transition or dim overlay begins.
- Trigger the same hosted App through LaunchServices and a notification; verify the fullscreen launch is rejected until the floating window is closed.
- Enter App Switcher with one and three hosted Apps. Verify hosted cards are invisible, unrelated cards remain visible and horizontally scroll without delayed touches.
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
- Respring or deliberately terminate SpringBoard while an App is hosted; after SpringBoard returns, verify the client does not retain stale hosted/audio-protection state.
- While hosted but outside a workspace transition, pause playback and deactivate the App audio session; verify those explicit App actions are not suppressed.
