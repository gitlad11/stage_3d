/// A three-dimensional vector expressed in Jolt world units.
///
/// The library treats one world unit as one meter by convention. The demo uses
/// the Y axis as up, matching Jolt's default gravity direction `(0, -9.81, 0)`.
final class Vector3 {
  /// Creates a vector with [x], [y], and [z] components.
  const Vector3(this.x, this.y, this.z);

  /// A vector whose three components are zero.
  static const zero = Vector3(0, 0, 0);

  /// The component along the horizontal X axis.
  final double x;

  /// The component along the vertical Y axis.
  final double y;

  /// The component along the depth Z axis.
  final double z;

  /// Returns a copy translated by the supplied component offsets.
  Vector3 translate(double dx, double dy, double dz) =>
      Vector3(x + dx, y + dy, z + dz);

  @override
  bool operator ==(Object other) =>
      other is Vector3 && other.x == x && other.y == y && other.z == z;

  @override
  int get hashCode => Object.hash(x, y, z);
}
