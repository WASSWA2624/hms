/**
 * ManualBody - Contents and chapters of the user manual
 *
 * On computers with a mouse or trackpad, from 1024px wide, the manual fills
 * the window below the site header as two panes that scroll independently:
 * the contents on the left and the chapters on the right. The page still
 * scrolls as a whole around them. While the panes are only partly in view,
 * the wheel moves the page and stops it where the panes line up with the
 * header; from there it scrolls the pane under the pointer, and scrolling past
 * either end of the chapters carries on through the page. The contents
 * collapse to a narrow rail with their toggle button, and the choice is
 * remembered.
 *
 * Touch screens and narrower windows keep the chapters in the page's own
 * scroll, because scroll areas nested inside a scrolling page are awkward to
 * use by touch. There the contents open from a bar that stays below the site
 * header, scroll on their own and close once a topic is chosen.
 *
 * In both layouts the entry for the section being read is highlighted and
 * kept in view, and in-page links scroll whichever area holds their target.
 *
 * @component
 * @param {Object} props
 * @param {Array<Object>} props.chapters - Numbered chapters from numberUserManual()
 * @param {Object} props.figures - Screenshot data keyed by figure id
 * @param {Array<Object>} [props.searchIndex] - Prebuilt search index; built here if omitted
 * @param {React.Ref} [props.searchRef] - Ref forwarded to the contents search field
 * @returns {JSX.Element} Rendered manual body
 * @file src/components/manual/ManualBody.js
 */
'use client';

import React, { useCallback, useEffect, useMemo, useRef, useState, useSyncExternalStore, useImperativeHandle } from 'react';
import styled, { useTheme } from 'styled-components';
import { Icon } from '@/components/ui';
import { ManualBlocks } from './ManualBlocks';
import { ManualSearch } from './ManualSearch';
import { ManualToc } from './ManualToc';
import { buildManualSearchIndex } from '@/lib/manualSearch';

const CONTENTS_ID = 'manual-contents';
const CONTENTS_STORAGE_KEY = 'hosspi-manual-contents';
const CONTENTS_CHANGE_EVENT = 'hosspi-manual-contents-change';
/* Space left above a heading that has been scrolled to. */
const HEADING_GAP_PX = 24;
/* Scroll-spy pauses while a smooth scroll to a chosen heading runs. */
const NAVIGATION_LOCK_MS = 900;
/* A heading counts as being read once it is this far into the view. */
const READING_LINE_MAX_PX = 160;

/* Two scrolling panes need a precise pointer and room for both. */
const panesMedia = ({ theme }) =>
  `(min-width: ${theme.breakpoints.md}) and (hover: hover) and (pointer: fine)`;

/* null until the browser has answered, so the server and first client render agree. */
function useMediaQuery(query) {
  const [matches, setMatches] = useState(null);

  useEffect(() => {
    const list = window.matchMedia(query);
    const update = () => setMatches(list.matches);
    update();
    list.addEventListener('change', update);
    return () => list.removeEventListener('change', update);
  }, [query]);

  return matches;
}

function preferredScrollBehavior() {
  return window.matchMedia('(prefers-reduced-motion: reduce)').matches ? 'instant' : 'smooth';
}

/*
 * Whether the reader collapsed the contents, kept in localStorage. Read as an
 * external store so the server render (always expanded) hydrates cleanly.
 * The in-memory copy covers browsers where storage is unavailable.
 */
let contentsPreference = 'expanded';

function subscribeContentsPreference(onChange) {
  window.addEventListener('storage', onChange);
  window.addEventListener(CONTENTS_CHANGE_EVENT, onChange);
  return () => {
    window.removeEventListener('storage', onChange);
    window.removeEventListener(CONTENTS_CHANGE_EVENT, onChange);
  };
}

function readContentsPreference() {
  try {
    return window.localStorage.getItem(CONTENTS_STORAGE_KEY) === 'collapsed' ? 'collapsed' : 'expanded';
  } catch {
    return contentsPreference;
  }
}

function readServerContentsPreference() {
  return 'expanded';
}

function writeContentsPreference(value) {
  contentsPreference = value;
  try {
    window.localStorage.setItem(CONTENTS_STORAGE_KEY, value);
  } catch {
    // Storage can be unavailable, for example in private windows.
  }
  window.dispatchEvent(new Event(CONTENTS_CHANGE_EVENT));
}

