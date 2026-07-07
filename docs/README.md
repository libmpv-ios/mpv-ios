# mpv-ios Documentation

This folder contains reference documentation beyond the top-level guides.
If you're new here, start with the repo root instead:

- **[README.md](../README.md)** — project overview, build steps, architecture notes.
- **[CONTRIBUTING.md](../CONTRIBUTING.md)** — why and how to contribute.
- **[ROADMAP.md](../ROADMAP.md)** — current status and future plans.
- **[TESTING.md](../TESTING.md)** — testing the app without a Mac or iPhone.

## In this folder

- **[RESEARCH.md](RESEARCH.md)** — chronological log of every bug found
  and fixed while porting mpv to iOS: what broke, why, how it was
  diagnosed, and what was learned. The best starting point if you're
  picking up development after a break, or hitting an error that might
  already be documented here.
- **[url_scheme.md](url_scheme.md)** — the URL scheme / Universal Links
  integration spec for launching mpv-ios from another app (mirrors
  mpv-android's Intent specification). Currently a proposed spec, not yet
  implemented — see the status note at the top of that file.
- **[privacy_policy.md](privacy_policy.md)** — the app's privacy policy.
- **[release_process.md](release_process.md)** — maintainer-only release
  checklist. Not needed unless you're cutting a release.

Unlike mpv-android's `docs/` folder, this one isn't published as a
separate GitHub Pages site (mpv-android's `index.html` + `default.css`
serve that purpose there) — everything here renders natively as Markdown
directly on GitHub, which was simpler to keep in sync given this project
doesn't yet have the CI/Pages setup that would be needed to publish an
HTML version. If that changes, this index would become the natural
landing page to convert.
