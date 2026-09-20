/**
 * ManualView - User manual page: hero, search and chapters
 *
 * Client wrapper so the search index is built once and shared by the hero
 * field and the contents field. Keyboard shortcuts land on the field that is
 * actually on screen: the hero while it is in view, otherwise the contents.
 *
 * @component
 * @param {Object} props
 * @param {Array<Object>} props.chapters - Numbered chapters from numberUserManual()
 * @param {Object} props.figures - Screenshot data keyed by figure id
 * @param {string} props.eyebrow - Small label above the title
 * @param {string} props.title - Page title
 * @param {string} props.intro - Summary paragraph
 * @param {Array<{icon: string, label: string}>} [props.meta] - Facts about the manual
 * @param {string} props.downloadLabel - Download button text
 * @param {string} props.appHref - Application URL
 * @param {string} props.appLabel - Application link text
 * @returns {JSX.Element} Rendered manual
 * @file src/components/manual/ManualView.js
 */
'use client';

import React, { useCallback, useEffect, useMemo, useRef } from 'react';
import { ManualBody } from './ManualBody';
import { ManualHero } from './ManualHero';
import { ManualSearch } from './ManualSearch';
import { buildManualSearchIndex } from '@/lib/manualSearch';

function isTypingInField(target) {
  return target instanceof HTMLElement && (
    target.isContentEditable
    || ['INPUT', 'TEXTAREA', 'SELECT'].includes(target.tagName)
  );
}

export const ManualView = React.memo(({
  chapters,
  figures,
  eyebrow,
  title,
  intro,
  meta,
  downloadLabel,
  appHref,
  appLabel,
}) => {
  const index = useMemo(() => buildManualSearchIndex(chapters), [chapters]);
  const bodyRef = useRef(null);
  const heroSearchRef = useRef(null);
  const sidebarSearchRef = useRef(null);

  const selectSection = useCallback((id) => {
    if (window.location.hash === `#${id}`) {
      bodyRef.current?.selectSection(id);
      return;
    }
    window.location.hash = id;
  }, []);

  const focusSearch = useCallback(() => {
    const header = document.querySelector('header[role="banner"]');
    const headerBottom = header ? header.getBoundingClientRect().bottom : 0;
    const heroField = document.querySelector('#user-manual-title')
      ?.closest('section')
      ?.querySelector('input[type="search"]');
    const heroRect = heroField?.getBoundingClientRect();
    const heroVisible = Boolean(
      heroRect
      && heroRect.bottom > headerBottom + 8
      && heroRect.top < window.innerHeight
    );

    if (heroVisible) {
      heroSearchRef.current?.focus();
      return;
    }

    bodyRef.current?.revealSearch();
    window.requestAnimationFrame(() => {
      window.requestAnimationFrame(() => {
        sidebarSearchRef.current?.focus();
      });
    });
  }, []);

  useEffect(() => {
    const handleKeyDown = (event) => {
      if ((event.ctrlKey || event.metaKey) && event.key.toLowerCase() === 'k') {
        event.preventDefault();
        focusSearch();
        return;
      }
      if (
        event.key === '/'
        && !isTypingInField(event.target)
        && !event.ctrlKey
        && !event.metaKey
        && !event.altKey
      ) {
        event.preventDefault();
        focusSearch();
      }
    };

    document.addEventListener('keydown', handleKeyDown);
    return () => document.removeEventListener('keydown', handleKeyDown);
  }, [focusSearch]);

  return (
    <>
      <ManualHero
        eyebrow={eyebrow}
        title={title}
        intro={intro}
        meta={meta}
        downloadLabel={downloadLabel}
        appHref={appHref}
        appLabel={appLabel}
        search={
          <ManualSearch
            ref={heroSearchRef}
            variant="hero"
            index={index}
            shortcut={false}
            onSelect={selectSection}
          />
        }
      />
      <ManualBody
        ref={bodyRef}
        chapters={chapters}
        figures={figures}
        searchIndex={index}
        searchRef={sidebarSearchRef}
      />
    </>
  );
});

ManualView.displayName = 'ManualView';
