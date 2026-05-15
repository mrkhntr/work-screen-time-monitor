// @ts-check

const config = {
  title: 'Work Screen Time',
  tagline: 'A calmer stop-working boundary for macOS.',
  url: 'https://mrkhntr.com',
  baseUrl: '/work-screen-time-monitor/',
  organizationName: 'mrkhntr',
  projectName: 'work-screen-time-monitor',
  favicon: 'img/favicon.png',
  onBrokenLinks: 'throw',
  trailingSlash: false,
  markdown: {
    hooks: {
      onBrokenMarkdownLinks: 'warn',
    },
  },
  i18n: {
    defaultLocale: 'en',
    locales: ['en'],
  },
  customFields: {
    appVersion: process.env.WORK_SCREEN_TIME_VERSION || 'local',
    downloadUrl:
      process.env.WORK_SCREEN_TIME_DOWNLOAD_URL ||
      'https://github.com/mrkhntr/work-screen-time-monitor/releases/latest',
    releaseNotesUrl:
      process.env.WORK_SCREEN_TIME_RELEASE_NOTES_URL ||
      'https://github.com/mrkhntr/work-screen-time-monitor/releases/latest',
  },
  presets: [
    [
      'classic',
      {
        docs: false,
        blog: false,
        theme: {
          customCss: require.resolve('./src/css/custom.css'),
        },
      },
    ],
  ],
  themeConfig: {
    metadata: [
      {
        name: 'description',
        content:
          'Download Work Screen Time, a macOS menu bar app that reminds you to stop working after hours.',
      },
    ],
    navbar: {
      title: 'Work Screen Time',
      logo: {
        alt: 'Work Screen Time',
        src: 'img/logo.png',
      },
      items: [
        {
          href: 'https://github.com/mrkhntr/work-screen-time-monitor',
          label: 'GitHub',
          position: 'right',
        },
      ],
    },
    footer: {
      style: 'dark',
      links: [
        {
          title: 'Release',
          items: [
            {
              label: 'Sparkle appcast',
              href: 'https://mrkhntr.com/work-screen-time-monitor/appcast.xml',
            },
            {
              label: 'Source',
              href: 'https://github.com/mrkhntr/work-screen-time-monitor',
            },
          ],
        },
      ],
      copyright: `Copyright © ${new Date().getFullYear()} Mark Hunter.`,
    },
  },
};

module.exports = config;
