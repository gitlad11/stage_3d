/// Reusable Flutter API for creating and simulating Jolt Physics rigid bodies.
///
/// Import this library to access [PhysicsWorld], collider shapes, rigid body
/// settings, transforms, quaternions, and vectors from a single entrypoint.
library;

import 'dart:ffi';
import 'dart:io';
import 'dart:math' as math;

import 'physics/collider_shape.dart';
import 'physics/physics_transform.dart';
import 'physics/ray_cast.dart';
import 'physics/rigid_body.dart';
import 'physics/vector3.dart';

export 'physics/collider_shape.dart';
export 'physics/physics_transform.dart';
export 'physics/ray_cast.dart';
export 'physics/rigid_body.dart';
export 'physics/vector3.dart';

typedef _CreateWorldNative = Int64 Function();
typedef _CreateWorldDart = int Function();
typedef _WorldNative = Void Function(Int64);
typedef _WorldDart = void Function(int);
typedef _StepNative = Void Function(Int64, Float);
typedef _StepDart = void Function(int, double);
typedef _CreateBodyNative =
    Uint32 Function(
      Int64,
      Int32,
      Float,
      Float,
      Float,
      Int32,
      Float,
      Float,
      Float,
      Float,
      Float,
      Bool,
    );
typedef _CreateBodyDart =
    int Function(
      int,
      int,
      double,
      double,
      double,
      int,
      double,
      double,
      double,
      double,
      double,
      bool,
    );
typedef _CreateCompoundNative = Int64 Function();
typedef _CreateCompoundDart = int Function();
typedef _DestroyCompoundNative = Void Function(Int64);
typedef _DestroyCompoundDart = void Function(int);
typedef _AddCompoundChildNative =
    Void Function(
      Int64,
      Int32,
      Float,
      Float,
      Float,
      Float,
      Float,
      Float,
      Float,
      Float,
      Float,
      Float,
    );
typedef _AddCompoundChildDart =
    void Function(
      int,
      int,
      double,
      double,
      double,
      double,
      double,
      double,
      double,
      double,
      double,
      double,
    );
typedef _CreateCompoundBodyNative =
    Uint32 Function(
      Int64,
      Int64,
      Int32,
      Float,
      Float,
      Float,
      Float,
      Float,
      Bool,
    );
typedef _CreateCompoundBodyDart =
    int Function(int, int, int, double, double, double, double, double, bool);
typedef _BodyNative = Void Function(Int64, Uint32);
typedef _BodyDart = void Function(int, int);
typedef _ReadBodyNative = Float Function(Int64, Uint32, Int32);
typedef _ReadBodyDart = double Function(int, int, int);
typedef _BodyVectorNative = Void Function(Int64, Uint32, Float, Float, Float);
typedef _BodyVectorDart = void Function(int, int, double, double, double);
typedef _SetTransformNative =
    Void Function(
      Int64,
      Uint32,
      Float,
      Float,
      Float,
      Float,
      Float,
      Float,
      Float,
      Bool,
    );
typedef _SetTransformDart =
    void Function(
      int,
      int,
      double,
      double,
      double,
      double,
      double,
      double,
      double,
      bool,
    );
typedef _MoveKinematicNative =
    Void Function(
      Int64,
      Uint32,
      Float,
      Float,
      Float,
      Float,
      Float,
      Float,
      Float,
      Float,
    );
typedef _MoveKinematicDart =
    void Function(
      int,
      int,
      double,
      double,
      double,
      double,
      double,
      double,
      double,
      double,
    );
typedef _CastRayNative =
    Bool Function(Int64, Float, Float, Float, Float, Float, Float);
typedef _CastRayDart =
    bool Function(int, double, double, double, double, double, double);
typedef _ReadWorldBodyNative = Uint32 Function(Int64);
typedef _ReadWorldBodyDart = int Function(int);
typedef _ReadWorldFloatNative = Float Function(Int64);
typedef _ReadWorldFloatDart = double Function(int);

