# ChevronLauncher

ChevronV3 is a RootHide/Theos SpringBoard tweak for hosting applications in floating windows on iOS 16.

The package contains two tweak targets:

- `ChevronV3`: SpringBoard launcher, floating-window host, Scene lifecycle and gesture handling.
- `ChevronV3VideoBridge`: application-side fullscreen-video orientation reporter. It reports orientation requests through a Darwin notification; SpringBoard remains the owner of hosted Scene geometry.

## Build

```sh
make
make package
```

Both `arm64` and `arm64e` are built. The target environment is RootHide on iOS 16.5.1; private APIs must be revalidated before changing the deployment OS.

## Diagnostics

Runtime diagnostics are written to `/var/mobile/Documents/ChevronV3_Logs.txt`. A successful build only validates compilation; use the device matrix in `test_plan.md` before release.
