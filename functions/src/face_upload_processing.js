const sharp = require('sharp');

const MAX_IMAGE_DIMENSION = 4096;
const MAX_IMAGE_PIXELS = 20 * 1024 * 1024;
const SANITIZED_FACE_MAX_DIMENSION = 1400;

async function sanitizeUploadedFaceImage(buffer) {
  let metadata;
  try {
    metadata = await sharp(buffer, {
      failOn: 'error',
      limitInputPixels: MAX_IMAGE_PIXELS,
    }).metadata();
  } catch (_) {
    throw new Error('Could not read that face photo.');
  }

  const width = Number(metadata.width || 0);
  const height = Number(metadata.height || 0);
  if (!width || !height) {
    throw new Error('Could not read that face photo.');
  }

  if (width > MAX_IMAGE_DIMENSION || height > MAX_IMAGE_DIMENSION) {
    throw new Error('That face photo is too large. Please choose a smaller image.');
  }

  if (width * height > MAX_IMAGE_PIXELS) {
    throw new Error(
      'That face photo has too many pixels. Please choose a smaller image.',
    );
  }

  const resized = await sharp(buffer, {
    failOn: 'error',
    limitInputPixels: MAX_IMAGE_PIXELS,
  })
    .rotate()
    .resize({
      width: SANITIZED_FACE_MAX_DIMENSION,
      height: SANITIZED_FACE_MAX_DIMENSION,
      fit: 'inside',
      withoutEnlargement: true,
    })
    .webp({
      quality: 82,
      effort: 5,
    })
    .toBuffer();

  const sanitizedMetadata = await sharp(resized).metadata();
  return {
    bytes: resized,
    width: Number(sanitizedMetadata.width || 0),
    height: Number(sanitizedMetadata.height || 0),
  };
}

module.exports = {
  MAX_IMAGE_DIMENSION,
  MAX_IMAGE_PIXELS,
  SANITIZED_FACE_MAX_DIMENSION,
  sanitizeUploadedFaceImage,
};
