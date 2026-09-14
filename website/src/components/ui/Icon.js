/**
 * Icon - Inline SVG icon set
 *
 * Stroke-based 24x24 icons drawn with `currentColor`, so they inherit the
 * surrounding text colour and work in both themes. Kept inline rather than
 * pulled from an icon package to avoid a runtime dependency and to keep the
 * set limited to what this site actually uses.
 *
 * @component
 * @param {Object} props
 * @param {string} props.name - Icon name from ICONS
 * @param {number|string} [props.size] - Rendered size in px
 * @param {string} [props.title] - Accessible label; omit for decorative icons
 * @returns {JSX.Element|null} Rendered icon
 * @file src/components/ui/Icon.js
 */
'use client';

import React from 'react';

const ICONS = {
  // Platforms
  globe: (
    <>
      <circle cx="12" cy="12" r="9" />
      <path d="M3 12h18" />
      <path d="M12 3c2.4 2.5 3.7 5.6 3.7 9S14.4 18.5 12 21c-2.4-2.5-3.7-5.6-3.7-9S9.6 5.5 12 3z" />
    </>
  ),
  smartphone: (
    <>
      <rect x="7" y="2" width="10" height="20" rx="2.5" />
      <path d="M11 18.5h2" />
    </>
  ),
  tablet: (
    <>
      <rect x="5" y="2" width="14" height="20" rx="2.5" />
      <path d="M10.5 18.5h3" />
    </>
  ),
  monitor: (
    <>
      <rect x="2" y="4" width="20" height="12.5" rx="2" />
      <path d="M12 16.5V20" />
      <path d="M8 20h8" />
    </>
  ),
  terminal: (
    <>
      <rect x="2" y="3.5" width="20" height="17" rx="2" />
      <path d="M7 9.5l3 3-3 3" />
      <path d="M13 15.5h4" />
    </>
  ),

  // Care and clinical
  clipboard: (
    <>
      <path d="M9 4H7a2 2 0 0 0-2 2v13a2 2 0 0 0 2 2h10a2 2 0 0 0 2-2V6a2 2 0 0 0-2-2h-2" />
      <rect x="9" y="2" width="6" height="4" rx="1.2" />
      <path d="M9 12h6" />
      <path d="M9 16h4" />
    </>
  ),
  stethoscope: (
    <>
      <path d="M6 3v5.5a4.5 4.5 0 0 0 9 0V3" />
      <path d="M6 3H4.5" />
      <path d="M15 3h1.5" />
      <path d="M10.5 13v2.5a4.5 4.5 0 0 0 9 0V15" />
      <circle cx="19.5" cy="13" r="2" />
    </>
  ),
  pulse: (
    <>
      <path d="M2.5 12H7l2.5-7 4 14 2.5-7h5.5" />
    </>
  ),
  bed: (
    <>
      <path d="M3 20V8" />
      <path d="M3 12h18a0 0 0 0 1 0 0v8" />
      <path d="M3 16h18" />
      <circle cx="7.5" cy="9.5" r="2" />
    </>
  ),
  scissors: (
    <>
      <circle cx="6" cy="18" r="2.6" />
      <circle cx="6" cy="6" r="2.6" />
      <path d="M8.1 7.9L20 20" />
      <path d="M8.1 16.1L20 4" />
    </>
  ),
  flask: (
    <>
      <path d="M9 2.5v6.2L4.4 18a2 2 0 0 0 1.8 3h11.6a2 2 0 0 0 1.8-3L15 8.7V2.5" />
      <path d="M8 2.5h8" />
      <path d="M7 15h10" />
    </>
  ),
  scan: (
    <>
      <path d="M3 8V5.5A2.5 2.5 0 0 1 5.5 3H8" />
      <path d="M16 3h2.5A2.5 2.5 0 0 1 21 5.5V8" />
      <path d="M21 16v2.5a2.5 2.5 0 0 1-2.5 2.5H16" />
      <path d="M8 21H5.5A2.5 2.5 0 0 1 3 18.5V16" />
      <circle cx="12" cy="12" r="3.2" />
    </>
  ),
  pill: (
    <>
      <rect x="2.6" y="8.4" width="18.8" height="7.2" rx="3.6" transform="rotate(-45 12 12)" />
      <path d="M8.7 8.7l6.6 6.6" />
    </>
  ),

  // Finance and admin
  receipt: (
    <>
      <path d="M5 21V4a1 1 0 0 1 1-1h12a1 1 0 0 1 1 1v17l-2.6-1.6L14 21l-2-1.6L10 21l-2.4-1.6z" />
      <path d="M9 8h6" />
      <path d="M9 12h6" />
    </>
  ),
  wallet: (
    <>
      <rect x="3" y="6" width="18" height="14" rx="2.5" />
      <path d="M3 10h18" />
      <circle cx="17" cy="15" r="1.3" />
    </>
  ),
  chart: (
    <>
      <path d="M3 3v18h18" />
      <path d="M7 16l4-5 3.5 2.6L20 7" />
    </>
  ),
  building: (
    <>
      <rect x="4" y="2.5" width="16" height="19" rx="1.5" />
      <path d="M9 7h1.5M13.5 7H15" />
      <path d="M9 11h1.5M13.5 11H15" />
      <path d="M10 21.5v-4h4v4" />
    </>
  ),
  shield: (
    <>
      <path d="M12 2.5l8 3.2v6c0 5.1-3.4 8.8-8 10.3-4.6-1.5-8-5.2-8-10.3v-6z" />
      <path d="M9.2 12.2l2 2 3.6-3.9" />
    </>
  ),
  settings: (
    <>
      <path d="M4 7h10" />
      <path d="M18 7h2" />
      <path d="M4 12h4" />
      <path d="M12 12h8" />
      <path d="M4 17h9" />
      <path d="M17 17h3" />
      <circle cx="16" cy="7" r="2" />
      <circle cx="10" cy="12" r="2" />
      <circle cx="15" cy="17" r="2" />
    </>
  ),
  users: (
    <>
      <circle cx="9" cy="8" r="3.4" />
      <path d="M2.8 20.5a6.2 6.2 0 0 1 12.4 0" />
      <path d="M16.5 5.2a3.4 3.4 0 0 1 0 6.4" />
      <path d="M18 14.6a6.2 6.2 0 0 1 3.2 5.9" />
    </>
  ),
  userPlus: (
    <>
      <circle cx="10" cy="8" r="3.6" />
      <path d="M3.5 20.5a6.5 6.5 0 0 1 13 0" />
      <path d="M19 7.5v5" />
      <path d="M16.5 10h5" />
    </>
  ),
  user: (
    <>
      <circle cx="12" cy="8" r="3.6" />
      <path d="M5.5 20.5a6.5 6.5 0 0 1 13 0" />
    </>
  ),
  headset: (
    <>
      <path d="M4 13v-1a8 8 0 0 1 16 0v1" />
      <rect x="2.5" y="13" width="4.5" height="6.5" rx="2" />
      <rect x="17" y="13" width="4.5" height="6.5" rx="2" />
      <path d="M19 19.5v.5a2.5 2.5 0 0 1-2.5 2.5H13" />
    </>
  ),

  // Intent and story
  target: (
    <>
      <circle cx="12" cy="12" r="8.5" />
      <circle cx="12" cy="12" r="4.8" />
      <circle cx="12" cy="12" r="1.4" />
    </>
  ),
  eye: (
    <>
      <path d="M2 12s3.8-6.8 10-6.8S22 12 22 12s-3.8 6.8-10 6.8S2 12 2 12z" />
      <circle cx="12" cy="12" r="3" />
    </>
  ),
  heart: (
    <>
      <path d="M12 20.8S3.8 15.5 3.8 9.8A4.4 4.4 0 0 1 12 7.3a4.4 4.4 0 0 1 8.2 2.5c0 5.7-8.2 11-8.2 11z" />
    </>
  ),
  flag: (
    <>
      <path d="M5 21.5V3" />
      <path d="M5 4h12l-2.4 3.6L17 11.2H5" />
    </>
  ),
  layers: (
    <>
      <path d="M12 2.8l9 4.6-9 4.6-9-4.6z" />
      <path d="M3 12.4l9 4.6 9-4.6" />
      <path d="M3 17l9 4.6 9-4.6" />
    </>
  ),
  sparkle: (
    <>
      <path d="M12 2.5l2.2 5.8L20 10.5l-5.8 2.2L12 18.5l-2.2-5.8L4 10.5l5.8-2.2z" />
      <path d="M18.5 17l.9 2.3 2.3.9-2.3.9-.9 2.3-.9-2.3-2.3-.9 2.3-.9z" />
    </>
  ),
  clock: (
    <>
      <circle cx="12" cy="12" r="9" />
      <path d="M12 7v5.4l3.4 2" />
    </>
  ),

  // Contact
  mail: (
    <>
      <rect x="2.5" y="4.5" width="19" height="15" rx="2.5" />
      <path d="M3 7l9 6 9-6" />
    </>
  ),
  phone: (
    <>
      <path d="M6.6 3h-2A1.6 1.6 0 0 0 3 4.7C3 13.7 10.3 21 19.3 21a1.6 1.6 0 0 0 1.7-1.6v-2a1.6 1.6 0 0 0-1.3-1.6l-3-.6a1.6 1.6 0 0 0-1.6.7l-1 1.4a13 13 0 0 1-5.4-5.4l1.4-1a1.6 1.6 0 0 0 .7-1.6l-.6-3A1.6 1.6 0 0 0 6.6 3z" />
    </>
  ),
  mapPin: (
    <>
      <path d="M12 21.5s7-6.4 7-12a7 7 0 1 0-14 0c0 5.6 7 12 7 12z" />
      <circle cx="12" cy="9.5" r="2.6" />
    </>
  ),
  message: (
    <>
      <path d="M21 11.6a8.4 8.4 0 0 1-11.9 7.6L3 21l1.8-6.1A8.4 8.4 0 1 1 21 11.6z" />
    </>
  ),
  send: (
    <>
      <path d="M21.5 2.5L11 13" />
      <path d="M21.5 2.5l-6.6 19-3.9-8.5-8.5-3.9z" />
    </>
  ),
  code: (
    <>
      <path d="M8.5 8L4 12l4.5 4" />
      <path d="M15.5 8L20 12l-4.5 4" />
      <path d="M13.5 4.5l-3 15" />
    </>
  ),

  // Interface
  arrowRight: (
    <>
      <path d="M4.5 12h15" />
      <path d="M13 5.5l6.5 6.5-6.5 6.5" />
    </>
  ),
  check: (
    <>
      <path d="M4.5 12.5l5 5 10-11" />
    </>
  ),
  external: (
    <>
      <path d="M14 4h6v6" />
      <path d="M20 4l-8.5 8.5" />
      <path d="M18 14.5V19a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2V8a2 2 0 0 1 2-2h4.5" />
    </>
  ),
  book: (
    <>
      <path d="M4 4.5A2.5 2.5 0 0 1 6.5 2H20v16H6.5A2.5 2.5 0 0 0 4 20.5z" />
      <path d="M4 20.5A2.5 2.5 0 0 1 6.5 18H20v4H6.5A2.5 2.5 0 0 1 4 19.5z" />
    </>
  ),
  download: (
    <>
      <path d="M12 3.5v12" />
      <path d="M7 11l5 5 5-5" />
      <path d="M4.5 20.5h15" />
    </>
  ),
  list: (
    <>
      <path d="M9 6h11" />
      <path d="M9 12h11" />
      <path d="M9 18h11" />
      <circle cx="4.5" cy="6" r="1" />
      <circle cx="4.5" cy="12" r="1" />
      <circle cx="4.5" cy="18" r="1" />
    </>
  ),
  info: (
    <>
      <circle cx="12" cy="12" r="9" />
      <path d="M12 11v5.5" />
      <path d="M12 7.5h.01" />
    </>
  ),
  alert: (
    <>
      <path d="M10.3 3.9L2.5 17.5A2 2 0 0 0 4.2 20.5h15.6a2 2 0 0 0 1.7-3L13.7 3.9a2 2 0 0 0-3.4 0z" />
      <path d="M12 9v4.5" />
      <path d="M12 17h.01" />
    </>
  ),
  lightbulb: (
    <>
      <path d="M9 18h6" />
      <path d="M10 21h4" />
      <path d="M12 3a6 6 0 0 0-3.6 10.8c.7.6 1.1 1.3 1.1 2.2h5c0-.9.4-1.6 1.1-2.2A6 6 0 0 0 12 3z" />
    </>
  ),
  chevronDown: (
    <>
      <path d="M6 9.5l6 6 6-6" />
    </>
  ),
  panelClose: (
    <>
      <rect x="3" y="4" width="18" height="16" rx="2" />
      <path d="M9 4v16" />
      <path d="M16 9.5L13.5 12l2.5 2.5" />
    </>
  ),
  panelOpen: (
    <>
      <rect x="3" y="4" width="18" height="16" rx="2" />
      <path d="M9 4v16" />
      <path d="M13.5 9.5L16 12l-2.5 2.5" />
    </>
  ),
};

export const ICON_NAMES = Object.keys(ICONS);

export const Icon = React.memo(({ name, size = 24, title, ...props }) => {
  const glyph = ICONS[name];

  if (!glyph) {
    if (process.env.NODE_ENV === 'development') {
      console.warn(`Icon "${name}" does not exist`);
    }
    return null;
  }

  return (
    <svg
      xmlns="http://www.w3.org/2000/svg"
      viewBox="0 0 24 24"
      width={size}
      height={size}
      fill="none"
      stroke="currentColor"
      strokeWidth="1.7"
      strokeLinecap="round"
      strokeLinejoin="round"
      role={title ? 'img' : undefined}
      aria-hidden={title ? undefined : 'true'}
      focusable="false"
      {...props}
    >
      {title && <title>{title}</title>}
      {glyph}
    </svg>
  );
});

Icon.displayName = 'Icon';
