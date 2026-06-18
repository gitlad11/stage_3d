import 'stage_object.dart';

/// Base class for reusable scene object behavior.
///
/// Components are attached to a [StageObject], receive update ticks from a
/// [StageScene], and can clean themselves up on detach. Concrete components can
/// bridge rendering, physics, input, animation, audio, or game-specific logic.
abstract class StageComponent {
  StageObject? _object;

  /// Object this component is currently attached to, if any.
  StageObject? get object => _object;

  /// Whether this component is attached to an object.
  bool get isAttached => _object != null;

  /// Called after the component is attached to [object].
  void onAttach(StageObject object) {}

  /// Called once per scene update.
  void update(double deltaSeconds) {}

  /// Called before the component is removed or its object is disposed.
  void onDetach() {}

  void attachTo(StageObject object) {
    if (_object == object) {
      return;
    }
    if (_object != null) {
      detach();
    }
    _object = object;
    onAttach(object);
  }

  void detach() {
    if (_object == null) {
      return;
    }
    onDetach();
    _object = null;
  }
}
