# URL Scheme Integration

> **Status: proposed spec, not yet implemented.** This document describes
> how third-party apps *would* launch mpv-ios directly, mirroring
> mpv-android's [Intent specification](https://mpv-android.github.io/mpv-android/intent.html).
> The app currently has no URL scheme or Universal Links handler
> registered (`Info.plist` defines no `CFBundleURLTypes`, and
> `MPVIOSPlayerApp.swift` has no `.onOpenURL` handler) — this is tracked
> in [ROADMAP.md](../ROADMAP.md) and is a genuinely good first
> contribution if you'd like to implement it (see
> [CONTRIBUTING.md](../CONTRIBUTING.md)). Everything below is the intended
> design, written up first so an implementation has a spec to match rather
> than being designed ad hoc in a PR.

## Why this instead of Android's Intent system

Android apps launch each other via Intents — an OS-level mechanism with no
direct iOS equivalent. iOS's nearest equivalents are:

- **Custom URL schemes** (`mpvios://...`) — any app can register one and
  any other app can open it via `UIApplication.shared.open(url)`; the
  system just needs the scheme registered in the opening app's
  `LSApplicationQueriesSchemes` for `canOpenURL` checks (not required just
  to open a URL, only to check availability first).
- **Universal Links** (`https://yourdomain.com/play?...`) — require
  hosting an `apple-app-site-association` file on a domain you control,
  but degrade gracefully (opens in Safari) if the app isn't installed,
  unlike a custom scheme which just fails silently.

This spec proposes supporting **both**, since they serve different needs:
a custom scheme is simpler for other apps/scripts to construct without
needing a real domain, while Universal Links are the better choice for
anything user-facing (a link shared in Messages, a website's "open in
app" button).

## Proposed custom scheme

```
mpvios://play?url=<url>&title=<title>&subs=<url>&subs=<url>&position=<seconds>
```

| Parameter | Required | Description |
|---|---|---|
| `url` | Yes | Percent-encoded URL of the media to play (`http(s)://`, or a `file://` URL for something already in the calling app's accessible container — see the "local files" caveat below). |
| `title` | No | Display title, equivalent to mpv-android's `title` extra. Defaults to the filename if omitted. |
| `subs` | No, repeatable | Percent-encoded subtitle file URL. Can appear multiple times for multiple tracks, matching mpv-android's `subs` array extra. |
| `position` | No | Starting playback position, in seconds (mpv-android uses milliseconds for its `position` extra — seconds is proposed here instead to match `MPVPlayer.seek(to:)`'s existing unit, avoiding a footgun where implementers forget to divide by 1000). |

### Example

```
mpvios://play?url=https%3A%2F%2Fexample.com%2Fvideo.mp4&title=My%20Video&position=120
```

### Swift (calling app)

```swift
var components = URLComponents(string: "mpvios://play")!
components.queryItems = [
    URLQueryItem(name: "url", value: "https://example.com/video.mp4"),
    URLQueryItem(name: "title", value: "My Video"),
    URLQueryItem(name: "position", value: "120"),
]
if let url = components.url {
    UIApplication.shared.open(url)
}
```

## Proposed Universal Link

```
https://<your-domain>/play?url=<url>&title=<title>&subs=<url>&position=<seconds>
```

Same query parameters as the custom scheme. Requires:

1. An `apple-app-site-association` file hosted at
   `https://<your-domain>/.well-known/apple-app-site-association`,
   associating the domain with this app's Team ID + Bundle ID (see Apple's
   Supporting Associated Domains documentation).
2. The `Associated Domains` capability enabled in the app's target, with
   `applinks:<your-domain>` added.

Since this project has no domain of its own and no Apple Developer account
yet (see CONTRIBUTING.md), this half of the spec is documented for
completeness but is lower priority to implement than the custom scheme,
which needs neither.

## Local files

mpv-android's Intent spec supports `content://` URIs (Android's
cross-app file-sharing mechanism). iOS's nearest equivalent is a
security-scoped bookmark or a shared App Group container — a bare
`file://` URL from another app's sandbox will not be readable by mpv-ios
without one of these, since iOS sandboxes each app's files from every
other app by default. A full local-file-sharing design is out of scope
for this initial spec and should be a separate proposal if needed.

## Suggested implementation sketch

For whoever picks this up (see CONTRIBUTING.md):

1. Add a `CFBundleURLTypes` entry to `Info.plist` registering the
   `mpvios` scheme.
2. In `MPVIOSPlayerApp.swift`, add `.onOpenURL { url in ... }` to the
   `WindowGroup`, parsing the query parameters above and presenting
   `MPVPlayerView` with the resulting `URL` — this should reuse
   `MPVPlayerView`'s existing `init(url:onDismiss:)` initializer rather
   than introducing a parallel playback path.
3. For `subs`/`position`, `MPVPlayerView`/`PlayerViewModel` will need
   small additions to accept initial subtitle URLs and a start position —
   neither currently exists (see `PlayerViewModel.loadFile(_:)`, which
   takes only a path today).
4. Write the actual `apple-app-site-association` handling only once a
   domain is available (see the Universal Link section above) —
   reasonable to ship the custom scheme alone first.
