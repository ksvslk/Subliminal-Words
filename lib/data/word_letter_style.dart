import 'package:flutter/material.dart';

const int kDefaultWordLetterWeightValue = 700;

class WordLetterWeightOption {
  final int value;
  final String label;

  const WordLetterWeightOption({
    required this.value,
    required this.label,
  });
}

const List<WordLetterWeightOption> kWordLetterWeightOptions =
    <WordLetterWeightOption>[
  WordLetterWeightOption(value: 200, label: 'Slim'),
  WordLetterWeightOption(value: 400, label: 'Narrow'),
  WordLetterWeightOption(value: 700, label: 'Bold'),
];

int normalizeWordLetterWeightValue(int value) {
  var closest = kWordLetterWeightOptions.first.value;
  var closestDistance = (value - closest).abs();

  for (final option in kWordLetterWeightOptions.skip(1)) {
    final distance = (value - option.value).abs();
    if (distance < closestDistance) {
      closest = option.value;
      closestDistance = distance;
    }
  }

  return closest;
}

FontWeight wordLetterFontWeight(int value) {
  switch (normalizeWordLetterWeightValue(value)) {
    case 200:
      return FontWeight.w200;
    case 400:
      return FontWeight.w400;
    case 700:
    default:
      return FontWeight.w700;
  }
}

double wordLetterEditorOutlineStrokeWidth(int value) {
  switch (normalizeWordLetterWeightValue(value)) {
    case 200:
      return 1.0;
    case 400:
      return 2.2;
    case 700:
    default:
      return 4.4;
  }
}

double wordLetterPainterBaseStrokeWidth(int value) {
  switch (normalizeWordLetterWeightValue(value)) {
    case 200:
      return 2.6;
    case 400:
      return 4.4;
    case 700:
    default:
      return 7.8;
  }
}

double wordLetterPainterGlowStrokeWidth(int value) {
  switch (normalizeWordLetterWeightValue(value)) {
    case 200:
      return 3.8;
    case 400:
      return 6.2;
    case 700:
    default:
      return 10.6;
  }
}

double wordLetterWidthScale(int value) {
  switch (normalizeWordLetterWeightValue(value)) {
    case 200:
      return 0.54;
    case 400:
      return 0.78;
    case 700:
    default:
      return 1.0;
  }
}
