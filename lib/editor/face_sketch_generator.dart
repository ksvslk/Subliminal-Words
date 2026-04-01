import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:operation_hermes/editor/generation_image_budget.dart';

const int _faceRenderSize = 1024;
const int _faceSourceTargetBytes = 140 * 1024;

class FaceSourceTransform {
  final double offsetX;
  final double offsetY;
  final double scale;
  final double rotation;

  const FaceSourceTransform({
    this.offsetX = 0,
    this.offsetY = 0,
    this.scale = 1,
    this.rotation = 0,
  });

  factory FaceSourceTransform.fromJson(Map<dynamic, dynamic>? json) {
    if (json == null) {
      return const FaceSourceTransform();
    }

    return FaceSourceTransform(
      offsetX: (json['offsetX'] as num?)?.toDouble() ?? 0,
      offsetY: (json['offsetY'] as num?)?.toDouble() ?? 0,
      scale: (json['scale'] as num?)?.toDouble() ?? 1,
      rotation: (json['rotation'] as num?)?.toDouble() ?? 0,
    );
  }

  FaceSourceTransform copyWith({
    double? offsetX,
    double? offsetY,
    double? scale,
    double? rotation,
  }) {
    return FaceSourceTransform(
      offsetX: offsetX ?? this.offsetX,
      offsetY: offsetY ?? this.offsetY,
      scale: scale ?? this.scale,
      rotation: rotation ?? this.rotation,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'offsetX': offsetX,
      'offsetY': offsetY,
      'scale': scale,
      'rotation': rotation,
    };
  }

  @override
  bool operator ==(Object other) {
    return other is FaceSourceTransform &&
        other.offsetX == offsetX &&
        other.offsetY == offsetY &&
        other.scale == scale &&
        other.rotation == rotation;
  }

  @override
  int get hashCode => Object.hash(offsetX, offsetY, scale, rotation);
}

class FaceSketchSettings {
  final double blurAmount;
  final double contrast;
  final double detailBoost;
  final double edgeStrength;
  final int edgeThreshold;
  final double noiseReduction;
  final int inkLevel;

  const FaceSketchSettings({
    this.blurAmount = 5,
    this.contrast = 2.8,
    this.detailBoost = 1.8,
    this.edgeStrength = 1.45,
    this.edgeThreshold = 62,
    this.noiseReduction = 1.0,
    this.inkLevel = 148,
  });

  factory FaceSketchSettings.fromJson(Map<dynamic, dynamic>? json) {
    if (json == null) {
      return const FaceSketchSettings();
    }

    return FaceSketchSettings(
      blurAmount: (json['blurAmount'] as num?)?.toDouble() ?? 5,
      contrast: (json['contrast'] as num?)?.toDouble() ?? 2.8,
      detailBoost: (json['detailBoost'] as num?)?.toDouble() ?? 1.8,
      edgeStrength: (json['edgeStrength'] as num?)?.toDouble() ?? 1.45,
      edgeThreshold: (json['edgeThreshold'] as num?)?.round() ?? 62,
      noiseReduction: (json['noiseReduction'] as num?)?.toDouble() ?? 1.0,
      inkLevel: (json['inkLevel'] as num?)?.round() ?? 148,
    );
  }

  FaceSketchSettings copyWith({
    double? blurAmount,
    double? contrast,
    double? detailBoost,
    double? edgeStrength,
    int? edgeThreshold,
    double? noiseReduction,
    int? inkLevel,
  }) {
    return FaceSketchSettings(
      blurAmount: blurAmount ?? this.blurAmount,
      contrast: contrast ?? this.contrast,
      detailBoost: detailBoost ?? this.detailBoost,
      edgeStrength: edgeStrength ?? this.edgeStrength,
      edgeThreshold: edgeThreshold ?? this.edgeThreshold,
      noiseReduction: noiseReduction ?? this.noiseReduction,
      inkLevel: inkLevel ?? this.inkLevel,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'blurAmount': blurAmount,
      'contrast': contrast,
      'detailBoost': detailBoost,
      'edgeStrength': edgeStrength,
      'edgeThreshold': edgeThreshold,
      'noiseReduction': noiseReduction,
      'inkLevel': inkLevel,
    };
  }
}

