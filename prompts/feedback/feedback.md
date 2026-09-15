# FEEDBACK PROMPTS GENERATOR

Use the **feedback workbook** in this folder as the **source of truth** to generate prompts for implementing/fixing all feedback mentioned in the **feedback workbook**.

First, read all repository rules:

- [project rules](.cursor)
- [backend rules](backend.cursor)
- [frontend rules](frontend.cursor)
- [app-write-up](.cursor/app-write-up.mdc)

Then analyze **all rows in the workbook before creating any prompts**.

Use all relevant Excel columns available in the workbook to understand each issue. These include:

Feedback ID, Submitted At (Africa/Kampala), Submitted At (UTC), Category, Feedback, Submitted By, User Email, User Name, User ID, Position Title, Roles, Permissions, Tenant, Tenant ID, Facility, Facility ID, Subscription Plan, Plan Code, Plan Tier, Subscription Status, Screen, Route, Route Name, Page URL, Platform, Device Type, App Version, Environment, Locale, Time Zone, Viewport (px), Display (px), Orientation, Breakpoint, Theme, Text Scale, Connectivity, Device Clock (UTC), User Agent, IP Address

The data collected from the Excel workbook is intended to provide enough context to fix/resolve each feedback.

### Consolidate

Identify duplicates, dependencies, common root causes, and cross-cutting changes.

**Merge feedback that can be resolved by the same implementation into one task.** Do not create separate prompts for related feedback.

Then order the consolidated tasks chronologically while respecting technical dependencies.

### Generate files

Create:

```text
prompts/feedback/(files).md
```

Generate:

```text
000-index.md
001-<implementation-task>.md
002-<implementation-task>.md
...
```

`000-index.md` should show:

- The implementation order
- Task titles
- The feedback items/IDs covered by each task

Each numbered file must be a **ready-to-use, context-aware, actionable, and specific coding-agent implementation prompt** containing:

- Objective
- Feedback covered and relevant Excel details
- Affected screen/feature/context
- Required behavior
- Implementation constraints from project rules and `app-write-up.md`
- Verification/tests
- Dependencies on other prompts, where applicable

Every Excel feedback item must be accounted for as **covered, merged, already resolved/no change required, or blocked**.

**Do not modify application source code. Only generate/update the prompt files.**