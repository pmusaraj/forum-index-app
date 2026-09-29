# Feedback API contract

The app has a Settings → Send feedback form with one plain-text message field.
No categories, attachments, or contact fields. Unsent text stays in local preferences.
Nothing is transmitted until Send is pressed. App/OS versions accompany the message;
the existing installation token is required.
Opted-out readers must enable contributions before submitting. The form explains this before sending.

## Request

`POST /api/v2/feedback`, JSON, required `Authorization: Bearer <installation token>`.

```json
{
  "request_id": "94E2D624-DDB0-420A-BFAD-9B7E32C761AA",
  "message": "Please add search for saved topics.",
  "app_version": "1.0.0",
  "app_build": "18",
  "platform": "ios",
  "os_version": "Version 26.0 (Build 23A344)"
}
```

- Trim surrounding whitespace; require 1–1,000 Unicode scalar values in `message`.
- Require a valid UUID `request_id`. Enforce a database unique constraint on its
  canonical value. Retries of the same message/ID return success without creating
  a duplicate. A reused ID with different message content returns 409. Version
  metadata or authentication may differ on a retry after an app update or expired
  credential; neither should create a duplicate or overwrite the original record.
- Accept `platform` values `ios` and `macos`; bound each version string to 200 characters.
  Do not interpret version strings as trusted identifiers.
- With valid credentials, derive the installation link server-side. Missing, invalid, or revoked credentials return 401; do not
  silently attribute the submission to a different installation. No trusted status
  is required. Feedback does not enroll anyone or affect ranking/read counts.
- Use existing rate-limiting infrastructure with both installation and IP
  limits, a bounded request body, and 429 plus `Retry-After`. Apply limits to new
  submissions; an idempotent retry should not consume another submission quota.

## Responses

Return 201 only after the message is durably stored; 200 for an idempotent retry.
A body such as `{"status":"received"}` is sufficient. Do not return feedback
contents or internal contributor details on duplicate requests.

Use 400/422 for validation, 401 for invalid credentials, 409 for request ID conflicts,
413 for oversized bodies, 429 for throttling, and 503 for temporary unavailability.
The app retains the draft and request ID on all failures; edits generate a new ID.
404/405/501/503 display an unavailable message while the endpoint is rolling out.
Only a successful response clears the submitted draft and shows confirmation.
There is no automatic background retry.

## Suggested storage

Use a `feedback` table with:

| Field | Type / constraint |
| --- | --- |
| `id` | Internal primary key |
| `request_id` | UUID, not null, unique |
| `installation_id` | Nullable foreign key; set null if installation is deleted |
| `message` | Text, not null, 1–1,000 Unicode scalars after trimming |
| `app_version`, `app_build`, `os_version` | Strings, each at most 200 characters |
| `platform` | `ios` or `macos` |
| `status` | `new` (default), `reviewed`, or `archived` |
| `created_at`, `updated_at` | Server timestamps |

Index `(status, created_at)` for the inbox. Use an atomic insert and the UUID unique
constraint for deduplication, rather than only checking before insertion. Retain the
original message, attribution, and metadata when handling retries. Do not let the
client supply installation IDs, status, or timestamps.

## Administration

Provide an admin-only inbox using the server's existing admin conventions. Show
message, received time, optional installation link, and app/OS versions. Support
new/reviewed/archived status, pagination, and deletion. Render message text escaped;
never treat it as HTML or Markdown. Do not expose a public list/read endpoint or log
auth headers or full message bodies. Apply the existing feedback/data-retention policy,
or document the chosen policy if none exists. Do not send messages or notifications
to external services as part of this implementation.

Test authenticated creation and rejection of missing credentials, validation boundaries (including Unicode),
revoked credentials, concurrent duplicate submissions, mismatched message reuse,
rate limits, escaped admin rendering, and admin authorization.
