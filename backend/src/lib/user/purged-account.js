/**
 * Permanently deleted accounts that records still point at.
 *
 * When audit, clinical, or operational rows reference a user, a permanent delete
 * keeps the user row as the author those rows need and erases everything
 * personal on it. Its email moves to a reserved `.invalid` domain (RFC 2606),
 * which can never be a real mailbox and is what marks the row as purged.
 *
 * @module lib/user/purged-account
 */

const PURGED_EMAIL_SUFFIX = '@purged.invalid';

/** Stands in for the erased first name on a profile that has to stay. */
const PURGED_ACCOUNT_NAME = 'Deleted user';

/** Replacement email for a purged account; unique per user, so per tenant too. */
const purgedEmailFor = (userId) => `deleted-user-${userId}${PURGED_EMAIL_SUFFIX}`;

const isPurgedAccount = (user) =>
  String(user?.email || '').trim().toLowerCase().endsWith(PURGED_EMAIL_SUFFIX);

/** Where clause matching accounts that have not been purged. */
const notPurgedWhere = () => ({ NOT: { email: { endsWith: PURGED_EMAIL_SUFFIX } } });

module.exports = {
  PURGED_ACCOUNT_NAME,
  purgedEmailFor,
  isPurgedAccount,
  notPurgedWhere
};
