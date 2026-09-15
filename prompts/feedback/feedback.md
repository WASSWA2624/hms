# FEEDBACK PROMPTS GENERATOR

Use the **feedback workbook** in this folder as the source of truth to generate prompts to implement/fix all the feedbacks mentioned in the **feedback workbook**.

First read all the repository rules ([project rules](.cursor), [backend rules](backend\.cursor), [frontend rules](frontend\.cursor)) and [app-write-up](.cursor\app-write-up.mdc)`, then analyze **all rows in the workbook before creating any prompts**.

Use all relevant Excel columns available in the workbook to understand each issue, especially fields such as:

- Feedback/Issue/Description
- Date/Time
- Category
- User/Reporter
- Role/Permissions
- Tenant/Facility
- Screen/Page/URL
- Platform/Device
- App Version
- Environment
- Status/Priority
- Reproduction or diagnostic details

Adapt to the actual column names and available data; do not assume these exact columns exist.

### Consolidate

Identify duplicates, dependencies, common root causes, and cross-cutting changes.

**Merge feedback that can be resolved by the same implementation into one task.** Do not create separate prompts for related feedback.

Then order the consolidated tasks chronologically, while respecting technical dependencies.

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

`000-index.md` should show the implementation order, task titles, and the feedback items/IDs covered by each task.

Each numbered file must be a **ready-to-use coding-agent implementation prompt** containing:

- Objective
- Feedback covered and relevant Excel details
- Affected screen/feature/context
- Required behavior
- Implementation constraints from project rules and `app-write-up.md`
- Verification/tests
- Dependencies on other prompts, where applicable

Every Excel feedback item must be accounted for as **covered, merged, already resolved/no change required, or blocked**.

**Do not modify application source code. Only generate/update the prompt files.**