/// A simulation world backed by Jolt Physics on Android.
///
/// Create bodies with [createBody], advance the simulation with [step], and
/// release native resources with [dispose]. Bodies belong to the world that
/// created them and must not be passed to another world.
abstract interface class PhysicsWorld {
  /// Human-readable name of the active physics backend.
  String get engineLabel;

  /// Spatial queries such as ray casting against collider shapes.
  PhysicsQueries get queries;

  /// Inserts a rigid body into this world.
  ///
  /// The returned handle remains valid until [destroyBody] or [dispose].
  RigidBody createBody(RigidBodySettings settings);

  /// Removes [body] from the simulation and releases its native resources.
  void destroyBody(RigidBody body);

  /// Reads the current world-space position and orientation of [body].
  PhysicsTransform getTransform(RigidBody body);

  /// Reads the current movement of [body] in world units per second.
  Vector3 getLinearVelocity(RigidBody body);

  /// Reads the current rotation speed of [body] in radians per second.
  Vector3 getAngularVelocity(RigidBody body);

  /// Captures all registered bodies for debug overlays and inspectors.
  List<RigidBodySnapshot> snapshotBodies();

  /// Teleports [body] to [transform].
  ///
  /// Use this for spawning, resets, and explicit teleports. Prefer
  /// [setLinearVelocity], [addImpulse], or [moveKinematic] for regular motion.
  void setTransform(
    RigidBody body,
    PhysicsTransform transform, {
    bool activate = true,
  });

  /// Replaces the current linear velocity of [body].
  void setLinearVelocity(RigidBody body, Vector3 velocity);

  /// Replaces the current angular velocity of [body].
  void setAngularVelocity(RigidBody body, Vector3 velocity);

  /// Applies an instantaneous impulse to a dynamic [body].
  ///
  /// Unlike [setLinearVelocity], this is interpreted as a physical push and is
  /// suitable for jumps, explosions, and impacts.
  void addImpulse(RigidBody body, Vector3 impulse);

  /// Moves a kinematic [body] toward [target] over [deltaSeconds].
  ///
  /// This allows Jolt to calculate the velocity needed for interactions with
  /// dynamic bodies. Use it for moving platforms, doors, and scripted objects.
  void moveKinematic(
    RigidBody body,
    PhysicsTransform target,
    double deltaSeconds,
  );

  /// Advances the simulation by [deltaSeconds].
  ///
  /// Call this from a ticker or game loop. The Android adapter clamps unusually
  /// long frames to keep this prototype stable after app resume.
  void step(double deltaSeconds);

  /// Releases this world's native resources and all remaining bodies.
  void dispose();
}

/// Creates a physics world.
///
/// Android uses Jolt through `dart:ffi`. Other platforms currently receive a
/// lightweight preview backend so UI development and tests can run without an
/// Android runtime.
PhysicsWorld createPhysicsWorld() {
  if (Platform.isAndroid) {
    try {
      return _JoltPhysicsWorld();
    } on Object {
      // Keep previews and tests usable while the native Android library is absent.
    }
  }
  return _PreviewPhysicsWorld();
}

