/**
 * ManualRichText - Inline formatting for user manual copy
 *
 * Supports the two inline marks the manual content uses: **bold** for the
 * exact on-screen labels, and [label](#section-id) for cross references.
 * Anything else renders as plain text, so content can never inject markup.
 *
 * @component
 * @param {Object} props
 * @param {string} props.text - Manual copy
 * @returns {JSX.Element} Rendered inline content
 * @file src/components/manual/ManualRichText.js
 */
'use client';

import React from 'react';

const TOKEN = /(\*\*[^*]+\*\*|\[[^\]]+\]\(#[a-z0-9-]+\))/g;
const LINK = /^\[([^\]]+)\]\((#[a-z0-9-]+)\)$/;

export const ManualRichText = React.memo(({ text }) => {
  const parts = String(text ?? '').split(TOKEN).filter(Boolean);

  return (
    <>
      {parts.map((part, index) => {
        if (part.startsWith('**') && part.endsWith('**')) {
          return <strong key={index}>{part.slice(2, -2)}</strong>;
        }
        const link = part.match(LINK);
        if (link) {
          return <a key={index} href={link[2]}>{link[1]}</a>;
        }
        return <React.Fragment key={index}>{part}</React.Fragment>;
      })}
    </>
  );
});

ManualRichText.displayName = 'ManualRichText';
