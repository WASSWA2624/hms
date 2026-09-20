/**
 * Follow-up schema tests
 *
 * @module tests/modules/follow-up/schemas
 * @description Tests for follow-up validation schemas
 * Per testing.mdc: Comprehensive validation schema tests required
 */

const {
  createFollowUpSchema,
  updateFollowUpSchema,
  followUpIdParamsSchema,
  listFollowUpsQuerySchema
} = require('@validations/follow-up/follow-up.schema');

describe('Follow-up Schemas', () => {
  describe('createFollowUpSchema', () => {
    const validData = {
      encounter_id: '550e8400-e29b-41d4-a716-446655440000',
      scheduled_at: '2026-01-25T10:00:00.000Z',
      notes: 'Follow-up appointment for blood pressure check'
    };

    it('should validate correct follow-up data', () => {
      const result = createFollowUpSchema.safeParse(validData);
      expect(result.success).toBe(true);
    });

    it('should require encounter_id', () => {
      const data = { ...validData };
      delete data.encounter_id;
      const result = createFollowUpSchema.safeParse(data);
      expect(result.success).toBe(false);
    });

    it('should require scheduled_at', () => {
      const data = { ...validData };
      delete data.scheduled_at;
      const result = createFollowUpSchema.safeParse(data);
      expect(result.success).toBe(false);
    });

    it('should allow optional notes', () => {
      const data = { ...validData };
      delete data.notes;
      const result = createFollowUpSchema.safeParse(data);
      expect(result.success).toBe(true);
    });

    it('should allow null notes', () => {
      const data = { ...validData, notes: null };
      const result = createFollowUpSchema.safeParse(data);
      expect(result.success).toBe(true);
    });

    it('should reject invalid encounter identifiers', () => {
      const data = { ...validData, encounter_id: 'not-a-uuid' };
      const result = createFollowUpSchema.safeParse(data);
      expect(result.success).toBe(false);
    });

    it('should accept human-friendly encounter identifiers', () => {
      const data = { ...validData, encounter_id: 'ENC000001' };
      const result = createFollowUpSchema.safeParse(data);
      expect(result.success).toBe(true);
      expect(result.data.encounter_id).toBe('ENC000001');
    });

    it('should reject invalid date format', () => {
      const data = { ...validData, scheduled_at: 'not-a-date' };
      const result = createFollowUpSchema.safeParse(data);
      expect(result.success).toBe(false);
    });

    it('should enforce notes max length', () => {
      const data = { ...validData, notes: 'x'.repeat(10001) };
      const result = createFollowUpSchema.safeParse(data);
      expect(result.success).toBe(false);
    });

    it('should accept valid ISO date formats', () => {
      const dates = [
        '2026-01-25T10:00:00.000Z',
        '2026-01-25T10:00:00Z',
        '2026-01-25T10:00:00.123Z'
      ];
      dates.forEach(scheduled_at => {
        const data = { ...validData, scheduled_at };
        const result = createFollowUpSchema.safeParse(data);
        expect(result.success).toBe(true);
      });
    });
  });

  describe('updateFollowUpSchema', () => {
    it('should validate correct update data', () => {
      const data = {
        scheduled_at: '2026-01-26T14:00:00.000Z',
        notes: 'Rescheduled appointment'
      };
      const result = updateFollowUpSchema.safeParse(data);
      expect(result.success).toBe(true);
    });

    it('should allow partial updates', () => {
      const data = { notes: 'Updated notes' };
      const result = updateFollowUpSchema.safeParse(data);
      expect(result.success).toBe(true);
    });

    it('should allow empty object', () => {
      const result = updateFollowUpSchema.safeParse({});
      expect(result.success).toBe(true);
    });

    it('should reject invalid date format', () => {
      const data = { scheduled_at: 'invalid-date' };
      const result = updateFollowUpSchema.safeParse(data);
      expect(result.success).toBe(false);
    });
  });

  describe('followUpIdParamsSchema', () => {
    it('should validate valid UUID', () => {
      const data = { id: '550e8400-e29b-41d4-a716-446655440000' };
      const result = followUpIdParamsSchema.safeParse(data);
      expect(result.success).toBe(true);
    });

    it('should reject invalid UUID', () => {
      const data = { id: 'not-a-uuid' };
      const result = followUpIdParamsSchema.safeParse(data);
      expect(result.success).toBe(false);
    });

    it('should require id', () => {
      const result = followUpIdParamsSchema.safeParse({});
      expect(result.success).toBe(false);
    });
  });

  describe('listFollowUpsQuerySchema', () => {
    it('should validate correct query parameters', () => {
      const data = {
        encounter_id: '550e8400-e29b-41d4-a716-446655440000',
        page: 1,
        limit: 20,
        sort_by: 'scheduled_at',
        order: 'asc'
      };
      const result = listFollowUpsQuerySchema.safeParse(data);
      expect(result.success).toBe(true);
    });

    it('should allow optional filters', () => {
      const data = { page: 1, limit: 20 };
      const result = listFollowUpsQuerySchema.safeParse(data);
      expect(result.success).toBe(true);
    });

    it('should accept tenant and facility scope identifiers', () => {
      const result = listFollowUpsQuerySchema.safeParse({
        tenant_id: 'TEN0000003',
        facility_id: 'FAC0000001',
        page: 1,
        limit: 20
      });
      expect(result.success).toBe(true);
      expect(result.data.tenant_id).toBe('TEN0000003');
      expect(result.data.facility_id).toBe('FAC0000001');
    });

    it('should reject invalid encounter_id', () => {
      const data = { encounter_id: 'not-a-uuid' };
      const result = listFollowUpsQuerySchema.safeParse(data);
      expect(result.success).toBe(false);
    });
  });
});
