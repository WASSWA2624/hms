### Feedback Submission and Management

Implement a **“Give Us Feedback”** floating button that is available throughout the application on **all screens, including authentication screens**.

When the user opens the feedback form and clicks **Submit**, the system must save the submitted feedback together with sufficient contextual information to accurately identify and understand the reported problem, complaint, suggestion, or area for improvement.

#### 1. Feedback information to be recorded

Each feedback submission should capture:

* Feedback/problem/complaint/improvement details entered in the feedback dialog.
* User email, where the user is authenticated.
* User identity/account information, where available.
* Tenant.
* Facility.
* Subscription/plan.
* Screen/page URL or route from which the feedback was submitted.
* Date and time of submission.
* User role and relevant permissions, where available.
* Any other contextual or technical information necessary to reproduce, investigate, and resolve the issue.

For users who are **not authenticated or cannot be identified**, the feedback must still be accepted and recorded as **Anonymous**. The system should retain any non-sensitive contextual information that is available.

#### 2. Feedback storage

Create a dedicated **Feedback table/database structure** for storing all feedback submissions.

The feedback storage mechanism must:

* Accept submissions from **any user**, whether authenticated or unauthenticated.
* Automatically append each new feedback record without overwriting previous submissions.
* Store all required metadata and contextual information associated with the submission.
* Use appropriate timestamps and unique identifiers for each feedback record.
* Support future querying, filtering, reporting, downloading, and administrative management.

The Feedback table/database should be treated as the **system of record** for feedback.

#### 3. Excel download

Provide a **Download Feedback** function that is accessible **only to Platform Admins and Owner Admins**.

When triggered, the system must export the currently stored feedback records into an **Excel (.xlsx)** file.

The downloaded file must use the following naming convention:

`HOSSPI-FEEDBACK-[DDMMYYYY-HHmmss].xlsx`

The timestamp must use the **24-hour format**.

Example:

`HOSSPI-FEEDBACK-14092026-143527.xlsx`

The export should contain all relevant feedback fields and preserve the information required for analysis and follow-up.

#### 4. Feedback administration controls

For users logged in with the **Platform Admin** or **Owner Admin** role, the floating feedback control should provide:

**Give Us Feedback** — Opens the feedback submission form.

**Download Feedback** — Downloads the stored feedback as an `.xlsx` file. This option must not be visible or accessible to unauthorized roles.

**Clear Feedback** — Provides an administrative function to clear/delete stored feedback. This action should require an appropriate confirmation step to prevent accidental deletion.

For all other users, only **Give Us Feedback** should be available.

#### 5. Availability and security

The **Give Us Feedback** function must work regardless of whether the user is logged in.

Authenticated submissions should automatically include the user's available account, tenant, facility, subscription, role, and other relevant context.

Unauthenticated submissions should be recorded anonymously while still capturing the available technical and page-level context.

The backend must enforce authorization for administrative functions such as **Download Feedback** and **Clear Feedback**; these permissions must not rely solely on hiding the buttons in the user interface.

#### 6. Implementation scope

This functionality should be implemented consistently across the entire application, including:

* Authentication screens.
* Dashboard screens.
* Facility and tenant management screens.
* Clinical, financial, HR, pharmacy, reporting, and analytics screens.
* Any future application screens added to the system.

The feedback mechanism should automatically identify the current screen/route and capture the relevant context without requiring the user to manually enter information that the system already knows.
