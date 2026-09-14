/**
 * User schema tests
 *
 * @module tests/modules/user/schemas
 * @description Tests for user validation schemas
 * Per testing.mdc: Comprehensive validation schema tests required
 */

const {
  USER_FIELD_LIMITS,
  createUserSchema,
  updateUserSchema,
  setUserPasswordSchema,
  userIdParamsSchema,
  listUsersQuerySchema
} = require('@validations/user/user.schema');

describe('User Schemas', () => {
  describe('createUserSchema', () => {
    const validData = {
      tenant_id: '550e8400-e29b-41d4-a716-446655440000',
      facility_id: '550e8400-e29b-41d4-a716-446655440001',
      first_name: 'Jane',
      last_name: 'Doe',
      position_title: 'Charge Nurse',
      email: 'test@example.com',
      phone: '+256700000000',
      password: 'StrongPass123!',
      status: 'ACTIVE'
    };

    it('should validate correct user data', () => {
      const result = createUserSchema.safeParse(validData);
      expect(result.success).toBe(true);
    });

    it('should require tenant_id', () => {
      const data = { ...validData };
      delete data.tenant_id;
      const result = createUserSchema.safeParse(data);
      expect(result.success).toBe(false);
    });

    it('should require email', () => {
      const data = { ...validData };
      delete data.email;
      const result = createUserSchema.safeParse(data);
      expect(result.success).toBe(false);
    });

    it('should require position_title', () => {
      const data = { ...validData };
      delete data.position_title;
      const result = createUserSchema.safeParse(data);
      expect(result.success).toBe(false);
    });

    it('should require first_name', () => {
      const data = { ...validData };
      delete data.first_name;
      const result = createUserSchema.safeParse(data);
      expect(result.success).toBe(false);
    });

    it('should allow optional last_name', () => {
      const data = { ...validData };
      delete data.last_name;
      const result = createUserSchema.safeParse(data);
      expect(result.success).toBe(true);
    });

    it('should validate email format', () => {
      const data = { ...validData, email: 'invalid-email' };
      const result = createUserSchema.safeParse(data);
      expect(result.success).toBe(false);
    });

    it('should require password', () => {
      const data = { ...validData };
      delete data.password;
      const result = createUserSchema.safeParse(data);
      expect(result.success).toBe(false);
    });

    it('should accept password when password_hash is omitted', () => {
      const data = { ...validData };
      delete data.password_hash;
      data.password = 'StrongPass123!';
      const result = createUserSchema.safeParse(data);
      expect(result.success).toBe(true);
    });

    it('should require status', () => {
      const data = { ...validData };
      delete data.status;
      const result = createUserSchema.safeParse(data);
      expect(result.success).toBe(false);
    });

    it('should validate status enum values', () => {
      const data = { ...validData, status: 'INVALID' };
      const result = createUserSchema.safeParse(data);
      expect(result.success).toBe(false);
    });

    it('should accept valid status values', () => {
      const statuses = ['ACTIVE', 'INACTIVE', 'SUSPENDED', 'PENDING'];
      statuses.forEach(status => {
        const data = { ...validData, status };
        const result = createUserSchema.safeParse(data);
        expect(result.success).toBe(true);
      });
    });

    it('should allow optional facility_id', () => {
      const data = { ...validData };
      delete data.facility_id;
      const result = createUserSchema.safeParse(data);
      expect(result.success).toBe(true);
    });

    it('should allow optional phone', () => {
      const data = { ...validData };
      delete data.phone;
      const result = createUserSchema.safeParse(data);
      expect(result.success).toBe(true);
    });

    it('should reject invalid identifier format for tenant_id', () => {
      const data = { ...validData, tenant_id: 'invalid-uuid' };
      const result = createUserSchema.safeParse(data);
      expect(result.success).toBe(false);
    });

    it('should reject invalid identifier format for facility_id', () => {
      const data = { ...validData, facility_id: 'invalid-uuid' };
      const result = createUserSchema.safeParse(data);
      expect(result.success).toBe(false);
    });

    it('should accept friendly identifier for tenant_id', () => {
      const data = { ...validData, tenant_id: 'TNT-0001' };
      const result = createUserSchema.safeParse(data);
      expect(result.success).toBe(true);
    });

    it('should accept friendly identifier for facility_id', () => {
      const data = { ...validData, facility_id: 'FAC-0001' };
      const result = createUserSchema.safeParse(data);
      expect(result.success).toBe(true);
    });

    it('should trim whitespace from email', () => {
      const data = { ...validData, email: '  test@example.com  ' };
      const result = createUserSchema.safeParse(data);
      expect(result.success).toBe(true);
      if (result.success) {
        expect(result.data.email).toBe('test@example.com');
      }
    });

    it('should trim whitespace from phone', () => {
      const data = { ...validData, phone: '  +256700000000  ' };
      const result = createUserSchema.safeParse(data);
      expect(result.success).toBe(true);
      if (result.success) {
        expect(result.data.phone).toBe('+256700000000');
      }
    });

    it('should trim whitespace from position_title', () => {
      const data = { ...validData, position_title: '  Charge Nurse  ' };
      const result = createUserSchema.safeParse(data);
      expect(result.success).toBe(true);
      if (result.success) {
        expect(result.data.position_title).toBe('Charge Nurse');
      }
    });

    it('should enforce email max length', () => {
      const data = { ...validData, email: 'a'.repeat(250) + '@example.com' };
      const result = createUserSchema.safeParse(data);
      expect(result.success).toBe(false);
    });

    it('should enforce phone max length', () => {
      const data = { ...validData, phone: '1'.repeat(41) };
      const result = createUserSchema.safeParse(data);
      expect(result.success).toBe(false);
    });

    it('should enforce position_title max length', () => {
      const data = { ...validData, position_title: 'a'.repeat(121) };
      const result = createUserSchema.safeParse(data);
      expect(result.success).toBe(false);
    });

    it('should drop a client-supplied password_hash so the policy cannot be bypassed', () => {
      const result = createUserSchema.safeParse({
        ...validData,
        password_hash: '$2b$10$abcdefghijklmnopqrstuvwxyz'
      });
      expect(result.success).toBe(true);
      expect(result.data.password_hash).toBeUndefined();
    });

    it.each([
      ['StrongPass!', 'errors.validation.password.number'],
      ['strongpass123!', 'errors.validation.password.uppercase'],
      ['STRONGPASS123!', 'errors.validation.password.lowercase'],
      ['StrongPass123', 'errors.validation.password.special'],
      ['  Ab1!  ', 'errors.validation.password.min_length']
    ])('should enforce the password policy for %p', (password, messageKey) => {
      const result = createUserSchema.safeParse({ ...validData, password });
      expect(result.success).toBe(false);
      expect(result.error.issues).toEqual(
        expect.arrayContaining([
          expect.objectContaining({ path: ['password'], message: messageKey })
        ])
      );
    });

    it('should enforce password min length', () => {
      const data = { ...validData, password: 'short' };
      const result = createUserSchema.safeParse(data);
      expect(result.success).toBe(false);
    });

    it('should accept nullable facility_id', () => {
      const data = { ...validData, facility_id: null };
      const result = createUserSchema.safeParse(data);
      expect(result.success).toBe(true);
    });

    it('should accept nullable phone', () => {
      const data = { ...validData, phone: null };
      const result = createUserSchema.safeParse(data);
      expect(result.success).toBe(true);
    });

    it('should accept multiple permission_ids', () => {
      const data = {
        ...validData,
        permission_ids: [
          '550e8400-e29b-41d4-a716-446655440010',
          '550e8400-e29b-41d4-a716-446655440011']};
      const result = createUserSchema.safeParse(data);
      expect(result.success).toBe(true);
    });

    it('should reject invalid permission_ids', () => {
      const data = {
        ...validData,
        permission_ids: ['not-a-uuid']};
      const result = createUserSchema.safeParse(data);
      expect(result.success).toBe(false);
    });

    it('should accept role_ids and a staff_profile for atomic creation', () => {
      const result = createUserSchema.safeParse({
        ...validData,
        role_ids: ['550e8400-e29b-41d4-a716-446655440020'],
        staff_profile: { position: 'Charge Nurse' }
      });
      expect(result.success).toBe(true);
    });

    it('should reject more role_ids than the limit', () => {
      const result = createUserSchema.safeParse({
        ...validData,
        role_ids: Array.from(
          { length: USER_FIELD_LIMITS.roleIds + 1 },
          (_, index) => `550e8400-e29b-41d4-a716-${String(446655440100 + index)}`
        )
      });
      expect(result.success).toBe(false);
      expect(result.error.issues[0]).toEqual(
        expect.objectContaining({ path: ['role_ids'], message: 'errors.validation.max_items' })
      );
    });

    it('should report an invalid phone number against the phone field', () => {
      const result = createUserSchema.safeParse({ ...validData, phone: '12345' });
      expect(result.success).toBe(false);
      expect(result.error.issues[0]).toEqual(
        expect.objectContaining({ path: ['phone'], message: 'errors.user.phone_invalid' })
      );
    });

    it('should accept a blank last_name and phone', () => {
      const result = createUserSchema.safeParse({ ...validData, last_name: '', phone: '' });
      expect(result.success).toBe(true);
    });

    it.each([
      ['a@b.c', false],
      ['user@localhost', false],
      ['first.last@example.co.ug', true],
      ["o'neil+ops@example.com", true]
    ])('should apply the shared email pattern to %p', (email, valid) => {
      const result = createUserSchema.safeParse({ ...validData, email });
      expect(result.success).toBe(valid);
    });

    it('should report a name that is too long with the max length key', () => {
      const result = createUserSchema.safeParse({
        ...validData,
        first_name: 'a'.repeat(USER_FIELD_LIMITS.name + 1)
      });
      expect(result.success).toBe(false);
      expect(result.error.issues[0]).toEqual(
        expect.objectContaining({ path: ['first_name'], message: 'errors.validation.max_length' })
      );
    });
  });

  describe('updateUserSchema', () => {
    it('should allow all fields to be optional', () => {
      const result = updateUserSchema.safeParse({});
      expect(result.success).toBe(true);
    });

    it('should validate email format when provided', () => {
      const result = updateUserSchema.safeParse({ email: 'invalid-email' });
      expect(result.success).toBe(false);
    });

    it('should validate status enum when provided', () => {
      const result = updateUserSchema.safeParse({ status: 'INVALID' });
      expect(result.success).toBe(false);
    });

    it('should accept valid status values', () => {
      const statuses = ['ACTIVE', 'INACTIVE', 'SUSPENDED', 'PENDING'];
      statuses.forEach(status => {
        const result = updateUserSchema.safeParse({ status });
        expect(result.success).toBe(true);
      });
    });

    it('should accept valid facility_id UUID', () => {
      const result = updateUserSchema.safeParse({
        facility_id: '550e8400-e29b-41d4-a716-446655440000'
      });
      expect(result.success).toBe(true);
    });

    it('should reject invalid facility_id UUID', () => {
      const result = updateUserSchema.safeParse({ facility_id: 'invalid-uuid' });
      expect(result.success).toBe(false);
    });

    it('should accept partial updates', () => {
      const result = updateUserSchema.safeParse({
        email: 'newemail@example.com',
        status: 'INACTIVE'
      });
      expect(result.success).toBe(true);
    });

    it('should trim whitespace from fields', () => {
      const result = updateUserSchema.safeParse({
        position_title: '  Head Nurse  ',
        email: '  test@example.com  ',
        phone: '  +256700000000  '
      });
      expect(result.success).toBe(true);
      if (result.success) {
        expect(result.data.position_title).toBe('Head Nurse');
        expect(result.data.email).toBe('test@example.com');
        expect(result.data.phone).toBe('+256700000000');
      }
    });

    it('should accept nullable fields', () => {
      const result = updateUserSchema.safeParse({
        facility_id: null,
        phone: null
      });
      expect(result.success).toBe(true);
    });

    it('should accept permission_ids on update', () => {
      const result = updateUserSchema.safeParse({
        permission_ids: [
          '550e8400-e29b-41d4-a716-446655440010',
          '550e8400-e29b-41d4-a716-446655440011']});
      expect(result.success).toBe(true);
    });

    it('should reject invalid permission_ids on update', () => {
      const result = updateUserSchema.safeParse({
        permission_ids: ['invalid']});
      expect(result.success).toBe(false);
    });

    it.each(['password', 'password_hash'])(
      'should reject %p so credentials never change through a profile edit',
      (field) => {
        const result = updateUserSchema.safeParse({ [field]: 'StrongPass123!' });
        expect(result.success).toBe(false);
        expect(result.error.issues[0]).toEqual(
          expect.objectContaining({
            path: [field],
            message: 'errors.user.password_change_requires_reset'
          })
        );
      }
    );
  });

  describe('setUserPasswordSchema', () => {
    it('should accept a password that meets the policy', () => {
      const result = setUserPasswordSchema.safeParse({ password: 'NewStrong123!' });
      expect(result.success).toBe(true);
    });

    it('should require a password', () => {
      expect(setUserPasswordSchema.safeParse({}).success).toBe(false);
    });

    it.each([
      ['NewStrong!', 'errors.validation.password.number'],
      ['newstrong123!', 'errors.validation.password.uppercase'],
      ['NewStrong123', 'errors.validation.password.special']
    ])('should enforce the password policy for %p', (password, messageKey) => {
      const result = setUserPasswordSchema.safeParse({ password });
      expect(result.success).toBe(false);
      expect(result.error.issues).toEqual(
        expect.arrayContaining([
          expect.objectContaining({ path: ['password'], message: messageKey })
        ])
      );
    });
  });

  describe('userIdParamsSchema', () => {
    it('should validate correct UUID', () => {
      const result = userIdParamsSchema.safeParse({
        id: '550e8400-e29b-41d4-a716-446655440000'
      });
      expect(result.success).toBe(true);
    });

    it('should accept friendly identifier', () => {
      const result = userIdParamsSchema.safeParse({ id: 'USR-0001' });
      expect(result.success).toBe(true);
    });

    it('should reject invalid identifier', () => {
      const result = userIdParamsSchema.safeParse({ id: 'invalid-uuid' });
      expect(result.success).toBe(false);
    });

    it('should require id field', () => {
      const result = userIdParamsSchema.safeParse({});
      expect(result.success).toBe(false);
    });
  });

  describe('listUsersQuerySchema', () => {
    it('should validate with no query params', () => {
      const result = listUsersQuerySchema.safeParse({});
      expect(result.success).toBe(true);
    });

    it('should accept valid tenant_id', () => {
      const result = listUsersQuerySchema.safeParse({
        tenant_id: '550e8400-e29b-41d4-a716-446655440000'
      });
      expect(result.success).toBe(true);
    });

    it('should accept valid facility_id', () => {
      const result = listUsersQuerySchema.safeParse({
        facility_id: '550e8400-e29b-41d4-a716-446655440000'
      });
      expect(result.success).toBe(true);
    });

    it('should accept email filter', () => {
      const result = listUsersQuerySchema.safeParse({
        email: 'test@example.com'
      });
      expect(result.success).toBe(true);
    });

    it('should accept position_title filter', () => {
      const result = listUsersQuerySchema.safeParse({
        position_title: 'Charge Nurse'
      });
      expect(result.success).toBe(true);
    });

    it('should accept status filter', () => {
      const result = listUsersQuerySchema.safeParse({ status: 'ACTIVE' });
      expect(result.success).toBe(true);
    });

    it('should reject invalid status filter', () => {
      const result = listUsersQuerySchema.safeParse({ status: 'INVALID' });
      expect(result.success).toBe(false);
    });

    it('should accept search parameter', () => {
      const result = listUsersQuerySchema.safeParse({ search: 'john' });
      expect(result.success).toBe(true);
    });

    it('should accept pagination params', () => {
      const result = listUsersQuerySchema.safeParse({
        page: '1',
        limit: '20',
        sort_by: 'created_at',
        order: 'desc'
      });
      expect(result.success).toBe(true);
    });

    it('should accept all filters combined', () => {
      const result = listUsersQuerySchema.safeParse({
        tenant_id: '550e8400-e29b-41d4-a716-446655440000',
        facility_id: '550e8400-e29b-41d4-a716-446655440001',
        email: 'test@example.com',
        status: 'ACTIVE',
        search: 'john',
        page: '1',
        limit: '20'
      });
      expect(result.success).toBe(true);
    });

    it('should reject invalid UUID for tenant_id', () => {
      const result = listUsersQuerySchema.safeParse({ tenant_id: 'invalid' });
      expect(result.success).toBe(false);
    });

    it('should reject invalid UUID for facility_id', () => {
      const result = listUsersQuerySchema.safeParse({ facility_id: 'invalid' });
      expect(result.success).toBe(false);
    });

    it('should trim whitespace from search', () => {
      const result = listUsersQuerySchema.safeParse({ search: '  john  ' });
      expect(result.success).toBe(true);
      if (result.success) {
        expect(result.data.search).toBe('john');
      }
    });
  });
});
