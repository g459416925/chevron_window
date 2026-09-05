# ChevronV3 Feature Roadmap

## Implemented

- Split app Scene hosting with reconnect and generation guards
- Portrait and landscape presentation with cross-orientation map restoration
- Independent keyboard hosting and keyboard avoidance handling
- Window move, resize, stash, restore, Expose, and app-icon launching
- Edge trigger hot zone configured at 30 pt
- Drag shadow settling without the release-time black flash
- Automatic appearance compatibility by preserving the hosted app idle-timer policy

## Current Release

- Persist each split window's last frame and orientation
- Restore a saved frame through the same safe-area clamping path used by manual movement
- Record host lifecycle transitions with bundle ID and generation for diagnostics

## Next Candidates

- Diagnostic panel showing Scene ID, host state, orientation, keyboard state, and generation
- Reuse an existing split window during Quick Switch instead of creating a duplicate
- Quick Switch hover prewarming with cancellation and generation guards
- Per-app rules for default orientation, window size, and restore behavior
- Resource protection that releases hidden render layers while retaining layout state
- Screenshot privacy mode with timeout-based restoration
- Clipboard-based image transfer for apps that support standard image paste

## Deferred

- System-wide forced image drag and drop into arbitrary apps
- Broad UIKit lifecycle hooks for all applications
- Prewarming multiple applications at once
- Forcing every hosted Scene to remain foreground-active

Deferred items require device-level compatibility testing because target apps and
private Scene APIs do not provide a uniform contract on iPhone.
