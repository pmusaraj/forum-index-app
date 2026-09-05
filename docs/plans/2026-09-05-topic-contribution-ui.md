# Topic Contribution UI Implementation Plan

> **For Hermes:** Use subagent-driven-development skill to implement this plan task-by-task.

**Goal:** Make topic bookmarking and useful/not-useful ranking actions obvious, and let an unapproved reader request anonymous ranking access from the Apple app.

**Architecture:** Keep bookmarks local and reuse the existing `Bookmark`, `SignalStore`, invite redemption, and topic-signal APIs. Add one approval queue to the Rails app. A newly issued 43-character request token is stored only in the requesting device's Keychain and as a SHA-256 digest on the server; approval creates an enabled `Installation` with the same digest, so the request token becomes the bearer credential without email, raw-secret persistence, or a fragile one-time handoff.

**Tech Stack:** SwiftUI, Observation, URLSession, Keychain Services, Rails 8.1, PostgreSQL, Minitest, XCTest/XCUITest. No new dependencies.

---

## Product decisions

- Keep the existing manual invite-code field for codes shared out of band.
- Add **Request an invite** beneath it. Ask only for a display name; derive a coarse platform label (`iPhone`, `iPad`, or `Mac`) in the app.
- An approved request enables ranking on that device automatically the next time the screen checks status. Do not reveal or email a literal code.
- Check status when the contribution screen opens and when the user taps **Check status**. No timers, push notifications, accounts, or email delivery.
- Bookmarking never requires approval.
- Useful/not-useful buttons remain visible to everyone. For an unapproved reader, tapping either opens the contribution-access screen instead of silently doing nothing.
- One signal per device/topic: useful, not useful, or cleared. Tapping the selected choice clears it; tapping the opposite choice switches it.

## Target interaction

### Topic reader bottom bar

`Useful | Not useful | Bookmark | Share | Safari | Close`

- Use native SF Symbols and 44×44 tap targets.
- Put the three contribution actions first.
- Use filled/tinted icons for selected useful, selected not useful, and bookmarked states.
- Keep optimistic signal updates and rollback errors from `SignalStore`.
- If ranking access is absent, show unselected thumbs with an accessibility hint that approval is required; a tap presents **Contribute to rankings**.

### Contribute to rankings screen

1. Short explanation: “Help improve topic rankings with anonymous useful and not useful votes.”
2. If enrolled: enabled status and **Remove access**.
3. If not enrolled: existing secure invite-code field and **Enable topic rankings**.
4. Divider/secondary section: **Request an invite** with display-name field and **Request access**.
5. Pending: “Waiting for review,” request date, and **Check status**.
6. Declined/revoked: plain status, existing manual code field, and **Request again**.

---

## Task 1: Add the server-side access-request lifecycle

**Objective:** Persist anonymous approval requests and bind approval to the exact opaque credential held by the requesting device.

**Backend files:**
- Create: `db/migrate/20260905170000_create_signal_access_requests.rb`
- Create: `app/models/signal_access_request.rb`
- Test: `test/models/signal_access_request_test.rb`

**Step 1: Write failing model tests**

Cover:

```ruby
request, token = SignalAccessRequest.issue!(
  name: "Penar",
  device_model: "iPhone",
  request_ip: "127.0.0.1"
)

assert_equal 43, token.length
assert_equal Digest::SHA256.hexdigest(token), request.request_token_digest
refute_includes request.attributes.values, token

installation = request.approve!(users(:one))
assert_equal request.request_token_digest, installation.token_digest
assert request.reload.approved?
assert_equal users(:one), request.approved_by
assert request.approved_at
assert_equal installation, request.approve!(users(:one))
```

Also test decline, revoke, invalid transition rejection, trimmed name/device values, length limits, and concurrent/double approval producing exactly one installation.

**Step 2: Verify RED**

```bash
RBENV_VERSION=ruby-3.4.9 rbenv exec bundle exec rails test test/models/signal_access_request_test.rb
```

Expected: failure because `SignalAccessRequest` does not exist.

**Step 3: Add the minimal schema**

Create `signal_access_requests` with:

- `name`, maximum 100, non-null;
- `device_model`, maximum 40, non-null;
- `request_token_digest`, 64 characters, non-null, unique;
- `request_ip_digest`, 64 characters, non-null;
- status: `pending`, `approved`, `declined`, or `revoked`;
- unique nullable `installation_id` with `ON DELETE SET NULL`;
- `approved_at/by`, `declined_at/by`, and `revoked_at/by`;
- timestamps;
- database checks for digest lengths and allowed statuses;
- index on `[status, created_at]`.

Do not store the raw request token or IP address.

**Step 4: Implement transitions under a row lock**

