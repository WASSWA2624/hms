/**
 * Feedback context sanitising
 *
 * @module lib/feedback
 * @description Feedback records where it was raised so the report can be
 * reproduced. Locations come from the client and can carry credentials: the
 * reset-password and verify-email screens put a token and an email address in
 * the query string, and Flutter's hash URL strategy moves that query into the
 * fragment. Every location is scrubbed before it is stored.
 */

const REDACTED_VALUE = 'redacted';
const LOCATION_PARSE_BASE = 'http://feedback.invalid';

/** Query parameter words that mark a value as a credential or personal data. */
const SENSITIVE_PARAM_WORDS = new Set([
  'token',
  'jwt',
  'code',
  'otp',
  'pin',
  'password',
  'passcode',
  'passwd',
  'pwd',
  'secret',
  'signature',
  'sig',
  'credential',
  'credentials',
  'auth',
  'authorization',
  'session',
  'sid',
  'cookie',
  'email',
  'phone',
  'mobile',
  'msisdn',
  'key',
  'apikey'
]);

/** Parameters whose value is itself a location (post-login redirects). */
const NESTED_LOCATION_PARAMS = new Set([
  'from',
  'next',
  'continue',
  'redirect',
  'redirect_to',
  'redirecturl',
  'return_to',
  'returnto'
]);

const CLIENT_CONTEXT_TEXT_FIELDS = Object.freeze({
  breakpoint: 16,
  theme_mode: 16,
  connectivity: 16,
  session_status: 24,
  orientation: 16
});

// Window widths in logical px, matching `AppBreakpoints.md` and `.xl` in the app.
const FEEDBACK_TABLET_MIN_WIDTH = 600;
const FEEDBACK_DESKTOP_MIN_WIDTH = 1200;
const FEEDBACK_DEVICE_TYPES = Object.freeze(['MOBILE', 'TABLET', 'DESKTOP']);

/**
 * Trim a value and cap its length; blank values become null.
 *
 * @param {*} value
 * @param {number} [maxLength]
 * @returns {string|null}
 */
const truncateFeedbackText = (value, maxLength) => {
  if (value === null || value === undefined) {
    return null;
  }
  const text = String(value).trim();
  if (!text) {
    return null;
  }
  return Number.isInteger(maxLength) && maxLength > 0 && text.length > maxLength
    ? text.slice(0, maxLength)
    : text;
};

const splitParamWords = (name) =>
  String(name || '')
    .replace(/([a-z0-9])([A-Z])/g, '$1 $2')
    .toLowerCase()
    .split(/[^a-z0-9]+/)
    .filter(Boolean);

/**
 * @param {string} name - Query parameter name
 * @returns {boolean} Whether the parameter value must not be stored
 */
const isSensitiveParam = (name) => {
  const words = splitParamWords(name);
  return words.some((word) => SENSITIVE_PARAM_WORDS.has(word)) ||
    SENSITIVE_PARAM_WORDS.has(words.join(''));
};

let scrubLocation;

const scrubQuery = (search, depth) => {
  const params = new URLSearchParams(search);
  const names = Array.from(new Set(params.keys()));

  names.forEach((name) => {
    if (isSensitiveParam(name)) {
      params.set(name, REDACTED_VALUE);
      return;
    }
    if (depth > 0 && NESTED_LOCATION_PARAMS.has(name.toLowerCase())) {
      const values = params.getAll(name).map((value) => scrubLocation(value, depth - 1));
      params.delete(name);
      values.forEach((value) => params.append(name, value));
    }
  });

  const serialized = params.toString();
  return serialized ? `?${serialized}` : '';
};

const scrubFragment = (hash, depth) => {
  if (!hash || hash === '#') {
    return '';
  }
  const fragment = hash.slice(1);
  const queryIndex = fragment.indexOf('?');
  if (queryIndex < 0) {
    return `#${fragment}`;
  }
  return `#${fragment.slice(0, queryIndex)}${scrubQuery(fragment.slice(queryIndex + 1), depth)}`;
};

scrubLocation = (raw, depth = 1) => {
  const text = String(raw ?? '').trim();
  if (!text) {
    return '';
  }

  const isAbsolute = /^[a-z][a-z0-9+.-]*:\/\//i.test(text);
  let url;
  try {
    url = new URL(text, LOCATION_PARSE_BASE);
  } catch (_) {
    // Unparseable input keeps only its path so a stray query cannot leak.
    return text.split(/[?#]/)[0];
  }

  const query = scrubQuery(url.search, depth);
  const fragment = scrubFragment(url.hash, depth);
  if (isAbsolute) {
    // `host` excludes user-info, so embedded credentials are dropped too.
    return `${url.protocol}//${url.host}${url.pathname}${query}${fragment}`;
  }
  return `${url.pathname}${query}${fragment}`;
};

/**
 * Scrub credentials and personal data from a route or URL, then cap its length.
 *
 * @param {string|null|undefined} value - Route location or absolute page URL
 * @param {number} maxLength - Column length
 * @returns {string|null}
 */
const sanitizeFeedbackLocation = (value, maxLength) =>
  truncateFeedbackText(scrubLocation(value), maxLength);

/**
 * Keep the display and device details worth storing as JSON.
 *
 * @param {Object} [context] - Validated client context
 * @returns {Object|null}
 */
const buildFeedbackClientContextJson = (context = {}) => {
  if (!context || typeof context !== 'object') {
    return null;
  }

  const snapshot = {};
  Object.entries(CLIENT_CONTEXT_TEXT_FIELDS).forEach(([key, maxLength]) => {
    const value = truncateFeedbackText(context[key], maxLength);
    if (value) {
      snapshot[key] = value;
    }
  });

  if (Number.isFinite(context.text_scale)) {
    snapshot.text_scale = context.text_scale;
  }
  if (Number.isInteger(context.utc_offset_minutes)) {
    snapshot.utc_offset_minutes = context.utc_offset_minutes;
  }

  // Viewport and display sizes have their own columns; keep the pixel ratio.
  if (Number.isFinite(context.viewport?.device_pixel_ratio)) {
    snapshot.device_pixel_ratio = context.viewport.device_pixel_ratio;
  }

  return Object.keys(snapshot).length > 0 ? snapshot : null;
};

/**
 * Screen size class of the window feedback came from.
 *
 * Uses the client's reported class when valid, otherwise derives it from the
 * viewport width so API clients that send only a viewport are still classified.
 *
 * @param {Object} [context] - Validated client context
 * @returns {'MOBILE'|'TABLET'|'DESKTOP'|null}
 */
const resolveFeedbackDeviceType = (context = {}) => {
  const reported = String(context?.device_type || '').trim().toUpperCase();
  if (FEEDBACK_DEVICE_TYPES.includes(reported)) {
    return reported;
  }

  const width = context?.viewport?.width;
  if (!Number.isFinite(width) || width <= 0) {
    return null;
  }
  if (width < FEEDBACK_TABLET_MIN_WIDTH) {
    return 'MOBILE';
  }
  return width < FEEDBACK_DESKTOP_MIN_WIDTH ? 'TABLET' : 'DESKTOP';
};

/**
 * @param {*} value - Logical pixel size
 * @returns {number|null} Whole pixels, or null when absent
 */
const toFeedbackPixelCount = (value) =>
  Number.isFinite(value) && value >= 0 ? Math.round(value) : null;

module.exports = {
  REDACTED_VALUE,
  buildFeedbackClientContextJson,
  isSensitiveParam,
  resolveFeedbackDeviceType,
  sanitizeFeedbackLocation,
  toFeedbackPixelCount,
  truncateFeedbackText
};
