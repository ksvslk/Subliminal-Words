import 'package:flutter_test/flutter_test.dart';
import 'package:operation_hermes/editor/word_overlay_editor.dart';

void main() {
  group('Word overlay SVG', () {
    const letters = <WordOverlayLetter>[
      WordOverlayLetter(
        id: 'custom_1',
        letter: 'A',
        normalizedCenter: Offset(0.25, 0.5),
        fontSize: 144,
        rotationDegrees: 12,
        scaleX: 1.1,
        scaleY: 0.95,
        skewXDegrees: 4,
        skewYDegrees: -2,
        opacity: 0.8,
        fontWeightValue: 700,
      ),
      WordOverlayLetter(
        id: 'custom_2',
        letter: '<&',
        normalizedCenter: Offset(0.75, 0.3),
        fontSize: 188,
        rotationDegrees: -8,
        scaleX: 0.9,
        scaleY: 1.2,
        skewXDegrees: 1,
        skewYDegrees: 3,
        opacity: 0.65,
        fontWeightValue: 400,
      ),
    ];

    test('generateWordOverlaySvg escapes letter text safely', () {
      final svg = generateWordOverlaySvg(letters);

      expect(svg, contains('id="custom_1"'));
      expect(svg, contains('id="custom_2"'));
      expect(svg, contains('aria-label="&lt;&amp;"'));
      expect(svg, contains('&lt;&amp;</text>'));
    });

    test('parseWordOverlayLetters round-trips generated svg data', () {
      final svg = generateWordOverlaySvg(letters);
      final parsed = parseWordOverlayLetters(svg);

      expect(parsed, hasLength(letters.length));

      for (var index = 0; index < letters.length; index += 1) {
        final original = letters[index];
        final roundTripped = parsed[index];

        expect(roundTripped.id, original.id);
        expect(roundTripped.letter, original.letter);
        expect(
          roundTripped.normalizedCenter.dx,
          closeTo(original.normalizedCenter.dx, 0.0001),
        );
        expect(
          roundTripped.normalizedCenter.dy,
          closeTo(original.normalizedCenter.dy, 0.0001),
        );
        expect(roundTripped.fontSize, closeTo(original.fontSize, 0.01));
        expect(
          roundTripped.rotationDegrees,
          closeTo(original.rotationDegrees, 0.01),
        );
        expect(roundTripped.scaleX, closeTo(original.scaleX, 0.001));
        expect(roundTripped.scaleY, closeTo(original.scaleY, 0.001));
        expect(
          roundTripped.skewXDegrees,
          closeTo(original.skewXDegrees, 0.01),
        );
        expect(
          roundTripped.skewYDegrees,
          closeTo(original.skewYDegrees, 0.01),
        );
        expect(roundTripped.opacity, closeTo(original.opacity, 0.001));
        expect(roundTripped.fontWeightValue, original.fontWeightValue);
      }
    });

    test('buildWordOverlayLettersFromSolution strips whitespace characters', () {
      final built = buildWordOverlayLettersFromSolution('A B  C');

      expect(built.map((letter) => letter.letter).toList(), ['A', 'B', 'C']);
      expect(built, hasLength(3));
    });
  });
}
