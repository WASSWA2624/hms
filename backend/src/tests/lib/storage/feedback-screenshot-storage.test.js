/**
 * Feedback screenshot storage tests
 *
 * @module tests/lib/storage
 * Per testing.mdc: the storage provider is mocked; no bytes leave the test.
 */

jest.mock('@lib/storage/factory', () => ({
  createStorageService: jest.fn()
}));

const { createStorageService } = require('@lib/storage/factory');
const {
  deleteFeedbackScreenshotObjects,
  readFeedbackScreenshot,
  storeFeedbackScreenshots
} = require('@lib/storage/feedback-screenshot-storage');

const buildStorage = (overrides = {}) => ({
  upload: jest.fn(async (_buffer, key) => ({ path: key })),
  download: jest.fn(async () => Buffer.from('image-bytes')),
  delete: jest.fn(async () => true),
  ...overrides
});

const screenshot = (overrides = {}) => ({
  buffer: Buffer.from([0x89, 0x50, 0x4e, 0x47]),
  content_type: 'image/png',
  byte_size: 4,
  width: 800,
  height: 600,
  caption: null,
  route_path: '/opd',
  route_name: 'opd',
  screen_title: 'Outpatients',
  captured_at: null,
  ...overrides
});

describe('feedback screenshot storage', () => {
  beforeEach(() => {
    jest.clearAllMocks();
  });

  describe('storeFeedbackScreenshots', () => {
    it('encrypts every image and numbers it in capture order', async () => {
      const storage = buildStorage();

      const result = await storeFeedbackScreenshots({
        feedbackId: 'feedback-1',
        screenshots: [screenshot(), screenshot({ content_type: 'image/jpeg' })],
        storage
      });

      expect(result.failed).toBe(0);
      expect(result.stored.map((image) => image.sequence)).toEqual([1, 2]);
      expect(storage.upload).toHaveBeenCalledTimes(2);
      const [, key, options] = storage.upload.mock.calls[0];
      expect(key).toMatch(/^fbshot-/);
      // A screenshot can show patient data: it never lands unencrypted.
      expect(options).toEqual(
        expect.objectContaining({ encrypt: true, mimeType: 'image/png' })
      );
      expect(result.stored[0]).toEqual(
        expect.objectContaining({ storage_key: key, route_name: 'opd', byte_size: 4 })
      );
    });

    it('keeps the images that did land when one is refused', async () => {
      const storage = buildStorage({
        upload: jest
          .fn()
          .mockRejectedValueOnce(new Error('bucket unreachable'))
          .mockImplementation(async (_buffer, key) => ({ path: key }))
      });

      const result = await storeFeedbackScreenshots({
        feedbackId: 'feedback-1',
        screenshots: [screenshot(), screenshot()],
        storage
      });

      expect(result.failed).toBe(1);
      expect(result.stored).toHaveLength(1);
      expect(result.stored[0].sequence).toBe(2);
    });

    it('asks the provider for nothing when there are no images', async () => {
      const result = await storeFeedbackScreenshots({ feedbackId: 'feedback-1' });

      expect(result).toEqual({ stored: [], failed: 0 });
      expect(createStorageService).not.toHaveBeenCalled();
    });
  });

  describe('readFeedbackScreenshot', () => {
    it('returns the decrypted bytes', async () => {
      const storage = buildStorage();

      await expect(readFeedbackScreenshot('fbshot-a.png', storage)).resolves.toEqual(
        Buffer.from('image-bytes')
      );
      expect(storage.download).toHaveBeenCalledWith('fbshot-a.png');
    });

    it('treats an unreadable image as absent rather than throwing', async () => {
      const storage = buildStorage({
        download: jest.fn().mockRejectedValue(new Error('File not found'))
      });

      await expect(readFeedbackScreenshot('gone.png', storage)).resolves.toBeNull();
      await expect(readFeedbackScreenshot('', storage)).resolves.toBeNull();
    });
  });

  describe('deleteFeedbackScreenshotObjects', () => {
    it('removes every key once, blanks and repeats dropped', async () => {
      const storage = buildStorage();

      const result = await deleteFeedbackScreenshotObjects(
        ['fbshot-a.png', 'fbshot-a.png', '  ', 'fbshot-b.png'],
        storage
      );

      expect(result).toEqual({ deleted: 2, failed: [] });
      expect(storage.delete.mock.calls.map(([key]) => key)).toEqual([
        'fbshot-a.png',
        'fbshot-b.png'
      ]);
    });

    it('reports the keys the provider would not delete', async () => {
      const storage = buildStorage({
        delete: jest
          .fn()
          .mockRejectedValueOnce(new Error('permission denied'))
          .mockResolvedValue(true)
      });

      const result = await deleteFeedbackScreenshotObjects(
        ['fbshot-a.png', 'fbshot-b.png'],
        storage
      );

      // The records are already gone; the caller logs what outlived them.
      expect(result).toEqual({ deleted: 1, failed: ['fbshot-a.png'] });
    });

    it('counts an image that is already gone as deleted, so a retry is safe', async () => {
      const storage = buildStorage({ delete: jest.fn(async () => false) });

      await expect(
        deleteFeedbackScreenshotObjects(['fbshot-a.png'], storage)
      ).resolves.toEqual({ deleted: 1, failed: [] });
    });
  });
});
