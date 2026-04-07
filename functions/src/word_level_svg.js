const SVG_SIZE = 1024;
const MIN_FONT_SIZE = 24;
const MAX_FONT_SIZE = 512;
const MIN_NORMALIZED_POSITION = 0;
const MAX_NORMALIZED_POSITION = 1;
const MIN_SCALE = 0.2;
const MAX_SCALE = 12.0;
const MAX_ABS_ROTATION = 360;
const MAX_ABS_SKEW = 80;
const MIN_OPACITY = 0;
const MAX_OPACITY = 1;
const ALLOWED_FONT_WEIGHTS = [200, 400, 700];

function escapeXml(value) {
  return String(value || '')
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll("'", '&apos;');
}

function normalizeSolutionCharacters(value) {
  return Array.from(String(value || ''))
    .filter((character) => character.trim() !== '');
}

function normalizeWordLetterWeightValue(value) {
  let closest = ALLOWED_FONT_WEIGHTS[0];
  let closestDistance = Math.abs(Number(value || closest) - closest);

  for (const candidate of ALLOWED_FONT_WEIGHTS.slice(1)) {
    const distance = Math.abs(Number(value || candidate) - candidate);
    if (distance < closestDistance) {
      closest = candidate;
      closestDistance = distance;
    }
  }

  return closest;
}

function requireFiniteNumber(value, message) {
  const parsed = Number(value);
  if (!Number.isFinite(parsed)) {
    throw new Error(message);
  }
  return parsed;
}

function requireNumberInRange(value, min, max, message) {
  const parsed = requireFiniteNumber(value, message);
  if (parsed < min || parsed > max) {
    throw new Error(message);
  }
  return parsed;
}

function sanitizeWordLettersForSolution(rawLetters, { answer = '' } = {}) {
  if (!Array.isArray(rawLetters) || rawLetters.length === 0) {
    throw new Error('Add the solution letters again so they match the solution.');
  }

  const solutionCharacters = normalizeSolutionCharacters(answer);
  if (solutionCharacters.length && solutionCharacters.length !== rawLetters.length) {
    throw new Error('Add the solution letters again so they match the solution.');
  }

  return rawLetters.map((rawLetter, index) => {
    const letter = String(rawLetter?.letter || '').trim();
    if (!letter || letter.length > 3) {
      throw new Error('Add the solution letters again so they match the solution.');
    }

    if (
      solutionCharacters.length &&
      letter.toUpperCase() !== solutionCharacters[index].toUpperCase()
    ) {
      throw new Error('Add the solution letters again so they match the solution.');
    }

    return {
      id: `letter_${index + 1}`,
      letter,
      x: requireFiniteNumber(
        rawLetter?.x ?? 0,
        'Word letter position is invalid.',
      ),
      y: requireFiniteNumber(
        rawLetter?.y ?? 0,
        'Word letter position is invalid.',
      ),
      fontSize: requireFiniteNumber(
        rawLetter?.fontSize ?? 12,
        'Word letter size is invalid.',
      ),
      rotationDegrees: requireFiniteNumber(
        rawLetter?.rotationDegrees ?? 0,
        'Word letter rotation is invalid.',
      ),
      scaleX: requireFiniteNumber(
        rawLetter?.scaleX ?? 1,
        'Word letter scale is invalid.',
      ),
      scaleY: requireFiniteNumber(
        rawLetter?.scaleY ?? 1,
        'Word letter scale is invalid.',
      ),
      skewXDegrees: requireFiniteNumber(
        rawLetter?.skewXDegrees ?? 0,
        'Word letter skew is invalid.',
      ),
      skewYDegrees: requireFiniteNumber(
        rawLetter?.skewYDegrees ?? 0,
        'Word letter skew is invalid.',
      ),
      opacity: requireFiniteNumber(
        rawLetter?.opacity ?? 1,
        'Word letter opacity is invalid.',
      ),
      fontWeightValue: normalizeWordLetterWeightValue(
        rawLetter?.fontWeightValue,
      ),
    };
  });
}

function buildCanonicalWordSolutionSvg(rawLetters, { answer = '' } = {}) {
  const letters = sanitizeWordLettersForSolution(rawLetters, { answer });
  const lines = [
    '<?xml version="1.0" encoding="UTF-8" standalone="no"?>',
    `<svg width="${SVG_SIZE}" height="${SVG_SIZE}" viewBox="0 0 ${SVG_SIZE} ${SVG_SIZE}" xmlns="http://www.w3.org/2000/svg">`,
  ];

  for (const letter of letters) {
    const x = letter.x * SVG_SIZE;
    const y = letter.y * SVG_SIZE;
    const escapedLetter = escapeXml(letter.letter);
    lines.push(
      `<text id="${letter.id}" aria-label="${escapedLetter}" x="0" y="0" ` +
        `font-size="${letter.fontSize.toFixed(2)}" ` +
        `font-weight="${letter.fontWeightValue}" ` +
        `font-family="Roboto, Arial, sans-serif" ` +
        `text-anchor="middle" dominant-baseline="middle" fill="#000000" ` +
        `fill-opacity="${letter.opacity.toFixed(3)}" ` +
        `transform="translate(${x.toFixed(2)} ${y.toFixed(2)}) rotate(${letter.rotationDegrees.toFixed(2)}) skewX(${letter.skewXDegrees.toFixed(2)}) skewY(${letter.skewYDegrees.toFixed(2)}) scale(${letter.scaleX.toFixed(3)} ${letter.scaleY.toFixed(3)})" ` +
        `data-x="${x.toFixed(2)}" data-y="${y.toFixed(2)}" ` +
        `data-font-size="${letter.fontSize.toFixed(2)}" ` +
        `data-font-weight="${letter.fontWeightValue}" ` +
        `data-rotation="${letter.rotationDegrees.toFixed(2)}" ` +
        `data-scale-x="${letter.scaleX.toFixed(3)}" ` +
        `data-scale-y="${letter.scaleY.toFixed(3)}" ` +
        `data-skew-x="${letter.skewXDegrees.toFixed(2)}" ` +
        `data-skew-y="${letter.skewYDegrees.toFixed(2)}" ` +
        `data-opacity="${letter.opacity.toFixed(3)}">${escapedLetter}</text>`,
    );
  }

  lines.push('</svg>');
  return lines.join('\n');
}

module.exports = {
  buildCanonicalWordSolutionSvg,
  normalizeSolutionCharacters,
  sanitizeWordLettersForSolution,
};
