import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

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
}) {
  return compute(
    _generateFaceSketchPngIsolate,
    <String, dynamic>{
      'sourceBytes': sourceBytes,
      'settings': settings.toJson(),
      'transform': transform.toJson(),
    },
  );
}

Uint8List _normalizeFaceSourceImageIsolate(Uint8List sourceBytes) {
  final decoded = img.decodeImage(sourceBytes);
  if (decoded == null) {
    throw StateError('Could not read the selected face image.');
  }

  final baked = img.bakeOrientation(decoded);
  final longestSide = math.max(baked.width, baked.height);
  final normalized = longestSide > 1600
      ? img.copyResize(
          baked,
          width: baked.width >= baked.height ? 1600 : null,
          height: baked.height > baked.width ? 1600 : null,
          interpolation: img.Interpolation.average,
        )
      : baked;

  return Uint8List.fromList(
    img.encodeJpg(normalized, quality: 92),
  );
}

Uint8List _generateFaceSketchPngIsolate(Map<String, dynamic> payload) {
  final sourceBytes = payload['sourceBytes'] as Uint8List;
  final settings = FaceSketchSettings.fromJson(
    payload['settings'] as Map<dynamic, dynamic>?,
  );
  final transform = FaceSourceTransform.fromJson(
    payload['transform'] as Map<dynamic, dynamic>?,
  );

  final decoded = img.decodeImage(sourceBytes);
  if (decoded == null) {
    throw StateError('Could not process the selected face image.');
  }

  final baked = img.bakeOrientation(decoded);
  final base = _renderFaceSourceToSquare(
    baked,
    transform: transform,
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

      final dodged = blurValue >= 255
          ? 255.0
          : (baseValue * 255.0) / (255.0 - blurValue);

      var lineValue =
          (dodged * (1 - (detailMix * 0.42))) + (baseValue * (detailMix * 0.42));

      if (edgeValue > effectiveThreshold) {
        final edgeConfidence =
            (edgeValue - effectiveThreshold) / (255 - effectiveThreshold == 0
                ? 1
                : 255 - effectiveThreshold);
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

img.Image _renderFaceSourceToSquare(
  img.Image source, {
  required FaceSourceTransform transform,
}) {
  const canvasSize = 1024;
  final output = img.Image(width: canvasSize, height: canvasSize);
  img.fill(output, color: img.ColorRgb8(255, 255, 255));

  final coverScale = math.max(
    canvasSize / source.width,
    canvasSize / source.height,
  );
  final effectiveScale =
      coverScale * transform.scale.clamp(0.25, 8.0);
  final centerX = (canvasSize / 2) + (transform.offsetX * canvasSize);
  final centerY = (canvasSize / 2) + (transform.offsetY * canvasSize);
  final cosTheta = math.cos(transform.rotation);
  final sinTheta = math.sin(transform.rotation);
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
