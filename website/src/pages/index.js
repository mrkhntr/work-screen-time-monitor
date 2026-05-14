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
        <h2>For friends trying it</h2>
        <p>
          Download the zip, unzip it, and open Work Screen Time. Since this
          early build is not Developer ID signed, macOS may ask you to
          right-click the app and choose Open the first time.
        </p>
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
