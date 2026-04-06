import 'package:flutter/foundation.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:image/image.dart' as img;

const int kGenerationPayloadTargetBytes = 50 * 1024;
const int kGenerationPayloadDimension = 1024;
const int kGenerationControlTargetBytes = 64 * 1024;
const int kStoredFactSolutionTargetBytes = 40 * 1024;
const int kStoredFactSolutionDimension = 1024;
const int kStoredPuzzleTargetBytes = 120 * 1024;
const int kStoredPuzzleDimension = 1024;
const int kStoredPuzzleThumbnailTargetBytes = 50 * 1024;
const int kStoredPuzzleThumbnailDimension = 400;

Future<Uint8List> compressGenerationImageWebp(
  Uint8List sourceBytes, {
  int targetBytes = kGenerationPayloadTargetBytes,
  int dimension = kGenerationPayloadDimension,
  String failureLabel = 'generation image',
}) async {
  final candidate = await _compressWebpNearTarget(
    sourceBytes,
    targetBytes: targetBytes,
    dimension: dimension,
    requireUnderBudget: true,
  );
  if (candidate.isEmpty || candidate.length > targetBytes) {
    throw StateError('Could not compress the $failureLabel.');
  }
  return candidate;
}

Future<Uint8List> buildGenerationControlJpeg(
  Uint8List sourceBytes, {
  int dimension = kGenerationPayloadDimension,
  int targetBytes = kGenerationControlTargetBytes,
  String failureLabel = 'generation control image',
}) async {
  return compute(
    _buildGenerationControlJpegIsolate,
    <String, dynamic>{
      'sourceBytes': sourceBytes,
      'dimension': dimension,
      'targetBytes': targetBytes,
      'failureLabel': failureLabel,
    },
  );
}

Uint8List _buildGenerationControlJpegIsolate(Map<String, dynamic> payload) {
  final sourceBytes = payload['sourceBytes'] as Uint8List;
  final dimension = payload['dimension'] as int? ?? kGenerationPayloadDimension;
  final targetBytes =
      payload['targetBytes'] as int? ?? kGenerationControlTargetBytes;
  final failureLabel =
      payload['failureLabel'] as String? ?? 'generation control image';

  final decoded = img.decodeImage(sourceBytes);
  if (decoded == null) {
    throw StateError('Could not decode the $failureLabel.');
  }

  final dimensions = <int>[];
  var candidateDimension = dimension;
  while (candidateDimension >= 384) {
    if (!dimensions.contains(candidateDimension)) {
      dimensions.add(candidateDimension);
    }
    if (candidateDimension <= 512) {
      break;
    }
    candidateDimension = (candidateDimension * 0.88).round();
  }

  const qualities = <int>[96, 92, 88, 84, 80, 76, 72, 68, 64, 60, 54, 48];
  Uint8List? bestUnderBudget;
  var smallestUnderDelta = 1 << 30;

  for (final candidateDimension in dimensions) {
    final resized = img.copyResize(
      decoded,
      width: candidateDimension,
      height: candidateDimension,
      interpolation: img.Interpolation.average,
    );

    for (final quality in qualities) {
      final encoded = Uint8List.fromList(
        img.encodeJpg(resized, quality: quality),
      );
      if (encoded.isEmpty) {
        continue;
      }
      final delta = encoded.length - targetBytes;
      if (delta <= 0) {
        final underDelta = -delta;
        if (underDelta < smallestUnderDelta) {
          smallestUnderDelta = underDelta;
          bestUnderBudget = encoded;
        }
      }
    }
  }

  if (bestUnderBudget == null) {
    throw StateError('Could not compress the $failureLabel.');
  }

  return bestUnderBudget;
}

Future<Uint8List> compressStoredFactSolutionWebp(
  Uint8List sourceBytes, {
  String failureLabel = 'solution image',
}) {
  return compressGenerationImageWebp(
    sourceBytes,
    targetBytes: kStoredFactSolutionTargetBytes,
    dimension: kStoredFactSolutionDimension,
    failureLabel: failureLabel,
  );
}

Future<Uint8List> compressStoredPuzzleWebp(
  Uint8List sourceBytes, {
  String failureLabel = 'puzzle image',
}) async {
  final candidate = await _compressWebpNearTarget(
    sourceBytes,
    targetBytes: kStoredPuzzleTargetBytes,
    dimension: kStoredPuzzleDimension,
    allowDownscaling: false,
  );
  if (candidate.isEmpty) {
    throw StateError('Could not compress the $failureLabel.');
  }
  return candidate;
}

