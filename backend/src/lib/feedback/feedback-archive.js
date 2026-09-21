/**
 * Feedback download archive
 *
 * @module lib/feedback
 * @description "Download feedback" hands back
 * `HOSSPI-FEEDBACK-DDMMYYYY-HHmmss.zip`, not a bare workbook:
 *
 * - the workbook, with its `Feedback`, `Screenshots` and `Export Details`
 *   sheets;
 * - `screenshots/FBK0000011.jpg` (then `-2`, `-3`, …), the images as the
 *   `Screenshots` sheet names them;
 * - `feedback-prompts-generator.md`, shipped verbatim from this folder, which
 *   tells a coding agent how to turn the archive into implementation prompts.
 *
 * The archive is streamed and each image is read from storage only as it is
 * appended, so exporting thousands of records never holds them all in memory.
 */

const fs = require('fs');
const path = require('path');
const archiver = require('archiver');
const { logger } = require('@lib/logging');
const { buildFeedbackExportFileName } = require('@lib/feedback/feedback-export');

const FEEDBACK_ARCHIVE_MIME_TYPE = 'application/zip';
const FEEDBACK_ARCHIVE_SCREENSHOT_FOLDER = 'screenshots';
const FEEDBACK_PROMPTS_GENERATOR_FILE_NAME = 'feedback-prompts-generator.md';

// Resolved from this module, not the working directory, so the file is found
// whatever the process was started from.
const PROMPTS_GENERATOR_PATH = path.join(__dirname, FEEDBACK_PROMPTS_GENERATOR_FILE_NAME);

let cachedPromptsGenerator = null;

/**
 * The prompts generator that ships inside every archive, byte for byte as it
 * is kept in the repository. Read once and kept in memory; a deployment that
 * somehow lacks the file still gets an archive, minus the generator.
 *
 * @returns {Promise<Buffer|null>}
 */
const readFeedbackPromptsGenerator = async () => {
  if (cachedPromptsGenerator) {
    return cachedPromptsGenerator;
  }
  try {
    cachedPromptsGenerator = await fs.promises.readFile(PROMPTS_GENERATOR_PATH);
    return cachedPromptsGenerator;
  } catch (error) {
    logger.error('Feedback prompts generator is missing from the deployment', {
      path: PROMPTS_GENERATOR_PATH,
      error: error?.message
    });
    return null;
  }
};

/**
 * `HOSSPI-FEEDBACK-DDMMYYYY-HHmmss.zip` on the export clock, matching the
 * workbook inside it.
 *
 * @param {Date} [date]
 * @param {Object} [clock] - From `resolveExportClock`
 * @returns {string}
 */
const buildFeedbackArchiveFileName = (date, clock) =>
  buildFeedbackExportFileName(date, clock).replace(/\.xlsx$/i, '.zip');

/**
 * Build the archive as a readable stream.
 *
 * Images are fetched one at a time through [readScreenshot]; one that cannot
 * be read is left out rather than failing the download, since the workbook
 * still describes it.
 *
 * @param {Object} options
 * @param {string} options.workbookFileName
 * @param {Buffer} options.workbookBuffer
 * @param {Object[]} [options.screenshots] - From `listFeedbackExportScreenshots`
 * @param {(storageKey: string) => Promise<Buffer|null>} [options.readScreenshot]
 * @returns {import('archiver').Archiver} Stream to pipe at the response
 */
const streamFeedbackArchive = ({
  workbookFileName,
  workbookBuffer,
  screenshots = [],
  readScreenshot
} = {}) => {
  const archive = archiver('zip', { zlib: { level: 9 } });

  // A missing image must not abort a download; anything else is fatal.
  archive.on('warning', (error) => {
    if (error?.code === 'ENOENT') {
      logger.warn('Feedback archive entry missing', { error: error?.message });
      return;
    }
    archive.emit('error', error);
  });

  const fill = async () => {
    archive.append(workbookBuffer, { name: workbookFileName });

    const generator = await readFeedbackPromptsGenerator();
    if (generator) {
      archive.append(generator, { name: FEEDBACK_PROMPTS_GENERATOR_FILE_NAME });
    }

    for (const entry of screenshots) {
      if (typeof readScreenshot !== 'function') {
        break;
      }
      const bytes = await readScreenshot(entry.storage_key);
      if (!bytes || bytes.length === 0) {
        logger.warn('Feedback archive skipped an unreadable screenshot', {
          storage_key: entry.storage_key,
          file_name: entry.file_name
        });
        continue;
      }
      archive.append(bytes, {
        name: `${FEEDBACK_ARCHIVE_SCREENSHOT_FOLDER}/${entry.file_name}`
      });
    }

    await archive.finalize();
  };

  fill().catch((error) => {
    archive.emit('error', error);
  });

  return archive;
};

module.exports = {
  FEEDBACK_ARCHIVE_MIME_TYPE,
  FEEDBACK_ARCHIVE_SCREENSHOT_FOLDER,
  FEEDBACK_PROMPTS_GENERATOR_FILE_NAME,
  buildFeedbackArchiveFileName,
  readFeedbackPromptsGenerator,
  streamFeedbackArchive
};
