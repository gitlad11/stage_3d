import 'physics_transform.dart';
import 'vector3.dart';

/// Base class for collision geometry attached to a rigid body.
///
/// A collider shape is invisible. A renderer may display any visual model while
/// Jolt uses the shape to calculate contacts, movement, and impulses.
sealed class ColliderShape {
  const ColliderShape();

  /// Internal identifier passed to the native Jolt adapter.
  int get nativeType;

  /// First native shape parameter.
  double get nativeA;

  /// Second native shape parameter.
  double get nativeB;

  /// Third native shape parameter.
  double get nativeC;
}

/// An axis-aligned box collider described by half-extents.
///
/// For a two-meter-wide box, use `halfWidth: 1`.
final class BoxShape extends ColliderShape {
  /// Creates a box collider from its positive half-extents.
  const BoxShape({
    required this.halfWidth,
    required this.halfHeight,
    required this.halfDepth,
  }) : assert(halfWidth > 0),
       assert(halfHeight > 0),
       assert(halfDepth > 0);

  /// Half of the total width along the X axis.
  final double halfWidth;

  /// Half of the total height along the Y axis.
  final double halfHeight;

  /// Half of the total depth along the Z axis.
  final double halfDepth;

  @override
  int get nativeType => 0;

  @override
  double get nativeA => halfWidth;

  @override
  double get nativeB => halfHeight;

  @override
  double get nativeC => halfDepth;
}

/// A capsule collider aligned with the Y axis.
///
/// Capsules are commonly used for characters and animals because they slide
/// smoothly over edges and are more stable than detailed mesh colliders.
final class CapsuleShape extends ColliderShape {
  /// Creates a capsule with a cylindrical half-height and rounded caps.
  const CapsuleShape({required this.halfHeight, required this.radius})
    : assert(halfHeight > 0),
      assert(radius > 0);

  /// Half of the cylindrical segment height, excluding the rounded caps.
  final double halfHeight;

  /// Radius of the cylindrical segment and both caps.
  final double radius;

  @override
  int get nativeType => 1;

  @override
  double get nativeA => halfHeight;

  @override
  double get nativeB => radius;

  @override
  double get nativeC => 0;
}

/// A spherical collider.
///
/// Spheres are useful for balls, projectiles, and inexpensive trigger volumes.
final class SphereShape extends ColliderShape {
  /// Creates a sphere with the supplied positive [radius].
  const SphereShape({required this.radius}) : assert(radius > 0);

  /// Radius of the sphere.
  final double radius;

  @override
  int get nativeType => 2;

  @override
  double get nativeA => radius;

  @override
  double get nativeB => 0;

  @override
  double get nativeC => 0;
}

/// A cylinder collider aligned with the Y axis.
///
/// Prefer a capsule when rounded edges are acceptable. Cylinders can be less
/// stable around sharp edges during dynamic simulation.
final class CylinderShape extends ColliderShape {
  /// Creates a cylinder from its positive [halfHeight] and [radius].
  const CylinderShape({required this.halfHeight, required this.radius})
    : assert(halfHeight > 0),
      assert(radius > 0);

  /// Half of the cylinder height along the Y axis.
  final double halfHeight;

  /// Radius of the circular caps.
  final double radius;

  @override
  int get nativeType => 3;

  @override
  double get nativeA => halfHeight;

  @override
  double get nativeB => radius;

  @override
  double get nativeC => 0;
}

/// A collider shape placed in a local node coordinate system.
///
/// [position] and [rotation] are relative to the owning rigid body transform.
/// Use this to build compound colliders from multiple simpler shapes.
final class PositionedShape {
  /// Creates a locally positioned collider part.
  const PositionedShape({
    required this.shape,
    this.position = Vector3.zero,
    this.rotation = Quaternion.identity,
  });

  /// Local collider geometry.
  final ColliderShape shape;

  /// Local position relative to the owning node/body origin.
  final Vector3 position;

  /// Local rotation relative to the owning node/body orientation.
  final Quaternion rotation;
}

/// A collider built from multiple locally positioned child shapes.
///
/// This maps to Jolt's static compound shape on Android. The owning
/// [RigidBodySettings.transform] remains the node's world transform; each
/// [PositionedShape] is placed in local coordinates inside that node.
final class CompoundShape extends ColliderShape {
  /// Creates a compound collider from at least one child shape.
  const CompoundShape(this.children);

  /// Child shapes in local node coordinates.
  final List<PositionedShape> children;

  @override
  int get nativeType => 4;

  @override
  double get nativeA => children.length.toDouble();

  @override
  double get nativeB => 0;

  @override
  double get nativeC => 0;
}
