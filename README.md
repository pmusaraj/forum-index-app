# Forum Index

A shared native SwiftUI companion app for iOS and macOS.

For questions or support, email [hey@theforumindex.com](mailto:hey@theforumindex.com).

## Requirements

- Swift 6
- iOS 18 or later
- macOS 15 or later
- Xcode 26.6
- XcodeGen 2.44.1 or later (verified with 2.45.4)

## Generate

```sh
xcodegen generate
open ForumIndex.xcodeproj
```

The shared sources are exposed through two clear platform schemes:

- `ForumIndex-iOS`
- `ForumIndex-macOS`

Both build the same SwiftUI app sources and run the same `ForumIndexCoreTests` suite against platform-specific targets.

## Signing and distribution

Release metadata is defined in `project.yml`: version `1.0.0`, build `1`, News category, app sandboxing on macOS, and a privacy manifest shared by both apps.

The complete `AppIcon` asset catalog is referenced by both apps. Settings on iOS and macOS shows the contributor nickname as a read-only Device name with a Generate new name button. The device label is reported separately.

New installations receive a persistent random contributor nickname such as
`DancingOtter42`, sent upstream as `display_name`. A dictionary of 64 verbs
and 64 nouns plus a two-digit suffix (`00`–`99`) provides 409,600 combinations.
Duplicate nicknames are acceptable: they are display metadata, not unique IDs.
Existing contributor names are preserved until a new name is generated. Changing an enrolled nickname requires the backend to accept `display_name` in `PATCH /api/v2/installation`. The system-provided device name (or
saved custom name) is already sent separately as `device_name`. Debug builds prefix
this device label with `[dev] `, including existing installations on their next status
refresh, matching Android. The label stays within 100 Unicode code points; Release
builds send device names unchanged.

See [the iOS release guide](docs/RELEASING.md) for remaining submission requirements, signing, archive commands, and App Store export. Create a Release archive with `./scripts/archive.sh ios` or `./scripts/archive.sh macos`; add `--unsigned` for a local packaging check. Both signed archives can be uploaded with `scripts/testflight.py` once the platform’s App Store Connect record and provisioning profile exist.

## Verify

```sh
xcodebuild -project ForumIndex.xcodeproj -scheme ForumIndex-macOS -destination 'platform=macOS,arch=arm64' test
xcodebuild -project ForumIndex.xcodeproj -scheme ForumIndex-iOS -destination 'platform=iOS Simulator,name=<installed device>,OS=<installed version>' test
```

## Legacy markdown

The older Discourse plugin format used by Privacy Guides is supported as **legacy markdown**. Its generated `Posts: N` field is hidden, and `Post N by @username — timestamp` headings use the shared native author row with `@username` and a right-aligned relative date.

## Appearance

Settings offers Auto (the default), Light, and Dark appearance on iOS and macOS. The choice is saved across launches and applies to topic lists, native Markdown previews, and sheets. Auto follows the system’s appearance. Websites receive the same appearance preference when they support dark mode; their header color independently controls iOS status-bar contrast.

## Feeds

Trending uses the public `GET /api/v2/topics?feed=trending` ranking. For You uses
`feed=for_you` with the installation credential and appears only when
`GET /api/v2/installation` returns `for_you_eligible: true`. The optional
`read_count` field is decoded for server compatibility; the app does not choose
or calculate the eligibility threshold. Missing eligibility fields keep For You hidden.

Eligible readers default to For You, Trending, then subjects. Other readers start
with Trending. Both feeds use the existing subject picker for visibility and ordering.
Existing Main selections become Trending in place, and For You is added first on
initial eligibility without resetting subject preferences. Subsequent customizations
persist, including across temporary loss of eligibility. Eligibility refreshes at
launch and after successful read reports. Unlocking For You adds its tab without
interrupting the currently open feed; the saved order applies on the next launch.

## Feedback

Settings → Send feedback opens a message-only form on iOS and macOS. Drafts stay
on the device until a successful send. Feedback uses `POST /api/v2/feedback`, with
required installation authentication and app/OS version metadata. Feedback is available
to all enrolled contributors, including those without trusted status. Missing server
support leaves the draft intact and shows an unavailable message. See
[the server API contract](docs/FEEDBACK_API.md) for validation, idempotency, and admin inbox requirements.

## Topic previews

Feeds advertise a nullable `reader_markdown_url`, which can point to native forum Markdown or the backend converter. The app persists this URL with bookmarks, fetches it with `Accept: text/markdown`, and renders successful Markdown responses natively using Textual. Explicit null uses the website; older records missing the field retain the `forum.supports_markdown` fallback. Pagination follows document links relative to the reader URL, while sharing, attribution, and bookmarks retain the original topic URL. Failed requests and non-Markdown responses offer the existing web preview. Retries honor `Retry-After` across reader requests to the same host. Native previews show a sticky forum header, topic details, and author rows with relative dates. Topics with external signals show Hacker News and Lobsters icons in the feed, with discussion links below the native preview title and above the first post. These links open in the system browser. Generated Discourse metadata is hidden. The full page loads in the background once the Markdown is ready. The topic title scrolls away with the article. After it leaves the screen, scrolling upward reveals a compact title element below the forum header; scrolling downward or returning to the original title hides it. The header icon reveals that same web view without restarting the request. More replies load automatically when the reader is within about one viewport of the end; failed page requests can be retried without losing the loaded posts.