Future<Uint8List> normalizeFaceSourceImage(Uint8List sourceBytes) {
  return compute(_normalizeFaceSourceImageIsolate, sourceBytes);
}

Future<Uint8List> generateFaceSketchPng({
  required Uint8List sourceBytes,
  required FaceSketchSettings settings,
  FaceSourceTransform transform = const FaceSourceTransform(),
  int renderSize = _faceRenderSize,
}) {
  return compute(
    _generateFaceSketchPngIsolate,
    <String, dynamic>{
      'sourceBytes': sourceBytes,
      'settings': settings.toJson(),
      'transform': transform.toJson(),
      'renderSize': renderSize,
    },
  );
}

Future<Uint8List> compressFaceSketchWebp(Uint8List sketchPngBytes) async {
  return compressGenerationImageWebp(
    sketchPngBytes,
    targetBytes: kGenerationPayloadTargetBytes,
    dimension: _faceRenderSize,
    failureLabel: 'face sketch',
  );
}

Future<Uint8List> generateHighFidelityFaceSketchSquare({
  required Uint8List sourceBytes,
  required FaceSketchSettings settings,
  required FaceSourceTransform transform,
}) async {
  return compute(
    _generateHighFidelityFaceSketchSquareIsolate,
    <String, dynamic>{
      'sourceBytes': sourceBytes,
      'settings': settings.toJson(),
      'transform': transform.toJson(),
    },
  );
}

Uint8List _generateHighFidelityFaceSketchSquareIsolate(Map<String, dynamic> payload) {
  final sourceBytes = payload['sourceBytes'] as Uint8List;
  final settings = FaceSketchSettings.fromJson(
    payload['settings'] as Map<dynamic, dynamic>?,
  );
  final transform = FaceSourceTransform.fromJson(
    payload['transform'] as Map<dynamic, dynamic>?,
  );

  final decoded = img.decodeImage(sourceBytes);
  if (decoded == null) {
    throw StateError('Invalid source image for high-fidelity puzzle generation.');
  }

  final baked = img.bakeOrientation(decoded);
  final base = _renderFaceSourceToSquare(
    baked,
    transform: transform,
    canvasSize: _faceRenderSize,
  );
  
  img.grayscale(base);
  img.contrast(base, contrast: settings.contrast * 100);

  final blurred = img.Image.from(base, noAnimation: true);
  img.invert(blurred);
  img.gaussianBlur(blurred, radius: settings.blurAmount.round().clamp(1, 16));

  final edges = img.Image.from(base, noAnimation: true);
  img.gaussianBlur(edges, radius: settings.noiseReduction.round().clamp(0, 8));
  img.sobel(edges);

  final output = img.Image.from(base, noAnimation: true);
  final detailMix = (settings.detailBoost / 3).clamp(0.0, 1.0);
  final effectiveThreshold = (settings.edgeThreshold - 16).clamp(0, 255);

  for (var y = 0; y < output.height; y += 1) {
    for (var x = 0; x < output.width; x += 1) {
      final baseValue = base.getPixel(x, y).r.toDouble();
      final blurValue = blurred.getPixel(x, y).r.toDouble();
      final edgeValue = edges.getPixel(x, y).r.toDouble();

      final dodged = blurValue >= 255 ? 255.0 : (baseValue * 255.0) / (255.0 - blurValue);
      var lineValue = (dodged * (1 - (detailMix * 0.42))) + (baseValue * (detailMix * 0.42));

      if (edgeValue > effectiveThreshold) {
        final edgeConfidence = (edgeValue - effectiveThreshold) /
            (255 - effectiveThreshold == 0 ? 1 : 255 - effectiveThreshold);
        lineValue -= edgeConfidence.clamp(0.0, 1.0) *
            255.0 *
            settings.edgeStrength.clamp(0.0, 2.5);
      }

      final clamped = lineValue.clamp(0.0, 255.0).round();
      output.setPixelRgba(x, y, clamped, clamped, clamped, 255);
    }
  }

  img.normalize(output, min: 0, max: 255);
  img.luminanceThreshold(output, threshold: (settings.inkLevel / 255).clamp(0.0, 1.0));

  return Uint8List.fromList(img.encodePng(output));
}

