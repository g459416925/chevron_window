# ChevronLauncher

ChevronV3 is a RootHide/Theos SpringBoard tweak for hosting applications in floating windows on iOS 16.

The package contains two tweak targets:

- `ChevronV3`: SpringBoard launcher, floating-window host, Scene lifecycle and gesture handling.
- `ChevronV3VideoBridge`: application-side fullscreen-video orientation reporter. It reports orientation requests through a Darwin notification; SpringBoard remains the owner of hosted Scene geometry.

The SpringBoard tweak also suppresses the compact Dynamic Island's outer border while preserving its background, app icon and expanded Live Activity content.

## Build

```sh
make
make package
```

Both `arm64` and `arm64e` are built. The target environment is RootHide on iOS 16.5.1; private APIs must be revalidated before changing the deployment OS.

## Diagnostics

Runtime diagnostics are written to `/var/mobile/Library/Logs/ChevronV3_Logs.txt` and rotated to `ChevronV3_Logs.txt.1` at 10 MB. A successful build only validates compilation; use the device matrix in `test_plan.md` before release.
