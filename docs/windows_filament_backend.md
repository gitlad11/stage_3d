# Windows Filament backend

The Windows native backend owns the Filament `Engine`, `Renderer`, `Scene`,
`View`, `Camera`, and a `SwapChain` through RAII. The current preview path uses
a dedicated child `HWND` so Filament never attaches its swap chain to Flutter's
own child window. It also has the first glTF asset path: load GLB bytes,
decode resources, create instanced models, apply transforms, and safely unload
assets after their instances are removed.

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

To show the native Filament clear-color preview window while running the app,
enable the preview flag:

```powershell
$env:STAGE_FILAMENT_PREVIEW = '1'
flutter run -d windows
```

For direct CMake configuration, the cache variable is also supported:

```powershell
cmake -S windows -B build\windows\x64 `
  -DSTAGE_FILAMENT_ROOT=C:\SDKs\filament
```

Without `STAGE_FILAMENT_ROOT`, the Windows runner keeps using the Flutter
preview and the Filament lifecycle remains disabled. Without
`STAGE_FILAMENT_PREVIEW=1`, the Filament backend is compiled in but does not
create a visible child window.

## Next slice

Move the child `HWND` behind a real Windows renderer bridge so Dart can create
the native viewport on demand, then wire Flutter asset byte loading and method
channel commands into the C++ renderer. After that, add lights and animation
sampling to the Windows scene.