```ruby
def approve!(actor)
  with_lock do
    return installation if approved?
    raise ActiveRecord::RecordInvalid, self unless pending?

    participant = Installation.create!(token_digest: request_token_digest)
    update!(status: :approved, installation: participant,
      approved_at: Time.current, approved_by: actor)
    participant
  end
end
```

Implement `decline!` only from pending. Implement `revoke!` only from approved; in one transaction disable the installation and record revoke actor/time/status.

**Step 5: Verify GREEN and migrate**

```bash
RBENV_VERSION=ruby-3.4.9 rbenv exec bundle exec rails db:migrate
RBENV_VERSION=ruby-3.4.9 rbenv exec bundle exec rails test test/models/signal_access_request_test.rb
```

Expected: focused tests pass and `db/schema.rb` contains the new table and constraints.

**Step 6: Commit in the backend repository**

```bash
git add app/models/signal_access_request.rb db/migrate/20260905170000_create_signal_access_requests.rb db/schema.rb test/models/signal_access_request_test.rb
git commit -m "feat: add signal access requests"
```

---

## Task 2: Add request/status API endpoints

**Objective:** Let an unauthenticated app submit a bounded request and check its status using the opaque request credential.

**Backend files:**
- Create: `app/controllers/api/v2/signal_access_requests_controller.rb`
- Modify: `config/routes.rb`
- Test: `test/integration/signal_access_requests_test.rb`

**Step 1: Write failing integration tests**

Required contract:

```http
POST /api/v2/signal-access-requests
Content-Type: application/json

{"name":"Penar","device_model":"iPhone"}

201 {"request_token":"<43 chars>","status":"pending"}
```

```http
GET /api/v2/signal-access-request
Authorization: Request <43-character-token>

200 {"status":"pending"}
```

After approval, the same request token must authenticate this existing endpoint:

```http
PUT /api/v2/topics/:topic_id/signal
Authorization: Bearer <same-request-token>
```

Test malformed/missing fields (`422`), invalid request credential (`401` + `WWW-Authenticate: Request`), declined/revoked statuses, raw-secret non-persistence, and rate-limit keys that hash credentials.

**Step 2: Verify RED**

```bash
RBENV_VERSION=ruby-3.4.9 rbenv exec bundle exec rails test test/integration/signal_access_requests_test.rb
```

Expected: route/controller failures.

**Step 3: Add routes and controller**

```ruby
post "signal-access-requests", to: "signal_access_requests#create"
get "signal-access-request", to: "signal_access_requests#show"
```

Reuse the proven limits from the prior implementation:

- create: 3/IP/hour;
- show: 60/IP/minute;
- show: 60/hashed-request-token/minute.

Parse only `Authorization: Request <43 URL-safe characters>`. The status endpoint returns only the lifecycle status; it never returns names, raw credentials, or installation details.

**Step 4: Verify GREEN**

Run the focused integration test. Expected: all request, status, approval, revocation, and rate-limit cases pass.

**Step 5: Commit in the backend repository**

```bash
git add app/controllers/api/v2/signal_access_requests_controller.rb config/routes.rb test/integration/signal_access_requests_test.rb
git commit -m "feat: expose signal access request API"
```

---

## Task 3: Restore the minimal admin approval queue

**Objective:** Let authenticated admins inspect, approve, decline, and revoke ranking contributors.

**Backend files:**
- Create: `app/controllers/admin/signal_access_requests_controller.rb`
- Create: `app/views/admin/signal_access_requests/index.html.erb`
- Modify: `app/views/layouts/admin.html.erb`
- Modify: `config/routes.rb`
- Test: `test/integration/admin_signal_access_requests_test.rb`

**Step 1: Write failing admin tests**

Test authentication for index and every mutation. Test that the queue displays name, coarse device label, request time, and status. Test approve, decline, and revoke actor/timestamp persistence and rejected repeated/invalid transitions.

**Step 2: Verify RED**

```bash
RBENV_VERSION=ruby-3.4.9 rbenv exec bundle exec rails test test/integration/admin_signal_access_requests_test.rb
```

**Step 3: Add the existing-style Rails UI**

- Add `resources :signal_access_requests, only: :index` under `namespace :admin`, with member `approve`, `decline`, and `revoke` PATCH routes.
- Add **Signal access** to the existing admin navigation.
- Reuse existing `table`, `.status`, `.compact-button`, and `.inline-actions` styles; add no new CSS unless visual QA proves it necessary.
- List newest 200 requests. Pending rows have Approve/Decline; approved rows have Revoke with Turbo confirmation; terminal rows have no mutation controls.

**Step 4: Verify GREEN**

Run the focused admin test and manually inspect the authenticated page at desktop and narrow widths.

