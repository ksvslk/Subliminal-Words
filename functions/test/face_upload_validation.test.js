const test = require('node:test');
const assert = require('node:assert/strict');

const {
  FACE_UPLOAD_MAX_BYTES,
  extractBase64Payload,
  detectImageFormat,
  assertFaceUploadBufferWithinSizeLimit,
} = require('../src/face_upload_validation');

test('extractBase64Payload removes data URL prefix and rejects empty values', () => {
  assert.equal(
    extractBase64Payload('data:image/png;base64,abc123'),
    'abc123',
  );
  assert.equal(extractBase64Payload(' raw-base64 '), 'raw-base64');
  assert.throws(() => extractBase64Payload('   '), /face photo is required/i);
});

test('detectImageFormat recognizes jpg png and webp magic bytes', () => {
  assert.deepEqual(
    detectImageFormat(Buffer.from([0xff, 0xd8, 0xff, 0xdb])),
    { contentType: 'image/jpeg', extension: 'jpg' },
  );
  assert.deepEqual(
    detectImageFormat(
      Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]),
    ),
    { contentType: 'image/png', extension: 'png' },
  );
  assert.deepEqual(
    detectImageFormat(Buffer.from('RIFFxxxxWEBP', 'ascii')),
    { contentType: 'image/webp', extension: 'webp' },
  );
});

test('detectImageFormat rejects non-raster content like svg', () => {
  assert.equal(
    detectImageFormat(Buffer.from('<svg xmlns="http://www.w3.org/2000/svg"/>')),
    null,
  );
});

test('assertFaceUploadBufferWithinSizeLimit enforces the max byte budget', () => {
  assert.doesNotThrow(() =>
    assertFaceUploadBufferWithinSizeLimit(Buffer.alloc(FACE_UPLOAD_MAX_BYTES)),
  );
  assert.throws(
    () =>
      assertFaceUploadBufferWithinSizeLimit(
        Buffer.alloc(FACE_UPLOAD_MAX_BYTES + 1),
      ),
    /too large/i,
  );
});