const StyledShell = styled.div`
  --manual-header: 4.5rem;
  --manual-contents-width: clamp(16.5rem, 21vw, 20rem);
  position: relative;

  @media ${panesMedia} {
    display: grid;
    grid-template-columns: var(--manual-contents-width) minmax(0, 1fr);
    height: calc(100vh - var(--manual-header));
    height: calc(100dvh - var(--manual-header));
    transition: grid-template-columns ${props => props.theme.transitions.normal};

    &[data-contents='collapsed'] {
      --manual-contents-width: 3.75rem;
    }
  }

  @media (prefers-reduced-motion: reduce) {
    transition: none;
  }

  @media print {
    display: block;
    height: auto;
  }
`;

const StyledContentsPane = styled.div`
  position: sticky;
  top: var(--manual-header);
  z-index: 5;
  border-bottom: 1px solid ${props => props.theme.colors.border};
  background-color: ${props => props.theme.colors.background};

  @media ${panesMedia} {
    position: relative;
    top: auto;
    display: flex;
    flex-direction: column;
    min-height: 0;
    border-bottom: 0;
    border-right: 1px solid ${props => props.theme.colors.border};
    background-color: ${props => props.theme.colors.backgroundSecondary};
  }

  @media print {
    display: none;
  }
`;

const StyledFlowToggle = styled.button`
  display: flex;
  align-items: center;
  gap: ${props => props.theme.spacing.sm};
  width: 100%;
  min-height: 3.25rem;
  padding: ${props => props.theme.spacing.sm} clamp(1rem, 5vw, 4rem);
  border: 0;
  background: transparent;
  color: ${props => props.theme.colors.text};
  font: inherit;
  font-weight: ${props => props.theme.typography.fontWeight.semibold};
  text-align: left;
  cursor: pointer;

  > svg {
    flex-shrink: 0;
  }

  > span:nth-of-type(2) {
    flex: 1;
    min-width: 0;
    overflow: hidden;
    color: ${props => props.theme.colors.textSecondary};
    font-size: ${props => props.theme.typography.fontSize.sm};
    font-weight: ${props => props.theme.typography.fontWeight.normal};
    text-overflow: ellipsis;
    white-space: nowrap;
  }

  > svg:last-child {
    transition: transform ${props => props.theme.transitions.fast};
  }

  &[aria-expanded='true'] > svg:last-child {
    transform: rotate(180deg);
  }

  &:focus-visible {
    outline: 2px solid ${props => props.theme.colors.primary};
    outline-offset: -2px;
  }

  @media ${panesMedia} {
    display: none;
  }
`;

const StyledPanesHeader = styled.div`
  display: none;

  @media ${panesMedia} {
    display: flex;
    align-items: center;
    justify-content: space-between;
    gap: ${props => props.theme.spacing.sm};
    padding: 0.75rem 0.75rem 0.5rem 1.1rem;

    [data-contents='collapsed'] & {
      justify-content: center;
      padding: 0.75rem 0;
    }
  }
`;

const StyledContentsTitle = styled.p`
  display: flex;
  align-items: center;
  gap: ${props => props.theme.spacing.sm};
  margin: 0;
  color: ${props => props.theme.colors.textTertiary};
  font-size: ${props => props.theme.typography.fontSize.xs};
  font-weight: ${props => props.theme.typography.fontWeight.semibold};
  letter-spacing: 0.1em;
  text-transform: uppercase;

  [data-contents='collapsed'] & {
    display: none;
  }
`;

const StyledPanesToggle = styled.button`
  display: inline-flex;
  flex-shrink: 0;
  align-items: center;
  justify-content: center;
  width: 2.25rem;
  height: 2.25rem;
  border: 1px solid ${props => props.theme.colors.border};
  border-radius: ${props => props.theme.borderRadius.md};
  background-color: ${props => props.theme.colors.background};
  color: ${props => props.theme.colors.textSecondary};
  cursor: pointer;
  transition: color ${props => props.theme.transitions.fast},
              border-color ${props => props.theme.transitions.fast};

  &:hover {
    border-color: ${props => props.theme.colors.primary};
    color: ${props => props.theme.colors.primary};
  }

  &:focus-visible {
    outline: 2px solid ${props => props.theme.colors.primary};
    outline-offset: 2px;
  }
`;

