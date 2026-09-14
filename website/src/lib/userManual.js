/**
 * HOSSPI HMS User Manual Content
 *
 * Single source for the /user-manual page and for the downloadable PDF built
 * by scripts/build-user-manual-pdf.mjs, so the two never drift apart.
 *
 * Audience rule: written for the people who use the application - hospital
 * staff and administrators. Installing, deploying or developing the system
 * never belongs here.
 *
 * Accuracy rule: describe only what users can reach in the current release,
 * and quote on-screen labels exactly, in bold.
 *
 * Block types:
 *   { type: 'p', text }
 *   { type: 'steps', figure?, caption?, items }   marker N on the figure = step N
 *   { type: 'figure', figure, caption? }
 *   { type: 'note', tone: 'tip'|'info'|'warning', title?, text }
 *   { type: 'list', items }
 *   { type: 'table', columns, rows }
 * Inline text supports **bold** and [label](#section-id) cross references.
 * Figures live in userManualFigures.json, keyed by id.
 *
 * Kept free of path aliases and React so the PDF script can import it.
 *
 * @file src/lib/userManual.js
 */

/** Where the PDF is served from; the download button renames it on save. */
export const USER_MANUAL_PDF_PATH = '/downloads/hosspi-user-manual.pdf';

/**
 * Download name for the PDF: hosspi-DDMMYYYYHHmm.pdf in 24-hour local time,
 * e.g. hosspi-141020261024.pdf for 14 October 2026 at 10:24.
 *
 * @param {Date} [date] - Moment of the download
 * @returns {string} File name
 */
export function userManualFileName(date = new Date()) {
  const pad = (value) => String(value).padStart(2, '0');
  return `hosspi-${pad(date.getDate())}${pad(date.getMonth() + 1)}${date.getFullYear()}${pad(date.getHours())}${pad(date.getMinutes())}.pdf`;
}

