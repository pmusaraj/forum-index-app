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

Both build the same SwiftUI app sources and run the same `ForumIndexCoreTests` suite against platform-specific targets.

## Signing and distribution

Release metadata is defined in `project.yml`: version `1.0.0`, build `1`, News category, app sandboxing on macOS, and a privacy manifest shared by both apps.

The complete `AppIcon` asset catalog is referenced by both apps. iOS user-assigned device names require Apple's restricted entitlement; without it, the editable device-name field starts with the generic system name.

## Verify

```sh
xcodebuild -project ForumIndex.xcodeproj -scheme ForumIndex-macOS -destination 'platform=macOS,arch=arm64' test
xcodebuild -project ForumIndex.xcodeproj -scheme ForumIndex-iOS -destination 'platform=iOS Simulator,name=<installed device>,OS=<installed version>' test
```
