# Privacy Policy

_Last updated: 2026-07-05_

This policy describes what mpv-ios (the app in `mpv-ios-player/`) does and
does not do with your data. It's written to be accurate to the actual
current codebase, not a generic template — if the app's behavior changes,
this file should be updated in the same PR that changes it.

## Summary

mpv-ios does not collect, transmit, or store any of your personal data on
any server. It has no analytics, no crash reporting, no tracking, and no
account system, because none of that code exists in the app.

## What the app does with files and URLs you open

- **Local files**: when you use the file picker (`MPVRootView`'s "Open
  File", backed by `fileImporter`/`UIDocumentPickerViewController`), the
  app reads the file you explicitly select in order to play it. Nothing
  about that file — its name, contents, or metadata — is sent anywhere.
  It stays on your device.
- **URLs**: when you use "Open URL" to play a network stream, the app
  connects directly to the URL you provide, the same way any video player
  or web browser would, in order to fetch and play that content. The app
  itself does not log, store, or transmit the URLs you enter to any
  server it controls (it has none). Whatever server actually hosts the
  media you're streaming from will, of course, see requests from your
  device the same way it would from any other player — that's inherent to
  how network streaming works, not something specific to this app.

## Third-party services

This app does not integrate any third-party SDK, analytics service, ad
network, or crash reporter. If that ever changes, this section will be
updated to name the service and link to its own privacy policy, the same
way this project already documents Appetize.io's role in
[TESTING.md](../TESTING.md) for CI/testing purposes only (Appetize.io is
used only in this project's own development/testing workflow — it is not
integrated into the app itself, and end users running the app do not
interact with Appetize.io in any way).

## Permissions

The app may request:

- **File / document access**: only when you actively choose to open a
  file, via the system's own document picker. The app cannot browse your
  files without you explicitly picking one.

No other permissions (location, contacts, camera, microphone, etc.) are
requested, because the app has no feature that would use them.

## Data retention

Since nothing is collected or transmitted, there is nothing retained on
any server. Locally, the app may cache in-memory playback state (current
position, volume, etc. — see `PlayerViewModel`) for the duration it's
running, which is cleared when the app is closed. No playback history is
written to persistent storage by the app itself.

## Children's privacy

This app does not knowingly collect any information from anyone,
including children, because it does not collect information from anyone
at all, per the above.

## Changes to this policy

If this app's data behavior changes in the future (for example, if crash
reporting or analytics is ever added), this document will be updated to
accurately reflect that, and the update will be called out in that
change's release notes (see `docs/release_process.md`).

## Contact

For questions about this policy, open an issue on the project's GitHub
repository using the **Question** template (see
[CONTRIBUTING.md](../CONTRIBUTING.md)).
