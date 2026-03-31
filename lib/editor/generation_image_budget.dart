import 'dart:typed_data';

import 'package:flutter_image_compress/flutter_image_compress.dart';

const int kGenerationPayloadTargetBytes = 40 * 1024;
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
  );
  if (candidate.isEmpty) {
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
}) async {
  const qualities = <int>[82, 76, 70, 64, 58, 52, 46, 40, 34, 28, 22];
  Uint8List? bestUnderBudget;
  var smallestUnderDelta = 1 << 30;
  Uint8List? closestOverBudget;
  var smallestOverDelta = 1 << 30;

  for (final quality in qualities) {
    final compressed = await FlutterImageCompress.compressWithList(
      bytes,
      format: CompressFormat.webp,
      quality: quality,
      minWidth: dimension,
      minHeight: dimension,
      keepExif: false,
    );
    final candidate = Uint8List.fromList(compressed);
    if (candidate.isEmpty) {
      continue;
    }

    final delta = candidate.length - targetBytes;
    if (delta <= 0) {
      final underDelta = -delta;
      if (underDelta < smallestUnderDelta) {
        smallestUnderDelta = underDelta;
        bestUnderBudget = candidate;
      }
    } else if (delta < smallestOverDelta) {
      smallestOverDelta = delta;
      closestOverBudget = candidate;
    }
  }

  return bestUnderBudget ?? closestOverBudget ?? Uint8List(0);
}
