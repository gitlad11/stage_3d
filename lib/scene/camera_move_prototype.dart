import '../input/virtual_joystick.dart';
import 'orbit_camera.dart';

/// Reusable movement settings for a camera controlled by a joystick.
///
/// The input source stays separate from the camera. A scene can reuse this
/// prototype with a virtual joystick, keyboard axes, gamepad sticks, or AI
/// camera scripts that produce the same normalized values.
final class CameraMovePrototype {
  /// Creates camera movement settings.
  const CameraMovePrototype({this.worldSpeed = 4, this.nativePanSpeed = 240})
    : assert(worldSpeed >= 0),
      assert(nativePanSpeed >= 0);

  /// Units per second for the Dart fallback camera.
  final double worldSpeed;

  /// Pixel-like pan units per second for the native Filament manipulator.
  final double nativePanSpeed;

  /// Applies joystick movement to the Dart camera target.
  void moveCamera(
    OrbitCamera camera,
    JoystickValue input,
    double deltaSeconds,
  ) {
    if (input == JoystickValue.zero || deltaSeconds <= 0) {
      return;
    }
    camera.moveTargetBy(
      right: input.x * worldSpeed * deltaSeconds,
      forward: -input.y * worldSpeed * deltaSeconds,
    );
  }

  /// Converts joystick movement to native renderer movement deltas.
  CameraMoveDelta nativeMove(JoystickValue input, double deltaSeconds) {
    if (input == JoystickValue.zero || deltaSeconds <= 0) {
      return CameraMoveDelta.zero;
    }
    return CameraMoveDelta(
      input.x * nativePanSpeed * deltaSeconds,
      input.y * nativePanSpeed * deltaSeconds,
    );
  }
}

/// Two-axis native camera movement delta.
final class CameraMoveDelta {
  /// Creates a camera movement delta.
  const CameraMoveDelta(this.right, this.forward);

  /// Empty movement.
  static const zero = CameraMoveDelta(0, 0);

  /// Horizontal strafe amount.
  final double right;

  /// Forward/back amount.
  final double forward;

  @override
  bool operator ==(Object other) =>
      other is CameraMoveDelta &&
      other.right == right &&
      other.forward == forward;

  @override
  int get hashCode => Object.hash(right, forward);
}