final class _JoltPhysicsWorld implements PhysicsWorld, PhysicsQueries {
  _JoltPhysicsWorld() {
    final library = DynamicLibrary.open('libjolt_ffi.so');
    _destroyWorld = library.lookupFunction<_WorldNative, _WorldDart>(
      'jolt_world_destroy',
    );
    _step = library.lookupFunction<_StepNative, _StepDart>('jolt_world_step');
    _createBody = library.lookupFunction<_CreateBodyNative, _CreateBodyDart>(
      'jolt_body_create',
    );
    _createCompound = library
        .lookupFunction<_CreateCompoundNative, _CreateCompoundDart>(
          'jolt_compound_create',
        );
    _destroyCompound = library
        .lookupFunction<_DestroyCompoundNative, _DestroyCompoundDart>(
          'jolt_compound_destroy',
        );
    _addCompoundChild = library
        .lookupFunction<_AddCompoundChildNative, _AddCompoundChildDart>(
          'jolt_compound_add_shape',
        );
    _createCompoundBody = library
        .lookupFunction<_CreateCompoundBodyNative, _CreateCompoundBodyDart>(
          'jolt_body_create_compound',
        );
    _destroyBody = library.lookupFunction<_BodyNative, _BodyDart>(
      'jolt_body_destroy',
    );
    _readPosition = library.lookupFunction<_ReadBodyNative, _ReadBodyDart>(
      'jolt_body_position',
    );
    _readRotation = library.lookupFunction<_ReadBodyNative, _ReadBodyDart>(
      'jolt_body_rotation',
    );
    _readLinearVelocity = library
        .lookupFunction<_ReadBodyNative, _ReadBodyDart>(
          'jolt_body_linear_velocity',
        );
    _readAngularVelocity = library
        .lookupFunction<_ReadBodyNative, _ReadBodyDart>(
          'jolt_body_angular_velocity',
        );
    _setTransform = library
        .lookupFunction<_SetTransformNative, _SetTransformDart>(
          'jolt_body_set_transform',
        );
    _setLinearVelocity = library
        .lookupFunction<_BodyVectorNative, _BodyVectorDart>(
          'jolt_body_set_linear_velocity',
        );
    _setAngularVelocity = library
        .lookupFunction<_BodyVectorNative, _BodyVectorDart>(
          'jolt_body_set_angular_velocity',
        );
    _addImpulse = library.lookupFunction<_BodyVectorNative, _BodyVectorDart>(
      'jolt_body_add_impulse',
    );
    _moveKinematic = library
        .lookupFunction<_MoveKinematicNative, _MoveKinematicDart>(
          'jolt_body_move_kinematic',
        );
    _castRay = library.lookupFunction<_CastRayNative, _CastRayDart>(
      'jolt_world_cast_ray',
    );
    _readRayHitBody = library
        .lookupFunction<_ReadWorldBodyNative, _ReadWorldBodyDart>(
          'jolt_world_ray_hit_body',
        );
    _readRayHitFraction = library
        .lookupFunction<_ReadWorldFloatNative, _ReadWorldFloatDart>(
          'jolt_world_ray_hit_fraction',
        );
    _handle = library.lookupFunction<_CreateWorldNative, _CreateWorldDart>(
      'jolt_world_create',
    )();
  }

  late final _WorldDart _destroyWorld;
  late final _StepDart _step;
  late final _CreateBodyDart _createBody;
  late final _CreateCompoundDart _createCompound;
  late final _DestroyCompoundDart _destroyCompound;
  late final _AddCompoundChildDart _addCompoundChild;
  late final _CreateCompoundBodyDart _createCompoundBody;
  late final _BodyDart _destroyBody;
  late final _ReadBodyDart _readPosition;
  late final _ReadBodyDart _readRotation;
  late final _ReadBodyDart _readLinearVelocity;
  late final _ReadBodyDart _readAngularVelocity;
  late final _SetTransformDart _setTransform;
  late final _BodyVectorDart _setLinearVelocity;
  late final _BodyVectorDart _setAngularVelocity;
  late final _BodyVectorDart _addImpulse;
  late final _MoveKinematicDart _moveKinematic;
  late final _CastRayDart _castRay;
  late final _ReadWorldBodyDart _readRayHitBody;
  late final _ReadWorldFloatDart _readRayHitFraction;
  late final int _handle;
  final _bodies = <int, RigidBody>{};
  bool _disposed = false;

  @override
  String get engineLabel => 'Jolt Physics 5.5.0 via Dart FFI';

  @override
  PhysicsQueries get queries => this;