**Step 5: Commit in the backend repository**

```bash
git add app/controllers/admin/signal_access_requests_controller.rb app/views/admin/signal_access_requests/index.html.erb app/views/layouts/admin.html.erb config/routes.rb test/integration/admin_signal_access_requests_test.rb
git commit -m "feat: review signal access requests"
```

---

## Task 4: Add the Apple request API and state machine

**Objective:** Store a pending request credential securely, check approval, and promote it to the existing signal bearer token without exposing another secret.

**Apple files:**
- Modify: `Sources/ForumIndexCore/APIClient.swift`
- Modify: `Sources/ForumIndexCore/SignalStore.swift`
- Modify: `Sources/ForumIndexApp/ReaderSceneModel.swift`
- Modify: `Tests/ForumIndexCoreTests/APIAndTaxonomyTests.swift`
- Modify: `Tests/ForumIndexCoreTests/SignalStoreTests.swift`

**Step 1: Write failing transport tests**

Add to `SignalAPIClientProtocol`:

```swift
func requestSignalAccess(name: String, deviceModel: String) async throws -> String
func fetchSignalAccessStatus(requestToken: String) async throws -> SignalAccessStatus
```

Verify exact paths, methods, JSON keys, `Request` authorization header, 43-character token validation, status decoding, and no language query.

**Step 2: Verify RED**

```bash
xcodebuild test -project ForumIndex.xcodeproj -scheme ForumIndex-macOS -destination 'platform=macOS,arch=arm64' -only-testing:ForumIndexCoreTests_macOS/URLSessionForumIndexAPIClientTests CODE_SIGNING_ALLOWED=NO
```

**Step 3: Implement the API contract**

Add a small `SignalAccessStatus: String, Codable, Sendable` enum and request/response DTOs beside the existing signal DTOs. Reuse `perform`; do not add another networking layer.

**Step 4: Write failing store tests**

Cover:

- trimmed name submission;
- pending token saved to a second `SignalTokenStore`;
- pending status restored across app restart;
- approved status saves the same token to the existing enrollment store, then removes it from pending storage;
- failed enrollment-store write preserves the pending token;
- declined/revoked state is shown and can be replaced by a new request;
- duplicate taps do not submit duplicate requests.

**Step 5: Implement the minimal state**

Extend `SignalStore` with request status/loading/error and:

```swift
func requestAccess(name: String, deviceModel: String) async
func refreshAccessRequest() async
func clearAccessRequest()
```

Inject a second `SignalTokenStore`. In production instantiate the existing `KeychainSignalTokenStore` with a separate service such as `com.musaraj.ForumIndex.signal-access-request`; use a second in-memory store in UI tests.

When status becomes approved:

1. save the request token to the existing enrollment token store;
2. set `isEnrolled = true`;
3. delete the pending token;
4. clear request state.

Never delete the pending token before the enrollment token is safely stored.

**Step 6: Verify GREEN and commit**

Run focused core tests, then commit:

```bash
git add Sources/ForumIndexCore/APIClient.swift Sources/ForumIndexCore/SignalStore.swift Sources/ForumIndexApp/ReaderSceneModel.swift Tests/ForumIndexCoreTests/APIAndTaxonomyTests.swift Tests/ForumIndexCoreTests/SignalStoreTests.swift
git commit -m "feat: request signal access from Apple app"
```

---

## Task 5: Build the contribution-access screen

**Objective:** Present manual invite entry and anonymous access request in one clear screen.

**Apple files:**
- Modify: `Sources/ForumIndexApp/ContentView.swift`
- Modify: `Tests/ForumIndexAppUITests/SwipeNavigationUITests.swift`

**Step 1: Write failing UI tests**

Test these states with the existing launch-environment fixture:

- gear opens **Contribute to rankings**;
- short explanation is visible;
- manual invite still enables signals;
- request form validates a nonblank name;
- successful request changes to **Waiting for review**;
- relaunch restores pending state;
- **Check status** changes approved state to enabled;
- declined state offers **Request again**;
- VoiceOver labels describe each action and status.

**Step 2: Verify RED**

Run only the new/updated XCUITest selector and confirm it fails on the absent request UI.

**Step 3: Implement with native `Form` sections**

Rename `SignalEnrollmentView` to `SignalAccessView` and the navigation title to **Contribute to rankings**. Reuse `TextField`, `SecureField`, `Button`, `Label`, and `ContentUnavailableView`/status text. Keep the existing platform sheet sizing and Done action.

Use a coarse platform label:

```swift
#if os(iOS)
let deviceModel = UIDevice.current.userInterfaceIdiom == .pad ? "iPad" : "iPhone"
#else
let deviceModel = "Mac"
#endif
```

