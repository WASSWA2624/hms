/**
 * Feedback screenshots
 *
 * @module lib/feedback
 * @description Limits, type sniffing, storage keys, and archive file names for
 * the images attached to "Give us feedback".
 *
 * Images are held by the storage provider, never in the database, and never
 * under a public path: a screenshot of this app can show patient data. Both
 * storage providers sanitize a key into a single flat file name, so the keys
 * built here carry no path separator.
 */

const crypto = require('crypto');

/** Shots one submission may carry, and the lower cap for anonymous reporters. */
const FEEDBACK_MAX_SCREENSHOTS = 10;
const FEEDBACK_MAX_ANONYMOUS_SCREENSHOTS = 3;

/** Per-image and whole-request size caps, mirrored by the app before upload. */
const FEEDBACK_SCREENSHOT_MAX_BYTES = 2 * 1024 * 1024;
const FEEDBACK_SCREENSHOTS_MAX_TOTAL_BYTES = 12 * 1024 * 1024;

/** The multipart field the app sends its images under. */
const FEEDBACK_SCREENSHOT_FIELD = 'screenshots';

/** Accepted image types, decided by content rather than by file extension. */
const FEEDBACK_SCREENSHOT_CONTENT_TYPES = Object.freeze([
  'image/jpeg',
  'image/png',
  'image/webp'
]);

const FEEDBACK_SCREENSHOT_EXTENSIONS = Object.freeze({
  'image/jpeg': 'jpg',
  'image/png': 'png',
  'image/webp': 'webp'
});

const FEEDBACK_SCREENSHOT_KEY_PREFIX = 'fbshot';
const MAX_STORAGE_KEY_LENGTH = 255;
const MAX_CAPTION_LENGTH = 255;

/**
 * The image type a buffer actually holds, from its magic bytes.
 *
 * A declared MIME type is the client's word for it; this is the file's own.
 *
 * @param {Buffer|null|undefined} buffer - Uploaded bytes
 * @returns {string|null} One of FEEDBACK_SCREENSHOT_CONTENT_TYPES, else null
 */
const detectFeedbackImageContentType = (buffer) => {
  if (!Buffer.isBuffer(buffer) || buffer.length < 12) {
    return null;
  }
  if (buffer[0] === 0xff && buffer[1] === 0xd8 && buffer[2] === 0xff) {
    return 'image/jpeg';
  }
  const pngSignature = Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]);
  if (buffer.subarray(0, 8).equals(pngSignature)) {
    return 'image/png';
  }
  if (
    buffer.subarray(0, 4).toString('ascii') === 'RIFF' &&
    buffer.subarray(8, 12).toString('ascii') === 'WEBP'
  ) {
    return 'image/webp';
  }
  return null;
};

/**
 * @param {string} contentType
 * @returns {string} File extension without the dot, e.g. `jpg`
 */
const feedbackScreenshotExtension = (contentType) =>
  FEEDBACK_SCREENSHOT_EXTENSIONS[contentType] || 'bin';

/**
 * Flat storage key for one screenshot: `fbshot-<id8>-<sequence>-<random>.jpg`.
 *
 * The feedback id fragment keeps the objects of one report together when a
 * bucket is listed; the random suffix keeps a re-upload from overwriting an
 * existing image.
 *
 * @param {Object} options
 * @param {string} options.feedbackId - The feedback row's uuid
 * @param {number} options.sequence - 1-based position in the submission
 * @param {string} options.contentType - Sniffed image type
 * @returns {string}
 */
const buildFeedbackScreenshotKey = ({ feedbackId, sequence, contentType }) => {
  const compact = String(feedbackId || '')
    .replace(/[^a-zA-Z0-9]/g, '')
    .toLowerCase();
  const idFragment = (compact.slice(-8) || 'feedback').slice(0, 8);
  const position = Math.max(1, Math.min(999, Number(sequence) || 1));
  const random = crypto.randomBytes(4).toString('hex');
  const key =
    `${FEEDBACK_SCREENSHOT_KEY_PREFIX}-${idFragment}-${position}-${random}` +
    `.${feedbackScreenshotExtension(contentType)}`;
  return key.slice(0, MAX_STORAGE_KEY_LENGTH);
};

