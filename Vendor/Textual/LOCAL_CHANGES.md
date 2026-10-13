# Textual selection fixes

This is Textual 0.5.0, upstream revision
`01b51875a5406eefc95f52a058cb059e7bc94dc4`, with its sources, tests,
package manifest, and licenses preserved.

Two pending upstream fixes are included:

- [PR #80](https://github.com/gonzalezreal/textual/pull/80), revision
  `bd9fbee3d775483b56015918308068beaae6c3d3`: validate retained text positions
  before indexing layouts. Includes the upstream empty-layout regression test.
- The `TextSelectionInteraction.swift` change from
  [PR #71](https://github.com/gonzalezreal/textual/pull/71), revision `251b3b7`:
  deliver layouts through
  a transparent platform view's update method. SwiftUI can drop the original
  `onChange` updates within a single frame, leaving selection with an empty layout.

Both changes are necessary: bounds checks alone stop the crash but leave text
unselectable. The app UI test `testSelectingTextInJuliaTopic` reproduces the
long-press crash using the reported topic and verifies the Copy action.

The local package makes these fixes reproducible without modifying SwiftPM caches
or depending on a moving pull-request branch. Restore the remote dependency in
`project.yml` and remove this directory once an upstream release includes both
fixes and passes the regression test. Regenerate the project with `xcodegen generate`.

Run the selection-model tests with:

```sh
swift test --package-path Vendor/Textual --scratch-path build/TextualTests --no-parallel --filter TextSelectionModelTests
```

Serial execution avoids concurrent CoreText font initialization stalling the
fixture-backed tests on macOS.
