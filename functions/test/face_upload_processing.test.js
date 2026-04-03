const test = require('node:test');
const assert = require('node:assert/strict');
const sharp = require('sharp');

const {
  SANITIZED_FACE_MAX_DIMENSION,
  sanitizeUploadedFaceImage,
} = require('../src/face_upload_processing');
const { detectImageFormat } = require('../src/face_upload_validation');

test('sanitizeUploadedFaceImage re-encodes a valid raster image as webp', async () => {
  const pngBytes = await sharp({
    create: {
      width: 120,
      height: 80,
      channels: 3,
      background: { r: 240, g: 180, b: 120 },
    },
  })
    .png()
    .toBuffer();

  const sanitized = await sanitizeUploadedFaceImage(pngBytes);
  assert.equal(detectImageFormat(sanitized.bytes)?.contentType, 'image/webp');
  assert.equal(sanitized.width, 120);
  assert.equal(sanitized.height, 80);
});

test('sanitizeUploadedFaceImage rejects unreadable bytes', async () => {
  await assert.rejects(
    () => sanitizeUploadedFaceImage(Buffer.from('not-an-image')),
    /could not read that face photo/i,
  );
});

test('sanitizeUploadedFaceImage rejects overly large source dimensions', async () => {
  const hugePng = await sharp({
    create: {
      width: 5000,
      height: 20,
      channels: 3,
      background: { r: 20, g: 30, b: 40 },
    },
  })
    .png()
    .toBuffer();

  await assert.rejects(
    () => sanitizeUploadedFaceImage(hugePng),
    /too large/i,
  );
});

test('sanitizeUploadedFaceImage downsizes larger images into the configured ceiling', async () => {
  const largePng = await sharp({
    create: {
      width: 2200,
      height: 1800,
      channels: 3,
      background: { r: 80, g: 90, b: 100 },
    },
  })
    .png()
    .toBuffer();

  const sanitized = await sanitizeUploadedFaceImage(largePng);
  assert.ok(sanitized.width <= SANITIZED_FACE_MAX_DIMENSION);
  assert.ok(sanitized.height <= SANITIZED_FACE_MAX_DIMENSION);
});