Uint8List _normalizeFaceSourceImageIsolate(Uint8List sourceBytes) {
  final decoded = img.decodeImage(sourceBytes);
  if (decoded == null) {
    throw StateError('Could not read the selected face image.');
  }

  final baked = img.bakeOrientation(decoded);
  var normalized = _resizeLongestSide(
    baked,
    maxLongestSide: 1400,
  );
  var encoded = _encodeJpegNearTarget(
    normalized,
    targetBytes: _faceSourceTargetBytes,
  );

  while (encoded.length > _faceSourceTargetBytes &&
      math.max(normalized.width, normalized.height) > _faceRenderSize) {
    normalized = _resizeByFactor(normalized, factor: 0.9);
    encoded = _encodeJpegNearTarget(
      normalized,
      targetBytes: _faceSourceTargetBytes,
    );
  }

  return encoded;
}

Uint8List _generateFaceSketchPngIsolate(Map<String, dynamic> payload) {
  final sourceBytes = payload['sourceBytes'] as Uint8List;
  final settings = FaceSketchSettings.fromJson(
    payload['settings'] as Map<dynamic, dynamic>?,
  );
  final transform = FaceSourceTransform.fromJson(
    payload['transform'] as Map<dynamic, dynamic>?,
  );
  final renderSize = payload['renderSize'] as int? ?? _faceRenderSize;

  final decoded = img.decodeImage(sourceBytes);
  if (decoded == null) {
    throw StateError('Could not process the selected face image.');
  }

  final baked = img.bakeOrientation(decoded);
  final base = _renderFaceSourceToSquare(
    baked,
    transform: transform,
    canvasSize: renderSize,
  );
  img.grayscale(base);
  img.contrast(base, contrast: settings.contrast * 100);

  final blurred = img.Image.from(base, noAnimation: true);
  img.invert(blurred);
  img.gaussianBlur(
    blurred,
    radius: settings.blurAmount.round().clamp(1, 16),
  );

  final edges = img.Image.from(base, noAnimation: true);
  img.gaussianBlur(
    edges,
    radius: settings.noiseReduction.round().clamp(0, 8),
  );
  img.sobel(edges);

  final output = img.Image.from(base, noAnimation: true);
  final detailMix = (settings.detailBoost / 3).clamp(0.0, 1.0);
  final effectiveThreshold = (settings.edgeThreshold - 16).clamp(0, 255);

  for (var y = 0; y < output.height; y += 1) {
    for (var x = 0; x < output.width; x += 1) {
      final baseValue = base.getPixel(x, y).r.toDouble();
      final blurValue = blurred.getPixel(x, y).r.toDouble();
      final edgeValue = edges.getPixel(x, y).r.toDouble();

      final dodged =
          blurValue >= 255 ? 255.0 : (baseValue * 255.0) / (255.0 - blurValue);

      var lineValue = (dodged * (1 - (detailMix * 0.42))) +
          (baseValue * (detailMix * 0.42));

      if (edgeValue > effectiveThreshold) {
        final edgeConfidence = (edgeValue - effectiveThreshold) /
            (255 - effectiveThreshold == 0 ? 1 : 255 - effectiveThreshold);
        lineValue -= edgeConfidence.clamp(0.0, 1.0) *
            255.0 *
            settings.edgeStrength.clamp(0.0, 2.5);
      }

      final clamped = lineValue.clamp(0.0, 255.0).round();
      output.setPixelRgba(x, y, clamped, clamped, clamped, 255);
    }
  }

  img.normalize(output, min: 0, max: 255);
  img.luminanceThreshold(
    output,
    threshold: (settings.inkLevel / 255).clamp(0.0, 1.0),
  );

  return Uint8List.fromList(img.encodePng(output));
}

