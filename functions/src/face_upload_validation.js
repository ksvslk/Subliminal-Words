const FACE_UPLOAD_MAX_BYTES = 3 * 1024 * 1024;

function extractBase64Payload(value) {
  const normalized = String(value || '').trim();
  if (!normalized) {
    throw new Error('A face photo is required.');
  }

  const match = normalized.match(/^data:[^;]+;base64,(.+)$/i);
  return match ? match[1] : normalized;
}

function detectImageFormat(buffer) {
  if (
    buffer.length >= 3 &&
    buffer[0] === 0xff &&
    buffer[1] === 0xd8 &&
    buffer[2] === 0xff
  ) {
    return { contentType: 'image/jpeg', extension: 'jpg' };
  }

  if (
    buffer.length >= 8 &&
    buffer[0] === 0x89 &&
    buffer[1] === 0x50 &&
    buffer[2] === 0x4e &&
    buffer[3] === 0x47 &&
    buffer[4] === 0x0d &&
    buffer[5] === 0x0a &&
    buffer[6] === 0x1a &&
    buffer[7] === 0x0a
  ) {
    return { contentType: 'image/png', extension: 'png' };
  }

  if (
    buffer.length >= 12 &&
    buffer.toString('ascii', 0, 4) === 'RIFF' &&
    buffer.toString('ascii', 8, 12) === 'WEBP'
  ) {
    return { contentType: 'image/webp', extension: 'webp' };
  }

  return null;
}

function assertFaceUploadBufferWithinSizeLimit(buffer) {
  if (buffer.length > FACE_UPLOAD_MAX_BYTES) {
    throw new Error('That face photo is too large. Please choose a smaller image.');
  }
}

module.exports = {
  FACE_UPLOAD_MAX_BYTES,
  extractBase64Payload,
  detectImageFormat,
  assertFaceUploadBufferWithinSizeLimit,
};