/**
 * The name one screenshot takes inside a download archive:
 * `FBK0000011.jpg`, then `FBK0000011-2.jpg`, `-3`, and so on.
 *
 * @param {Object} options
 * @param {string} options.referenceId - Feedback `human_friendly_id`
 * @param {number} options.position - 1-based position among that record's shots
 * @param {string} options.contentType
 * @returns {string}
 */
const buildFeedbackScreenshotFileName = ({ referenceId, position, contentType }) => {
  const reference = String(referenceId || 'FEEDBACK').replace(/[^A-Za-z0-9_-]/g, '');
  const suffix = position > 1 ? `-${position}` : '';
  return `${reference || 'FEEDBACK'}${suffix}.${feedbackScreenshotExtension(contentType)}`;
};

/**
 * How many shots a submitter may attach.
 *
 * @param {Object} [options]
 * @param {boolean} [options.authenticated] - Whether a session identified them
 * @returns {number}
 */
const maxFeedbackScreenshotsFor = ({ authenticated = false } = {}) =>
  authenticated ? FEEDBACK_MAX_SCREENSHOTS : FEEDBACK_MAX_ANONYMOUS_SCREENSHOTS;

const toPositiveInteger = (value, max) => {
  const number = Number(value);
  if (!Number.isFinite(number) || number <= 0) {
    return null;
  }
  return Math.min(Math.round(number), max);
};

const toTrimmedText = (value, maxLength) => {
  const text = String(value ?? '').trim();
  if (!text) {
    return null;
  }
  return text.length > maxLength ? text.slice(0, maxLength) : text;
};

const toOptionalDate = (value) => {
  if (!value) {
    return null;
  }
  const date = value instanceof Date ? value : new Date(value);
  return Number.isNaN(date.getTime()) ? null : date;
};

/**
 * Pair uploaded files with the per-shot metadata the app sent beside them, and
 * reject anything that is not an image the API accepts.
 *
 * The files decide the order: metadata is matched by position, so a missing or
 * malformed entry costs only its caption and screen, never the image.
 *
 * @param {Object} options
 * @param {Object[]} [options.files] - Multer memory-storage files
 * @param {Object[]} [options.metadata] - Validated per-shot metadata, in order
 * @returns {{ accepted: Object[], rejected: Object[] }}
 */
const prepareFeedbackScreenshots = ({ files = [], metadata = [] } = {}) => {
  const accepted = [];
  const rejected = [];

  files.forEach((file, index) => {
    const buffer = file?.buffer;
    const entry = metadata[index] && typeof metadata[index] === 'object' ? metadata[index] : {};
    const contentType = detectFeedbackImageContentType(buffer);
    if (!contentType) {
      rejected.push({ index, reason: 'unsupported_type' });
      return;
    }
    if (buffer.length > FEEDBACK_SCREENSHOT_MAX_BYTES) {
      rejected.push({ index, reason: 'too_large' });
      return;
    }

    accepted.push({
      buffer,
      content_type: contentType,
      byte_size: buffer.length,
      width: toPositiveInteger(entry.width, 100000),
      height: toPositiveInteger(entry.height, 100000),
      caption: toTrimmedText(entry.caption, MAX_CAPTION_LENGTH),
      route_path: toTrimmedText(entry.route_path, 512),
      route_name: toTrimmedText(entry.route_name, 120),
      screen_title: toTrimmedText(entry.screen_title, 255),
      client_context:
        entry.client_context && typeof entry.client_context === 'object'
          ? entry.client_context
          : null,
      captured_at: toOptionalDate(entry.captured_at)
    });
  });

  return { accepted, rejected };
};

module.exports = {
  FEEDBACK_MAX_ANONYMOUS_SCREENSHOTS,
  FEEDBACK_MAX_SCREENSHOTS,
  FEEDBACK_SCREENSHOTS_MAX_TOTAL_BYTES,
  FEEDBACK_SCREENSHOT_CONTENT_TYPES,
  FEEDBACK_SCREENSHOT_FIELD,
  FEEDBACK_SCREENSHOT_MAX_BYTES,
  buildFeedbackScreenshotFileName,
  buildFeedbackScreenshotKey,
  detectFeedbackImageContentType,
  feedbackScreenshotExtension,
  maxFeedbackScreenshotsFor,
  prepareFeedbackScreenshots
};
