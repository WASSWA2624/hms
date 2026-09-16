const { speechFormatTask } = require('@lib/ai/tasks/speech-format');

const parse = (completion, input) => speechFormatTask.outputParser(completion, input);

describe('speech_format output parser', () => {
  const fixtures = [
    ['text', 'hello, world', 'hello, world'],
    ['email', 'name@hospital.com', 'name@hospital.com'],
    ['digits', '1225', '1225'],
    ['decimal', '12.5', '12.5'],
    ['currency', '1500.00', '1500.00'],
    ['phone', '0772123456', '0772123456'],
    ['date', '2024-03-15', '2024-03-15'],
    ['time', '14:30', '14:30'],
  ];

  test.each(fixtures)('keeps format-only %s output', (mode, completion, expected) => {
    const input = { transcript: 'raw utterance', mode };
    expect(parse(completion, input)).toEqual({
      formatted_text: expected,
      mode,
    });
  });

  test('strips markdown fences and explanations', () => {
    const input = { transcript: 'name at hospital dot com', mode: 'email' };
    expect(
      parse('```\nname@hospital.com\n```\nThis is the email.', input).formatted_text
    ).toBe('name@hospital.com');
  });

  test('does not invent values when completion is empty', () => {
    const input = { transcript: 'patient has fever', mode: 'text' };
    expect(parse('   ', input).formatted_text).toBe('patient has fever');
  });

  test('keeps every paragraph of formatted prose', () => {
    const input = { transcript: 'raw dictation', mode: 'text' };
    expect(
      parse('```text\nThe patient is stable.\n\nReview tomorrow.\n```', input)
        .formatted_text
    ).toBe('The patient is stable.\n\nReview tomorrow.');
  });
});

describe('speech_format prompt', () => {
  test('passes preceding field text as context for a continuation', () => {
    const input = speechFormatTask.inputSchema.parse({
      transcript: 'since yesterday and she has a cough',
      mode: 'text',
      context_before: 'The patient has had a fever',
    });
    const prompt = speechFormatTask.buildUserPrompt(input);

    expect(prompt).toContain(
      'context_before (already written; do not repeat or change):\nThe patient has had a fever'
    );
    expect(prompt.endsWith('transcript:\nsince yesterday and she has a cough')).toBe(true);
    expect(prompt).toContain('Capitalize sentences');
  });

  test('omits context when none is given', () => {
    const input = speechFormatTask.inputSchema.parse({
      transcript: 'hello',
      mode: 'text',
    });
    expect(speechFormatTask.buildUserPrompt(input)).not.toContain('context_before');
  });

  test('rejects oversized context', () => {
    expect(() =>
      speechFormatTask.inputSchema.parse({
        transcript: 'hello',
        mode: 'text',
        context_before: 'x'.repeat(601),
      })
    ).toThrow();
  });
});
