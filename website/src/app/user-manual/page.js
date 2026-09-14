/**
 * User Manual Page - Step-by-step guide to using HOSSPI HMS
 *
 * Server Component. Renders the manual from src/lib/userManual.js, the same
 * content the downloadable PDF is printed from, so the page and the PDF match.
 */

import { StructuredData } from '@/components/common';
import { ManualHero, ManualBody } from '@/components/manual';
import { APP_NAME, APP_URL, APP_LOGIN_URL } from '@/lib/constants';
import { HMS_NAME } from '@/lib/product';
import { USER_MANUAL, USER_MANUAL_PDF_PATH, numberUserManual } from '@/lib/userManual';
import figures from '@/lib/userManualFigures.json';
import pdfInfo from '@/lib/userManualPdf.json';

const PAGE_DESCRIPTION = `Step-by-step user manual for ${HMS_NAME}: registration, sign-in, setup, users and roles, the patient journey, billing, accounts and reports, with annotated screenshots.`;

export const metadata = {
  title: 'User manual',
  description: PAGE_DESCRIPTION,
  keywords: [
    'HOSSPI user manual',
    'HOSSPI HMS manual',
    'hospital management system user manual',
    'HMS user guide PDF',
  ],
  alternates: {
    canonical: `${APP_URL}/user-manual`,
  },
  openGraph: {
    title: `User manual | ${HMS_NAME}`,
    description: PAGE_DESCRIPTION,
    url: `${APP_URL}/user-manual`,
    siteName: APP_NAME,
    images: [
      {
        url: `${APP_URL}/logos/og-image.png`,
        width: 1200,
        height: 630,
        alt: HMS_NAME,
      },
    ],
    type: 'article',
  },
  twitter: {
    card: 'summary_large_image',
    title: `User manual | ${HMS_NAME}`,
    description: PAGE_DESCRIPTION,
    images: [`${APP_URL}/logos/og-image.png`],
  },
};

export const revalidate = 3600;

function formatBytes(bytes) {
  if (!bytes) {
    return null;
  }
  const megabytes = bytes / (1024 * 1024);
  return megabytes >= 1 ? `${megabytes.toFixed(1)} MB` : `${Math.round(bytes / 1024)} KB`;
}

function formatDate(isoDate) {
  return new Intl.DateTimeFormat('en-GB', {
    day: 'numeric',
    month: 'long',
    year: 'numeric',
    timeZone: 'UTC',
  }).format(new Date(`${isoDate}T00:00:00Z`));
}

export default function UserManualPage() {
  const chapters = numberUserManual(USER_MANUAL);
  const topicCount = chapters.reduce((total, chapter) => total + chapter.sections.length, 0);

  const meta = [
    { icon: 'book', label: `${chapters.length} chapters, ${topicCount} topics` },
    { icon: 'clock', label: `Updated ${formatDate(USER_MANUAL.updated)}` },
    pdfInfo?.pages
      ? { icon: 'download', label: `PDF, ${pdfInfo.pages} pages, ${formatBytes(pdfInfo.bytes)}` }
      : null,
  ].filter(Boolean);

  const manualSchema = {
    '@context': 'https://schema.org',
    '@type': 'TechArticle',
    headline: USER_MANUAL.title,
    description: PAGE_DESCRIPTION,
    url: `${APP_URL}/user-manual`,
    dateModified: USER_MANUAL.updated,
    inLanguage: 'en',
    about: {
      '@type': 'SoftwareApplication',
      name: HMS_NAME,
      applicationCategory: 'HealthApplication',
      url: APP_LOGIN_URL,
    },
    encoding: {
      '@type': 'MediaObject',
      contentUrl: `${APP_URL}${USER_MANUAL_PDF_PATH}`,
      encodingFormat: 'application/pdf',
    },
  };

  return (
    <>
      <StructuredData data={manualSchema} />
      <ManualHero
        eyebrow={HMS_NAME}
        title="User manual"
        intro={USER_MANUAL.intro}
        meta={meta}
        downloadLabel="Download user manual"
        appHref={APP_LOGIN_URL}
        appLabel="Open the app"
      />
      <ManualBody chapters={chapters} figures={figures} />
    </>
  );
}
