// @ts-check
// Docusaurus configuration for the mpv-ios documentation site.
// See https://docusaurus.io/docs/api/docusaurus-config for the full
// reference of every option used below.

import { themes as prismThemes } from 'prism-react-renderer';

/**
 * IMPORTANT: replace the placeholders below before deploying:
 *   - `organizationName`: your GitHub username/org
 *   - `projectName`: your repo name (assumed "mpv-ios" here)
 *   - `url`: your GitHub Pages URL, following the pattern
 *     https://<organizationName>.github.io
 * These three must be correct for GitHub Pages deployment and for the
 * "Edit this page" links to point at the right repository.
 */

/** @type {import('@docusaurus/types').Config} */
const config = {
  title: 'mpv-ios',
  tagline: 'A libmpv-based media player for iOS — documentation and build/porting notes',
  favicon: 'img/favicon.ico',

  future: {
    v4: true, // opt in to Docusaurus v4 compatibility improvements early
  },

  // Set the production url of your site here
  url: 'https://libmpv-ios.github.io',
  // Set the /<baseUrl>/ pathname under which your site is served
  // For GitHub pages deployment, it is often '/<projectName>/'
  baseUrl: '/mpv-ios/',

  // GitHub pages deployment config.
  organizationName: 'YOUR-GITHUB-USERNAME', // Usually your GitHub org/user name.
  projectName: 'mpv-ios', // Usually your repo name.
  deploymentBranch: 'gh-pages',
  trailingSlash: false,

  onBrokenLinks: 'warn',
  onBrokenMarkdownLinks: 'warn',

  // Even if you don't use internationalization, you can use this field to
  // set useful metadata like html lang.
  i18n: {
    defaultLocale: 'en',
    locales: ['en'],
  },

  presets: [
    [
      'classic',
      /** @type {import('@docusaurus/preset-classic').Options} */
      ({
        docs: {
          sidebarPath: './sidebars.js',
          editUrl:
            'https://github.com/YOUR-GITHUB-USERNAME/mpv-ios/edit/main/documentation-site/',
        },
        blog: false, // no blog section needed for this project
        theme: {
          customCss: './src/css/custom.css',
        },
      }),
    ],
  ],

  themeConfig:
    /** @type {import('@docusaurus/preset-classic').ThemeConfig} */
    ({
      // Replace with your own project social card image later (see
      // static/img/README.md for the expected dimensions).
      image: 'img/social-card.png',
      navbar: {
        title: 'mpv-ios',
        logo: {
          alt: 'mpv-ios logo',
          src: 'img/logo.png',
        },
        items: [
          {
            type: 'docSidebar',
            sidebarId: 'docsSidebar',
            position: 'left',
            label: 'Documentation',
          },
          {
            href: 'https://github.com/YOUR-GITHUB-USERNAME/mpv-ios',
            label: 'GitHub',
            position: 'right',
          },
        ],
      },
      footer: {
        style: 'dark',
        links: [
          {
            title: 'Docs',
            items: [
              { label: 'Getting Started', to: '/docs/' },
              { label: 'Research Log', to: '/docs/research' },
              { label: 'Roadmap', to: '/docs/roadmap' },
            ],
          },
          {
            title: 'Community',
            items: [
              {
                label: 'Contributing',
                to: '/docs/contributing',
              },
              {
                label: 'GitHub Issues',
                href: 'https://github.com/YOUR-GITHUB-USERNAME/mpv-ios/issues',
              },
            ],
          },
          {
            title: 'More',
            items: [
              {
                label: 'GitHub Repository',
                href: 'https://github.com/YOUR-GITHUB-USERNAME/mpv-ios',
              },
              {
                label: 'mpv-android (sibling project)',
                href: 'https://github.com/mpv-android/mpv-android',
              },
            ],
          },
        ],
        copyright: `Copyright © ${new Date().getFullYear()} mpv-ios contributors. Built with Docusaurus.`,
      },
      prism: {
        theme: prismThemes.github,
        darkTheme: prismThemes.dracula,
        additionalLanguages: ['bash', 'swift', 'diff', 'yaml', 'c'],
      },
      colorMode: {
        defaultMode: 'dark',
        respectPrefersColorScheme: true,
      },
      docs: {
        sidebar: {
          hideable: true,
          autoCollapseCategories: true,
        },
      },
    }),
};

export default config;