FaceSourceTransform clampFaceTransformToCoverSquare({
  required FaceSourceTransform transform,
  required double sourceWidth,
  required double sourceHeight,
  required double canvasSize,
  double minScale = 1.0,
  double maxScale = 12.0,
}) {
  final clampedRotation = transform.rotation;
  final minimumScale = _minimumUserScaleToCoverSquare(
    sourceWidth: sourceWidth,
    sourceHeight: sourceHeight,
    canvasSize: canvasSize,
    rotation: clampedRotation,
  );
  final clampedScale = transform.scale
      .clamp(math.max(minScale, minimumScale), maxScale)
      .toDouble();
  final coverScale = math.max(canvasSize / sourceWidth, canvasSize / sourceHeight);
  final effectiveScale = coverScale * clampedScale;
  final halfWidth = (sourceWidth * effectiveScale) / 2;
  final halfHeight = (sourceHeight * effectiveScale) / 2;
  final cosTheta = math.cos(clampedRotation);
  final sinTheta = math.sin(clampedRotation);

  var minA = double.negativeInfinity;
  var maxA = double.infinity;
  var minB = double.negativeInfinity;
  var maxB = double.infinity;

  for (final corner in <(double, double)>[
    (0, 0),
    (canvasSize, 0),
    (0, canvasSize),
    (canvasSize, canvasSize),
  ]) {
    final cornerA = (cosTheta * corner.$1) + (sinTheta * corner.$2);
    final cornerB = (sinTheta * corner.$1) - (cosTheta * corner.$2);
    minA = math.max(minA, cornerA - halfWidth);
    maxA = math.min(maxA, cornerA + halfWidth);
    minB = math.max(minB, cornerB - halfHeight);
    maxB = math.min(maxB, cornerB + halfHeight);
  }

  final desiredCenterX = (canvasSize / 2) + (transform.offsetX * canvasSize);
  final desiredCenterY = (canvasSize / 2) + (transform.offsetY * canvasSize);
  final desiredA = (cosTheta * desiredCenterX) + (sinTheta * desiredCenterY);
  final desiredB = (sinTheta * desiredCenterX) - (cosTheta * desiredCenterY);
  final clampedA = desiredA.clamp(minA, maxA).toDouble();
  final clampedB = desiredB.clamp(minB, maxB).toDouble();
  final clampedCenterX = (cosTheta * clampedA) + (sinTheta * clampedB);
  final clampedCenterY = (sinTheta * clampedA) - (cosTheta * clampedB);

  return transform.copyWith(
    scale: clampedScale,
    offsetX: (clampedCenterX - (canvasSize / 2)) / canvasSize,
    offsetY: (clampedCenterY - (canvasSize / 2)) / canvasSize,
  );
}

img.Image _renderFaceSourceToSquare(
  img.Image source, {
  required FaceSourceTransform transform,
  required int canvasSize,
}) {
  final output = img.Image(width: canvasSize, height: canvasSize);
  img.fill(output, color: img.ColorRgb8(255, 255, 255));

  final clampedTransform = clampFaceTransformToCoverSquare(
    transform: transform,
    sourceWidth: source.width.toDouble(),
    sourceHeight: source.height.toDouble(),
    canvasSize: canvasSize.toDouble(),
  );
  final coverScale = math.max(
    canvasSize / source.width,
    canvasSize / source.height,
  );
  final effectiveScale = coverScale * clampedTransform.scale;
  final centerX = (canvasSize / 2) + (clampedTransform.offsetX * canvasSize);
  final centerY = (canvasSize / 2) + (clampedTransform.offsetY * canvasSize);
  final cosTheta = math.cos(clampedTransform.rotation);
  final sinTheta = math.sin(clampedTransform.rotation);
  final halfWidth = source.width / 2.0;
  final halfHeight = source.height / 2.0;

  for (var y = 0; y < canvasSize; y += 1) {
    for (var x = 0; x < canvasSize; x += 1) {
      final dx = (x + 0.5) - centerX;
      final dy = (y + 0.5) - centerY;

      final localX = ((cosTheta * dx) + (sinTheta * dy)) / effectiveScale;
      final localY = ((-sinTheta * dx) + (cosTheta * dy)) / effectiveScale;

      final sourceX = localX + halfWidth;
      final sourceY = localY + halfHeight;
      if (sourceX < 0 ||
          sourceX >= source.width - 1 ||
          sourceY < 0 ||
          sourceY >= source.height - 1) {
        continue;
      }

      final sampled = _sampleBilinear(source, sourceX, sourceY);
      output.setPixelRgba(
        x,
        y,
        sampled.$1,
        sampled.$2,
        sampled.$3,
        255,
      );
    }
  }

  return output;
}

