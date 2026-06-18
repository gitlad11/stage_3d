import '../physics/physics_transform.dart';
import '../physics/vector3.dart';
import 'stage_component.dart';
import 'transform_component.dart';

/// Runtime scene object made from small reusable components.
final class StageObject {
  /// Creates a scene object with a stable [name].
  StageObject(this.name, {TransformComponent? transform})
    : transform = transform ?? TransformComponent() {
    add(this.transform);
  }

  /// Creates a scene object and attaches [components] immediately.
  ///
  /// This is the node-style constructor: [transform] is the world transform of
  /// the node, while attached components may describe local models, colliders,
  /// lights, scripts, or other behavior.
  factory StageObject.node(
    String name, {
    PhysicsTransform? transform,
    Iterable<StageComponent> components = const [],
  }) {
    final object = StageObject(
      name,
      transform: TransformComponent(
        transform: transform ?? const PhysicsTransform(position: Vector3.zero),
      ),
    );
    for (final component in components) {
      object.add(component);
    }
    return object;
  }

  /// Human-readable object name useful for debugging and scene queries.
  final String name;

  /// Required transform shared by render and physics components.
  final TransformComponent transform;

  final _components = <StageComponent>[];

  /// All components attached to this object.
  List<StageComponent> get components => List.unmodifiable(_components);

  /// Adds [component] to this object.
  T add<T extends StageComponent>(T component) {
    if (_components.contains(component)) {
      return component;
    }
    _components.add(component);
    component.attachTo(this);
    return component;
  }

  /// Returns the first component assignable to [T], or `null`.
  T? get<T extends StageComponent>() {
    for (final component in _components) {
      if (component is T) {
        return component;
      }
    }
    return null;
  }

  /// Removes [component] from this object.
  bool remove(StageComponent component) {
    final removed = _components.remove(component);
    if (removed) {
      component.detach();
    }
    return removed;
  }

  /// Updates all components in insertion order.
  void update(double deltaSeconds) {
    for (final component in List<StageComponent>.of(_components)) {
      component.update(deltaSeconds);
    }
  }

  /// Detaches all components.
  void dispose() {
    for (final component in _components.reversed) {
      component.detach();
    }
    _components.clear();
  }
}