Published Discourse summaries headed `AI-generated summary` before the first author row are shown through a small “Read AI summary” control beside the date and reply count. The summary expands inline and retains Markdown formatting. Post content with the same heading is preserved. At larger text sizes or in narrow readers, the control moves below the metadata. Once the complete topic has loaded, a separated footer shows “You reached the end of topic:” with the topic title and community host, available reply and participant totals, and a compact “Open in browser” button on both platforms. Participant totals require identified authors on every loaded post; single-post and partial-page previews do not show a completion footer.

Tapping the forum logo or name opens a popover with the site icon and information loaded from `GET /api/v2/forums/:id`. Forum and organization links open in the system browser. Links use the endpoint’s `site_url` and `parent_site_url`; the organization link is omitted when unavailable.

Long-press a topic and choose About to see its excerpt and community description. Open topic continues in the app’s reader; community and parent website links open in the system browser. Missing descriptions or excerpts show a placeholder, and community information can be retried if loading fails.

Images in Markdown previews open in a dark lightbox when clicked or tapped. Zoom controls and pinch gestures enlarge images up to 5×; scroll to inspect details and use Fit to reset. Close (or Escape on Mac) returns to the same reading position.

Saved native Markdown topics with unread replies open at the first unread post, with a “New replies since last read” marker. The reader uses Discourse’s post-ID index to locate the page directly, rather than walking through earlier pages. Existing timestamp-only bookmarks acquire a stable post-number cursor on their next unread visit. Opening the reader does not clear the unread indicator: a reply advances progress after its bottom remains visible for 750 ms. Earlier pages load when scrolling back to the loaded boundary, after scrolling settles, and “Back to top” opens the original post directly. Failed resume lookups offer Retry or Back to top without losing saved progress. Converted topics record the same upstream post-number progress. Their unread bookmarks resume on the original webpage at the located post; switching back to the reader starts at the beginning, without inferring a converter page from a post number. Website previews retain their existing read behavior.

Same-site links load a new Markdown preview in the current screen, including links to individual posts. The header’s Back button returns to the previous Markdown and its scroll position. The browser-view toggle, share action, and bookmark action follow the currently displayed page. External links continue to open in the system browser.

On iOS, topics push onto a native navigation stack. Horizontal content swipes page through the current feed’s loaded topics, while the leading-edge swipe and floating dismiss button return to the list. The navigation bar stays hidden so only the site header appears above the article. Paging updates the selected topic; returning reveals and highlights its row. Without paging, the list retains its exact scroll offset.

## macOS reader

The Mac window uses three resizable columns: subjects, topics, and an inline reader. The subject list scrolls independently; Bookmarks and Settings remain pinned below it. The subject header’s ellipsis opens subject customization. Settings is also available with Command-comma, and Command-R refreshes the current feed. Up/Down selects the previous/next topic (or the first topic when none is selected); Command-Up/Down changes subjects. B toggles the displayed topic’s bookmark. Bookmarked topic buttons use the accent color and animate the change, respecting Reduce Motion on Mac and iOS. In Markdown mode, Space scrolls down a page and Shift-Space scrolls up. Website views keep their native keyboard behavior. These shortcuts are also listed in the Navigate menu. Press `?` (or choose Help → Keyboard Shortcuts) for the shortcut reference. The sidebar can be toggled from the topic-list header or with Control-Command-S. The native split panes fill the window without navigation toolbar insets. The native window buttons remain visible without adding a toolbar row above the reader; feed refresh remains available with Command-R. Sidebar appearance and pane sizing stay consistent when a topic is selected or dismissed.

The detail pane reuses the mobile topic header, Markdown/website switch, share, bookmark, and dismiss controls. New bookmarks retain topic metadata so they reopen in the native reader; older bookmarks without that metadata open the website inline. The macOS scheme includes a UI smoke test for the inline reader and pinned sidebar actions.

### Mac development signing

Mac Debug builds use an Apple Development certificate with the configured development team. Build and launch with:

```sh
xcodebuild -project ForumIndex.xcodeproj -scheme ForumIndex-macOS -configuration Debug -destination 'platform=macOS' -derivedDataPath /tmp/forum-index-macos build
open /tmp/forum-index-macos/Build/Products/Debug/ForumIndex.app
```

Do not override signing with `CODE_SIGN_IDENTITY=-` or `CODE_SIGNING_ALLOWED=NO` for builds you launch against your real Keychain. Ad-hoc signatures change between builds and can trigger repeated access prompts for the contribution token. After switching an existing installation from ad-hoc signing, macOS may request access once; choose Always Allow for the signed Forum Index app to retain access across subsequent builds. The token stays in Keychain and is not reset by rebuilding.
