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

import { COMPANY_PHONE, CONTACT_EMAIL } from './constants.js';

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
    {
      id: 'finding-your-way-around',
      title: 'Finding your way around',
      summary:
        'The parts of the screen you use every day: the menu, the top bar, your dashboard, your account menu and the tools on every list.',
      sections: [
        {
          id: 'the-workspace-at-a-glance',
          title: 'The workspace at a glance',
          audience: 'Everyone',
          blocks: [
            {
              type: 'p',
              text: 'After you sign in, HOSSPI HMS opens your **Dashboard**. Every screen shares the same frame: the menu on the left, the top bar across the top, and the screen you are working on in the middle.',
            },
            {
              type: 'steps',
              figure: 'shell-overview',
              caption: 'The workspace, showing the Dashboard of a hospital administrator.',
              items: [
                '**Toggle sidebar** hides or shows the menu to give the page more room.',
                '**Search menu** finds any menu item by name. See [Find a screen with Search menu](#find-a-screen-with-search-menu).',
                'The menu lists the areas your role can open, grouped by type of work. A number beside an item shows how many records are waiting there; **99+** means more than 99.',
                'The subscription badge shows your facility’s package, for example **Pro**. Administrators select it to renew or change the package. See [Renew or change your subscription](#renew-or-change-your-subscription).',
                'The connection indicator shows whether HOSSPI HMS is **Online** or **Offline**.',
                '**Full screen** hides the browser’s toolbars. Select it again to leave full screen.',
                '**Account**, shown as your initials, opens your account menu. See [Your account menu](#your-account-menu).',
                'Summary cards show the figures that matter to your role. Select a card that has an arrow to open the records behind it.',
                '**Quick actions** are shortcuts to the tasks you carry out most often.',
              ],
            },
            {
              type: 'note',
              tone: 'info',
              title: 'Your dashboard matches your role',
              text: 'The layout is the same for everyone, but the cards, quick actions, alerts and charts change with your role. An administrator sees facilities, users and revenue, while a receptionist’s dashboard focuses on the front desk and a pharmacist’s on dispensing. Select an alert, such as **Facility Setup Pending**, to go straight to the records it refers to.',
            },
          ],
        },
        {
          id: 'find-a-screen-with-search-menu',
          title: 'Find a screen with Search menu',
          audience: 'Everyone',
          blocks: [
            {
              type: 'steps',
              figure: 'shell-search-menu',
              caption: 'Search menu narrows the menu as you type.',
              items: [
                'Select **Search menu** at the top of the menu and type part of the screen’s name, for example **lab**.',
                'Select the matching item. If nothing matches, the menu shows **No menu items found**. Check the spelling, or ask your administrator whether your role includes that screen.',
              ],
            },
            {
              type: 'note',
              tone: 'tip',
              title: 'Dictate instead of typing',
              text: 'The microphone icon in search boxes and text fields lets you speak instead of typing, where your device and browser allow microphone access.',
            },
          ],
        },
        {
          id: 'your-account-menu',
          title: 'Your account menu',
          audience: 'Everyone',
          blocks: [
            {
              type: 'steps',
              figure: 'shell-account-menu',
              caption: 'The account menu shows who is signed in and where.',
              items: [
                'Select your initials at the top right of the screen. The menu shows your name, email address, facility and roles.',
                '**Profile** opens your profile. See [Your profile and settings](#your-profile-and-settings).',
                '**Settings** opens your personal settings, such as the theme and accessibility options.',
                '**Change password** opens the form for choosing a new password.',
                '**Logout** signs you out of HOSSPI HMS.',
              ],
            },
            {
              type: 'note',
              tone: 'warning',
              title: 'Sign out of shared computers',
              text: 'Your session stays open until you sign out. Always select **Logout** before you leave a shared or public computer.',
            },
          ],
        },
        {
          id: 'working-with-lists',
          title: 'Working with lists',
          audience: 'Everyone',
          blocks: [
            {
              type: 'p',
              text: 'Most screens show records as a list, such as patients, invoices, staff or departments. Every list has the same tools, so once you know one list you know them all.',
            },
            {
              type: 'steps',
              figure: 'shell-list-tools',
              caption: 'The tools on a list, shown on the Departments tab of Tenant setup.',
              items: [
                'Type in the search box to show only matching records. The hint in the box tells you what you can search by.',
                '**Filters** narrows the list, for example by date, facility or status. Choose the values, then select **Apply filters**; **Clear filters** removes them. A number beside **Filters** shows how many filters are in use.',
                '**Settings** chooses the columns the list shows. Tick the columns you want and select **Apply columns**, or select **Reset columns** to return to the standard set.',
                '**Export** saves the list as a file. Choose the columns and filters to include, then select **Export**.',
                '**Print** prepares the list for printing.',
                'The create button adds a new record to the list, here **Create department**.',
                'Select a column heading to sort by that column, and select it again to reverse the order. Drag the edge of a heading to widen or narrow the column.',
                'Row actions work on a single record, for example **Edit** and **Delete**. On some lists you select the row itself to open the record.',
                'The count shows which records are on screen and how many there are in total. Scroll down or use the page arrows to see more, and select **Go to top** to return to the start.',
              ],
            },
          ],
        },
      ],
    },
    {
      id: 'setting-up-your-facility',
      title: 'Setting up your facility',
      summary:
        'Describe your organisation to HOSSPI HMS: its details, facilities, departments, wards, rooms and beds, the clinical services you offer, your default fees, and your subscription.',
      sections: [
        {
          id: 'open-tenant-setup',
          title: 'Open Tenant setup',
          audience: 'Administrators',
          blocks: [
            {
              type: 'p',
              text: 'HOSSPI HMS calls your organisation the **tenant**. A tenant can run several **facilities**, such as a hospital and a pharmacy, and each facility is organised into departments, units, wards, rooms and beds.',
            },
            {
              type: 'p',
              text: 'Select **Tenant setup** at the bottom of the menu. Facility administrators see **Facility setup** instead, which covers their own facility.',
            },
            {
              type: 'steps',
              figure: 'setup-tenant',
              caption: 'Tenant setup, open on the Tenant tab.',
              items: [
                'The tabs cover each part of your organisation, such as **Tenant**, **Facilities**, **Departments**, **Units**, **Wards**, **Rooms**, **Beds** and **Clinical Services**. The number on a tab shows how many records it holds.',
                '**More tabs** lists the tabs that do not fit on the screen, such as **Users**, **Roles** and **Permissions**.',
                '**Edit tenant** changes your organisation’s details. See [Update your organisation’s details](#update-your-organisations-details).',
                '**Tenant defaults** shows the currency and consultation fee used when a facility does not set its own.',
              ],
            },
            {
              type: 'note',
              tone: 'info',
              title: 'Set up from the top down',
              text: 'Add records in order: facilities first, then departments and units, then wards, rooms and beds. Each record is linked to the one above it, so a ward needs its facility, and a bed needs its ward.',
            },
          ],
        },
        {
          id: 'update-your-organisations-details',
          title: 'Update your organisation’s details',
          audience: 'Tenant administrators',
          blocks: [
            {
              type: 'p',
              text: 'On the **Tenant** tab, select **Edit tenant**.',
            },
            {
              type: 'steps',
              figure: 'setup-edit-tenant',
              caption: 'Edit tenant: your organisation’s details and defaults.',
              items: [
                'Check the **Tenant name**, the name of your organisation as it appears throughout HOSSPI HMS.',
                'Keep **Active** switched on. Staff can only work in an active organisation.',
                'Enter the **Contact name**, **Phone** and **Email** of the person to contact about the organisation.',
                'Choose the **Default currency** for prices and amounts at facilities that do not set their own.',
                'Enter the **Default consultation fee**, charged for new consultations when no practitioner fee is set.',
                'Select **Edit tenant** to save your changes.',
              ],
            },
            {
              type: 'note',
              tone: 'tip',
              text: '**Tenant slug** is an optional short name for your organisation. **Tenant ID** is assigned by HOSSPI HMS and cannot be changed.',
            },
          ],
        },
        {
          id: 'add-or-edit-a-facility',
          title: 'Add or edit a facility',
          audience: 'Tenant administrators',
          blocks: [
            {
              type: 'p',
              text: 'Select the **Facilities** tab, then **Create facility**. To change a facility that already exists, select **Edit** on its row instead.',
            },
            {
              type: 'steps',
              figure: 'setup-create-facility',
              caption: 'Create facility, completed with sample details.',
              items: [
                'Enter the **Facility name**.',
                'Choose the **Facility type**.',
                'Choose a **Default currency** if this facility prices services in a different currency from the tenant default.',
                'Enter a **Default consultation fee** if this facility charges a different fee from the tenant default.',
                'Select **Choose image** to add the facility’s logo: a JPG, PNG or WebP image of up to 5 MB. Crop it, then save.',
                'Enter the facility’s **Phone** number.',
                'Enter the facility’s **Email** address.',
                'Add the **Address line**, **City** and **Country** if you wish.',
                'Select **Save facility**.',
              ],
            },
            {
              type: 'note',
              tone: 'warning',
              title: 'Deleting a facility',
              text: 'Selecting **Delete** on a facility’s row affects everyone who works there. Agree the change with your team before you delete a facility.',
            },
          ],
        },
        {
          id: 'add-departments-and-units',
          title: 'Add departments and units',
          audience: 'Administrators',
          blocks: [
            {
              type: 'p',
              text: 'Departments group your services, for example Outpatient, Laboratory or Pharmacy. Units are the teams inside a department. Select the **Departments** tab, then **Create department**.',
            },
            {
              type: 'steps',
              figure: 'setup-create-department',
              caption: 'Create department.',
              items: [
                'Enter the **Department name**.',
                'Enter a **Department short name** if you want an abbreviation for places where space is limited.',
                'Choose the **Department type**.',
                'Keep **Active** switched on so the department can be used.',
                'Select **Create**.',
              ],
            },
            {
              type: 'p',
              text: 'To add a unit, select the **Units** tab, then **Create unit**. Complete the form, enter the **Unit name**, keep **Active** switched on and select **Create**.',
            },
          ],
        },
        {
          id: 'add-wards-rooms-and-beds',
          title: 'Add wards, rooms and beds',
          audience: 'Administrators',
          blocks: [
            {
              type: 'p',
              text: 'Wards, rooms and beds describe where patients stay. Admission and ward screens allocate patients to these beds, so set them up before you admit patients. Select the **Wards** tab, then **Create ward**.',
            },
            {
              type: 'steps',
              figure: 'setup-create-ward',
              caption: 'Create ward.',
              items: [
                'Choose the **Facility** the ward belongs to.',
                'Enter the **Ward name**.',
                'Choose the **Ward type**, for example **General**, **ICU**, **Maternity**, **Pediatric** or **Surgical**.',
                'Choose the **Department** that runs the ward, if you wish.',
                'Keep **Active** switched on.',
                'Select **Create**.',
              ],
            },
            {
              type: 'p',
              text: 'To add a room, select the **Rooms** tab, then **Create room**. Choose the **Facility** and enter the **Room name**. Choose the **Ward** the room is on, or leave it unassigned for an outpatient or department consulting room. Add the **Floor** if you wish, then select **Create**.',
            },
            {
              type: 'p',
              text: 'To add a bed, select the **Beds** tab, then **Create bed**.',
            },
            {
              type: 'steps',
              figure: 'setup-create-bed',
              caption: 'Create bed.',
              items: [
                'Choose the **Facility**.',
                'Enter the **Bed label** shown on the ward, for example **B12**.',
                'Choose the **Ward** the bed is on.',
                'Choose the **Room**, if the bed is in one.',
                'Choose the **Bed status**. New beds are usually **Available**.',
                'Select **Create**.',
              ],
            },
            {
              type: 'table',
              columns: ['Bed status', 'Meaning'],
              rows: [
                ['**Available**', 'Ready for a patient.'],
                ['**Occupied**', 'A patient is using the bed.'],
                ['**Reserved**', 'Held for a patient who is expected.'],
                ['**Cleaning**', 'Being cleaned before the next patient.'],
                ['**Maintenance**', 'Out of use while it is repaired.'],
                ['**Blocked**', 'Not to be used.'],
              ],
            },
          ],
        },
        {
          id: 'choose-your-clinical-services',
          title: 'Choose the clinical services you offer',
          audience: 'Administrators',
          blocks: [
            {
              type: 'p',
              text: 'The **Clinical Services** tab holds the catalogues that clinicians choose from when they order investigations or record a diagnosis. HOSSPI HMS comes with ready-made catalogues; you decide which items your facility offers. Open **More tabs** if **Clinical Services** is not visible.',
            },
            {
              type: 'steps',
              figure: 'setup-clinical-services',
              caption: 'Clinical Services, showing the radiology catalogue.',
              items: [
                'Choose a catalogue: **Radiology**, **Lab** or **Diagnoses**.',
                'Search the catalogue by name, code or category.',
                '**Configure** lists the catalogue so you can choose the items this facility offers. Tick the items and select **Next**, enter a **Unit price** for each item you chose, then select **Next** again to finish.',
                '**Create procedure** adds an item that is not in the catalogue. Enter its **Name**, an optional **Test code** and the **Modality**, then select **Save**. On the other catalogues this button is named after the kind of item it adds.',
              ],
            },
          ],
        },
        {
          id: 'set-default-fees-and-currency',
          title: 'Set default consultation fees and currency',
          audience: 'Administrators',
          blocks: [
            {
              type: 'p',
              text: 'Open **Settings** and select the **Configuration** tab.',
            },
            {
              type: 'steps',
              figure: 'settings-configuration',
              caption: 'Settings, Configuration tab.',
              items: [
                'Under **Tenant defaults**, enter the **Default consultation fee** for the whole organisation.',
                'Choose the currency beside the fee.',
                'Select **Save configuration**.',
                'Under **Facility defaults**, set a different fee or currency for the current facility if it charges differently, then select its **Save configuration**. Facility values override the tenant defaults.',
                '**Reset to default** clears the saved values in that section, after you confirm. Once a facility’s values are cleared, the tenant defaults apply to it again.',
              ],
            },
            {
              type: 'note',
              tone: 'info',
              text: 'The default consultation fee is used for new consultations when the practitioner has no fee of their own.',
            },
          ],
        },
        {
          id: 'renew-or-change-your-subscription',
          title: 'Renew or change your subscription',
          audience: 'Administrators',
          blocks: [
            {
              type: 'p',
              text: 'Your subscription package decides which areas of HOSSPI HMS your facility can use, and how many users and facilities it can have. Select the package badge at the top of the screen, for example **Pro**, to open the subscription window.',
            },
            {
              type: 'steps',
              figure: 'subscription-plans',
              caption: 'Comparing packages in the subscription window.',
              items: [
                'Choose **Monthly** or **Annual** billing.',
                'Compare the **Free**, **Basic**, **Advanced**, **Pro** and **Custom** packages by price, users, facilities, storage and the areas each one includes, then select the package you want. Your present package is marked **Current plan**.',
                'For **Custom**, select **Contact us** to agree pricing and contents with the HOSSPI team.',
                'Select **Next** and follow the steps: choose how you will pay, make the payment using the details shown, then send the payment reference and, if you have it, proof of payment.',
              ],
            },
            {
              type: 'p',
              text: 'The HOSSPI team checks the payment and activates the package. Until then, the window shows **Activation request in progress** and package changes are locked. Select **Cancel request** if you need to choose a different package. If a request is rejected, the window gives the reason, and you can select **Contact admins**.',
            },
            {
              type: 'note',
              tone: 'info',
              text: 'Moving to the **Free** package needs no payment. Confirm the change and the HOSSPI team applies it.',
            },
          ],
        },
      ],
    },
    {
      id: 'users-roles-and-permissions',
      title: 'Users, roles and permissions',
      summary:
        'Give every member of staff their own account, control what they can open and do through roles, and keep access up to date as people join, change jobs and leave.',
      sections: [
        {
          id: 'how-access-works',
          title: 'How access works',
          audience: 'Administrators',
          blocks: [
            {
              type: 'p',
              text: 'Every member of staff signs in with their own account. What each person can open and do is decided by three things together:',
            },
            {
              type: 'list',
              items: [
                '**Your subscription package** sets which areas of HOSSPI HMS your organisation can use at all.',
                '**Roles** bundle the permissions a job needs, such as **Receptionist**, **Nurse** or **Accountant**. HOSSPI HMS comes with ready-made roles, and you can create your own.',
                '**Direct permissions** give one extra permission to one person, for exceptions.',
              ],
            },
            {
              type: 'p',
              text: 'Everything a person’s roles and direct permissions allow, within your package, makes up their **effective permissions**.',
            },
            {
              type: 'note',
              tone: 'tip',
              title: 'Give people the access their job needs',
              text: 'Assign the role that matches each job and keep direct permissions for rare exceptions. Review a person’s access whenever they change jobs or leave.',
            },
          ],
        },
        {
          id: 'open-access-administration',
          title: 'Open access administration',
          audience: 'Administrators',
          blocks: [
            {
              type: 'p',
              text: 'On your **Dashboard**, select **Manage users** or **Manage roles and permissions** under **Quick actions**. The same lists are also on the **Users** and **Roles** tabs of **Tenant setup**.',
            },
            {
              type: 'steps',
              figure: 'access-user-directory',
              caption: 'Access administration, User directory tab.',
              items: [
                'The tabs: **User directory** lists staff accounts, **Roles** lists roles, **Permissions** describes every permission, and **Module entitlements** shows the areas your package includes.',
                '**Create staff** adds a staff account. See [Create a staff account](#create-a-staff-account).',
                'Search by name, email address, role or permission.',
                'Select a staff member’s row to open their record.',
              ],
            },
          ],
        },
        {
          id: 'create-a-staff-account',
          title: 'Create a staff account',
          audience: 'Administrators',
          blocks: [
            {
              type: 'p',
              text: 'On the **User directory** tab, select **Create staff**.',
            },
            {
              type: 'steps',
              figure: 'access-create-staff',
              caption: 'Create staff, completed with sample details.',
              items: [
                'Choose the **Facility** the person works at. Leave it blank to give them access across every facility in the organisation.',
                'Enter their **First name** and, if you wish, their **Last name**.',
                'Enter their **Email** address. They sign in with it.',
                'Enter their **Phone** number if you wish. They can sign in with it too.',
                'Enter their **Position title**, for example Registered Nurse.',
                'Leave **Status** as **Active** so they can sign in.',
                'Set a starting **Password** of at least 8 characters, with an upper-case letter, a lower-case letter, a number and a symbol.',
                'When you have chosen the person’s roles, as described below, select **Save**.',
              ],
            },
            {
              type: 'p',
              text: 'Scroll down to **Roles** in the same form.',
            },
            {
              type: 'steps',
              figure: 'access-create-staff-roles',
              caption: 'Choosing roles for a new staff account.',
              items: [
                'Type part of a role’s name in **Search roles**, for example nurse.',
                'Tick each role the person needs. The figure under each role is the number of permissions it grants.',
                'Select **Save**.',
              ],
            },
            {
              type: 'note',
              tone: 'warning',
              title: 'Share the starting password safely',
              text: 'Give the starting password to the person privately, never in a group message, and ask them to change it after they first sign in. See [Change your password](#change-your-password).',
            },
          ],
        },
        {
          id: 'review-and-change-a-staff-account',
          title: 'Review and change a staff account',
          audience: 'Administrators',
          blocks: [
            {
              type: 'p',
              text: 'Select a staff member in the **User directory** to open their record.',
            },
            {
              type: 'steps',
              figure: 'access-staff-record',
              caption: 'A staff record.',
              items: [
                'The account details: ID, email address, phone, position title and status.',
                '**Assigned roles** lists the person’s roles and how many permissions each one grants. Select **Add role** to assign another role, or remove a role to take away its permissions.',
                '**Direct permissions** lists permissions given to this person alone. Select **Add permission** only for a one-off exception.',
                '**Effective permissions** shows everything the person can do, grouped by area. Search it to check whether they have a particular permission.',
              ],
            },
            {
              type: 'p',
              text: 'Depending on the account, these actions are also available:',
            },
            {
              type: 'table',
              columns: ['Action', 'What it does'],
              rows: [
                ['**Edit staff**', 'Change the person’s name, contact details, position title or status.'],
                ['**Deactivate staff**', 'Stop the person signing in, for example when they leave. **Activate staff** gives access back.'],
                ['**Send password reset email**', 'Email the person a single-use link to choose a new password. Their current password keeps working until they use the link, and all their signed-in sessions end when they do.'],
                ['**Delete staff**', 'Remove an account created by mistake. Deactivate staff who leave instead.'],
                ['**Open HR profile**', 'Open the person’s staff profile in Human resources.'],
              ],
            },
            {
              type: 'note',
              tone: 'info',
              text: 'Protected accounts that the organisation depends on cannot be deleted.',
            },
          ],
        },
        {
          id: 'create-a-custom-role',
          title: 'Create a custom role',
          audience: 'Administrators',
          blocks: [
            {
              type: 'p',
              text: 'Create a role when none of the ready-made roles fits a job. Select the **Roles** tab.',
            },
            {
              type: 'steps',
              figure: 'access-roles-list',
              caption: 'The Roles tab.',
              items: [
                'Select **Create role** to start a new role.',
                'Select a role to see the permissions it grants and the staff who have it. Select **Edit permissions** to change what it grants.',
              ],
            },
            {
              type: 'steps',
              figure: 'access-create-role',
              caption: 'Create role, completed with sample details.',
              items: [
                'Under **Scope**, choose **Tenant(s)** for a role used across the organisation, or **Facility(ies)** for a role used at particular facilities.',
                'Tick the organisation or facilities the role applies to.',
                'Enter a **Role name**: a short, unique name such as FRONT_DESK_SUPERVISOR.',
                'Enter the **Display name** that staff see.',
                'Describe what the role is for in **Description**.',
                'Choose the permissions the role grants, then select **Save**.',
              ],
            },
            {
              type: 'note',
              tone: 'warning',
              title: 'Deleting a role',
              text: '**Delete role** detaches the role from every staff member who has it. The role stays in the list, so you can restore it later.',
            },
          ],
        },
        {
          id: 'look-up-permissions-and-entitlements',
          title: 'Look up permissions and module entitlements',
          audience: 'Administrators',
          blocks: [
            {
              type: 'p',
              text: 'The **Permissions** tab lists every permission with its name, description and code, for example **Patient — Read**, which allows read access to patient records. Search it when you need to know exactly what a permission allows.',
            },
            {
              type: 'p',
              text: 'The **Module entitlements** tab shows the areas of HOSSPI HMS that your subscription package includes. If staff need an area your package does not include, see [Renew or change your subscription](#renew-or-change-your-subscription).',
            },
          ],
        },
      ],
    },
    {
      id: 'your-profile-and-settings',
      title: 'Your profile and settings',
      summary:
        'Settings that belong to you: the theme, accessibility options, your profile and password, leave requests and your roster.',
      sections: [
        {
          id: 'open-settings',
          title: 'Open Settings',
          audience: 'Everyone',
          blocks: [
            {
              type: 'p',
              text: 'Select **Settings** in the menu, or select your initials at the top right and then **Settings**. The tabs you see depend on your role.',
            },
            {
              type: 'steps',
              figure: 'settings-preferences',
              caption: 'Settings, open on the Preferences tab.',
              items: [
                'The tabs group your settings, for example **Preferences**, **Accessibility**, **Account and security**, **Leaves** and **Rosters**. Select a tab to open it.',
                'Under **App theme**, choose **System** to follow your device’s setting, **Light** or **Dark**.',
              ],
            },
          ],
        },
        {
          id: 'make-the-screen-easier-to-read',
          title: 'Make the screen easier to read',
          audience: 'Everyone',
          blocks: [
            {
              type: 'p',
              text: 'Select the **Accessibility** tab.',
            },
            {
              type: 'steps',
              figure: 'settings-accessibility',
              caption: 'Settings, Accessibility tab.',
              items: [
                'Switch on **Reduce motion** for simpler transitions and fewer animations.',
                'Switch on **Bold text** to make text heavier and easier to read.',
                'Choose a **Text size** to make text larger or smaller throughout HOSSPI HMS.',
              ],
            },
          ],
        },
        {
          id: 'view-and-update-your-profile',
          title: 'View and update your profile',
          audience: 'Everyone',
          blocks: [
            {
              type: 'p',
              text: 'Select your initials and then **Profile**, or select the **Account and security** tab in Settings.',
            },
            {
              type: 'steps',
              figure: 'settings-account',
              caption: 'Settings, Account and security tab.',
              items: [
                '**Change password** lets you choose a new password. See [Change your password](#change-your-password).',
                '**Edit profile** updates your **First name**, **Middle name**, **Last name** and **Gender**. Select **Save** when you have finished.',
                '**Account** shows your email address, phone number, user ID and account status.',
                '**Professional details** shows your role, user type, title, organisation, facility and staff number.',
                '**Assigned roles** lists the roles on your account, which decide what you can open and do.',
              ],
            },
            {
              type: 'note',
              tone: 'info',
              text: 'Your email address, phone number, title and roles are managed by your administrator. Ask them if any of these need to change.',
            },
          ],
        },
        {
          id: 'change-your-password',
          title: 'Change your password',
          audience: 'Everyone',
          blocks: [
            {
              type: 'p',
              text: 'Select your initials and then **Change password**, or select **Change password** on the **Account and security** tab.',
            },
            {
              type: 'steps',
              figure: 'settings-change-password',
              caption: 'Change password.',
              items: [
                'Enter your **Current password**.',
                'Enter a **New password** of at least 8 characters. Mixing upper- and lower-case letters, numbers and symbols makes it harder to guess.',
                'Enter the new password again in **Confirm password**.',
                'Select **Change password**.',
              ],
            },
            {
              type: 'p',
              text: 'If you are asked to sign in again, use your new password. Forgotten your current password? Sign out and follow [Reset a forgotten password](#reset-a-forgotten-password).',
            },
          ],
        },
        {
          id: 'request-leave',
          title: 'Request leave',
          audience: 'Staff',
          blocks: [
            {
              type: 'p',
              text: 'Select the **Leaves** tab in Settings, then **Request leave**.',
            },
            {
              type: 'steps',
              figure: 'settings-request-leave',
              caption: 'Request leave.',
              items: [
                'Choose the **Leave type**.',
                'Enter the **Start date**.',
                'Tick **Half-day leave** if you will be away for a single morning or afternoon.',
                'Enter the **End date**.',
                'Add a **Reason** if you wish.',
                'Select **Request leave**.',
              ],
            },
            {
              type: 'p',
              text: 'Your request joins the list on the **Leaves** tab with its status. Use **All**, **Pending**, **Approved**, **Rejected** and **Cancelled** to choose which requests you see.',
            },
          ],
        },
        {
          id: 'view-your-roster',
          title: 'View your roster',
          audience: 'Staff',
          blocks: [
            {
              type: 'p',
              text: 'Select the **Rosters** tab in Settings to see the shifts assigned to you. Choose the period to show: **Today**, **Tomorrow**, **This week**, **This month**, **Last month**, **Next month** or **Next 3 months**, or select **Custom range** and pick your own dates.',
            },
          ],
        },
      ],
    },
    {
      id: 'troubleshooting-and-getting-help',
      title: 'Troubleshooting and getting help',
      summary:
        'Answers to common problems, the meaning of the terms used in HOSSPI HMS, and how to reach the HOSSPI team.',
      sections: [
        {
          id: 'common-problems',
          title: 'Common problems',
          audience: 'Everyone',
          blocks: [
            {
              type: 'table',
              columns: ['Problem', 'What to do'],
              rows: [
                ['I cannot sign in.', 'Check that you chose **Email** or **Phone** correctly under **Sign in with**, and that Caps Lock is off. If you have forgotten your password, select **Reset password**. If your account is new, ask your administrator to check that it is **Active**.'],
                ['The sign-in screen says **Account pending approval**.', 'Your facility is waiting for approval from HOSSPI. Contact one of the platform administrators listed in the message.'],
                ['A menu item, tab or button in this manual is missing on my screen.', 'Your role, or your organisation’s subscription package, does not include it. Ask your administrator to check your roles and the package.'],
                ['A list does not show a record I expect.', 'Clear the search box, then select **Filters** and **Clear filters**. Check that the record belongs to your facility.'],
                ['A form will not save.', 'Look for fields highlighted with a message beneath them. Fields marked with an asterisk (*) must be completed.'],
                ['The connection indicator shows **Offline**.', 'Check your internet connection, and wait until it shows **Online** again before you continue working.'],
                ['I see a message that the subscription has expired.', 'Ask an administrator to renew it. See [Renew or change your subscription](#renew-or-change-your-subscription).'],
                ['I cannot find a screen.', 'Type part of its name in **Search menu**. See [Find a screen with Search menu](#find-a-screen-with-search-menu).'],
                ['Text is too small to read comfortably.', 'Increase the **Text size** or switch on **Bold text**. See [Make the screen easier to read](#make-the-screen-easier-to-read).'],
              ],
            },
          ],
        },
        {
          id: 'glossary',
          title: 'Glossary',
          audience: 'Everyone',
          blocks: [
            {
              type: 'table',
              columns: ['Term', 'Meaning'],
              rows: [
                ['**Tenant**', 'Your organisation as a whole, including all its facilities.'],
                ['**Facility**', 'A hospital, clinic, laboratory or pharmacy that belongs to your organisation.'],
                ['**Department** and **unit**', 'A department groups related services, such as the laboratory. A unit is a team within a department.'],
                ['**Ward**, **room** and **bed**', 'The places where admitted patients stay. A ward contains rooms and beds.'],
                ['**Role**', 'A named set of permissions for a job, such as Receptionist or Nurse.'],
                ['**Permission**', 'One thing a person is allowed to see or do, such as reading patient records.'],
                ['**Module**', 'An area of HOSSPI HMS, such as Laboratory or Billing. Your subscription package decides which modules you can use.'],
                ['**Patient registry**', 'The list of every patient registered at your organisation.'],
                ['**MRN**', 'Medical Record Number: the number that identifies a patient’s record.'],
                ['**Encounter**', 'One visit or episode of care, from the patient’s arrival until the visit is completed.'],
                ['**OPD**', 'Outpatient department: care for patients who are not admitted.'],
                ['**IPD**', 'Inpatient department: care for patients admitted to a ward.'],
                ['**ICU**', 'Intensive care unit.'],
                ['**Triage**', 'Deciding how urgently a patient needs care, usually with their vital signs.'],
                ['**Vitals**', 'Measurements such as blood pressure, temperature, pulse, breathing rate, oxygen saturation, weight and height.'],
                ['**Disposition**', 'The decision at the end of a consultation, such as sending the patient home, admitting them or referring them.'],
                ['**Order** or **request**', 'A request for a laboratory test, imaging study or medicine made during an encounter.'],
                ['**Formulary**', 'The medicines your facility has approved for use.'],
                ['**Price book**', 'The prices your facility charges for services and items.'],
                ['**Invoice**', 'A bill for the services a patient received.'],
                ['**Pre-authorisation**', 'An insurer’s approval for a service before it is provided.'],
                ['**Claim**', 'A request to an insurer to pay for the services a patient received.'],
                ['**Journal**', 'An accounting entry recorded in your books.'],
                ['**Fiscal period**', 'An accounting period, such as a month, that can be closed once its books are complete.'],
                ['**Roster**', 'The schedule of shifts assigned to staff.'],
              ],
            },
          ],
        },
        {
          id: 'getting-help',
          title: 'Getting help',
          audience: 'Everyone',
          blocks: [
            {
              type: 'p',
              text: 'Start with your facility administrator, who manages your account, your roles and your facility’s settings.',
            },
            {
              type: 'p',
              text: 'For help with registration, your subscription or anything your administrator cannot resolve, contact the HOSSPI team:',
            },
            {
              type: 'list',
              items: [
                `Email: **${CONTACT_EMAIL}**`,
                `Phone and WhatsApp: **${COMPANY_PHONE}**`,
                'Website: **www.hosspi.com/contact**',
              ],
            },
            {
              type: 'note',
              tone: 'tip',
              title: 'Report a problem clearly',
              text: 'Tell us your facility’s name, the screen you were using, what you expected to happen, what happened instead and roughly when. A screenshot helps.',
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
