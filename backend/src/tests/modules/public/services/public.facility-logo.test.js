const mockStorage = {
  exists: jest.fn(),
  download: jest.fn()};

jest.mock('@lib/storage', () => ({
  createStorageService: jest.fn(() => mockStorage)}));

const publicService = require('@services/public/public.service');
const { facilityLogoKeyParamsSchema } = require('@validations/public/public.schema');

describe('public facility logo delivery', () => {
  beforeEach(() => {
    mockStorage.exists.mockReset();
    mockStorage.download.mockReset();
  });

  describe('key validation', () => {
    // The route is unauthenticated, so the key shape is the only thing standing
    // between it and the rest of the uploads directory.
    it.each([
      'logo-585d8466.png',
      'logo-585d8466.PNG',
      'logo-abc.jpg',
      'logo-abc.jpeg',
      'logo-abc.webp'])('accepts the facility logo key %s', (key) => {
      expect(facilityLogoKeyParamsSchema.safeParse({ key }).success).toBe(true);
    });

    it.each([
      'reports_9322e26a_2026_09_appointment-throughput.pdf',
      '../.env',
      '../../package.json',
      'nested/logo-585d8466.png',
      'logo-585d8466.png/../../.env',
      'logo-585d8466.pdf',
      'logo-585d8466.svg',
      'logo-.png',
      'notalogo-585d8466.png',
      ''])('rejects %s', (key) => {
      expect(facilityLogoKeyParamsSchema.safeParse({ key }).success).toBe(false);
    });
  });

  describe('getFacilityLogo', () => {
    it('returns the stored bytes with a matching mime type', async () => {
      const buffer = Buffer.from([1, 2, 3]);
      mockStorage.exists.mockResolvedValue(true);
      mockStorage.download.mockResolvedValue(buffer);

      const result = await publicService.getFacilityLogo('logo-585d8466.png');

      expect(result).toEqual({ buffer, mime_type: 'image/png' });
      expect(mockStorage.download).toHaveBeenCalledWith('logo-585d8466.png');
    });

    it('maps jpg and webp extensions to their mime types', async () => {
      mockStorage.exists.mockResolvedValue(true);
      mockStorage.download.mockResolvedValue(Buffer.from([0]));

      await expect(publicService.getFacilityLogo('logo-abc.jpg')).resolves.toMatchObject({
        mime_type: 'image/jpeg'});
      await expect(publicService.getFacilityLogo('logo-abc.webp')).resolves.toMatchObject({
        mime_type: 'image/webp'});
    });

    it('404s when the logo is not in storage', async () => {
      mockStorage.exists.mockResolvedValue(false);

      await expect(publicService.getFacilityLogo('logo-missing.png')).rejects.toMatchObject({
        statusCode: 404});
      expect(mockStorage.download).not.toHaveBeenCalled();
    });
  });
});
