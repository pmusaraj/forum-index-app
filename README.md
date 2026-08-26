# Forum Index

A shared native SwiftUI companion app for iOS and macOS.

## Requirements

- Swift 6
- iOS 17 or later
- macOS 14 or later
- Xcode 26.6
- XcodeGen 2.44.1

## Generate

```sh
xcodegen generate
open ForumIndex.xcodeproj
```

The shared sources are exposed through two clear platform schemes:

- `ForumIndex-iOS`
- `ForumIndex-macOS`

Both build the same SwiftUI app sources and run the same `ForumIndexCoreTests` suite against platform-specific targets. The production reader uses `https://do3.musaraj.com`.

## Signing and distribution

`DEVELOPMENT_TEAM` is intentionally empty in `project.yml`. Set it to your Apple Developer Team ID (or select a team in Xcode) before running on a physical device, archiving, or distributing the app.

No `AppIcon` asset is referenced because this repository does not yet include a complete, validated icon set. `ASSETCATALOG_COMPILER_APPICON_NAME` is explicitly empty to disable XcodeGen's default missing-asset reference. Add a proper asset catalog and distribution-ready icon artwork, then set it to that asset name before archive submission.

## Verify

```sh
xcodebuild -project ForumIndex.xcodeproj -scheme ForumIndex-macOS -destination 'platform=macOS,arch=arm64' test
xcodebuild -project ForumIndex.xcodeproj -scheme ForumIndex-iOS -destination 'platform=iOS Simulator,name=<installed device>,OS=<installed version>' test
```
