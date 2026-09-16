/**
 * speech_format task
 *
 * Rewrites a speech-to-text transcript into a field's expected format.
 */

const { z } = require('zod');
const { AI_MAX_INPUT_CHARS } = require('@config/env');

const SPEECH_FORMAT_MODES = Object.freeze([
  'text',
  'email',
  'digits',
  'decimal',
  'date',
  'time',
  'phone',
  'currency',
]);

/** Longest `context_before` accepted: enough to know how a sentence began. */
const SPEECH_FORMAT_CONTEXT_MAX_CHARS = 600;

const MODE_RULES = {
  text: [
    'Write clean, readable prose.',
    'Capitalize sentences and the pronoun I.',
    'Add the punctuation a careful writer would: commas, periods, question marks, apostrophes.',
    'Fix spacing between words and sentences.',
    'Correct words the recognizer clearly misheard, using the surrounding context.',
    'Remove filler (um, uh) and accidental repeated words; light grammar cleanup only.',
    'Punctuation words become marks. Spoken cardinals become digits.',
    "Keep the speaker's wording and meaning; preserve paragraph breaks.",
  ].join(' '),
  email: 'Convert spoken email tokens (at, dot) into a compact address with no spaces.',
  digits: 'Return an integer digit string only.',
  decimal: 'Return a numeric string using a period as the decimal separator.',
  currency: 'Return a numeric amount string using a period as the decimal separator. Do not invent currency codes.',
  phone: 'Return the digit sequence only. Do not invent a country code.',
  date: 'If a full date is present, return ISO YYYY-MM-DD. Otherwise return the clearest partial the utterance supports.',
  time: 'If a time is present, return HH:mm in 24-hour form.',
};

/**
 * @param {string} raw - Model completion
 * @param {{ multiline?: boolean }} [options] - Keep every line (prose)
 *   instead of the first non-empty one
 * @returns {string} The formatted value
 */
const stripCompletion = (raw, { multiline = false } = {}) => {
  let text = String(raw || '').trim();
  if (!text) {
    return '';
  }
  text = text.replace(/^```(?:json|text)?\s*/i, '').replace(/\s*```$/i, '').trim();
  if (
    (text.startsWith('"') && text.endsWith('"')) ||
    (text.startsWith("'") && text.endsWith("'"))
  ) {
    text = text.slice(1, -1).trim();
  }
  try {
    const parsed = JSON.parse(text);
    if (parsed && typeof parsed === 'object' && parsed.formatted_text != null) {
      return String(parsed.formatted_text).trim();
    }
  } catch (_error) {
    // Plain text completion.
  }
  if (multiline) {
    return text;
  }
  const firstLine = text.split(/\r?\n/).find((line) => line.trim());
  return String(firstLine || text).trim();
};

const speechFormatTask = {
  key: 'speech_format',
  failOpen: true,
  inputSchema: z.object({
    transcript: z
      .string()
      .trim()
      .min(1)
      .max(AI_MAX_INPUT_CHARS),
    mode: z.enum(SPEECH_FORMAT_MODES),
    locale: z.string().trim().min(1).max(32).optional().default('en'),
    hint: z.string().trim().max(200).optional(),
    // Text already in the field right before the transcript, so a dictated
    // continuation is capitalized and punctuated in context.
    context_before: z
      .string()
      .max(SPEECH_FORMAT_CONTEXT_MAX_CHARS)
      .optional(),
  }),
  systemPrompt: [
    'You rewrite speech-to-text transcripts into the exact field format requested.',
    'Output only the formatted value. No markdown, labels, quotes, or explanation.',
    'Do not invent clinical facts, diagnoses, medications, identifiers, or missing values.',
    'When context_before is given, the transcript continues that text: return only the rewritten transcript, never the context,',
    'and start with a lowercase word when the context ends mid-sentence.',
    'If the utterance is already correctly formatted, return it unchanged.',
    'If you cannot format it confidently, return the input transcript unchanged.',
  ].join(' '),
  buildUserPrompt: (input) => {
    const lines = [
      `mode: ${input.mode}`,
      `locale: ${input.locale || 'en'}`,
      `mode_rules: ${MODE_RULES[input.mode]}`,
    ];
    if (input.hint) {
      lines.push(`hint: ${input.hint}`);
    }
    const contextBefore = String(input.context_before || '').trim();
    if (contextBefore) {
      lines.push('context_before (already written; do not repeat or change):');
      lines.push(contextBefore);
    }
    lines.push('transcript:');
    lines.push(input.transcript);
    return lines.join('\n');
  },
  outputParser: (completionText, input) => {
    const formatted = stripCompletion(completionText, {
      // Prose may span paragraphs; other modes are a single value.
      multiline: input.mode === 'text',
    });
    return {
      formatted_text: formatted || input.transcript,
      mode: input.mode,
    };
  },
  failOpenOutput: (input) => ({
    formatted_text: input.transcript,
    mode: input.mode,
  }),
};

module.exports = {
  speechFormatTask,
  SPEECH_FORMAT_MODES,
  SPEECH_FORMAT_CONTEXT_MAX_CHARS,
};