Future<Uint8List> prepareStoredPuzzleSourceJpeg(
  Uint8List sourceBytes, {
  String failureLabel = 'puzzle image',
}) {
  return compute(
    _prepareStoredPuzzleSourceJpegIsolate,
    <String, dynamic>{
      'sourceBytes': sourceBytes,
      'failureLabel': failureLabel,
    },
  );
}

Future<Uint8List> compressStoredPuzzleThumbnailWebp(
  Uint8List sourceBytes, {
  String failureLabel = 'puzzle thumbnail',
}) async {
  final candidate = await _compressWebpNearTarget(
    sourceBytes,
    targetBytes: kStoredPuzzleThumbnailTargetBytes,
    dimension: kStoredPuzzleThumbnailDimension,
  );
  if (candidate.isEmpty) {
    throw StateError('Could not compress the $failureLabel.');
  }
  return candidate;
}

Future<({Uint8List imageBytes, Uint8List thumbnailBytes})>
    buildStoredPuzzleWebpAssets(
  Uint8List sourceBytes,
) async {
  final imageBytes = await compressStoredPuzzleWebp(sourceBytes);
  final thumbnailBytes = await compressStoredPuzzleThumbnailWebp(sourceBytes);
  return (
    imageBytes: imageBytes,
    thumbnailBytes: thumbnailBytes,
  );
}

Uint8List _prepareStoredPuzzleSourceJpegIsolate(Map<String, dynamic> payload) {
  final sourceBytes = payload['sourceBytes'] as Uint8List;
  final failureLabel = payload['failureLabel'] as String? ?? 'puzzle image';

  final decodedImage = img.decodeImage(sourceBytes);
  if (decodedImage == null) {
    throw StateError('Could not read the selected $failureLabel.');
  }

  final normalizedImage =
      decodedImage.width > kStoredPuzzleDimension ||
              decodedImage.height > kStoredPuzzleDimension
          ? img.copyResize(
              decodedImage,
              width: decodedImage.width >= decodedImage.height
                  ? kStoredPuzzleDimension
                  : null,
              height: decodedImage.height > decodedImage.width
                  ? kStoredPuzzleDimension
                  : null,
              interpolation: img.Interpolation.average,
            )
          : decodedImage;

  return Uint8List.fromList(
    img.encodeJpg(normalizedImage, quality: 94),
  );
}

Future<Uint8List> _compressWebpNearTarget(
  Uint8List bytes, {
  required int targetBytes,
  required int dimension,
  bool requireUnderBudget = false,
  bool allowDownscaling = true,
}) async {
  const qualities = <int>[80, 74, 68, 62, 56, 50, 44, 38, 30, 24, 18, 14, 10, 8, 5, 2, 0];
  final dimensions = <int>[dimension];
  
  if (allowDownscaling) {
    var nextDimension = (dimension * 0.84).round();
    while (nextDimension >= 256) {
      if (!dimensions.contains(nextDimension)) {
        dimensions.add(nextDimension);
      }
      if (nextDimension <= 320) {
        break;
      }
      nextDimension = (nextDimension * 0.84).round();
    }
  }
  Uint8List? bestUnderBudget;
  var smallestUnderDelta = 1 << 30;
  Uint8List? smallestOverall;
  var smallestOverallSize = 1 << 30;

  for (final candidateDimension in dimensions) {
    for (final quality in qualities) {
      final compressed = await FlutterImageCompress.compressWithList(
        bytes,
        format: CompressFormat.webp,
        quality: quality,
        minWidth: candidateDimension,
        minHeight: candidateDimension,
        keepExif: false,
      );
      final candidate = Uint8List.fromList(compressed);
      if (candidate.isEmpty) {
        continue;
      }

      if (candidate.length < smallestOverallSize) {
        smallestOverallSize = candidate.length;
        smallestOverall = candidate;
      }

      final delta = candidate.length - targetBytes;
      if (delta <= 0) {
        final underDelta = -delta;
        if (underDelta < smallestUnderDelta) {
          smallestUnderDelta = underDelta;
          bestUnderBudget = candidate;
        }
      }
    }
  }

  if (requireUnderBudget) {
    return bestUnderBudget ?? Uint8List(0);
  }

  return bestUnderBudget ?? smallestOverall ?? Uint8List(0);
}
