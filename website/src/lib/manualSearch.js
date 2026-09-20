/**
 * User manual search
 *
 * Turns the manual into a searchable index and ranks sections against a query.
 * Pure functions with no React and no path aliases, so the search behaves the
 * same wherever it runs and can be exercised on its own.
 *
 * What "intelligently" means here, in the order a query is stretched:
 *
 *   1. Exact and prefix matches on the words a section actually contains, so
 *      typing "disch" already finds "Discharge a patient".
 *   2. Synonyms, because readers search with their own words rather than the
 *      manual's: "login" finds "Sign in", "medicine" finds the pharmacy, "bill"
 *      finds invoicing. Kept as one table below so the vocabulary is visible
 *      and editable rather than buried in scoring code.
 *   3. Typo tolerance on longer words, within one edit for 4-7 letters and two
 *      for 8 or more, so "pharmcy" and "regsitration" still land.
 *
 * Matches are weighted by where they land - a hit in a section title means far
 * more than one in the middle of a paragraph - and a section that contains the
 * query as a phrase is pushed above one that merely contains the same words
 * scattered about.
 *
 * @file src/lib/manualSearch.js
 */

/** Field weights. A title hit outranks a body hit by design. */
const FIELD_WEIGHTS = {
  title: 12,
  chapter: 5,
  audience: 4,
  keywords: 6,
  body: 1,
};

/** Multipliers applied to a field's weight by how well the word matched. */
const MATCH_QUALITY = {
  exact: 1,
  prefix: 0.75,
  synonym: 0.6,
  fuzzy: 0.45,
};

/** Every query word present beats one strong hit on a single word. */
const COVERAGE_WEIGHT = 40;

/**
 * Query words landing in the section title.
 *
 * Without this a long section that happens to contain the query as a phrase
 * outranks the section actually named after it - "lab test" would find a ward
 * page that mentions lab tests before "Create a lab order".
 */
const TITLE_COVERAGE_WEIGHT = 34;

/** The whole query appearing as written, in a title or in the prose. */
const PHRASE_BONUS = { title: 60, body: 18 };

/** Words too common in this manual to say anything about relevance. */
const STOP_WORDS = new Set([
  'a', 'an', 'and', 'are', 'as', 'at', 'be', 'by', 'can', 'do', 'for', 'from',
  'how', 'i', 'if', 'in', 'is', 'it', 'its', 'of', 'on', 'or', 'that', 'the',
  'their', 'then', 'this', 'to', 'up', 'use', 'want', 'was', 'what', 'when',
  'where', 'which', 'who', 'will', 'with', 'you', 'your',
]);

/**
 * Reader vocabulary mapped onto the manual's vocabulary.
 *
 * Each entry lists words that should find each other. Expanded both ways, so
 * "invoice" finds "bill" and "bill" finds "invoice" without listing twice.
 */
