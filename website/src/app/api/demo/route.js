/**
 * POST /api/demo - Demo request from the landing page
 *
 * Takes a phone number and an email address, nothing else: the whole point is
 * that a visitor can ask for a demo in two fields. Emails the request to every
 * address in DEMO_REQUEST_EMAILS, and delivers it over WhatsApp to every number
 * in DEMO_REQUEST_WHATSAPP too when the Cloud API is configured. The response
 * always carries a wa.me deep link to the company number so the browser can
 * open a pre-filled WhatsApp message when server-side delivery is not set up.
 *
 * @file src/app/api/demo/route.js
 */

import { NextResponse } from 'next/server';
import { COMPANY_WHATSAPP, DEMO_REQUEST_EMAILS, DEMO_REQUEST_WHATSAPP } from '@/lib/constants';
import { createTransporter, fromAddress } from '@/lib/mailer';
import { formatTimestamp } from '@/lib/datetime';
import { sendWhatsAppText } from '@/lib/whatsapp';

/** Loose on purpose - international numbers vary and a rejected demo lead is worse than a messy one. */
const PHONE_PATTERN = /^\+?[0-9][0-9\s\-().]{6,24}$/;
const EMAIL_PATTERN = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;

/**
 * Strip control characters and cap length so nothing odd reaches the inbox.
 *
 * @param {unknown} value - Raw field
 * @param {number} max - Maximum length
 * @returns {string} Cleaned value
 */
function clean(value, max) {
  return String(value ?? '')
    // Control characters only - header injection and mail-body tricks
    // live there. Spaces, plus signs and brackets are legitimate in
    // phone numbers and must survive.
    .replace(/[\u0000-\u001F\u007F]/g, '')
    .trim()
    .slice(0, max);
}

export async function POST(request) {
  let payload;
  try {
    payload = await request.json();
  } catch {
    return NextResponse.json({ error: 'Invalid request body' }, { status: 400 });
  }

  const phone = clean(payload?.phone, 32);
  const email = clean(payload?.email, 254);
  const facility = clean(payload?.facility, 120);

  if (!phone || !email) {
    return NextResponse.json(
      { error: 'A phone number and an email address are both required.' },
      { status: 400 }
    );
  }
  if (!PHONE_PATTERN.test(phone)) {
    return NextResponse.json(
      { error: 'That phone number does not look right.' },
      { status: 400 }
    );
  }
  if (!EMAIL_PATTERN.test(email)) {
    return NextResponse.json(
      { error: 'That email address does not look right.' },
      { status: 400 }
    );
  }

  const submittedAt = formatTimestamp();
  const lines = [
    'New demo request from the HOSSPI website.',
    '',
    `Phone: ${phone}`,
    `Email: ${email}`,
    ...(facility ? [`Facility: ${facility}`] : []),
    `Received: ${submittedAt}`,
  ];
  const text = lines.join('\n');

  // The email is the record; WhatsApp is the nudge. Neither failing should
  // lose the lead, so both are attempted and their outcomes reported.
  let emailed = false;
  const transporter = createTransporter();

  if (transporter) {
    try {
      await transporter.sendMail({
        from: fromAddress(),
        to: DEMO_REQUEST_EMAILS,
        replyTo: email,
        subject: `Demo request - ${email}`,
        text,
        html: `
          <h2>New demo request</h2>
          <table cellpadding="6" style="border-collapse:collapse">
            <tr><td><strong>Phone</strong></td><td><a href="tel:${phone}">${phone}</a></td></tr>
            <tr><td><strong>Email</strong></td><td><a href="mailto:${email}">${email}</a></td></tr>
            ${facility ? `<tr><td><strong>Facility</strong></td><td>${facility}</td></tr>` : ''}
            <tr><td><strong>Received</strong></td><td>${submittedAt}</td></tr>
          </table>
          <p>Reply to this email to reach them directly.</p>
        `,
      });
      emailed = true;
    } catch (error) {
      console.error('Demo request email failed:', error?.message || error);
    }
  } else {
    console.log('Demo request (email not configured):', { phone, email, facility, submittedAt });
  }

  const deliveries = await Promise.all(
    DEMO_REQUEST_WHATSAPP.map(async (number) => ({
      number,
      ...(await sendWhatsAppText(number, text)),
    }))
  );
  for (const { number, sent, reason } of deliveries) {
    if (!sent && reason !== 'not-configured') {
      console.error(`Demo request WhatsApp to ${number} failed:`, reason);
    }
  }
  // The deep link only reaches the company number, so its delivery alone
  // decides whether the browser still needs to open it.
  const whatsappSent = deliveries.some(
    ({ number, sent }) => sent && number === COMPANY_WHATSAPP
  );

  return NextResponse.json(
    {
      message: 'Demo request received',
      emailed,
      whatsappSent,
      // Always returned: the client opens this when the server could not send
      // the WhatsApp message itself, so the request still lands either way.
      whatsappUrl: `https://wa.me/${COMPANY_WHATSAPP}?text=${encodeURIComponent(text)}`,
    },
    { status: 200 }
  );
}