Do not send device names, hardware identifiers, email addresses, or analytics.

**Step 4: Verify GREEN and commit**

```bash
git add Sources/ForumIndexApp/ContentView.swift Tests/ForumIndexAppUITests/SwipeNavigationUITests.swift
git commit -m "feat: add ranking access request UI"
```

---

## Task 6: Consolidate topic actions into one visible bar

**Objective:** Make useful, not useful, and bookmark actions equally discoverable in the topic reader.

**Apple files:**
- Modify: `Sources/ForumIndexApp/ContentView.swift`
- Modify: `Tests/ForumIndexAppUITests/SwipeNavigationUITests.swift`

**Step 1: Write failing UI tests**

Test:

- useful, not useful, and bookmark controls are visible together;
- bookmarking works with no ranking access and survives relaunch;
- an unapproved thumb tap opens **Contribute to rankings**;
- useful selection fills/tints, tapping again clears, and tapping not useful switches selection;
- a failed signal rolls back the selected appearance and exposes an accessible error;
- all controls have 44×44 hit targets and remain unclipped on the smallest supported iPhone simulator and macOS minimum sheet.

**Step 2: Verify RED**

Run the updated topic-sheet XCUITests; expect the locked-thumb discoverability checks to fail.

**Step 3: Reuse the current bar**

- Fold `TopicSignalControls` into the existing `WebPageSheet` bottom `HStack` rather than creating a second toolbar component.
- Always render both thumb buttons.
- If enrolled, call existing `SignalStore.toggleSignal`.
- If not enrolled, set local `showingSignalAccess = true` and present `SignalAccessView` as a nested sheet.
- Keep existing bookmark persistence and Share/Safari/Close actions.
- Use `hand.thumbsup(.fill)`, `hand.thumbsdown(.fill)`, and `bookmark(.fill)` state variants with tint; do not add counters or animations.

**Step 4: Verify GREEN and commit**

```bash
git add Sources/ForumIndexApp/ContentView.swift Tests/ForumIndexAppUITests/SwipeNavigationUITests.swift
git commit -m "feat: clarify topic contribution actions"
```

---

## Task 7: Full verification, review, deployment, and device delivery

**Objective:** Prove the two-repository flow works end to end and ship the updated Apple build.

**Step 1: Backend quality gates**

```bash
RBENV_VERSION=ruby-3.4.9 rbenv exec bundle exec rails test
RBENV_VERSION=ruby-3.4.9 rbenv exec bundle exec rubocop
RBENV_VERSION=ruby-3.4.9 rbenv exec bundle exec brakeman --no-pager
git diff --check
```

**Step 2: Apple quality gates**

```bash
xcodebuild test -project ForumIndex.xcodeproj -scheme ForumIndex-macOS -destination 'platform=macOS,arch=arm64' CODE_SIGNING_ALLOWED=NO
xcodebuild test -project ForumIndex.xcodeproj -scheme ForumIndex-iOS -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' CODE_SIGNING_ALLOWED=NO
xcodebuild build -project ForumIndex.xcodeproj -scheme ForumIndex-iOS -configuration Release -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO
git diff --check
```

Confirm nonzero XCTest counts; rerun any simulator-killed test in isolation and do not call a source failure fixed until it passes.

**Step 3: End-to-end acceptance**

1. Submit a request from the app.
2. Verify the admin queue shows only name, coarse device type, status, and request time.
3. Approve it.
4. Tap **Check status** in the app.
5. Verify the app becomes enrolled without displaying or transmitting another credential.
6. Mark a real topic useful, switch it to not useful, clear it, and bookmark it.
7. Verify the server has at most one signal row for the installation/topic and the bookmark remains device-local.
8. Revoke access and verify the next signal write fails closed.

**Step 4: Independent reviews**

Request separate backend and Apple reviews. Resolve every P1/P2 finding and rerun affected gates.

**Step 5: Visual QA**

Capture and inspect:

- topic reader bar: unapproved, useful selected, not useful selected, bookmarked;
- access screen: fresh, pending, approved, declined;
- admin queue: pending and terminal rows;
- iPhone portrait, largest Dynamic Type that fits supported layout, dark mode, and macOS minimum window.

**Step 6: Push and deploy in dependency order**

1. Push backend commits.
2. Deploy backend migration/API/admin queue and verify `/up` plus request/status API behavior.
3. Push Apple commits.
4. Build, sign, install, launch, and read back the app on the trusted iPhone.

---

## Explicitly skipped

- Email/SMS delivery, user accounts, passkeys, push notifications, automatic polling, vote totals, list-row swipe actions, synced bookmarks, and separate bookmark storage infrastructure.
- Add any of these only after the anonymous request/approval funnel and topic action bar are used enough to show a concrete need.