  @override
  RigidBody createBody(RigidBodySettings settings) {
    final id = _createNativeBody(settings);
    final body = RigidBody(id: BodyId(id), settings: settings);
    _bodies[id] = body;
    setTransform(body, settings.transform);
    setLinearVelocity(body, settings.linearVelocity);
    setAngularVelocity(body, settings.angularVelocity);
    return body;
  }

  int _createNativeBody(RigidBodySettings settings) {
    final shape = settings.shape;
    final position = settings.transform.position;
    if (shape is CompoundShape) {
      return _createNativeCompoundBody(settings, shape);
    }
    return _createBody(
      _handle,
      shape.nativeType,
      shape.nativeA,
      shape.nativeB,
      shape.nativeC,
      settings.motionType.nativeValue,
      position.x,
      position.y,
      position.z,
      settings.friction,
      settings.restitution,
      settings.isSensor,
    );
  }

  int _createNativeCompoundBody(
    RigidBodySettings settings,
    CompoundShape shape,
  ) {
    if (shape.children.isEmpty) {
      throw ArgumentError.value(
        shape,
        'shape',
        'CompoundShape must contain at least one PositionedShape.',
      );
    }
    final compound = _createCompound();
    try {
      for (final child in shape.children) {
        final childShape = child.shape;
        if (childShape is CompoundShape) {
          throw UnsupportedError('Nested CompoundShape is not supported yet.');
        }
        _addCompoundChild(
          compound,
          childShape.nativeType,
          childShape.nativeA,
          childShape.nativeB,
          childShape.nativeC,
          child.position.x,
          child.position.y,
          child.position.z,
          child.rotation.x,
          child.rotation.y,
          child.rotation.z,
          child.rotation.w,
        );
      }
      final position = settings.transform.position;
      final id = _createCompoundBody(
        _handle,
        compound,
        settings.motionType.nativeValue,
        position.x,
        position.y,
        position.z,
        settings.friction,
        settings.restitution,
        settings.isSensor,
      );
      if (id == 0) {
        throw StateError('Jolt failed to create CompoundShape body.');
      }
      return id;
    } finally {
      _destroyCompound(compound);
    }
  }

  @override
  void destroyBody(RigidBody body) {
    _destroyBody(_handle, body.id.value);
    _bodies.remove(body.id.value);
  }

  @override
  PhysicsTransform getTransform(RigidBody body) {
    final id = body.id.value;
    return PhysicsTransform(
      position: Vector3(
        _readPosition(_handle, id, 0),
        _readPosition(_handle, id, 1),
        _readPosition(_handle, id, 2),
      ),
      rotation: Quaternion(
        _readRotation(_handle, id, 0),
        _readRotation(_handle, id, 1),
        _readRotation(_handle, id, 2),
        _readRotation(_handle, id, 3),
      ),
    );
  }

  @override
  Vector3 getLinearVelocity(RigidBody body) {
    final id = body.id.value;
    return Vector3(
      _readLinearVelocity(_handle, id, 0),
      _readLinearVelocity(_handle, id, 1),
      _readLinearVelocity(_handle, id, 2),
    );
  }

  @override
  Vector3 getAngularVelocity(RigidBody body) {
    final id = body.id.value;
    return Vector3(
      _readAngularVelocity(_handle, id, 0),
      _readAngularVelocity(_handle, id, 1),
      _readAngularVelocity(_handle, id, 2),
    );
  }

  @override
  List<RigidBodySnapshot> snapshotBodies() => [
    for (final body in _bodies.values)
      RigidBodySnapshot(body: body, transform: getTransform(body)),
  ];

  @override
  void setTransform(
    RigidBody body,
    PhysicsTransform transform, {
    bool activate = true,
  }) {
    final position = transform.position;
    final rotation = transform.rotation;
    _setTransform(
      _handle,
      body.id.value,
      position.x,
      position.y,
      position.z,
      rotation.x,
      rotation.y,
      rotation.z,
      rotation.w,
      activate,
    );
  }

