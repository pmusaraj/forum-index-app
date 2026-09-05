# Topic contribution implementation

## Goal

Let every app installation submit useful/not-useful signals. Keep bookmarks local and unrestricted. Treat new contributors as public; let an administrator promote a named installation to trusted. Use Apple DeviceCheck on iOS as abuse friction, not proof of a person.

## Contract

### Enrollment

`POST /api/v2/installations`

Request:

```json
{
  "display_name": "Penar",
  "device_name": "iPhone",
  "devicecheck_token": "optional base64 token"
}
```

Response (`201`):

```json
{
  "token": "private bearer token",
  "installation": {
    "public_id": "A7K-29Q",
    "display_name": "Penar",
    "device_name": "iPhone",
    "device_verified": true,
    "trusted": false
  }
}
```

The bearer token remains the only signal credential and is stored in Keychain. Names and device labels are display metadata, never authorization. macOS and iOS DeviceCheck failures still enroll as public/unverified so contributions are not gated by Apple availability.

The server validates DeviceCheck tokens only when Apple credentials are configured. It uses Apple bit 0 to record whether that physical device has enrolled before and stores `device_reused` as an abuse-review hint. DeviceCheck does not expose a stable device identifier, so the server-generated `public_id` identifies the installation shown to users/admins.

### Installation status

`GET /api/v2/installation` with the bearer token returns current metadata and trust state. The app refreshes this when opening Topic Signals settings.

### Signals

Keep the existing authenticated `PUT /api/v2/topics/:id/signal` endpoint and three-state behavior (`1`, `-1`, `0`). Store every public and trusted signal. Ranking/admin queries expose public and trusted aggregates separately.

## Backend work

1. Add installation metadata: `public_id`, `display_name`, `device_name`, `device_verified`, `device_reused`, `trusted`.
2. Add minimal stdlib DeviceCheck HTTP/JWT client; no new gem.
3. Replace invite-only enrollment with public installation enrollment while retaining the old invite endpoint temporarily for installed-version compatibility.
4. Add bearer-authenticated installation status.
5. Add an admin installations page with Trust/Untrust/Revoke actions and audit actor/timestamps.
6. Publish separate public/trusted signal totals to ranking/admin output without discarding either tier.
7. Test validation, token secrecy, DeviceCheck outcomes, admin authorization/actions, status, and aggregates.

## Apple work

1. Add a small `DCDevice` token provider on iOS and an unavailable provider on macOS.
2. Replace invite entry with name enrollment, installation code, verification state, and public/trusted status.
3. Keep useful/not-useful controls always visible; a locked tap opens Topic Signals settings.
4. Keep Bookmark, Share, Safari, and Close in the same compact topic action bar.
5. Preserve optimistic signal toggle/clear/switch and local bookmarks.
6. Test transport, store state, fallback enrollment, locked routing, signal toggles, bookmarks, and accessibility.

## Verification and shipping

- Rails focused/full tests, RuboCop, Brakeman.
- iOS/macOS focused/full tests and builds.
- Real Simulator visual QA against production data.
- Independent spec review, then code-quality review; fix all P1/P2 findings.
- Commit and push both repositories.
- Deploy an immutable backend image with backup/rollback, migrate, recreate, and verify public endpoints plus running revision.
- Build/sign/install/launch/read back on the trusted iPhone 17 Pro Max.

## Deliberate limits

- No App Attest or per-vote signatures.
- No account system, name verification, recovery flow, weighting formula, or synced identity.
- DeviceCheck credentials are operational configuration and are never committed.
