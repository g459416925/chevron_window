# ChevronV3 Feature Task List

This list tracks the 16 requested capabilities against the current project.
Items are split into releases so Scene hosting and global gesture hooks can be
verified independently.

## Release 1: Window Workflow

- [x] 1. Quick Switch: focus and reuse an existing split window.
  - Existing `CV3OpenBundleInFloatingWindow` and launcher drag path already reuse
    the window for the same Bundle ID. Remaining work is a dedicated switcher UI.
- [x] 2. Per-App window layout persistence.
  - Frame and orientation persistence shipped in 1.0.6.
- [ ] 3. Window maximize and half-screen presets.
- [x] 4. Edge snapping and multi-window alignment.
  - Existing window drag magnetic alignment and Expose equal-spacing layout cover
    the current implementation; a dedicated alignment toolbar remains optional.
- [x] 5. Drag an App icon out of the launcher to create or focus a split.
- [x] 6. Edge stash and restore.
- [x] 7. Floating window action menu.

## Release 2: Input And Media

- [x] 8. Keyboard avoidance and hosted keyboard release.
  - Existing handling is stable; add explicit keyboard ownership state before
    changing behavior.
- [x] 9. Automatic video landscape handling.
  - `ChevronV3VideoBridge` publishes video orientation and the SpringBoard side
    applies it with restoration to portrait.
- [ ] 10. Screenshot and recording privacy mode.
  - Deferred until the screenshot API path is verified on this iOS build.
- [x] 11. Resource protection for long-hidden hosted Scenes.
  - Stashed windows allow the hosted app to background and avoid forced
    foreground refresh; full render-layer release remains a later optimization.
- [x] 12. Scene disconnect detection and bounded recovery.
  - Existing recovery and generation guards cover the current hosting path.

## Release 3: Content Transfer And Diagnostics

- [x] 13. Clipboard-based image transfer to apps supporting image paste.
  - The floating-window menu now copies a rendered PNG of the hosted content to
    the system pasteboard. It does not force unsupported apps to accept images.
- [ ] 14. Text and URL quick copy.
- [ ] 15. Diagnostic panel for Scene, orientation, keyboard, and generation state.
- [ ] 16. Per-App blacklist and behavior rules.

## Ordering And Gates

1. Implement items 3, 4, and 16 without adding global UIKit hooks.
2. Add the diagnostic panel before enabling items 9, 10, or 11.
3. Add keyboard ownership state before changing item 8 behavior.
4. Test items 9, 10, and 11 on the device after each individual change.
5. Implement items 13 and 14 with `UIPasteboard`; do not claim arbitrary-App
   drag-and-drop support.

Items marked complete describe capabilities already present in the project; they
are retained here so regressions remain visible while the remaining work lands.
