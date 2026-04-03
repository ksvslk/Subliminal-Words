const test = require('node:test');
const assert = require('node:assert/strict');

const {
  buildCanonicalWordSolutionSvg,
  sanitizeWordLettersForSolution,
} = require('../src/word_level_svg');

test('sanitizeWordLettersForSolution normalizes ids and font weights', () => {
  const result = sanitizeWordLettersForSolution(
    [
      {
        id: 'custom_a',
        letter: 'A',
        x: 0.25,
        y: 0.4,
        fontSize: 140,
        rotationDegrees: 12,
        scaleX: 1.3,
        scaleY: 0.9,
        skewXDegrees: 5,
        skewYDegrees: -3,
        opacity: 0.75,
        fontWeightValue: 650,
      },
      {
        id: 'custom_b',
        letter: 'B',
        x: 0.6,
        y: 0.7,
        fontSize: 180,
        rotationDegrees: -8,
        scaleX: 1.0,
        scaleY: 1.0,
        skewXDegrees: 0,
        skewYDegrees: 0,
        opacity: 1,
        fontWeightValue: 210,
      },
    ],
    { answer: 'AB' },
  );

  assert.equal(result.length, 2);
  assert.equal(result[0].id, 'letter_1');
  assert.equal(result[1].id, 'letter_2');
  assert.equal(result[0].fontWeightValue, 700);
  assert.equal(result[1].fontWeightValue, 200);
});

test('buildCanonicalWordSolutionSvg escapes XML-sensitive content', () => {
  const svg = buildCanonicalWordSolutionSvg(
    [
      {
        letter: '<',
        x: 0.5,
        y: 0.5,
        fontSize: 160,
        rotationDegrees: 0,
        scaleX: 1,
        scaleY: 1,
        skewXDegrees: 0,
        skewYDegrees: 0,
        opacity: 1,
        fontWeightValue: 400,
      },
    ],
    { answer: '<' },
  );

  assert.match(svg, /aria-label="&lt;"/);
  assert.match(svg, />&lt;<\/text>/);
  assert.match(svg, /id="letter_1"/);
  assert.match(svg, /viewBox="0 0 1024 1024"/);
});

test('buildCanonicalWordSolutionSvg rejects mismatched answer content', () => {
  assert.throws(
    () =>
      buildCanonicalWordSolutionSvg(
        [
          {
            letter: 'A',
            x: 0.5,
            y: 0.5,
            fontSize: 160,
            rotationDegrees: 0,
            scaleX: 1,
            scaleY: 1,
            skewXDegrees: 0,
            skewYDegrees: 0,
            opacity: 1,
            fontWeightValue: 400,
          },
        ],
        { answer: 'B' },
      ),
    /Add the solution letters again/,
  );
});

test('buildCanonicalWordSolutionSvg rejects out-of-range geometry', () => {
  assert.throws(
    () =>
      buildCanonicalWordSolutionSvg(
        [
          {
            letter: 'A',
            x: 1.2,
            y: 0.5,
            fontSize: 160,
            rotationDegrees: 0,
            scaleX: 1,
            scaleY: 1,
            skewXDegrees: 0,
            skewYDegrees: 0,
            opacity: 1,
            fontWeightValue: 400,
          },
        ],
        { answer: 'A' },
      ),
    /position is invalid/i,
  );
});
