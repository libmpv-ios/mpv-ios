# Testing mpv-ios-player without a Mac or iPhone — full walkthrough

This is the exact order of steps to go from "I just forked this repo" to
"tapping around the app in a browser." Follow in order the first time;
after that, only the "Day-to-day" section at the bottom applies.

## One-time setup

### 1. Fork this repository

This project already lives on GitHub — you don't need to create a new repo
or push anything from scratch. Instead:

1. Go to the project's GitHub page and click **Fork** (top-right) to create
   your own copy under your account.
2. Clone your fork locally:
   ```bash
   git clone https://github.com/AeonCoreX-Lab/mpv-ios.git
   cd mpv-ios
   ```
3. That's it for this step — everything below (secrets, variables, running
   workflows) happens on **your fork**, not the original repository. Forks
   get their own independent Actions runs, secrets, and Appetize
   preview — nothing you do here affects the original project or other
   people's forks.

> **Important:** GitHub does not copy secrets or variables from the
> original repository into your fork, by design (so a fork can't
> accidentally leak the original maintainer's tokens). You'll set up your
> own `APPETIZE_API_TOKEN` below, specific to your own free Appetize
> account — this is expected and normal, not something going wrong.

If you later make changes you'd like to contribute back, see
[CONTRIBUTING.md](CONTRIBUTING.md) for how to open a pull request from
your fork.

### 2. Enable GitHub Actions on your fork

GitHub disables Actions by default on a freshly created fork (a security
measure, so a fork doesn't silently start running arbitrary CI). Nothing
in this guide will work until you turn it on:

1. On your fork, click the **Actions** tab.
2. You'll see a banner: *"Workflows aren't being run on this forked
   repository."* Click **I understand my workflows, go ahead and enable
   them**.

You only need to do this once per fork.

### 3. Create your Appetize.io account

1. Go to https://appetize.io/signup
2. Sign up with email — no credit card needed for the Free plan. You do
   **not** need to separately "create an organization" — signing up gives
   you an account that Appetize's dashboard calls an "organization" (with
   you as its admin by default); it's just their term for your account,
   not a separate company/team you need to set up.
3. Log in, then go to **Organization → API Tokens** in the dashboard.
4. Click **Generate API Token**.
   - **Label**: something recognizable, e.g. "GitHub CI".
   - **Role**: Developer is enough for uploading builds; you don't need Admin.
5. Click **Generate Token** — the full token is shown **once**. Copy it
   immediately and store it somewhere safe (e.g. directly into the GitHub
   secret in the next step) — Appetize will only ever show a masked
   version of it again afterward.

### 4. Add the token as a GitHub secret

1. On GitHub: your fork → **Settings** → **Secrets and variables** →
   **Actions** → **Secrets** tab → **New repository secret**.
2. Name: `APPETIZE_API_TOKEN`
3. Value: paste the token Appetize gave you.
4. Save.

### 5. Run the Appetize preview build

You do **not** need to build `Libmpv.xcframework` yourself, and you do
**not** need to publish a release from your fork. That framework is a big,
slow cross-compilation (mbedtls, dav1d, ffmpeg, libass, libplacebo, mpv —
see the main [README](README.md) if you're curious what that involves) that
only the main project needs to build and publish. As a contributor, your
job is to test the app, fix bugs, and add features — not to re-run that
whole pipeline.

The `appetize-preview.yml` workflow already knows this: it automatically
downloads the prebuilt `Libmpv.xcframework.zip` from the main project's own
GitHub Releases, so your fork only ever needs to touch
`mpv-ios-player/` (the app) or `MPVKit/Sources/` (the Swift wrapper) — the
parts you're actually likely to be changing.

To run it:

1. Your fork → **Actions** tab → **appetize-preview** workflow (left
   sidebar) → **Run workflow** button → pick your branch → **Run workflow**.
2. Wait for it to finish (a full build typically takes several minutes).
3. Open the run's log and expand the **"Upload to Appetize.io (new app)"**
   step. Look for a `publicKey` value in its output.
4. **Save that publicKey** as a repository *variable* (not secret) so
   future runs update the same app instead of creating a new one each
   time (Free plan has a cap on distinct apps):
   - Your fork → Settings → Secrets and variables → Actions → **Variables** tab
     → New repository variable → name `APPETIZE_PUBLIC_KEY`, paste the key.

**If this step fails** with an error about not finding
`Libmpv.xcframework.zip`: this almost always means the main project hasn't
published a release yet, not something wrong on your end — open an issue
on the main repo using the **Build / CI Failure** template
(see [CONTRIBUTING.md](CONTRIBUTING.md)) rather than trying to build and
publish the framework yourself.

> **Only relevant if you're the project maintainer, not a contributor:**
> the framework itself is built and published by pushing a version tag
> (`git tag v1.0.0 && git push --tags`), which triggers `release.yml`. This
> is a maintainer task, done on the main repository — contributors testing
> from a fork should never need to do this.

## Actually testing the app

1. Go to https://appetize.io/dashboard
2. You'll see your uploaded app (named after the note/publicKey). Click it.
3. Click **Play** / **Tap to play** on the embedded phone frame.
4. After a short boot (a few seconds), you'll see the app's UI live —
   the "mpv-ios" screen with **Open File** / **Open URL** buttons — and it
   is genuinely interactive: click and drag with your mouse the way you'd
   tap and swipe on a real phone.

### What you can actually test this way

- **UI rendering**: does `MPVRootView`, `MPVPlayerView`, the track sheet,
  etc. look and lay out correctly.
- **Navigation**: tapping "Open URL", typing a URL, tapping Play — does
  the player screen appear.
- **Basic interaction**: tap-to-toggle controls, the seek bar responding
  to drags, buttons reacting to taps.
- **Crashes on launch**: if MPVCore.create()/initialize() throws or the
  render context fails to attach, you'll see it immediately (either a
  visible error banner from `PlayerViewModel.errorMessage`, or the app
  crashing back to springboard).

### What this will NOT reliably tell you

- **Real video playback quality/performance** — the Simulator's GPU/video
  path does not exercise real VideoToolbox hardware decode the way a
  physical device does. A file may play in the Simulator and still behave
  differently in frame timing, decode speed, or power draw on a real
  iPhone.
- **Network video URLs may or may not load** — Appetize's simulator has
  its own network path; test with a known-public direct video URL (an
  `.mp4` link) rather than something behind auth/geo-restriction for a
  clean test.
- Free tier streaming time is capped per day — if the embed stops
  responding, you've likely hit the daily limit; it resets the next day.

## Day-to-day (after the one-time setup above)

Once `APPETIZE_PUBLIC_KEY` is saved as a repo variable, any push to
`main`/`master` touching `mpv-ios-player/` or `MPVKit/Sources/` will
automatically rebuild and update the same Appetize app in place — refresh
https://appetize.io/dashboard, click your app, and the latest build is
already there waiting to test. No need to re-run anything manually unless
you want to test a branch that isn't `main`/`master` (use **Run workflow**
manually for that).