const SYNONYM_GROUPS = [
  ['login', 'log', 'signin', 'sign', 'signing'],
  ['logout', 'signout', 'exit'],
  ['password', 'passcode', 'credentials'],
  ['register', 'registration', 'signup', 'onboard', 'enrol', 'enroll'],
  ['staff', 'employee', 'user', 'account', 'team', 'personnel'],
  ['role', 'permission', 'permissions', 'access', 'rights', 'privileges'],
  ['patient', 'client', 'visitor'],
  ['appointment', 'booking', 'schedule', 'scheduling'],
  ['bill', 'billing', 'invoice', 'charge', 'charges'],
  ['payment', 'pay', 'paid', 'receipt', 'cash', 'money'],
  ['medicine', 'medication', 'drug', 'drugs', 'pharmacy', 'prescription', 'dispense'],
  ['stock', 'inventory', 'supply', 'supplies'],
  ['lab', 'laboratory', 'specimen', 'sample'],
  ['radiology', 'imaging', 'scan', 'xray', 'ultrasound'],
  ['admission', 'admit', 'inpatient', 'ipd', 'ward'],
  ['discharge', 'release', 'checkout'],
  ['outpatient', 'opd', 'consultation', 'clinic'],
  ['triage', 'vitals', 'observations'],
  ['report', 'reports', 'reporting', 'analytics', 'statistics'],
  ['accounts', 'accounting', 'finance', 'financial', 'ledger'],
  ['setup', 'configure', 'configuration', 'settings', 'set'],
  ['facility', 'hospital', 'clinic', 'branch', 'site'],
  ['delete', 'remove', 'cancel'],
  ['edit', 'change', 'update', 'modify'],
  ['add', 'create', 'new'],
  ['find', 'search', 'lookup'],
  ['print', 'download', 'export', 'pdf'],
  ['insurance', 'claim', 'claims', 'scheme', 'cover', 'preauth', 'preauthorisation', 'preauthorization', 'authorization'],
  ['emergency', 'casualty', 'urgent'],
  ['theatre', 'theater', 'surgery', 'operation', 'ot'],
  ['hr', 'human', 'workforce'],
  ['payroll', 'salary', 'salaries', 'wages', 'compensation', 'payslip'],
  ['theme', 'dark', 'light', 'contrast', 'accessibility', 'fontsize'],
  ['cashier', 'pos', 'till', 'tender'],
  ['icu', 'intensive', 'critical'],
  ['kpi', 'dashboard', 'dashboards', 'metrics'],
  ['audit', 'trail', 'compliance'],
  ['help', 'support', 'contact', 'troubleshoot', 'troubleshooting', 'feedback'],
  ['leave', 'holiday', 'vacation', 'timeoff', 'absence'],
  ['roster', 'rota', 'shift', 'shifts', 'duty', 'timetable'],
  ['journal', 'debit', 'credit', 'ledger', 'bookkeeping'],
  ['walkin', 'otc', 'overthecounter', 'counter'],
  ['barcode', 'scan', 'scanning'],
  ['mrn', 'filenumber', 'hospitalnumber'],
  ['queue', 'waiting', 'waitlist'],
  ['feedback', 'suggestion', 'complaint', 'bugreport'],
  ['dictate', 'dictation', 'microphone', 'speech', 'voice'],
  ['stockorder', 'transfer', 'replenish', 'replenishment'],
];

/**
 * Extra words for a section that readers type but the copy never says.
 *
 * Kept here, not on the manual content, so the PDF is not padded with search
 * hints and the vocabulary stays next to the ranking rules.
 */
const SECTION_KEYWORDS = {
  'sign-in': ['login', 'signin', 'logon'],
  'reset-a-forgotten-password': ['forgot', 'forgotten', 'unlock'],
  'find-a-screen-with-search-menu': ['navigate', 'menuitem', 'gotoscreen'],
  'your-account-menu': ['signout', 'logout', 'profilemenu'],
  'make-the-screen-easier-to-read': ['dark', 'mode', 'darkmode', 'theme', 'fontsize', 'accessibility', 'contrast', 'boldtext'],
  'create-a-staff-account': ['invite', 'newuser', 'adduser', 'addstaff', 'onboard'],
  'find-a-patient': ['mrn', 'lookup', 'searchpatient'],
  'register-a-new-patient': ['newpatient', 'addpatient', 'enrolpatient'],
  'book-an-appointment': ['booking', 'schedule'],
  'take-a-payment': ['cashier', 'pos', 'collectpayment', 'receivepayment', 'tender'],
  'charge-a-patient': ['addcharge', 'price', 'fee'],
  'dispense-a-prescription': ['givemedicine', 'fillprescription', 'pharmacy'],
  'sell-to-a-walk-in-customer': ['otc', 'walkin', 'overthecounter', 'counter'],
  'the-pharmacy-worklist': ['stock', 'catalogue', 'inventory', 'carelocation'],
  'main-and-hospital-pharmacy': ['mainpharmacy', 'hospitalpharmacy', 'switchpharmacy', 'locations'],
  'order-stock-between-pharmacies': ['stockorder', 'replenish', 'transfer', 'issue', 'receive'],
  'set-pharmacy-prices': ['walkinprice', 'sellingprice', 'supplyprice'],
  'send-feedback': ['feedback', 'suggestion', 'complaint', 'reportproblem'],
  'delete-a-patient': ['remove', 'gdpr', 'erase', 'purge', 'restore'],
  'admit-a-patient': ['ipd', 'bed', 'allocate'],
  'finalize-a-discharge': ['sendhome', 'checkout'],
  'record-triage-and-vital-signs': ['bp', 'temperature', 'pulse', 'spo2'],
  'order-laboratory-tests': ['bloodtest', 'requestlab'],
  'order-imaging': ['xray', 'scan', 'ct', 'mri', 'ultrasound'],
  'run-payroll': ['salary', 'wages', 'payslip'],
  'manage-leave': ['holiday', 'vacation', 'timeoff'],
  'getting-help': ['support', 'contact', 'whatsapp', 'feedback'],
  'common-problems': ['error', 'bug', 'cannot', 'offline', 'missing', 'dictation', 'microphone'],
  'set-up-insurance': ['nhis', 'scheme', 'insurer'],
  'the-claims-worklist': ['preauth', 'authorization'],
  'close-your-shift': ['endshift', 'cashup', 'reconciliation'],
  'renew-or-change-your-subscription': ['package', 'plan', 'expired', 'renew'],
};

