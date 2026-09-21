/**
 * Feedback screenshot helper tests
 *
 * @module tests/lib/feedback
 */

const {
  FEEDBACK_MAX_ANONYMOUS_SCREENSHOTS,
  FEEDBACK_MAX_SCREENSHOTS,
  FEEDBACK_SCREENSHOT_MAX_BYTES,
  buildFeedbackScreenshotFileName,
  buildFeedbackScreenshotKey,
  detectFeedbackImageContentType,
  maxFeedbackScreenshotsFor,
  prepareFeedbackScreenshots
} = require('@lib/feedback/feedback-screenshots');
const { sanitizeFilename } = require('@lib/storage/storage-service');

const withMagic = (magic, size = 64) =>
  Buffer.concat([Buffer.from(magic), Buffer.alloc(Math.max(4, size - magic.length), 7)]);

const PNG = [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a];
const JPEG = [0xff, 0xd8, 0xff, 0xe0];
const webpBytes = () =>
  Buffer.concat([
    Buffer.from('RIFF'),
    Buffer.alloc(4, 0),
    Buffer.from('WEBP'),
    Buffer.alloc(32, 3)
  ]);

describe('feedback screenshots', () => {
  describe('detectFeedbackImageContentType', () => {
    it.each([
      ['image/png', withMagic(PNG)],
      ['image/jpeg', withMagic(JPEG)],
      ['image/webp', webpBytes()]
    ])('reads %s from the file itself', (expected, buffer) => {
      expect(detectFeedbackImageContentType(buffer)).toBe(expected);
    });

    it.each([
      ['a script', Buffer.from('<?php echo "hi"; ?>                ')],
      ['an empty buffer', Buffer.alloc(0)],
      ['something too short to tell', Buffer.from([0x89, 0x50])],
      ['nothing at all', null]
    ])('refuses %s', (_label, buffer) => {
      expect(detectFeedbackImageContentType(buffer)).toBeNull();
    });
  });

  describe('buildFeedbackScreenshotKey', () => {
    it('builds a flat key both storage providers keep intact', () => {
      const key = buildFeedbackScreenshotKey({
        feedbackId: '3f2a1b4c-5d6e-4f70-8a9b-0c1d2e3f4a5b',
        sequence: 2,
        contentType: 'image/jpeg'
      });

      // The last eight characters of the id, dashes dropped.
      expect(key).toMatch(/^fbshot-2e3f4a5b-2-[0-9a-f]{8}\.jpg$/);
      // Both providers sanitize a key into one file name; a key with a path
      // separator would come back changed and never be found again.
      expect(sanitizeFilename(key)).toBe(key);
    });

    it('keeps two shots of one record apart', () => {
      const first = buildFeedbackScreenshotKey({
        feedbackId: 'feedback-1',
        sequence: 1,
        contentType: 'image/png'
      });
      const second = buildFeedbackScreenshotKey({
        feedbackId: 'feedback-1',
        sequence: 1,
        contentType: 'image/png'
      });

      expect(first).not.toBe(second);
    });
  });

  describe('buildFeedbackScreenshotFileName', () => {
    it.each([
      [1, 'image/jpeg', 'FBK0000011.jpg'],
      [2, 'image/png', 'FBK0000011-2.png'],
      [3, 'image/webp', 'FBK0000011-3.webp']
    ])('names shot %s as %s', (position, contentType, expected) => {
      expect(
        buildFeedbackScreenshotFileName({ referenceId: 'FBK0000011', position, contentType })
      ).toBe(expected);
    });

    it('strips anything a file name cannot carry', () => {
      expect(
        buildFeedbackScreenshotFileName({
          referenceId: '../../etc/passwd',
          position: 1,
          contentType: 'image/png'
        })
      ).toBe('etcpasswd.png');
    });
  });

  describe('maxFeedbackScreenshotsFor', () => {
    it('lets signed-in reporters send more than anonymous ones', () => {
      expect(maxFeedbackScreenshotsFor({ authenticated: true })).toBe(FEEDBACK_MAX_SCREENSHOTS);
      expect(maxFeedbackScreenshotsFor()).toBe(FEEDBACK_MAX_ANONYMOUS_SCREENSHOTS);
      expect(FEEDBACK_MAX_ANONYMOUS_SCREENSHOTS).toBeLessThan(FEEDBACK_MAX_SCREENSHOTS);
    });
  });

  describe('prepareFeedbackScreenshots', () => {
    it('pairs each file with the metadata sent for its position', () => {
      const { accepted, rejected } = prepareFeedbackScreenshots({
        files: [{ buffer: withMagic(PNG) }, { buffer: withMagic(JPEG) }],
        metadata: [
          {
            width: 1280.6,
            height: 800,
            caption: '  the queue  ',
            route_name: 'opd',
            route_path: '/opd',
            screen_title: 'Outpatients',
            captured_at: '2026-09-20T09:00:00.000Z'
          },
          { caption: '' }
        ]
      });

      expect(rejected).toEqual([]);
      expect(accepted[0]).toEqual(
        expect.objectContaining({
          content_type: 'image/png',
          width: 1281,
          height: 800,
          caption: 'the queue',
          route_name: 'opd',
          screen_title: 'Outpatients',
          captured_at: new Date('2026-09-20T09:00:00.000Z')
        })
      );
      expect(accepted[1]).toEqual(
        expect.objectContaining({ content_type: 'image/jpeg', caption: null, route_name: null })
      );
    });

    it('keeps an image whose metadata is missing or unusable', () => {
      const { accepted } = prepareFeedbackScreenshots({
        files: [{ buffer: withMagic(PNG) }],
        metadata: [{ width: -5, captured_at: 'not a date' }]
      });

      expect(accepted).toHaveLength(1);
      expect(accepted[0].width).toBeNull();
      expect(accepted[0].captured_at).toBeNull();
    });

    it.each([
      ['a file that is not an image', { buffer: Buffer.from('GIF89a and then some text') }, 'unsupported_type'],
      [
        'a file over the per-image cap',
        { buffer: withMagic(PNG, FEEDBACK_SCREENSHOT_MAX_BYTES + 1) },
        'too_large'
      ]
    ])('rejects %s', (_label, file, reason) => {
      const { accepted, rejected } = prepareFeedbackScreenshots({ files: [file] });

      expect(accepted).toEqual([]);
      expect(rejected).toEqual([{ index: 0, reason }]);
    });
  });
});