const StyledContentsNav = styled.nav`
  display: none;
  position: absolute;
  top: 100%;
  right: 0;
  left: 0;
  max-height: min(70vh, 36rem);
  overflow-y: auto;
  overscroll-behavior: contain;
  padding: ${props => props.theme.spacing.sm} clamp(0.5rem, 4vw, 3.5rem) ${props => props.theme.spacing.md};
  border-bottom: 1px solid ${props => props.theme.colors.border};
  background-color: ${props => props.theme.colors.background};
  box-shadow: ${props => props.theme.shadows.lg};

  [data-flow-contents='open'] & {
    display: block;
  }

  @media ${panesMedia} {
    display: block;
    position: static;
    flex: 1;
    min-height: 0;
    max-height: none;
    padding: 0 0.5rem 1.5rem;
    border-bottom: 0;
    background-color: transparent;
    box-shadow: none;
    scrollbar-width: thin;

    [data-contents='collapsed'] & {
      display: none;
    }
  }
`;

const StyledContentPane = styled.div`
  @media ${panesMedia} {
    min-height: 0;
    overflow-y: auto;
    scrollbar-gutter: stable;

    &:focus-visible {
      outline: 2px solid ${props => props.theme.colors.primary};
      outline-offset: -2px;
    }
  }

  @media print {
    overflow: visible;
  }
`;

const StyledContent = styled.article`
  min-width: 0;
  max-width: 62rem;
  margin: 0 auto;
  padding: clamp(1.5rem, 4vw, 3rem) clamp(1rem, 5vw, 4rem) clamp(2.5rem, 6vw, 5rem);
`;

const StyledChapter = styled.section`
  scroll-margin-top: calc(var(--manual-header) + 4.5rem);

  & + & {
    margin-top: clamp(2.5rem, 5vw, 4rem);
    padding-top: clamp(2.5rem, 5vw, 4rem);
    border-top: 1px solid ${props => props.theme.colors.border};
  }

  @media ${panesMedia} {
    scroll-margin-top: ${HEADING_GAP_PX}px;
  }
`;

const StyledChapterEyebrow = styled.p`
  margin: 0 0 ${props => props.theme.spacing.xs} 0;
  color: ${props => props.theme.colors.primary};
  font-size: ${props => props.theme.typography.fontSize.sm};
  font-weight: ${props => props.theme.typography.fontWeight.semibold};
  letter-spacing: 0.1em;
  text-transform: uppercase;
`;

const StyledChapterTitle = styled.h2`
  margin: 0 0 ${props => props.theme.spacing.sm} 0;
  font-size: clamp(1.6rem, 1.1rem + 1.6vw, 2.35rem);
  letter-spacing: -0.02em;
  line-height: 1.15;

  &:focus {
    outline: none;
  }

  &:focus-visible {
    outline: 2px solid ${props => props.theme.colors.primary};
    outline-offset: 4px;
  }
`;

const StyledChapterSummary = styled.p`
  margin: 0 0 ${props => props.theme.spacing.xl} 0;
  color: ${props => props.theme.colors.textSecondary};
  font-size: ${props => props.theme.typography.fontSize.lg};
  line-height: ${props => props.theme.typography.lineHeight.relaxed};
  max-width: 68ch;
`;

const StyledSection = styled.section`
  scroll-margin-top: calc(var(--manual-header) + 4.5rem);
  margin-top: clamp(1.75rem, 3vw, 2.5rem);

  @media ${panesMedia} {
    scroll-margin-top: ${HEADING_GAP_PX}px;
  }
`;

const StyledSectionTitle = styled.h3`
  display: flex;
  gap: ${props => props.theme.spacing.sm};
  margin: 0 0 ${props => props.theme.spacing.md} 0;
  font-size: clamp(1.2rem, 1rem + 0.6vw, 1.5rem);
  line-height: 1.25;

  span {
    color: ${props => props.theme.colors.primary};
    font-variant-numeric: tabular-nums;
  }

  &:focus {
    outline: none;
  }

  &:focus-visible {
    outline: 2px solid ${props => props.theme.colors.primary};
    outline-offset: 4px;
  }
`;

