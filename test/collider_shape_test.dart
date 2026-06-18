import 'package:flutter_test/flutter_test.dart';
import 'package:stage_3d/physics/collider_shape.dart';
import 'package:stage_3d/physics/vector3.dart';

void main() {
  test('BoxShape maps dimensions to the native ABI', () {
    const shape = BoxShape(halfWidth: 1, halfHeight: 2, halfDepth: 3);

    expect(shape.nativeType, 0);
    expect(shape.nativeA, 1);
    expect(shape.nativeB, 2);
    expect(shape.nativeC, 3);
  });

  test('CapsuleShape maps dimensions to the native ABI', () {
    const shape = CapsuleShape(halfHeight: 1.5, radius: 0.4);

    expect(shape.nativeType, 1);
    expect(shape.nativeA, 1.5);
    expect(shape.nativeB, 0.4);
    expect(shape.nativeC, 0);
  });

  test('SphereShape maps dimensions to the native ABI', () {
    const shape = SphereShape(radius: 0.75);

    expect(shape.nativeType, 2);
    expect(shape.nativeA, 0.75);
  });

  test('CylinderShape maps dimensions to the native ABI', () {
    const shape = CylinderShape(halfHeight: 1.5, radius: 0.4);

    expect(shape.nativeType, 3);
    expect(shape.nativeA, 1.5);
    expect(shape.nativeB, 0.4);
  });

  test('CompoundShape stores locally positioned child shapes', () {
    const shape = CompoundShape([
      PositionedShape(shape: CapsuleShape(halfHeight: 0.65, radius: 0.45)),
      PositionedShape(
        shape: BoxShape(halfWidth: 0.3, halfHeight: 0.1, halfDepth: 0.25),
        position: Vector3(0, -1, 0),
      ),
    ]);

    expect(shape.nativeType, 4);
    expect(shape.nativeA, 2);
    expect(shape.children.last.position.y, -1);
  });
}
