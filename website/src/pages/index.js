import React from 'react';
import Layout from '@theme/Layout';
import Link from '@docusaurus/Link';
import useDocusaurusContext from '@docusaurus/useDocusaurusContext';
import styles from './index.module.css';

function DownloadHero() {
  const {siteConfig} = useDocusaurusContext();
  const {appVersion, downloadUrl, releaseNotesUrl} = siteConfig.customFields;

  return (
    <main className={styles.hero}>
      <section className={styles.copy}>
        <img src="img/app-icon.png" alt="" className={styles.appIcon} />
        <p className={styles.kicker}>macOS menu bar app</p>
        <h1>Work Screen Time</h1>
        <p className={styles.lede}>
          A small app that notices when you are working past the boundary you
          set, then puts a full-screen reminder between you and one more task.
        </p>
        <div className={styles.actions}>
          <Link className={styles.primaryButton} href={downloadUrl}>
            Download for Mac
          </Link>
          <span className={styles.version}>Version {appVersion}</span>
        </div>
      </section>

      <section className={styles.panel} aria-label="Install notes">
        <h2>Installation</h2>
        <div className={styles.installGuide}>
          <img src="img/install-guide.svg" alt="Drag Work Screen Time to Applications" className={styles.guideImage} />
        </div>
        <p>
          Download and unzip the app, then drag <strong>Work Screen Time</strong> into the <strong>Applications</strong> folder using the shortcut provided.
        </p>
        <p>
          As this build is unsigned, macOS Gatekeeper may block it. To open:
        </p>
        <ul>
          <li>Right-click (Control-click) the app in Finder and choose <strong>Open</strong>.</li>
          <li>If blocked, go to <strong>System Settings</strong> &gt; <strong>Privacy & Security</strong> and click <strong>Open Anyway</strong>.</li>
          <li>Or run: <code>xattr -rd com.apple.quarantine /Applications/WorkScreenTimeApp.app</code></li>
        </ul>
        <div className={styles.links}>
          <Link href={releaseNotesUrl}>Release notes</Link>
          <a href="appcast.xml">Sparkle appcast</a>
        </div>
      </section>
    </main>
  );
}

export default function Home() {
  return (
    <Layout
      title="Download"
      description="Download Work Screen Time for macOS.">
      <DownloadHero />
    </Layout>
  );
}
