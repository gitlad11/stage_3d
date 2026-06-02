import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../physics/vector3.dart';

final class OrbitCamera extends ChangeNotifier {
  static const _defaultYaw = -0.6;
  static const _defaultPitch = 0.42;
  static const _defaultDistance = 14.0;

  double _yaw = _defaultYaw;
  double _pitch = _defaultPitch;
  double _distance = _defaultDistance;
  double _scaleStartDistance = _defaultDistance;

  double get yaw => _yaw;

  double get pitch => _pitch;

  double get distance => _distance;

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

  void reset() {
    _yaw = _defaultYaw;
    _pitch = _defaultPitch;
    _distance = _defaultDistance;
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
    final yawCos = math.cos(_yaw);
    final yawSin = math.sin(_yaw);
    final yawX = point.x * yawCos - point.z * yawSin;
    final yawZ = point.x * yawSin + point.z * yawCos;
    final pitchCos = math.cos(_pitch);
    final pitchSin = math.sin(_pitch);
    return Vector3(
      yawX,
      point.y * pitchCos - yawZ * pitchSin,
      point.y * pitchSin + yawZ * pitchCos,
    );
  }
}
