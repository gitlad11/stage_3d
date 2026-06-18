import 'stage_object.dart';

/// Component-friendly runtime scene.
///
/// [StageScene] owns scene objects and drives their update lifecycle. It is
/// intentionally renderer-agnostic and physics-agnostic; specialized components
/// can connect objects to Jolt, Filament, input, animation, or app logic.
final class StageScene {
  final _objects = <StageObject>[];

  /// Objects currently owned by the scene.
  List<StageObject> get objects => List.unmodifiable(_objects);

  /// Adds [object] to the scene.
  T add<T extends StageObject>(T object) {
    if (!_objects.contains(object)) {
      _objects.add(object);
    }
    return object;
  }

  /// Finds the first object with [name], or `null`.
  StageObject? findByName(String name) {
    for (final object in _objects) {
      if (object.name == name) {
        return object;
      }
    }
    return null;
  }

  /// Removes [object] and disposes its components.
  bool remove(StageObject object) {
    final removed = _objects.remove(object);
    if (removed) {
      object.dispose();
    }
    return removed;
  }

  /// Updates all scene objects in insertion order.
  void update(double deltaSeconds) {
    for (final object in List<StageObject>.of(_objects)) {
      object.update(deltaSeconds);
    }
  }

  /// Disposes all scene objects.
  void dispose() {
    for (final object in _objects.reversed) {
      object.dispose();
    }
    _objects.clear();
  }
}
