# mpv-ios documentation site

This is the source for the mpv-ios documentation site, built with
[Docusaurus](https://docusaurus.io/) and deployed to GitHub Pages.

## Before you deploy

Three placeholders need replacing with your actual GitHub username/org
before this works as a live site — search for `YOUR-GITHUB-USERNAME` and
replace every occurrence:

- `docusaurus.config.js` — `url`, `organizationName`, and the `editUrl`
  in the docs preset options.
- Any `github.com/YOUR-GITHUB-USERNAME/...` links elsewhere in the site.

## Local development

```bash
npm install
npm start
```

This starts a local dev server at `http://localhost:3000` with hot
reload. Most changes are reflected live without restarting the server.

## Build

```bash
npm run build
```

Generates a static site into `build/`. This is what
`.github-workflow-deploy-docs.yml` (move this file to
`.github/workflows/deploy-docs.yml` in the repo root — see below) runs in
CI.

## Deployment

This site deploys via GitHub Actions to GitHub Pages, automatically, on
every push to `main`/`master` that touches this folder. Setup steps:

1. Move `.github-workflow-deploy-docs.yml` (in this folder) to
   `.github/workflows/deploy-docs.yml` at the repo root — it was named
   with a leading dot-prefix instead of living directly in
   `.github/workflows/` here only so it wouldn't be mistaken for an
   already-active workflow before you've reviewed and placed it.
2. On GitHub: repo → Settings → Pages → **Source** → select **"GitHub
   Actions"** (not "Deploy from a branch" — the workflow handles
   deployment directly).
3. Push a change under `documentation-site/` to `main`/`master`, or
   trigger the workflow manually from the Actions tab.
4. Once the workflow succeeds, your site is live at
   `https://<your-username>.github.io/mpv-ios/` (adjust if your repo name
   differs from `mpv-ios`, matching whatever `baseUrl`/`projectName` you
   set in `docusaurus.config.js`).

## Content structure

```
documentation-site/
├── docs/
│   ├── index.md              # Landing/intro page
│   ├── building.md           # Build instructions
│   ├── architecture.md       # Architecture decisions
│   ├── testing-without-a-mac.md
│   ├── contributing.md
│   ├── roadmap.md
│   ├── url-scheme.md
│   ├── privacy-policy.md
│   ├── release-process.md
│   └── research/             # Engineering Notes / Research Log
│       ├── index.md          # Category landing page
│       ├── 01-*.md .. 16-*.md  # One page per research log entry
│       └── 99-general-patterns.md
├── src/
│   ├── css/custom.css        # Theme colors
│   └── pages/index.tsx       # Homepage hero (separate from docs/index.md)
├── static/img/               # Logo, favicon, social card - see img/README.md
├── docusaurus.config.js
├── sidebars.js
└── package.json
```

## Keeping docs in sync with the main repo

This site's content was generated from the repo's existing Markdown docs
(`README.md`, `CONTRIBUTING.md`, `ROADMAP.md`, `TESTING.md`,
`docs/*.md`, `docs/RESEARCH.md`). It is **not** automatically kept in
sync — if you update one of those source files, the corresponding page
here needs updating too.

The Research Log entries in `docs/research/` were split programmatically
from a single `RESEARCH.md`, one entry per file, each with Docusaurus
front-matter added. If `docs/RESEARCH.md` (in the repo root's `docs/`
folder) gains new entries, add a correspondingly-numbered file here
rather than growing an existing one, to keep the one-entry-per-page
structure intact.