export const USER_MANUAL = {
  title: 'HOSSPI HMS User Manual',
  subtitle: 'Step-by-step guide for hospital staff and administrators',
  version: '1.0',
  updated: '2026-09-14',
  intro:
    'Everything you need to run your facility on HOSSPI HMS, in the order you will need it: registering and signing in, setting up your facility, giving staff their accounts, looking after patients from arrival to discharge, and billing, accounts and reporting. Every task is explained step by step, with numbered screenshots.',
  chapters: [
    {
      id: 'introduction',
      title: 'Introduction',
      summary: 'What HOSSPI HMS is, who this manual is for, and how to read it.',
      sections: [
        {
          id: 'about-hosspi-hms',
          title: 'About HOSSPI HMS',
          blocks: [
            {
              type: 'p',
              text: 'HOSSPI Hospital Management System (HOSSPI HMS) runs the whole facility from one system. Reception, the consulting rooms, the wards, the laboratory, radiology, the pharmacy and the finance office all work from the same patient record, so information entered once is available to everyone who needs it.',
            },
            {
              type: 'p',
              text: 'You can use HOSSPI HMS in any modern web browser at **app.hosspi.com**, or in the HOSSPI apps for Android, iOS, Windows, macOS and Linux. Your account and your records are the same on every device, and so are the steps in this manual.',
            },
          ],
        },
        {
          id: 'who-this-manual-is-for',
          title: 'Who this manual is for',
          blocks: [
            {
              type: 'p',
              text: 'This manual is for everyone who uses HOSSPI HMS at a hospital, clinic, laboratory or pharmacy:',
            },
            {
              type: 'list',
              items: [
                '**Facility owners and administrators**, who register the facility, set it up and create staff accounts.',
                '**Clinical staff** (doctors, nurses, laboratory, radiology and pharmacy teams), who look after patients.',
                '**Front office and finance staff** (reception, billing officers, cashiers and accountants).',
                '**Human resources staff and managers**, who keep staff records and read reports.',
              ],
            },
          ],
        },
        {
          id: 'how-to-read-this-manual',
          title: 'How to read this manual',
          blocks: [
            {
              type: 'p',
              text: 'The chapters follow the order in which a facility starts using HOSSPI HMS: registration and sign-in first, then setup and staff accounts, then the patient journey, and finally billing, accounts and reporting. Read the chapters that match your work, or use the contents to go straight to a task.',
            },
            {
              type: 'list',
              items: [
                '**Numbered markers** on a screenshot match the numbered steps beneath it: marker 1 shows where to carry out step 1, and so on.',
                'Words in **bold** are the exact labels you see on screen, such as buttons, menu items, tabs and field names.',
                'Fields marked with an asterisk (*) must be completed before a form can be saved.',
              ],
            },
            {
              type: 'note',
              tone: 'info',
              title: 'What you see depends on your role',
              text: 'HOSSPI HMS shows each person only the menu items, tabs and buttons that their role allows, and only the areas included in your facility’s subscription package. If something described here is missing from your screen, ask your facility administrator whether your role should include it.',
            },
            {
              type: 'note',
              tone: 'tip',
              title: 'Screenshots use sample data',
              text: 'The screenshots were taken in a demonstration workspace, DemoCare General Hospital. The names, patients and amounts in them are examples, not real people.',
            },
          ],
        },
        {
          id: 'what-you-need',
          title: 'What you need',
          blocks: [
            {
              type: 'list',
              items: [
                'A computer, tablet or phone with an up-to-date web browser (Chrome, Edge, Firefox or Safari), or the HOSSPI app installed.',
                'An internet connection.',
                'The email address or phone number of your account, and your password. Staff accounts are created by the facility administrator.',
              ],
            },
          ],
        },
      ],
    },
    {
      id: 'registering-and-signing-in',
      title: 'Registering and signing in',
      summary:
        'Create your facility’s account, verify your email address, wait for approval and sign in. Also covers resetting a forgotten password.',
      sections: [
        {
          id: 'how-registration-works',
          title: 'How registration works',
          blocks: [
            {
              type: 'p',
              text: 'A facility joins HOSSPI HMS in four stages. Only the first administrator registers. Everyone else gets an account from an administrator later, as described in [Users, roles and permissions](#users-roles-and-permissions).',
            },
            {
              type: 'table',
              columns: ['Stage', 'What happens', 'Who does it'],
              rows: [
                ['1. Create your account', 'Enter the administrator and facility details on the registration form.', 'Facility administrator'],
                ['2. Verify your email', 'Enter the six-digit code sent to your email address.', 'Facility administrator'],
                ['3. Wait for approval', 'The HOSSPI platform team reviews and approves the new facility.', 'HOSSPI'],
                ['4. Sign in', 'Sign in with the email address or phone number and password you registered.', 'Facility administrator'],
              ],
            },
            {
              type: 'figure',
              figure: 'auth-register-guide',
              caption: 'The same four stages are summarised under How to register on the sign-in and registration screens.',
            },
          ],
        },
        {
          id: 'register-your-facility',
          title: 'Register your facility',
          audience: 'The person who will administer the facility',
          blocks: [
            {
              type: 'p',
              text: 'Go to **app.hosspi.com**. On the sign-in screen, select **Register** to open **Set up your facility**.',
            },
            {
              type: 'steps',
              figure: 'auth-register',
              caption: 'Set up your facility: the registration form.',
              items: [
                'Enter your full name in **Administrator name**. You become the first administrator of the facility.',
                'Enter the email address you will sign in with in **Email**. The verification code is sent here, so use an inbox you can open now.',
                'Choose a **Password** of at least 8 characters. Select the eye icon to show or hide what you typed.',
                'Enter the name of your hospital, clinic, laboratory or pharmacy in **Facility name**.',
                'Choose the **Facility type**: **Hospital**, **Clinic**, **Lab**, **Pharmacy** or **Other**.',
                'In **Phone**, choose your country and enter the phone number. You can also sign in with this number later.',
                'Select **Create account**.',
              ],
            },
            {
              type: 'p',
              text: 'HOSSPI HMS creates your facility’s workspace and opens **Verify your email**.',
            },
            {
              type: 'note',
              tone: 'warning',
              title: 'If the form is not accepted',
              text: 'Any field with a problem is highlighted with an explanation beneath it. Other problems, such as an email address that is already registered, are explained in a message above the form. If you already have an account, select **Sign in** or **Reset password** instead.',
            },
          ],
        },
        {
          id: 'verify-your-email',
          title: 'Verify your email address',
          blocks: [
            {
              type: 'p',
              text: 'Look in the inbox of the email address you registered for a message with a six-digit verification code. If it has not arrived after a few minutes, check your spam or junk folder.',
            },
            {
              type: 'steps',
              figure: 'auth-verify',
              caption: 'Verify your email: enter the six-digit code from your inbox.',
              items: [
                'Check that the email address in the message at the top is the one you registered.',
                'Type the six-digit code into **Verification code**.',
                'Select **Verify**.',
                'If the code has expired or never arrived, select **Send new code**, then enter the newest code.',
              ],
            },
            {
              type: 'note',
              tone: 'info',
              text: 'If the screen shows **Account created** with a warning that the verification email has not gone out yet, your workspace has still been created. Select **Send new code** to receive your code.',
            },
          ],
        },
        {
          id: 'wait-for-approval',
          title: 'Wait for approval',
          blocks: [
            {
              type: 'p',
              text: 'Once your email address is verified, the HOSSPI platform team checks the new facility before anyone can sign in. HOSSPI HMS returns you to the sign-in screen and explains that your account is **Awaiting approval**.',
            },
            {
              type: 'figure',
              figure: 'auth-pending',
              caption: 'Awaiting approval, with the platform administrators you can contact.',
            },
            {
              type: 'p',
              text: 'The message lists the platform administrators you can contact if approval takes longer than expected. Select an email address or phone number to copy it, then select **Close**. If you try to sign in before your account is approved, the same information appears under **Account pending approval**.',
            },
          ],
        },
        {
          id: 'sign-in',
          title: 'Sign in',
          audience: 'Everyone',
          blocks: [
            {
              type: 'p',
              text: 'Go to **app.hosspi.com**. The sign-in screen, **Welcome back**, opens.',
            },
            {
              type: 'steps',
              figure: 'auth-login',
              caption: 'Welcome back: the sign-in screen.',
              items: [
                'Under **Sign in with**, choose **Email** or **Phone**.',
                'Enter the email address, or choose the country and enter the phone number, of your account.',
                'Enter your **Password**.',
                'Select **Sign in**.',
              ],
            },
            {
              type: 'p',
              text: 'HOSSPI HMS opens your **Dashboard**, or the page you were trying to open when you were asked to sign in.',
            },
            {
              type: 'table',
              columns: ['If you see', 'What to do'],
              rows: [
                ['**The sign-in details are not valid.** or **The password is incorrect for this account.**', 'Check the email address or phone number and the password, including capital letters, and try again.'],
                ['**No account for that email or phone.**', 'Check for typing mistakes. If you are a member of staff, ask your facility administrator to create your account.'],
                ['**Too many attempts.**', 'Wait until the time shown, then try again.'],
                ['**Verify your email**', 'The account has not been verified yet. Enter the code sent to your email address.'],
                ['**Account pending approval**', 'The facility is still waiting for HOSSPI approval. Contact one of the platform administrators listed.'],
                ['**This facility account has been deactivated.**', 'Contact the platform administrator shown in the message.'],
              ],
            },
          ],
        },
        {
          id: 'reset-a-forgotten-password',
          title: 'Reset a forgotten password',
          audience: 'Everyone',
          blocks: [
            {
              type: 'p',
              text: 'On the sign-in screen, select **Reset password**. The **Reset your password** screen opens.',
            },
            {
              type: 'steps',
              figure: 'auth-forgot',
              caption: 'Reset your password: request a reset code.',
              items: [
                'Enter the **Email** address of your account.',
                'Select **Send reset instructions**. If the address belongs to accounts in more than one workspace, choose the workspace you want to reset.',
              ],
            },
            {
              type: 'p',
              text: 'HOSSPI HMS sends a reset link and a six-digit code to your email address and opens **Choose a new password**.',
            },
            {
              type: 'steps',
              figure: 'auth-reset',
              caption: 'Choose a new password: enter the reset code and your new password.',
              items: [
                'Enter the six-digit **Reset code** from the email.',
                'Enter a **New password** of at least 8 characters.',
                'Select **Reset password**.',
              ],
            },
            {
              type: 'p',
              text: 'The sign-in screen opens with the message **Password updated**. Sign in with your new password. You can also open the link in the email instead of typing the code; it takes you straight to **Choose a new password**.',
            },
          ],
        },
      ],
    },
  ],
};

/**
 * Attach chapter, section and figure numbers so the page and the PDF agree.
 *
 * @param {typeof USER_MANUAL} [manual] - Manual content
 * @returns {Array<Object>} Chapters with number, section numbers and figureNumber on figure blocks
 */
export function numberUserManual(manual = USER_MANUAL) {
  return manual.chapters.map((chapter, chapterIndex) => {
    const number = chapterIndex + 1;
    let figureCount = 0;
    return {
      ...chapter,
      number,
      sections: chapter.sections.map((section, sectionIndex) => ({
        ...section,
        number: `${number}.${sectionIndex + 1}`,
        blocks: section.blocks.map((block) => (
          block.figure ? { ...block, figureNumber: `${number}.${++figureCount}` } : block
        )),
      })),
    };
  });
}
