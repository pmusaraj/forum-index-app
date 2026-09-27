# iOS App Store release

This release targets iPhone and iPad. The macOS target remains available for development but is outside this submission.

## Release identity

`project.yml` is the source of truth. Run `xcodegen generate` after changing it and commit the generated project and shared schemes together with the YAML.

| Setting | Value |
| --- | --- |
| Display name | Forum Index |
| Version / build | 1.0.0 / 15 |
| Developer team | M4XMDAF939 |
| iOS bundle ID | com.musaraj.forumindex |
| Category | News |
| Minimum OS | iOS 18 |

The iOS App Store Connect record uses `com.musaraj.forumindex`; the iOS target must match it exactly. Do not change an ID already associated with a published app. Verify the team owns this ID and update `Config/ExportOptions-AppStore.plist` if the team changes. The macOS target uses a different ID; any future universal-purchase plan needs to account for that before its first upload.

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

## Upload with a private App Store Connect key

Use a Developer team API key for uploads and a local Apple Distribution certificate for signing. In Xcode → Settings → Accounts, select your team, open Manage Certificates, and use + → Apple Distribution to create the local certificate and private key. Alternatively, import an existing distribution identity with its private key. The upload script checks that a valid local identity for the configured team exists before exporting.

Configure the API key once on this Mac:

```sh
python3 scripts/testflight.py configure \
  --key-id '<key ID>' --issuer-id '<issuer UUID>' \
  --key-path '/absolute/path/to/AuthKey.p8'
python3 scripts/testflight.py check
```

The script copies the key into `~/Library/Application Support/Forum Index/App Store Connect/` and saves the key ID, issuer ID, and copied key's path in `credentials.json` there. The directory is mode `700`; the key and configuration are mode `600`. This local storage is shared by worktrees, outside Git, and readable only by the current macOS user (or privileged processes). The original file is left unchanged. `check` validates local configuration and permissions, not access to Apple. Never put actual IDs, key paths, or key contents in repository files.

After incrementing the build number, verifying the app, and creating a signed archive:

```sh
python3 scripts/testflight.py upload 'build/archives/<signed-archive>.xcarchive'
```

This explicitly uploads to App Store Connect using Xcode's API-key authentication flags. Add `--export-only` to export locally without uploading. Xcode output is saved in private logs alongside the credentials. The existing export plist keeps its local-export default. A previously uploaded build number cannot be uploaded again.

Export also requires a matching distribution provisioning profile. Xcode can manage profiles with `-allowProvisioningUpdates` and the saved key; if the key lacks the necessary profile permissions, install the App Store distribution profile using the signed-in Xcode account. The workflow uses the local signing identity to avoid depending on cloud-signing permissions. See Apple's [cloud-managed certificate documentation](https://developer.apple.com/help/account/certificates/cloud-managed-certificates/).

After creating or renewing a local certificate, an existing profile may not include it. If export reports that mismatch, run the local export command above once with `-allowProvisioningUpdates` and your signed-in Xcode account, then retry `testflight.py upload ... --export-only`. This refreshes signing assets without uploading a duplicate build. The exported `DistributionSummary.plist` identifies the signing certificate used.

Run the script tests with `PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover -s Tests/ReleaseScripts -v`. Tests generate temporary keys and mock Xcode; they never upload a build.

Verified on 2026-09-26: version 1.0.0 build 11 uploaded successfully using the saved Developer API key and local Apple Distribution identity. Apple accepted the upload and began processing it. All four upload-script tests passed; credentials remain outside Git.

Apple's [API-key setup guide](https://developer.apple.com/help/app-store-connect/get-started/app-store-connect-api) describes team keys and permissions. Both the IDs and the `.p8` file are needed; the script never prints the private key.

## Draft review notes

Forum Index is a native reader for activity across Discourse forums. Browse the main feed and subjects without signing in. Starred topics and reading state are available locally. The device automatically enrolls using a generated contributor name and the system-provided device name (or a saved custom name). Enabled contributions report reading, star changes, and topic reports to improve ranking and personalize the main feed. Settings explains this behavior and provides an opt-out that persists across launches. If automatic enrollment fails, browsing remains available and Settings offers an explicit retry button. Forum submission is available only to trusted contributors; provide review access if that feature needs to be evaluated. Links open content from the original forum.

Before submission, replace these draft notes with verified steps and any reviewer access needed. Do not claim opt-out deletes server data until that behavior is confirmed.

References: [App Review](https://developer.apple.com/app-store/review/), [privacy disclosures](https://developer.apple.com/help/app-store-connect/manage-app-information/manage-app-privacy), and [encryption declarations](https://developer.apple.com/documentation/security/complying-with-encryption-export-regulations).

## Preparation verification — 2026-09-21

These results predate the bundle ID change to `com.musaraj.forumindex`. Create and validate a new archive for that ID; old archives cannot be uploaded to its App Store Connect record.

- iOS Release archives succeeded both unsigned and signed with the local Apple Development certificate for team `M4XMDAF939`.
- Verified archive metadata, iPhone/iPad support, embedded core framework, privacy manifest, and app/framework dSYMs. The 1024px icon has no alpha channel; conversion preserved every visible pixel.
- All 122 iOS unit tests passed on the iPhone 17 Pro simulator with iOS 26.0. Of 16 UI tests, 14 passed initially; the remaining two passed in a focused rerun after constraining the scroll-test gesture and updating the changed privacy-copy expectation. The complete suite was not rerun after those test fixes.
- All 122 macOS core tests also passed while checking the shared code.
- Local App Store export failed with `No profiles for 'com.musaraj.ForumIndex.iOS' were found`. Distribution signing/provisioning is still required; the successful development-signed archive does not establish App Store validation.
- Privacy-policy/support URLs, store metadata/screenshots, server privacy/deletion confirmation, and physical-device/TestFlight checks remain open. Nothing was uploaded or submitted.
