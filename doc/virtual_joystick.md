# Virtual Joystick

`VirtualJoystick` is a reusable Flutter-only input component. It does not know
about Filament, Jolt, cameras, or scene objects. Its controller exposes a
normalized `JoystickValue` through the standard `ValueNotifier` listener API.

```dart
final joystick = VirtualJoystickController();

joystick.addListener(() {
  final value = joystick.value;
  camera.orbitBy(value.x, value.y);
});
```

Render the component anywhere in a Flutter interface:

```dart
VirtualJoystick(
  controller: joystick,
  size: 116,
  deadZone: 0.08,
)
```

Both axes use the `-1..1` range. Releasing the pointer automatically returns the
controller to `JoystickValue.zero`.

For smooth motion, read the current value from the application's frame ticker
and multiply it by speed and delta time:

```dart
void tick(double deltaSeconds) {
  final value = joystick.value;
  camera.orbitBy(
    value.x * orbitSpeed * deltaSeconds,
    value.y * orbitSpeed * deltaSeconds,
  );
}
```
