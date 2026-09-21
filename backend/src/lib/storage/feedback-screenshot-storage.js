/**
 * Feedback screenshot storage
 *
 * @module lib/storage
 * @description Puts the images attached to "Give us feedback" in the
 * configured provider and takes them out again. Everything goes through
 * `createStorageService()`, so local and S3 deployments behave the same, and
 * every object is encrypted at rest: a screenshot of this app can show
 * patient data.
 *
 * Nothing here returns a public URL. Images are read back as bytes and
 * streamed to platform owners and admins by the feedback routes.
 */

const { createStorageService } = require('@lib/storage/factory');
const { logger } = require('@lib/logging');
const {
  buildFeedbackScreenshotKey,
  feedbackScreenshotExtension
} = require('@lib/feedback/feedback-screenshots');

/**
 * Store the images of one submission.
 *
 * Best effort by design: an image that cannot be stored is reported back and
 * the feedback itself is still recorded. The caller writes a row only for
 * what actually landed in storage.
 *
 * @param {Object} options
 * @param {string} options.feedbackId - Owning feedback row
 * @param {Object[]} options.screenshots - From `prepareFeedbackScreenshots`
 * @param {Object} [options.storage] - Storage service; created when omitted
 * @returns {Promise<{ stored: Object[], failed: number }>} Rows to persist
 */
const storeFeedbackScreenshots = async ({ feedbackId, screenshots = [], storage } = {}) => {
  if (screenshots.length === 0) {
    return { stored: [], failed: 0 };
  }

  const service = storage || createStorageService();
  const stored = [];
  let failed = 0;

  for (let index = 0; index < screenshots.length; index += 1) {
    const screenshot = screenshots[index];
    const sequence = index + 1;
    const storageKey = buildFeedbackScreenshotKey({
      feedbackId,
      sequence,
      contentType: screenshot.content_type
    });

    try {
      const uploaded = await service.upload(screenshot.buffer, storageKey, {
        mimeType: screenshot.content_type,
        encrypt: true,
        metadata: { feedback_id: feedbackId, sequence: String(sequence) }
      });
      stored.push({
        sequence,
        storage_key: uploaded?.path || storageKey,
        content_type: screenshot.content_type,
        byte_size: screenshot.byte_size,
        width: screenshot.width,
        height: screenshot.height,
        caption: screenshot.caption,
        route_path: screenshot.route_path,
        route_name: screenshot.route_name,
        screen_title: screenshot.screen_title,
        client_context_json: screenshot.client_context,
        captured_at: screenshot.captured_at
      });
    } catch (error) {
      failed += 1;
      // The image is lost, the feedback is not: never fail a submission here.
      logger.warn('Feedback screenshot could not be stored', {
        feedback_id: feedbackId,
        sequence,
        error: error?.message
      });
    }
  }

  return { stored, failed };
};

/**
 * Read one screenshot back for an authorized viewer.
 *
 * @param {string} storageKey
 * @param {Object} [storage] - Storage service; created when omitted
 * @returns {Promise<Buffer|null>} Decrypted bytes, or null when gone
 */
const readFeedbackScreenshot = async (storageKey, storage) => {
  if (!storageKey) {
    return null;
  }
  const service = storage || createStorageService();
  try {
    const bytes = await service.download(storageKey);
    return Buffer.isBuffer(bytes) ? bytes : Buffer.from(bytes || []);
  } catch (error) {
    logger.warn('Feedback screenshot could not be read', {
      storage_key: storageKey,
      error: error?.message
    });
    return null;
  }
};

/**
 * Remove stored images, so none outlives the feedback it belonged to.
 *
 * Deleting an object that is already gone counts as deleted, which makes a
 * retry after a partial failure safe.
 *
 * @param {string[]} storageKeys
 * @param {Object} [storage] - Storage service; created when omitted
 * @returns {Promise<{ deleted: number, failed: string[] }>}
 */
const deleteFeedbackScreenshotObjects = async (storageKeys = [], storage) => {
  const keys = Array.from(
    new Set(storageKeys.map((key) => String(key || '').trim()).filter(Boolean))
  );
  if (keys.length === 0) {
    return { deleted: 0, failed: [] };
  }

  const service = storage || createStorageService();
  const failed = [];
  let deleted = 0;

  for (const key of keys) {
    try {
      await service.delete(key);
      deleted += 1;
    } catch (error) {
      failed.push(key);
      logger.error('Feedback screenshot could not be deleted', {
        storage_key: key,
        error: error?.message
      });
    }
  }

  return { deleted, failed };
};

module.exports = {
  deleteFeedbackScreenshotObjects,
  feedbackScreenshotExtension,
  readFeedbackScreenshot,
  storeFeedbackScreenshots
};
