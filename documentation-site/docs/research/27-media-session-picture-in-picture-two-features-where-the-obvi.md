---
id: 27-media-session-picture-in-picture-two-features-where-the-obvi
title: "Media Session + Picture in Picture: two features where the \"obvious\" iOS API is a documented trap"
sidebar_label: "27. Media Session + Picture in Picture: two features where the \"obvious\" iOS API is a documented trap"
sidebar_position: 28
---

## 27. Media Session + Picture in Picture: two features where the "obvious" iOS API is a documented trap

**What was added:** Control Center/lock-screen integration
(`MediaSessionManager`, wrapping `MPNowPlayingInfoCenter` +
`MPRemoteCommandCenter` + `AVAudioSession` interruption/route-change
notifications) and Picture in Picture (`PictureInPictureRenderer` in
MPVKit, `PictureInPictureCoordinator` + `PictureInPictureLayerView` in
the app target). Both features have an "obvious first approach" that
turned out to be wrong or unsafe on inspection, in a way this entry
records so neither gets silently reintroduced later.

**1. `mpv_render_context_render()` cannot safely be called twice per
frame.** The first PiP design considered was: render once for the
screen (existing path, unchanged), then render a second time into a
separate FBO sized for PiP. `render.h`'s own documentation rules this
out — each call "implicitly pulls a video frame from the internal
queue," so two calls per displayed frame risk the screen and PiP paths
showing different frames, or one starving the other. The actual design
renders once (screen path, byte-for-byte unchanged) and reads back that
same already-rendered frame via `glBlitFramebuffer` (OpenGL ES 3.0,
confirmed available given this project's `.openGLES3` context) into an
IOSurface-backed `CVPixelBuffer` — a GPU-side copy, not a second mpv
render and not a `glReadPixels` CPU readback.

**2. `CVOpenGLESTextureCacheCreateTextureFromImage`'s internal-format
parameter is not the same kind of thing as a sized GL storage enum.**
An early draft passed `GL_RGBA8_OES` as `internalFormat` (reasoning by
analogy from unrelated render-target-texture-storage code elsewhere).
Checked against a working reference implementation
(a widely-cited "render to IOSurface-backed CVPixelBuffer via texture
cache" writeup) rather than assumed: the correct triple for a BGRA
`CVPixelBuffer` is `internalFormat=GL_RGBA` (channel count, not a sized
OES enum) with `format=GL_BGRA` / `type=GL_UNSIGNED_BYTE` describing the
buffer's actual memory layout. Worth remembering this API doesn't follow
the same convention as plain `glTexStorage2D`-style calls elsewhere in
GL code, even though the parameter is also named "internalFormat" there.

**3. The "standard" iOS trick for setting system volume is an
Apple-acknowledged unsupported hack, not a sanctioned workaround.**
Already covered from the gesture-porting side in entry 26; recorded
again here because `MediaSessionManager`'s remote-command handling
raised the same question independently (whether PiP/lock-screen volume
controls should drive system volume) and reached the same answer for
the same reason — `AVAudioSession.outputVolume` is read-only, and the
`MPVolumeView`-slider trick reaches into a private view hierarchy Apple
has stated isn't supported and which behaves inconsistently with
AirPlay across iOS versions.

**4. `MPNowPlayingInfoPropertyMediaType` and
`MPMediaItemPropertyMediaType` are two different keys expecting two
different enums, and mixing them up is a real shipped mistake, not a
hypothetical one.** Confirmed via IINA's own GitHub issue tracker
containing exactly this confusion. `MediaSessionManager.updateMetadata`
uses the correct key deliberately, with a comment warning against
"correcting" it to the similarly-named one.

**5. `MPMediaItemArtwork`'s `requestHandler` closure has an
Apple-DTS-acknowledged, still-unresolved crash risk under Swift 6
strict concurrency** when it captures and returns an external `UIImage`
value — exactly the shape `updateMetadata` uses. This project currently
builds under Swift 5.9 (`project.yml`), so it isn't hit today; flagged
in-code so a future move to Swift 6 language mode re-checks Apple's
developer forums rather than assuming this still works unchanged.

**6. `AVSampleBufferDisplayLayer` renders nothing — and cannot support
PiP — while it has a zero-size frame or isn't in any view's layer
hierarchy**, confirmed via an Apple Developer Forums thread reporting
exactly that failure mode. `PictureInPictureLayerView` therefore hosts
the coordinator's `displayLayer` at a real, non-zero size at all times
and hides it with `.opacity(0)` rather than `.hidden` or a zero frame,
specifically to avoid silently breaking PiP the next time it's
requested.

**7. `UIBackgroundModes` needs both `audio` and `picture-in-picture`
for PiP to keep rendering once backgrounded** — this project already
had `audio` (for background audio playback, unrelated to PiP), and it
alone is not sufficient; multiple third-party PiP integration guides
add both keys together via Xcode's combined "Audio, AirPlay, and
Picture in Picture" capability checkbox, which was the signal that these
are treated as a pair, not that `audio` implies the other.

**8. `AVSampleBufferDisplayLayer.enqueue(_:)` is safe to call from a
background queue** — confirmed against the WWDC 2014 reference pattern
for this API (`requestMediaDataWhenReadyOnQueue` explicitly takes a
caller-provided background queue). `PictureInPictureCoordinator` enqueues
directly from `MPVGLView`'s own render queue rather than hopping to the
main actor first, avoiding an extra thread transition on every video
frame that would have bought nothing correctness-wise.

**Design choices carried over intentionally:** both
`MediaSessionManager` and `PictureInPictureCoordinator` are separate
types from `PlayerViewModel`, communicating only through an `Action`
enum + closures rather than holding a reference to `MPVCore` directly —
matching mpv-android's own separation between `PlayerActivity`'s
transport-control logic and its `initMediaSession()`/PiP-params setup,
which only ever *signal* PlayerActivity rather than touching `MPVLib`
themselves.

**Lesson:** both features had a first-instinct implementation (render
twice; set system volume directly; a sized GL enum for internalFormat;
hide the PiP layer when not in PiP) that looked reasonable and matched
a nearby, superficially-similar pattern elsewhere — and every one of
them was wrong for a documented reason findable by checking current
official sources (`render.h`, Apple DTS forum threads, a working
reference implementation) rather than reasoning from the shape of
similar-looking code. Consistent with entry 26's own lesson: the
platform-specific *handler*/integration layer is where unverified
analogy-based reasoning is most likely to silently produce something
that compiles, looks plausible, and is subtly wrong.