const StyledAudience = styled.p`
  display: inline-flex;
  align-items: center;
  gap: ${props => props.theme.spacing.xs};
  margin: 0 0 ${props => props.theme.spacing.md} 0;
  padding: 0.2rem 0.65rem;
  border-radius: ${props => props.theme.borderRadius.full};
  background-color: ${props => props.theme.colors.backgroundTertiary};
  color: ${props => props.theme.colors.primaryDark};
  font-size: ${props => props.theme.typography.fontSize.xs};
  font-weight: ${props => props.theme.typography.fontWeight.semibold};
  line-height: 1.6;

  [data-theme='dark'] & {
    color: ${props => props.theme.colors.primaryLight};
  }
`;

StyledShell.displayName = 'StyledManualShell';
StyledContentsPane.displayName = 'StyledManualContentsPane';
StyledFlowToggle.displayName = 'StyledManualFlowToggle';
StyledPanesHeader.displayName = 'StyledManualPanesHeader';
StyledContentsTitle.displayName = 'StyledManualContentsTitle';
StyledPanesToggle.displayName = 'StyledManualPanesToggle';
StyledContentsNav.displayName = 'StyledManualContentsNav';
StyledContentPane.displayName = 'StyledManualContentPane';
StyledContent.displayName = 'StyledManualContent';
StyledChapter.displayName = 'StyledManualChapter';
StyledChapterEyebrow.displayName = 'StyledManualChapterEyebrow';
StyledChapterTitle.displayName = 'StyledManualChapterTitle';
StyledChapterSummary.displayName = 'StyledManualChapterSummary';
StyledSection.displayName = 'StyledManualSection';
StyledSectionTitle.displayName = 'StyledManualSectionTitle';
StyledAudience.displayName = 'StyledManualAudience';

