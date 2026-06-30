import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stage_3d/stage_3d.dart';

void main() {
  testWidgets('VirtualJoystick reports normalized values and resets', (
    tester,
  ) async {
    final controller = VirtualJoystickController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: VirtualJoystick(
            key: const ValueKey('joystick'),
            controller: controller,
            size: 100,
          ),
        ),
      ),
    );

    final center = tester.getCenter(find.byKey(const ValueKey('joystick')));
    final gesture = await tester.startGesture(center);
    await gesture.moveBy(const Offset(50, -50));
    await tester.pump();

    expect(controller.value.x, closeTo(0.707, 0.01));
    expect(controller.value.y, closeTo(-0.707, 0.01));
    expect(controller.value.magnitude, closeTo(1, 0.01));

    await gesture.up();
    await tester.pump();

    expect(controller.value, JoystickValue.zero);
  });

}
