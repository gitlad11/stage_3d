import 'package:flutter_test/flutter_test.dart';
import 'package:stage_3d/jolt_rendering.dart';

void main() {
  test('CameraMovePrototype moves orbit camera target from joystick input', () {
    final camera = OrbitCamera();
    const movement = CameraMovePrototype(worldSpeed: 4, nativePanSpeed: 100);

    movement.moveCamera(camera, const JoystickValue(1, -0.5), 0.5);

    expect(camera.target.x, greaterThan(0));
    expect(camera.target.z, isNot(0));
  });

  test('CameraMovePrototype converts joystick input to native move delta', () {
    const movement = CameraMovePrototype(worldSpeed: 4, nativePanSpeed: 100);

    final move = movement.nativeMove(const JoystickValue(0.5, -1), 0.25);

    expect(move, const CameraMoveDelta(12.5, -25));
  });
}