export const ManualBody = React.memo(React.forwardRef(({
  chapters,
  figures,
  searchIndex: searchIndexProp,
  searchRef,
}, ref) => {
  const theme = useTheme();
  const panesQuery = panesMedia({ theme });
  const panes = useMediaQuery(panesQuery);
  const contentsExpanded = useSyncExternalStore(
    subscribeContentsPreference,
    readContentsPreference,
    readServerContentsPreference
  ) === 'expanded';

  const ids = useMemo(
    () => chapters.flatMap((chapter) => [chapter.id, ...chapter.sections.map((section) => section.id)]),
    [chapters]
  );
  const labels = useMemo(
    () => new Map(chapters.flatMap((chapter) => [
      [chapter.id, `${chapter.number}. ${chapter.title}`],
      ...chapter.sections.map((section) => [section.id, `${section.number} ${section.title}`]),
    ])),
    [chapters]
  );
  const searchIndex = useMemo(
    () => searchIndexProp || buildManualSearchIndex(chapters),
    [chapters, searchIndexProp]
  );

  const [activeId, setActiveId] = useState(ids[0]);
  const [flowContentsOpen, setFlowContentsOpen] = useState(false);
  const [headerHeight, setHeaderHeight] = useState(null);
  const [searching, setSearching] = useState(false);

  const shellRef = useRef(null);
  const barRef = useRef(null);
  const contentsRef = useRef(null);
  const contentRef = useRef(null);
  const flowToggleRef = useRef(null);
  const headerHeightRef = useRef(0);
  const activeIdRef = useRef(ids[0]);
  const lockUntilRef = useRef(0);
  const previousPanesRef = useRef(null);
  const hashHandledRef = useRef(false);

  const inPanes = useCallback(() => window.matchMedia(panesQuery).matches, [panesQuery]);

  useEffect(() => {
    activeIdRef.current = activeId;
  }, [activeId]);

  // The fixed site header changes height across breakpoints.
  useEffect(() => {
    const header = document.querySelector('header[role="banner"]');
    if (!header) {
      return undefined;
    }
    const measure = () => {
      headerHeightRef.current = header.offsetHeight;
      setHeaderHeight(header.offsetHeight);
    };
    measure();
    const observer = new ResizeObserver(measure);
    observer.observe(header);
    return () => observer.disconnect();
  }, []);

  const toggleContents = useCallback(() => {
    writeContentsPreference(contentsExpanded ? 'collapsed' : 'expanded');
  }, [contentsExpanded]);

  // Brings a chapter or section to the top of whichever area holds it.
  const scrollToSection = useCallback((id, { behavior, updateHash = true } = {}) => {
    const target = document.getElementById(id);
    if (!target) {
      return false;
    }
    const how = behavior || preferredScrollBehavior();
    lockUntilRef.current = performance.now() + (how === 'smooth' ? NAVIGATION_LOCK_MS : 50);
    setActiveId(id);

    const headerOffset = headerHeightRef.current;
    const shell = shellRef.current;
    const pane = contentRef.current;
    if (inPanes() && shell && pane) {
      const dockTop = window.scrollY + shell.getBoundingClientRect().top - headerOffset;
      if (Math.abs(window.scrollY - dockTop) > 1) {
        window.scrollTo({ top: dockTop, behavior: how });
      }
      const top = pane.scrollTop + target.getBoundingClientRect().top - pane.getBoundingClientRect().top - HEADING_GAP_PX;
      pane.scrollTo({ top: Math.max(0, top), behavior: how });
    } else {
      const barHeight = barRef.current ? barRef.current.offsetHeight : 0;
      const top = window.scrollY + target.getBoundingClientRect().top - headerOffset - barHeight - HEADING_GAP_PX;
      window.scrollTo({ top: Math.max(0, top), behavior: how });
    }

    if (updateHash && window.location.hash !== `#${id}`) {
      window.history.replaceState(window.history.state, '', `#${id}`);
    }
    return true;
  }, [inPanes]);

  const selectSection = useCallback((id, options = {}) => {
    if (!scrollToSection(id, options)) {
      return false;
    }
    setFlowContentsOpen(false);
    document.getElementById(`${id}-title`)?.focus({ preventScroll: true });
    return true;
  }, [scrollToSection]);

  useImperativeHandle(ref, () => ({
    revealSearch() {
      writeContentsPreference('expanded');
      setFlowContentsOpen(true);
    },
    selectSection,
  }), [selectSection]);

  // Contents entries and cross references inside the chapters.
  const handleClick = useCallback((event) => {
    if (event.defaultPrevented || event.button !== 0 || event.metaKey || event.ctrlKey || event.shiftKey || event.altKey) {
      return;
    }
    const link = event.target instanceof Element ? event.target.closest('a[href^="#"]') : null;
    if (!link) {
      return;
    }
    const id = decodeURIComponent(link.getAttribute('href').slice(1));
    if (!scrollToSection(id)) {
      return;
    }
    event.preventDefault();
    setFlowContentsOpen(false);
    document.getElementById(`${id}-title`)?.focus({ preventScroll: true });
  }, [scrollToSection]);

  // Arriving with a section in the address, e.g. /user-manual#take-a-payment.
  useEffect(() => {
    if (headerHeight === null || panes === null || hashHandledRef.current) {
      return;
    }
    hashHandledRef.current = true;
    const id = decodeURIComponent(window.location.hash.slice(1));
    if (id && document.getElementById(id)) {
      window.requestAnimationFrame(() => scrollToSection(id, { behavior: 'instant', updateHash: false }));
    }
  }, [headerHeight, panes, scrollToSection]);

  useEffect(() => {
    const handleHashChange = () => {
      const id = decodeURIComponent(window.location.hash.slice(1));
      if (id && document.getElementById(id)) {
        selectSection(id, { updateHash: false });
      }
    };
    window.addEventListener('hashchange', handleHashChange);
    return () => window.removeEventListener('hashchange', handleHashChange);
  }, [selectSection]);

  // Keep the reader's place when the window switches between the two layouts.
  useEffect(() => {
    if (panes === null) {
      return;
    }
    const previous = previousPanesRef.current;
    previousPanesRef.current = panes;
    if (previous === null || previous === panes) {
      return;
    }
    window.requestAnimationFrame(() => {
      setFlowContentsOpen(false);
      const shellTop = shellRef.current ? shellRef.current.getBoundingClientRect().top : 0;
      if (shellTop <= headerHeightRef.current + 1) {
        scrollToSection(activeIdRef.current, { behavior: 'instant', updateHash: false });
      }
    });
  }, [panes, scrollToSection]);

  // Until the panes line up with the header, the wheel scrolls the page and
  // stops there; after that the panes scroll themselves.
  useEffect(() => {
    const shell = shellRef.current;
    if (!panes || !shell) {
      return undefined;
    }

    const handleWheel = (event) => {
      const pane = contentRef.current;
      if (!pane || event.ctrlKey || Math.abs(event.deltaX) > Math.abs(event.deltaY)) {
        return;
      }
      const unit = event.deltaMode === 1 ? 16 : event.deltaMode === 2 ? window.innerHeight : 1;
      const delta = event.deltaY * unit;
      if (!delta) {
        return;
      }
      const offset = shell.getBoundingClientRect().top - headerHeightRef.current;

      if (Math.abs(offset) <= 1) {
        // Over the contents heading or the collapsed rail, move the chapters.
        if (!event.target.closest('[data-manual-scroll]')) {
          const canScroll = delta > 0
            ? pane.scrollTop + pane.clientHeight < pane.scrollHeight - 1
            : pane.scrollTop > 0;
          if (canScroll) {
            event.preventDefault();
            pane.scrollBy({ top: delta, behavior: 'instant' });
          }
        }
        return;
      }

      event.preventDefault();
      let move = delta;
      if (offset > 0 && delta > 0) {
        move = Math.min(delta, offset);
      } else if (offset < 0 && delta < 0) {
        move = Math.max(delta, offset);
      }
      window.scrollTo({ top: window.scrollY + move, behavior: 'instant' });
    };

    shell.addEventListener('wheel', handleWheel, { passive: false });
    return () => shell.removeEventListener('wheel', handleWheel);
  }, [panes]);

  // The active entry is the last heading that has reached the reading line.
  useEffect(() => {
    const headings = ids.map((id) => document.getElementById(id)).filter(Boolean);
    const pane = contentRef.current;
    if (!headings.length) {
      return undefined;
    }
    let frame = 0;

    const update = () => {
      frame = 0;
      if (performance.now() < lockUntilRef.current) {
        return;
      }
      const panesLayout = inPanes() && pane;
      let viewTop;
      let viewBottom;
      if (panesLayout) {
        const rect = pane.getBoundingClientRect();
        viewTop = rect.top;
        viewBottom = rect.bottom;
      } else {
        viewTop = headerHeightRef.current + (barRef.current ? barRef.current.offsetHeight : 0);
        viewBottom = window.innerHeight;
      }
      const readingLine = viewTop + Math.min(READING_LINE_MAX_PX, (viewBottom - viewTop) * 0.25);

      let current = headings[0].id;
      for (const heading of headings) {
        if (heading.getBoundingClientRect().top <= readingLine) {
          current = heading.id;
        } else {
          break;
        }
      }
      // At the end of the chapters, the last heading on screen is the one being read.
      if (panesLayout && pane.scrollTop + pane.clientHeight >= pane.scrollHeight - 2) {
        for (const heading of headings) {
          if (heading.getBoundingClientRect().top < viewBottom) {
            current = heading.id;
          }
        }
      }
      setActiveId((previous) => (previous === current ? previous : current));
    };

    const schedule = () => {
      if (!frame) {
        frame = window.requestAnimationFrame(update);
      }
    };

    schedule();
    pane?.addEventListener('scroll', schedule, { passive: true });
    window.addEventListener('scroll', schedule, { passive: true });
    window.addEventListener('resize', schedule);
    return () => {
      pane?.removeEventListener('scroll', schedule);
      window.removeEventListener('scroll', schedule);
      window.removeEventListener('resize', schedule);
      if (frame) {
        window.cancelAnimationFrame(frame);
      }
    };
  }, [ids, panes, inPanes]);

  // Keep the highlighted entry visible inside the contents' own scroll area.
  useEffect(() => {
    const container = contentsRef.current;
    const item = container?.querySelector('[aria-current="location"]');
    if (!container || !item || container.scrollHeight <= container.clientHeight) {
      return;
    }
    const margin = 48;
    const itemTop = item.getBoundingClientRect().top - container.getBoundingClientRect().top + container.scrollTop;
    const itemBottom = itemTop + item.offsetHeight;
    let top = null;
    if (itemTop < container.scrollTop + margin) {
      top = Math.max(0, itemTop - margin);
    } else if (itemBottom > container.scrollTop + container.clientHeight - margin) {
      top = itemBottom - container.clientHeight + margin;
    }
    if (top !== null) {
      container.scrollTo({ top, behavior: preferredScrollBehavior() });
    }
  }, [activeId, contentsExpanded, flowContentsOpen]);

  // The contents panel on touch screens closes on Escape or a tap elsewhere.
  useEffect(() => {
    if (!flowContentsOpen) {
      return undefined;
    }
    const handlePointerDown = (event) => {
      if (barRef.current && !barRef.current.contains(event.target)) {
        setFlowContentsOpen(false);
      }
    };
    const handleKeyDown = (event) => {
      if (event.key === 'Escape') {
        setFlowContentsOpen(false);
        flowToggleRef.current?.focus();
      }
    };
    document.addEventListener('pointerdown', handlePointerDown);
    document.addEventListener('keydown', handleKeyDown);
    return () => {
      document.removeEventListener('pointerdown', handlePointerDown);
      document.removeEventListener('keydown', handleKeyDown);
    };
  }, [flowContentsOpen]);

  return (
    <StyledShell
      ref={shellRef}
      lang="en"
      dir="ltr"
      data-contents={contentsExpanded ? 'expanded' : 'collapsed'}
      data-flow-contents={flowContentsOpen ? 'open' : 'closed'}
      style={headerHeight ? { '--manual-header': `${headerHeight}px` } : undefined}
      onClick={handleClick}
    >
      <StyledContentsPane ref={barRef}>
        <StyledFlowToggle
          ref={flowToggleRef}
          type="button"
          aria-expanded={flowContentsOpen}
          aria-controls={CONTENTS_ID}
          onClick={() => setFlowContentsOpen((open) => !open)}
        >
          <Icon name="list" size={18} />
          <span>Contents</span>
          <span>{labels.get(activeId)}</span>
          <Icon name="chevronDown" size={18} />
        </StyledFlowToggle>

        <StyledPanesHeader>
          <StyledContentsTitle>
            <Icon name="list" size={14} />
            Contents
          </StyledContentsTitle>
          <StyledPanesToggle
            type="button"
            aria-expanded={contentsExpanded}
            aria-controls={CONTENTS_ID}
            aria-label={contentsExpanded ? 'Collapse contents' : 'Expand contents'}
            title={contentsExpanded ? 'Collapse contents' : 'Expand contents'}
            onClick={toggleContents}
          >
            <Icon name={contentsExpanded ? 'panelClose' : 'panelOpen'} size={18} />
          </StyledPanesToggle>
        </StyledPanesHeader>

        <StyledContentsNav
          id={CONTENTS_ID}
          ref={contentsRef}
          aria-label="User manual contents"
          data-manual-scroll
        >
          <ManualSearch
            ref={searchRef}
            variant="sidebar"
            index={searchIndex}
            activeId={activeId}
            shortcut={false}
            onActiveChange={setSearching}
            onSelect={selectSection}
          />
          {!searching && <ManualToc chapters={chapters} activeId={activeId} />}
        </StyledContentsNav>
      </StyledContentsPane>

      <StyledContentPane
        ref={contentRef}
        role="region"
        aria-label="User manual chapters"
        tabIndex={panes ? 0 : undefined}
        data-manual-scroll
      >
        <StyledContent>
          {chapters.map((chapter) => (
            <StyledChapter key={chapter.id} id={chapter.id} aria-labelledby={`${chapter.id}-title`}>
              <StyledChapterEyebrow>Chapter {chapter.number}</StyledChapterEyebrow>
              <StyledChapterTitle id={`${chapter.id}-title`} tabIndex={-1}>{chapter.title}</StyledChapterTitle>
              {chapter.summary && <StyledChapterSummary>{chapter.summary}</StyledChapterSummary>}

              {chapter.sections.map((section) => (
                <StyledSection key={section.id} id={section.id} aria-labelledby={`${section.id}-title`}>
                  <StyledSectionTitle id={`${section.id}-title`} tabIndex={-1}>
                    <span>{section.number}</span>
                    {section.title}
                  </StyledSectionTitle>
                  {section.audience && (
                    <StyledAudience>
                      <Icon name="users" size={14} />
                      {section.audience}
                    </StyledAudience>
                  )}
                  <ManualBlocks blocks={section.blocks} figures={figures} />
                </StyledSection>
              ))}
            </StyledChapter>
          ))}
        </StyledContent>
      </StyledContentPane>
    </StyledShell>
  );
}));

ManualBody.displayName = 'ManualBody';
