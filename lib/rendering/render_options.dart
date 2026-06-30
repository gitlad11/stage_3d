/// Scene render quality and post-processing options.
///
/// These settings describe how a backend renders the active view. Backends can
/// ignore unsupported knobs while preserving the same Dart API.
final class RenderOptions {
  const RenderOptions({
    this.postProcessing = true,
    this.shadows = true,
    this.shadowType = ShadowType.pcf,
    this.ambientOcclusion = const AmbientOcclusionOptions(),
    this.bloom = const BloomOptions(),
    this.screenSpaceReflections = const ScreenSpaceReflectionsOptions(),
    this.msaa = const MsaaOptions(),
  });

  final bool postProcessing;
  final bool shadows;
  final ShadowType shadowType;
  final AmbientOcclusionOptions ambientOcclusion;
  final BloomOptions bloom;
  final ScreenSpaceReflectionsOptions screenSpaceReflections;
  final MsaaOptions msaa;

  Map<String, Object> toMessage() => {
    'postProcessing': postProcessing,
    'shadows': shadows,
    'shadowType': shadowType.name,
    'ambientOcclusion': ambientOcclusion.toMessage(),
    'bloom': bloom.toMessage(),
    'screenSpaceReflections': screenSpaceReflections.toMessage(),
    'msaa': msaa.toMessage(),
  };
}

enum ShadowType { pcf, vsm, dpcf, pcss }

final class AmbientOcclusionOptions {
  const AmbientOcclusionOptions({
    this.enabled = false,
    this.radius = 0.3,
    this.intensity = 1,
    this.power = 1,
    this.quality = RenderQuality.low,
  });

  final bool enabled;
  final double radius;
  final double intensity;
  final double power;
  final RenderQuality quality;

  Map<String, Object> toMessage() => {
    'enabled': enabled,
    'radius': radius,
    'intensity': intensity,
    'power': power,
    'quality': quality.name,
  };
}

final class BloomOptions {
  const BloomOptions({
    this.enabled = false,
    this.strength = 0.1,
    this.resolution = 384,
    this.levels = 6,
    this.threshold = true,
    this.quality = RenderQuality.low,
  });

  final bool enabled;
  final double strength;
  final int resolution;
  final int levels;
  final bool threshold;
  final RenderQuality quality;

  Map<String, Object> toMessage() => {
    'enabled': enabled,
    'strength': strength,
    'resolution': resolution,
    'levels': levels,
    'threshold': threshold,
    'quality': quality.name,
  };
}

final class ScreenSpaceReflectionsOptions {
  const ScreenSpaceReflectionsOptions({
    this.enabled = false,
    this.thickness = 0.1,
    this.bias = 0.01,
    this.maxDistance = 3,
    this.stride = 2,
  });

  final bool enabled;
  final double thickness;
  final double bias;
  final double maxDistance;
  final double stride;

  Map<String, Object> toMessage() => {
    'enabled': enabled,
    'thickness': thickness,
    'bias': bias,
    'maxDistance': maxDistance,
    'stride': stride,
  };
}

final class MsaaOptions {
  const MsaaOptions({this.enabled = false, this.sampleCount = 4});

  final bool enabled;
  final int sampleCount;

  Map<String, Object> toMessage() => {
    'enabled': enabled,
    'sampleCount': sampleCount,
  };
}

enum RenderQuality { low, medium, high, ultra }