  @override
  void setLinearVelocity(RigidBody body, Vector3 velocity) {
    _setLinearVelocity(
      _handle,
      body.id.value,
      velocity.x,
      velocity.y,
      velocity.z,
    );
  }

  @override
  void setAngularVelocity(RigidBody body, Vector3 velocity) {
    _setAngularVelocity(
      _handle,
      body.id.value,
      velocity.x,
      velocity.y,
      velocity.z,
    );
  }

  @override
  void addImpulse(RigidBody body, Vector3 impulse) {
    _addImpulse(_handle, body.id.value, impulse.x, impulse.y, impulse.z);
  }

  @override
  void moveKinematic(
    RigidBody body,
    PhysicsTransform target,
    double deltaSeconds,
  ) {
    final position = target.position;
    final rotation = target.rotation;
    _moveKinematic(
      _handle,
      body.id.value,
      position.x,
      position.y,
      position.z,
      rotation.x,
      rotation.y,
      rotation.z,
      rotation.w,
      deltaSeconds,
    );
  }

  @override
  void step(double deltaSeconds) => _step(_handle, deltaSeconds);

  @override
  RayCastHit? castRay(Ray ray) {
    final direction = ray.normalizedDirection;
    final didHit = _castRay(
      _handle,
      ray.origin.x,
      ray.origin.y,
      ray.origin.z,
      direction.x * ray.maxDistance,
      direction.y * ray.maxDistance,
      direction.z * ray.maxDistance,
    );
    if (!didHit) {
      return null;
    }
    final body = _bodies[_readRayHitBody(_handle)];
    if (body == null) {
      return null;
    }
    final fraction = _readRayHitFraction(_handle);
    return RayCastHit(
      body: body,
      position: ray.pointAtFraction(fraction),
      fraction: fraction,
      distance: fraction * ray.maxDistance,
    );
  }

  @override
  void dispose() {
    if (!_disposed) {
      _destroyWorld(_handle);
      _disposed = true;
    }
  }
}

final class _PreviewPhysicsWorld implements PhysicsWorld, PhysicsQueries {
  final _bodies = <int, _PreviewBody>{};
  var _nextId = 1;

  @override
  String get engineLabel => 'Preview fallback (Android uses Jolt FFI)';

  @override
  PhysicsQueries get queries => this;

  @override
  RigidBody createBody(RigidBodySettings settings) {
    final body = RigidBody(id: BodyId(_nextId++), settings: settings);
    _bodies[body.id.value] = _PreviewBody(
      body: body,
      transform: settings.transform,
      linearVelocity: settings.linearVelocity,
      angularVelocity: settings.angularVelocity,
      motionType: settings.motionType,
    );
    return body;
  }

  @override
  void destroyBody(RigidBody body) => _bodies.remove(body.id.value);

  @override
  PhysicsTransform getTransform(RigidBody body) => _state(body).transform;

  @override
  Vector3 getLinearVelocity(RigidBody body) => _state(body).linearVelocity;

  @override
  Vector3 getAngularVelocity(RigidBody body) => _state(body).angularVelocity;

  @override
  List<RigidBodySnapshot> snapshotBodies() => [
    for (final state in _bodies.values)
      RigidBodySnapshot(body: state.body, transform: state.transform),
  ];

  @override
  void setTransform(
    RigidBody body,
    PhysicsTransform transform, {
    bool activate = true,
  }) {
    _state(body).transform = transform;
  }

  @override
  void setLinearVelocity(RigidBody body, Vector3 velocity) {
    _state(body).linearVelocity = velocity;
  }

  @override
  void setAngularVelocity(RigidBody body, Vector3 velocity) {
    _state(body).angularVelocity = velocity;
  }

