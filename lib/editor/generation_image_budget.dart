import 'dart:typed_data';

import 'package:flutter_image_compress/flutter_image_compress.dart';

const int kGenerationPayloadTargetBytes = 50 * 1024;
const int kGenerationPayloadDimension = 1024;
const int kStoredFactSolutionTargetBytes = 40 * 1024;
const int kStoredFactSolutionDimension = 1024;
const int kStoredPuzzleTargetBytes = 150 * 1024;
const int kStoredPuzzleDimension = 1920;
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
  );
  if (candidate.isEmpty) {
    throw StateError('Could not compress the $failureLabel.');
  }
  return candidate;
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

Future<Uint8List> _compressWebpNearTarget(
  Uint8List bytes, {
  required int targetBytes,
  required int dimension,
  bool requireUnderBudget = false,
}) async {
  const qualities = <int>[84, 76, 68, 60, 52, 44, 36, 30, 24, 18, 14, 10, 8];
  final dimensions = <int>[];
  var nextDimension = dimension;
  while (nextDimension >= 256) {
    if (!dimensions.contains(nextDimension)) {
      dimensions.add(nextDimension);
    }
    if (nextDimension <= 320) {
      break;
    }
    nextDimension = (nextDimension * 0.84).round();
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
