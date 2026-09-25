# Forum Index

A shared native SwiftUI companion app for iOS and macOS.

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

The complete `AppIcon` asset catalog is referenced by both apps. iOS user-assigned device names require Apple's restricted entitlement; without it, the editable device-name field starts with the generic system name.

See [the iOS release guide](docs/RELEASING.md) for remaining submission requirements, signing, archive commands, and App Store export. Create an iOS Release archive with `./scripts/archive.sh ios`; add `--unsigned` for a local packaging check.

## Verify

```sh
xcodebuild -project ForumIndex.xcodeproj -scheme ForumIndex-macOS -destination 'platform=macOS,arch=arm64' test
xcodebuild -project ForumIndex.xcodeproj -scheme ForumIndex-iOS -destination 'platform=iOS Simulator,name=<installed device>,OS=<installed version>' test
```

## Legacy markdown

The older Discourse plugin format used by Privacy Guides is supported as **legacy markdown**. Its generated `Posts: N` field is hidden, and `Post N by @username — timestamp` headings use the shared native author row with `@username` and a right-aligned relative date.

## Appearance

Settings offers Auto (the default), Light, and Dark appearance on iOS and macOS. The choice is saved across launches and applies to topic lists, native Markdown previews, and sheets. Auto follows the system’s appearance. Websites receive the same appearance preference when they support dark mode; their header color independently controls iOS status-bar contrast.

## Topic previews

Feeds advertise Markdown support through `forum.supports_markdown`. Supported topics are fetched from their original URL with `Accept: text/markdown` and rendered natively using Textual. Missing support flags, failed requests, and non-Markdown responses use the existing web preview. Native previews show a sticky forum header, topic details, and author rows with relative dates. Generated Discourse metadata is hidden. The full page loads in the background once the Markdown is ready. The header icon reveals that same web view without restarting the request. More replies load automatically when the reader is within about one viewport of the end; failed page requests can be retried without losing the loaded posts.

Tapping the forum logo or name opens a popover with the site icon and information loaded from `GET /api/v2/forums/:id`. Forum and organization links open in the system browser. Links use the endpoint’s `site_url` and `parent_site_url`; the organization link is omitted when unavailable.

Same-site links load a new Markdown preview in the current screen, including links to individual posts. The header’s Back button returns to the previous Markdown and its scroll position. The browser-view toggle, share action, and bookmark action follow the currently displayed page. External links continue to open in the system browser.

On iOS, topics push onto a native navigation stack. Horizontal content swipes page through the current feed’s loaded topics, while the leading-edge swipe and floating dismiss button return to the list. The navigation bar stays hidden so only the site header appears above the article. Paging updates the selected topic; returning reveals and highlights its row. Without paging, the list retains its exact scroll offset.
