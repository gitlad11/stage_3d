# Windows Filament backend

The Windows native backend owns the Filament `Engine`, `Renderer`, `Scene`,
`View`, `Camera`, and a `SwapChain` through RAII. The repository demo uses a
dedicated child `HWND` so Filament never attaches its swap chain to Flutter's
own child window. It supports GLB loading, model instances, animation sampling,
camera control, lights, environment settings, render options, procedural
meshes, textures, and compiled `.filamat` materials.

Important packaging note: this Windows backend currently lives in the
repository demo runner under `windows/runner`. A downstream Flutter app that
adds `stage_3d` as a git dependency will not automatically receive this Windows
runner integration yet. Android is already packaged as a Flutter plugin
backend; Windows plugin extraction is still pending.

## Prerequisites

Install Visual Studio 2022 Build Tools with:

- Desktop development with C++
- MSVC v143
- Windows 10 or Windows 11 SDK
- CMake tools for Windows

Download and extract an official Windows Filament SDK from
[google/filament releases](https://github.com/google/filament/releases). Its
root must contain:

```text
include/filament/Engine.h
lib/x86_64/
```

## Configure

Set the extracted SDK directory before building:

```powershell
$env:STAGE_FILAMENT_ROOT = 'C:\SDKs\filament'
flutter build windows --debug
```

To persist the setting for future terminals:

```powershell
[Environment]::SetEnvironmentVariable(
  'STAGE_FILAMENT_ROOT',
  'C:\SDKs\filament',
  'User'
)
```

Run the demo:

```powershell
flutter run -d windows
```

For direct CMake configuration, the cache variable is also supported:

```powershell
cmake -S windows -B build\windows\x64 `
  -DSTAGE_FILAMENT_ROOT=C:\SDKs\filament
```

Without `STAGE_FILAMENT_ROOT`, the Windows runner builds without the Filament
backend and the Flutter fallback remains available.

## Downstream Apps

For a separate Flutter app that depends on `stage_3d`, Android works through
the packaged plugin backend. Windows currently requires moving the repository
runner integration into that app's Windows runner or waiting for the Windows
backend to be extracted into a real Flutter Windows plugin target.

The remaining packaging work is:

- move `StageWindowsRendererBridge` out of `windows/runner`;
- create a `windows` Flutter plugin CMake target for `stage_3d`;
- register the Windows method channel from plugin registration;
- create/manage the Filament child `HWND` from the plugin instead of the demo
  runner;
- keep the current C++ renderer, material compilation, and asset loading paths
  reusable from package code.