double _minimumUserScaleToCoverSquare({
  required double sourceWidth,
  required double sourceHeight,
  required double canvasSize,
  required double rotation,
}) {
  final coverScale = math.max(canvasSize / sourceWidth, canvasSize / sourceHeight);
  final cosTheta = math.cos(rotation).abs();
  final sinTheta = math.sin(rotation).abs();

  final rotatedWidth = (sourceWidth * cosTheta) + (sourceHeight * sinTheta);
  final rotatedHeight = (sourceWidth * sinTheta) + (sourceHeight * cosTheta);

  final requiredScale = math.max(
    canvasSize / rotatedWidth,
    canvasSize / rotatedHeight,
  );

  return (requiredScale / coverScale).clamp(1.0, 12.0);
}

img.Image _resizeLongestSide(
  img.Image source, {
  required int maxLongestSide,
}) {
  final longestSide = math.max(source.width, source.height);
  if (longestSide <= maxLongestSide) {
    return source;
  }

  return img.copyResize(
    source,
    width: source.width >= source.height ? maxLongestSide : null,
    height: source.height > source.width ? maxLongestSide : null,
    interpolation: img.Interpolation.average,
  );
}

img.Image _resizeByFactor(
  img.Image source, {
  required double factor,
}) {
  final width = math.max(1, (source.width * factor).round());
  final height = math.max(1, (source.height * factor).round());
  return img.copyResize(
    source,
    width: width,
    height: height,
    interpolation: img.Interpolation.average,
  );
}

Uint8List _encodeJpegNearTarget(
  img.Image source, {
  required int targetBytes,
}) {
  const qualities = <int>[88, 82, 76, 70, 64, 58, 52, 46, 40];
  Uint8List? bestUnderBudget;
  var smallestUnderDelta = 1 << 30;
  Uint8List? closestOverBudget;
  var smallestOverDelta = 1 << 30;

  for (final quality in qualities) {
    final encoded = Uint8List.fromList(
      img.encodeJpg(source, quality: quality),
    );
    final delta = encoded.length - targetBytes;
    if (delta <= 0) {
      final underDelta = -delta;
      if (underDelta < smallestUnderDelta) {
        smallestUnderDelta = underDelta;
        bestUnderBudget = encoded;
      }
    } else if (delta < smallestOverDelta) {
      smallestOverDelta = delta;
      closestOverBudget = encoded;
    }
  }

  return bestUnderBudget ?? closestOverBudget ?? Uint8List(0);
}

(int, int, int) _sampleBilinear(img.Image source, double x, double y) {
  final x0 = x.floor();
  final y0 = y.floor();
  final x1 = (x0 + 1).clamp(0, source.width - 1);
  final y1 = (y0 + 1).clamp(0, source.height - 1);
  final tx = x - x0;
  final ty = y - y0;

  final p00 = source.getPixel(x0, y0);
  final p10 = source.getPixel(x1, y0);
  final p01 = source.getPixel(x0, y1);
  final p11 = source.getPixel(x1, y1);

  int blendChannel(
    double c00,
    double c10,
    double c01,
    double c11,
  ) {
    final top = c00 + ((c10 - c00) * tx);
    final bottom = c01 + ((c11 - c01) * tx);
    return (top + ((bottom - top) * ty)).round().clamp(0, 255);
  }

  return (
    blendChannel(
      p00.r.toDouble(),
      p10.r.toDouble(),
      p01.r.toDouble(),
      p11.r.toDouble(),
    ),
    blendChannel(
      p00.g.toDouble(),
      p10.g.toDouble(),
      p01.g.toDouble(),
      p11.g.toDouble(),
    ),
    blendChannel(
      p00.b.toDouble(),
      p10.b.toDouble(),
      p01.b.toDouble(),
      p11.b.toDouble(),
    ),
  );
}