  @override
  void addImpulse(RigidBody body, Vector3 impulse) {
    final state = _state(body);
    state.linearVelocity = Vector3(
      state.linearVelocity.x + impulse.x,
      state.linearVelocity.y + impulse.y,
      state.linearVelocity.z + impulse.z,
    );
  }

  @override
  void moveKinematic(
    RigidBody body,
    PhysicsTransform target,
    double deltaSeconds,
  ) {
    _state(body).transform = target;
  }

  @override
  void step(double deltaSeconds) {
    for (final entry in _bodies.entries) {
      final state = entry.value;
      if (state.motionType != MotionType.dynamic) {
        continue;
      }
      final velocity = Vector3(
        state.linearVelocity.x,
        state.linearVelocity.y - 9.81 * deltaSeconds,
        state.linearVelocity.z,
      );
      final position = state.transform.position;
      final nextY = math.max(0.65, position.y + velocity.y * deltaSeconds);
      state
        ..linearVelocity = nextY == 0.65
            ? Vector3(velocity.x, 0, velocity.z)
            : velocity
        ..transform = PhysicsTransform(
          position: Vector3(
            position.x + velocity.x * deltaSeconds,
            nextY,
            position.z + velocity.z * deltaSeconds,
          ),
          rotation: state.transform.rotation,
        );
    }
  }

  @override
  RayCastHit? castRay(Ray ray) {
    final direction = ray.normalizedDirection;
    _PreviewBody? closest;
    var closestDistance = ray.maxDistance;
    for (final state in _bodies.values) {
      final center = state.transform.position;
      final offset = Vector3(
        center.x - ray.origin.x,
        center.y - ray.origin.y,
        center.z - ray.origin.z,
      );
      final projection =
          offset.x * direction.x +
          offset.y * direction.y +
          offset.z * direction.z;
      final radius = _previewRadius(state.body.settings.shape);
      final centerDistanceSquared =
          offset.x * offset.x + offset.y * offset.y + offset.z * offset.z;
      final perpendicularSquared =
          centerDistanceSquared - projection * projection;
      final radiusSquared = radius * radius;
      if (perpendicularSquared > radiusSquared) {
        continue;
      }
      final distance =
          projection - math.sqrt(radiusSquared - perpendicularSquared);
      if (distance >= 0 && distance <= closestDistance) {
        closest = state;
        closestDistance = distance;
      }
    }
    if (closest == null) {
      return null;
    }
    final fraction = closestDistance / ray.maxDistance;
    return RayCastHit(
      body: closest.body,
      position: ray.pointAtFraction(fraction),
      fraction: fraction,
      distance: closestDistance,
    );
  }

  @override
  void dispose() => _bodies.clear();

  _PreviewBody _state(RigidBody body) => _bodies[body.id.value]!;

  double _previewRadius(ColliderShape shape) => switch (shape) {
    BoxShape() => math.sqrt(
      shape.halfWidth * shape.halfWidth +
          shape.halfHeight * shape.halfHeight +
          shape.halfDepth * shape.halfDepth,
    ),
    CapsuleShape() => shape.halfHeight + shape.radius,
    SphereShape() => shape.radius,
    CylinderShape() => math.sqrt(
      shape.halfHeight * shape.halfHeight + shape.radius * shape.radius,
    ),
    CompoundShape() => shape.children.fold(0, (radius, child) {
      final position = child.position;
      final childDistance = math.sqrt(
        position.x * position.x +
            position.y * position.y +
            position.z * position.z,
      );
      return math.max(radius, childDistance + _previewRadius(child.shape));
    }),
  };
}

final class _PreviewBody {
  _PreviewBody({
    required this.body,
    required this.transform,
    required this.linearVelocity,
    required this.angularVelocity,
    required this.motionType,
  });

  final RigidBody body;
  PhysicsTransform transform;
  Vector3 linearVelocity;
  Vector3 angularVelocity;
  MotionType motionType;
}
