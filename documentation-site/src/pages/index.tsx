import type { ReactNode } from 'react';
import clsx from 'clsx';
import Link from '@docusaurus/Link';
import Layout from '@theme/Layout';
import Heading from '@theme/Heading';

import styles from './index.module.css';

function HomepageHeader() {
  return (
    <header className={clsx('hero hero--primary', styles.heroBanner)}>
      <div className="container">
        <Heading as="h1" className="hero__title">
          mpv-ios
        </Heading>
        <p className="hero__subtitle">
          A libmpv-based media player for iOS — plays what AVPlayer won't.
        </p>
        <div className={styles.buttons}>
          <Link className="button button--secondary button--lg" to="/docs/">
            Read the Docs
          </Link>
          <Link
            className="button button--outline button--secondary button--lg"
            to="/research"
            style={{ marginLeft: '1rem' }}>
            Research Log
          </Link>
        </div>
      </div>
    </header>
  );
}

const features = [
  {
    title: 'Real libmpv, not AVPlayer',
    description: (
      <>
        The same playback engine behind VLC, IINA, and mpv-android. MKV,
        obscure subtitle formats, and codec combinations AVPlayer simply
        refuses to open.
      </>
    ),
  },
  {
    title: 'Native Swift & SwiftUI',
    description: (
      <>
        MPVKit wraps libmpv's C API in a clean Swift interface —
        MPVCore, MPVPlayer, and an EAGL-based render view — no
        Objective-C bridging headaches in application code.
      </>
    ),
  },
  {
    title: 'Documented, not just working',
    description: (
      <>
        Every non-obvious build decision and bug fix is written up in the{' '}
        <Link to="/docs/research">Research Log</Link> — a rare level of
        transparency for a cross-compiled iOS project.
      </>
    ),
  },
];

function Feature({ title, description }: { title: string; description: ReactNode }) {
  return (
    <div className={clsx('col col--4')}>
      <div className="padding-horiz--md">
        <Heading as="h3">{title}</Heading>
        <p>{description}</p>
      </div>
    </div>
  );
}

export default function Home(): ReactNode {
  return (
    <Layout
      title="mpv-ios"
      description="A libmpv-based media player for iOS, documentation and engineering notes.">
      <HomepageHeader />
      <main>
        <section className={styles.features}>
          <div className="container">
            <div className="row">
              {features.map((props, idx) => (
                <Feature key={idx} {...props} />
              ))}
            </div>
          </div>
        </section>
      </main>
    </Layout>
  );
}
