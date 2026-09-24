# iOS App Store release

This release targets iPhone and iPad. The macOS target remains available for development but is outside this submission.

## Release identity

`project.yml` is the source of truth. Run `xcodegen generate` after changing it and commit the generated project and shared schemes together with the YAML.

| Setting | Value |
| --- | --- |
| Display name | Forum Index |
| Version / build | 1.0.0 / 1 |
| Developer team | M4XMDAF939 |
| iOS bundle ID | com.musaraj.ForumIndex.iOS |
| Category | News |
| Minimum OS | iOS 18 |

Create or select the iOS App Store Connect record for `com.musaraj.ForumIndex.iOS`. Do not change an ID already associated with a published app. Verify the team owns this ID and update `Config/ExportOptions-AppStore.plist` if the team changes. The macOS target uses a different ID; any future universal-purchase plan needs to account for that before its first upload.

Increment `CURRENT_PROJECT_VERSION` before each new uploaded build. Version and build settings are shared with the embedded frameworks. The app uses HTTPS and Apple security APIs; `ITSAppUsesNonExemptEncryption` is `NO`. Reassess that declaration if adding other cryptography.

## Before the first upload

- Supply a public privacy-policy URL and add an accessible link inside the app. There is currently no policy link in the app. Supply a support URL with contact information for the store listing.
- Confirm privacy disclosures against server behavior, retention, logs, and third-party web content. The manifest currently declares name, device ID, product interaction, and other data, linked to the contributor, for app functionality; no tracking. The repository alone cannot establish the server's complete collection practices.
- Verify what `DELETE /api/v2/installation` removes. The app's opt-out promises revocation, not deletion of retained contributions. Confirm whether additional account/data deletion is needed for the enrollment flow.
- Confirm the production API at `https://do3.musaraj.com` is the intended public service and works from a physical device without development access.
- Prepare screenshots for supported iPhone and iPad sizes, description, keywords, copyright, age rating, content rights, pricing, availability, and review contact details in App Store Connect.
- Check moderation/reporting behavior for forum content. Complete the age-rating questionnaire based on the content actually available.
- Add the developer account for team `M4XMDAF939` in Xcode Settings → Accounts. Ensure the necessary distribution certificates and provisioning profiles are available. A certificate for another team cannot sign this app for distribution.

## Verify

Use a stable Xcode accepted by App Store Connect; this project has been built with Xcode 26.6. Check [Apple's current submission requirements](https://developer.apple.com/app-store/submitting/) before uploading.

```sh
xcodegen generate
xcodebuild -project ForumIndex.xcodeproj -scheme ForumIndex-macOS \
  -destination 'platform=macOS,arch=arm64' test
xcodebuild -project ForumIndex.xcodeproj -scheme ForumIndex-iOS \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.0' test
```

Choose an installed simulator if that destination is unavailable. Smoke-test browsing, subject navigation, starring, web pages, offline/error states, enrollment, opt-out, and persistence on real devices. Confirm enrollment does not gate ordinary browsing.

## Archive

```sh
./scripts/archive.sh ios
```

The script writes timestamped Release archives under ignored `build/archives/`. For local compilation and packaging checks without signing, append `--unsigned`; those archives are not distribution builds. To let Xcode create/download signing profiles using its configured account, explicitly pass `-allowProvisioningUpdates`.

Open the signed iOS archive in Xcode Organizer, choose **Validate App**, then **Distribute App → App Store Connect**. Upload a TestFlight build first and verify the installed distribution build before submitting for review.

For a local command-line export:

```sh
xcodebuild -exportArchive \
  -archivePath 'build/archives/<signed-archive>.xcarchive' \
  -exportPath 'build/export' \
  -exportOptionsPlist Config/ExportOptions-AppStore.plist
```

The export options write files locally; they do not upload. Preserve release archives and dSYMs outside Git for crash symbolication.

## Draft review notes

Forum Index is a native reader for activity across Discourse forums. Browse the main feed and subjects without signing in. Starred topics and reading state are available locally. Optional contributions enroll this device using a display name and device name; enabled contributions report reading, star changes, and topic reports to improve ranking and personalize the main feed. Open the Forum Index contribution sheet to enroll or opt out. Forum submission is available only to trusted contributors; provide review access if that feature needs to be evaluated. Links open content from the original forum.

Before submission, replace these draft notes with verified steps and any reviewer access needed. Do not claim opt-out deletes server data until that behavior is confirmed.

References: [App Review](https://developer.apple.com/app-store/review/), [privacy disclosures](https://developer.apple.com/help/app-store-connect/manage-app-information/manage-app-privacy), and [encryption declarations](https://developer.apple.com/documentation/security/complying-with-encryption-export-regulations).

## Preparation verification — 2026-09-21

- iOS Release archives succeeded both unsigned and signed with the local Apple Development certificate for team `M4XMDAF939`.
- Verified archive metadata, iPhone/iPad support, embedded core framework, privacy manifest, and app/framework dSYMs. The 1024px icon has no alpha channel; conversion preserved every visible pixel.
- All 122 iOS unit tests passed on the iPhone 17 Pro simulator with iOS 26.0. Of 16 UI tests, 14 passed initially; the remaining two passed in a focused rerun after constraining the scroll-test gesture and updating the changed privacy-copy expectation. The complete suite was not rerun after those test fixes.
- All 122 macOS core tests also passed while checking the shared code.
- Local App Store export failed with `No profiles for 'com.musaraj.ForumIndex.iOS' were found`. Distribution signing/provisioning is still required; the successful development-signed archive does not establish App Store validation.
- Privacy-policy/support URLs, store metadata/screenshots, server privacy/deletion confirmation, and physical-device/TestFlight checks remain open. Nothing was uploaded or submitted.
