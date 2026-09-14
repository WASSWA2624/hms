# Feedback device context (20260914130000)

## Affected tables

- `feedback` (altered): records the screen size each submission came from.
  - `device_type` (`MOBILE`, `TABLET`, `DESKTOP`, nullable, indexed): the size
    class of the app window, using the app's breakpoints: `MOBILE` below 600
    logical px, `TABLET` 600-1199, `DESKTOP` 1200 and up. The client sends it;
    when a client sends only a viewport, the API derives it from the width.
  - `viewport_width`, `viewport_height`: the app window in logical pixels.
  - `screen_width`, `screen_height`: the whole display in logical pixels, so a
    narrow browser window on a desktop monitor can be told apart from a phone.
  - The device pixel ratio and orientation stay in `client_context_json`.
- Rows created before this migration keep `NULL` in the new columns.

## Deployment

1. Apply migration `20260914130000_feedback_device_context`
   (`npm run prisma:migrate:deploy`) after `20260914120000_feedback`.
2. Deploy application code.
3. Verify a submission from a phone-width window stores `device_type = 'MOBILE'`
   and the download shows Device Type, Viewport (px), and Display (px).

## Recovery

Forward-only and additive. To roll back, add
`rollback_20260914130000_feedback_device_context` dropping index
`feedback_device_type_idx` and the five columns; no other data is affected.
