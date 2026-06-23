import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../physics/vector3.dart';
import '../rendering/stage_camera.dart';

final class OrbitCamera extends ChangeNotifier {
  static const _defaultYaw = -0.6;
  static const _defaultPitch = 0.42;
  static const _defaultDistance = 14.0;

  double _yaw = _defaultYaw;
  double _pitch = _defaultPitch;
  double _distance = _defaultDistance;
  double _scaleStartDistance = _defaultDistance;
  Vector3 _target = Vector3.zero;

  double get yaw => _yaw;

  double get pitch => _pitch;

  double get distance => _distance;

  Vector3 get target => _target;

  void setCamera(StageCamera camera, {bool notify = true}) {
    _yaw = camera.yaw;
    _pitch = camera.pitch;
    _distance = camera.distance;
    _scaleStartDistance = camera.distance;
    _target = camera.target;
    if (notify) {
      notifyListeners();
    }
  }

  void beginGesture() {
    _scaleStartDistance = _distance;
  }

  void updateGesture(ScaleUpdateDetails details) {
    if (details.pointerCount == 1) {
      _yaw += details.focalPointDelta.dx * 0.01;
      _pitch = (_pitch - details.focalPointDelta.dy * 0.01).clamp(-0.15, 1.2);
    } else {
      _distance = (_scaleStartDistance / details.scale).clamp(7, 24);
    }
    notifyListeners();
  }

  void orbitBy(double deltaYaw, double deltaPitch) {
    if (deltaYaw == 0 && deltaPitch == 0) {
      return;
    }
    _yaw += deltaYaw;
    _pitch = (_pitch + deltaPitch).clamp(-0.15, 1.2);
    notifyListeners();
  }

  void moveTargetBy({required double right, required double forward}) {
    if (right == 0 && forward == 0) {
      return;
    }
    final yawCos = math.cos(_yaw);
    final yawSin = math.sin(_yaw);
    final worldRight = Vector3(yawCos, 0, -yawSin);
    final worldForward = Vector3(yawSin, 0, yawCos);
    _target = Vector3(
      _target.x + worldRight.x * right + worldForward.x * forward,
      _target.y,
      _target.z + worldRight.z * right + worldForward.z * forward,
    );
    notifyListeners();
  }

  void reset() {
    _yaw = _defaultYaw;
    _pitch = _defaultPitch;
    _distance = _defaultDistance;
    _target = Vector3.zero;
    notifyListeners();
  }

  Offset project(Vector3 point, Size size) {
    final view = _worldToCamera(point);
    final depth = view.z + _distance;
    final scale = math.min(size.width, size.height) * 0.9 / depth;
    return Offset(
      size.width * 0.5 + view.x * scale,
      size.height * 0.68 - view.y * scale,
    );
  }

  Vector3 _worldToCamera(Vector3 point) {
    final relative = Vector3(
      point.x - _target.x,
      point.y - _target.y,
      point.z - _target.z,
    );
    final yawCos = math.cos(_yaw);
    final yawSin = math.sin(_yaw);
    final yawX = relative.x * yawCos - relative.z * yawSin;
    final yawZ = relative.x * yawSin + relative.z * yawCos;
    final pitchCos = math.cos(_pitch);
    final pitchSin = math.sin(_pitch);
    return Vector3(
      yawX,
      relative.y * pitchCos - yawZ * pitchSin,
      relative.y * pitchSin + yawZ * pitchCos,
    );
  }
}