/** word -> Set of words it should also match. Built once from the groups. */
const SYNONYMS = (() => {
  const map = new Map();
  for (const group of SYNONYM_GROUPS) {
    for (const word of group) {
      const related = map.get(word) || new Set();
      for (const other of group) {
        if (other !== word) {
          related.add(other);
        }
      }
      map.set(word, related);
    }
  }
  return map;
})();

/**
 * Split text into comparable words.
 *
 * Strips the manual's inline marks so `**Save**` indexes as `save`, and folds
 * accents so a query typed without them still matches.
 *
 * @param {string} text - Raw manual copy or a reader's query
 * @returns {string[]} Lowercase words, two letters or more
 */
export function tokenize(text) {
  const prepared = String(text ?? '')
    .normalize('NFD')
    .replace(/\p{M}/gu, '')
    .toLowerCase()
    .replace(/\*\*/g, '')
    .replace(/\[([^\]]+)\]\(#[a-z0-9-]*\)/g, '$1');

  const words = prepared.split(/[^a-z0-9]+/).filter((word) => word.length > 1);

  /* "x-ray" and "sign-in" also index as "xray" and "signin". */
  const compounds = prepared.match(/[a-z0-9]+(?:-[a-z0-9]+)+/g) || [];
  for (const compound of compounds) {
    const joined = compound.replace(/-/g, '');
    if (joined.length > 1) {
      words.push(joined);
    }
  }

  return words;
}

/** Lowercased, accent-folded text for phrase tests. */
function normalizeText(text) {
  return String(text ?? '')
    .normalize('NFD')
    .replace(/\p{M}/gu, '')
    .toLowerCase()
    .replace(/\*\*/g, '')
    .replace(/\[([^\]]+)\]\(#[a-z0-9-]*\)/g, '$1')
    .replace(/\s+/g, ' ')
    .trim();
}

/**
 * Readable text of one content block, for the snippet and the body index.
 *
 * @param {Object} block - A manual block
 * @returns {string} Plain text, or an empty string for blocks that carry none
 */
function blockText(block) {
  if (!block || typeof block !== 'object') {
    return '';
  }
  switch (block.type) {
    case 'p':
      return block.text || '';
    case 'note':
      return [block.title, block.text].filter(Boolean).join('. ');
    case 'list':
      return (block.items || []).join(' ');
    case 'steps':
      return [block.caption, ...(block.items || [])].filter(Boolean).join(' ');
    case 'figure':
      return block.caption || '';
    case 'table':
      return [...(block.columns || []), ...(block.rows || []).flat()].join(' ');
    default:
      return '';
  }
}

/**
 * Build the search index for a manual.
 *
 * One entry per section, because a section is the smallest thing a reader can
 * be sent to. Chapter titles and summaries ride along on their sections rather
 * than competing with them as separate results.
 *
 * @param {Array<Object>} chapters - Numbered chapters from numberUserManual()
 * @returns {Array<Object>} Index entries, one per section
 */
export function buildManualSearchIndex(chapters = []) {
  const entries = [];

  for (const chapter of chapters) {
    for (const section of chapter.sections || []) {
      const body = (section.blocks || []).map(blockText).filter(Boolean).join(' ');
      const extraKeywords = SECTION_KEYWORDS[section.id] || [];
      const fields = {
        title: section.title || '',
        chapter: [chapter.title, chapter.summary].filter(Boolean).join('. '),
        audience: section.audience || '',
        keywords: [...(section.keywords || []), ...extraKeywords].join(' '),
        body,
      };

      /* Word -> best field it appears in, so scoring is a map lookup per word. */
      const words = new Map();
      for (const [field, text] of Object.entries(fields)) {
        for (const word of tokenize(text)) {
          const current = words.get(word);
          if (!current || FIELD_WEIGHTS[field] > FIELD_WEIGHTS[current]) {
            words.set(word, field);
          }
        }
      }

      entries.push({
        id: section.id,
        title: section.title,
        number: section.number,
        chapterId: chapter.id,
        chapterTitle: chapter.title,
        chapterNumber: chapter.number,
        audience: section.audience || null,
        body,
        normalizedTitle: normalizeText(section.title),
        normalizedBody: normalizeText(body),
        titleWords: new Set(tokenize(section.title)),
        words,
      });
    }
  }

  return entries;
}

/**
 * Levenshtein distance, stopped as soon as it exceeds `max`.
 *
 * @param {string} a - First word
 * @param {string} b - Second word
 * @param {number} max - Distance beyond which the answer stops mattering
 * @returns {number} Distance, or `max + 1` once it is certainly greater
 */
function editDistance(a, b, max) {
  if (a === b) {
    return 0;
  }
  if (Math.abs(a.length - b.length) > max) {
    return max + 1;
  }

  let previous = Array.from({ length: b.length + 1 }, (_, index) => index);
  for (let i = 1; i <= a.length; i += 1) {
    const current = [i];
    let rowBest = i;
    for (let j = 1; j <= b.length; j += 1) {
      const cost = a[i - 1] === b[j - 1] ? 0 : 1;
      current[j] = Math.min(current[j - 1] + 1, previous[j] + 1, previous[j - 1] + cost);
      rowBest = Math.min(rowBest, current[j]);
    }
    if (rowBest > max) {
      return max + 1;
    }
    previous = current;
  }
  return previous[b.length];
}

/** How far a word of this length may be mistyped and still match. */
function fuzzyAllowance(word) {
  if (word.length >= 8) {
    return 2;
  }
  if (word.length >= 5) {
    return 1;
  }
  return 0;
}

/**
 * Best match for one query word against one indexed section.
 *
 * @param {string} queryWord - A word from the query
 * @param {boolean} allowShortPrefix - Whether a 2–3 letter prefix may match
 * @param {Map<string, string>} words - Indexed word -> field
 * @returns {{score: number, quality: string, titleHit: boolean, matchedWord: string}|null}
 */
function matchWord(queryWord, allowShortPrefix, words) {
  let best = null;
  const consider = (field, quality, matchedWord) => {
    const score = FIELD_WEIGHTS[field] * MATCH_QUALITY[quality];
    if (!best || score > best.score) {
      best = { score, quality, titleHit: field === 'title', matchedWord };
    }
  };

  const exactField = words.get(queryWord);
  if (exactField) {
    consider(exactField, 'exact', queryWord);
  }

  /*
   * Prefix: the word still being typed may be two letters; a finished word
   * only prefixes from five, so "sign" does not swallow "signs".
   */
  const prefixMin = allowShortPrefix ? 2 : 5;
  if (queryWord.length >= prefixMin) {
    for (const [word, field] of words) {
      if (word.length > queryWord.length && word.startsWith(queryWord)) {
        consider(field, 'prefix', word);
      }
    }
  }

  const related = SYNONYMS.get(queryWord);
  if (related) {
    for (const alternative of related) {
      const field = words.get(alternative);
      if (field) {
        consider(field, 'synonym', alternative);
      }
    }
  }

  if (!best || best.quality === 'fuzzy') {
    const allowance = fuzzyAllowance(queryWord);
    if (allowance > 0) {
      for (const [word, field] of words) {
        if (Math.abs(word.length - queryWord.length) > allowance) {
          continue;
        }
        if (editDistance(queryWord, word, allowance) <= allowance) {
          consider(field, 'fuzzy', word);
        }
      }
    }
  }

  return best;
}

/** True when this query word, or a synonym of it, appears in the section title. */
function titleCoversWord(entry, queryWord, match) {
  if (match.titleHit || entry.titleWords.has(queryWord) || entry.titleWords.has(match.matchedWord)) {
    return true;
  }
  const related = SYNONYMS.get(queryWord);
  if (!related) {
    return false;
  }
  for (const alternative of related) {
    if (entry.titleWords.has(alternative)) {
      return true;
    }
  }
  return false;
}

/**
 * A short piece of the section that shows why it matched.
 *
 * Centred on the first matched word so the reader sees the term in context
 * rather than the opening sentence of every result.
 *
 * @param {Object} entry - Index entry
 * @param {string[]} queryWords - Tokenized query
 * @returns {string} Snippet, trimmed to about 160 characters
 */
/** Manual copy without inline marks, kept in the original case for snippets. */
function readableText(text) {
  return String(text ?? '')
    .replace(/\*\*/g, '')
    .replace(/\[([^\]]+)\]\(#[a-z0-9-]*\)/g, '$1')
    .replace(/\s+/g, ' ')
    .trim();
}

/**
 * A short piece of the section that shows why it matched.
 *
 * Centred on the first matched word so the reader sees the term in context
 * rather than the opening sentence of every result.
 *
 * @param {Object} entry - Index entry
 * @param {string[]} queryWords - Tokenized query
 * @returns {string} Snippet, trimmed to about 160 characters
 */
function buildSnippet(entry, queryWords) {
  const text = readableText(entry.body);
  if (!text) {
    return '';
  }
  const haystack = text.toLowerCase();

  let at = -1;
  for (const word of queryWords) {
    const found = haystack.indexOf(word);
    if (found !== -1 && (at === -1 || found < at)) {
      at = found;
    }
  }

  const width = 160;
  if (at === -1) {
    return text.length > width ? `${text.slice(0, width).trimEnd()}...` : text;
  }

  let start = Math.max(0, at - 60);
  if (start > 0) {
    const space = text.indexOf(' ', start);
    start = space === -1 ? start : space + 1;
  }
  const end = Math.min(text.length, start + width);
  const slice = text.slice(start, end).trim();
  return `${start > 0 ? '...' : ''}${slice}${end < text.length ? '...' : ''}`;
}

/**
 * Rank the manual against a reader's query.
 *
 * @param {Array<Object>} index - Entries from buildManualSearchIndex()
 * @param {string} query - What the reader typed
 * @param {Object} [options]
 * @param {number} [options.limit] - Most results to return
 * @returns {Array<Object>} Ranked results with a snippet and the words that hit
 */
export function searchManual(index = [], query = '', { limit = 12 } = {}) {
  const normalizedQuery = normalizeText(query);
  if (normalizedQuery.length < 2) {
    return [];
  }

  const allWords = tokenize(query);
  /* Drop stop words, unless that would leave nothing to search for. */
  const meaningful = allWords.filter((word) => !STOP_WORDS.has(word));
  const queryWords = meaningful.length ? meaningful : allWords;
  if (!queryWords.length) {
    return [];
  }

  const endsMidWord = /[a-z0-9]$/i.test(query.trim());
  const lastTyped = query.trim().toLowerCase().split(/[^a-z0-9]+/).filter(Boolean).pop();
  const lastIsPrefix = Boolean(endsMidWord && lastTyped && !STOP_WORDS.has(lastTyped));
  const results = [];

  for (const entry of index) {
    let score = 0;
    let matched = 0;
    let titleHits = 0;
    const hits = [];

    queryWords.forEach((word) => {
      const allowShortPrefix = lastIsPrefix && word === lastTyped;
      const match = matchWord(word, allowShortPrefix, entry.words);
      if (match) {
        score += match.score;
        matched += 1;
        hits.push(word);
        if (match.matchedWord && match.matchedWord !== word) {
          hits.push(match.matchedWord);
        }
        if (titleCoversWord(entry, word, match)) {
          titleHits += 1;
        }
      }
    });

    if (!matched) {
      continue;
    }

    /* Covering the whole query matters more than any single strong hit. */
    const coverage = matched / queryWords.length;
    score += coverage * COVERAGE_WEIGHT;
    score += (titleHits / queryWords.length) * TITLE_COVERAGE_WEIGHT;

    const titleSignificantWords = tokenize(entry.title).filter((word) => !STOP_WORDS.has(word));
    const titleSignificant = titleSignificantWords.join(' ');
    const querySignificant = queryWords.join(' ');
    const multiWord = queryWords.length > 1 || normalizedQuery.includes(' ');

    /* Whole-phrase bonuses only; a single word must not hit inside "signs". */
    if (multiWord && normalizedQuery.length >= 4) {
      if (entry.normalizedTitle.includes(normalizedQuery) || titleSignificant.includes(querySignificant)) {
        score += PHRASE_BONUS.title;
      } else if (entry.normalizedBody.includes(normalizedQuery)) {
        score += PHRASE_BONUS.body;
      }
    }

    /* A short title that is mostly the query is a better answer than a long one. */
    if (
      entry.normalizedTitle.startsWith(normalizedQuery)
      || titleSignificant.startsWith(querySignificant)
    ) {
      score += 25;
    }

    results.push({
      id: entry.id,
      title: entry.title,
      number: entry.number,
      chapterId: entry.chapterId,
      chapterTitle: entry.chapterTitle,
      chapterNumber: entry.chapterNumber,
      audience: entry.audience,
      score,
      coverage,
      hits,
      snippet: buildSnippet(entry, hits),
    });
  }

  /* Partial matches stay, but only once nothing covers the whole query. */
  const complete = results.filter((result) => result.coverage === 1);
  const ranked = (complete.length ? complete : results).sort((a, b) => (
    b.score - a.score || a.number.localeCompare(b.number, 'en', { numeric: true })
  ));

  return ranked.slice(0, limit);
}

/**
 * Split text into plain and matched runs, for highlighting a result.
 *
 * Works on whole words so a match on "pay" does not light up the middle of
 * "display".
 *
 * @param {string} text - Snippet or title
 * @param {string[]} words - Words that matched
 * @returns {Array<{text: string, match: boolean}>} Runs in order
 */
export function highlightParts(text, words = []) {
  const source = String(text ?? '');
  if (!source || !words.length) {
    return [{ text: source, match: false }];
  }

  const escaped = words
    .filter(Boolean)
    .map((word) => word.replace(/[.*+?^${}()|[\]\\]/g, '\\$&'))
    .sort((a, b) => b.length - a.length);
  if (!escaped.length) {
    return [{ text: source, match: false }];
  }

  const pattern = new RegExp(`(?<![a-z0-9])(${escaped.join('|')})[a-z0-9]*`, 'gi');
  const parts = [];
  let index = 0;

  for (const match of source.matchAll(pattern)) {
    if (match.index > index) {
      parts.push({ text: source.slice(index, match.index), match: false });
    }
    parts.push({ text: match[0], match: true });
    index = match.index + match[0].length;
  }
  if (index < source.length) {
    parts.push({ text: source.slice(index), match: false });
  }

  return parts.length ? parts : [{ text: source, match: false }];
}
