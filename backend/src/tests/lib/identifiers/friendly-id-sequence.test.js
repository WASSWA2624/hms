const {
  buildCounterScopeKey,
  deriveModelPrefix,
  formatFriendlyId
} = require('@lib/identifiers/friendly-id-sequence');

describe('friendly id sequence', () => {
  it('numbers feedback on one platform-wide FBK counter', () => {
    expect(deriveModelPrefix('feedback')).toBe('FBK');
    expect(
      buildCounterScopeKey('feedback', { tenantId: 'tenant-1', facilityId: 'facility-1' }, 'FBK')
    ).toBe('global:model:feedback:prefix:FBK');
    expect(formatFriendlyId('FBK', 12)).toBe('FBK0000012');
  });

  it('keeps facility and tenant scoping for other models', () => {
    expect(
      buildCounterScopeKey('encounter', { tenantId: 'tenant-1', facilityId: 'facility-1' }, 'ENC')
    ).toBe('facility:facility-1:model:encounter:prefix:ENC');
    expect(buildCounterScopeKey('audit_log', { tenantId: 'tenant-1' }, 'AUD')).toBe(
      'tenant:tenant-1:model:audit_log:prefix:AUD'
    );
    expect(buildCounterScopeKey('module', {}, 'MOD')).toBe('global:model:module:prefix:MOD');
  });
});
