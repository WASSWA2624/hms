/**
 * ManualBody - Table of contents and chapters of the user manual
 *
 * From 1024px the contents sit in a sticky sidebar beside the chapters; below
 * that they collapse into a "Contents" disclosure above them. Scrolling keeps
 * the entry for the section in view highlighted and scrolled into the
 * sidebar's own view.
 *
 * @component
 * @param {Object} props
 * @param {Array<Object>} props.chapters - Numbered chapters from numberUserManual()
 * @param {Object} props.figures - Screenshot data keyed by figure id
 * @returns {JSX.Element} Rendered manual body
 * @file src/components/manual/ManualBody.js
 */
'use client';

import React, { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import styled from 'styled-components';
import { Icon } from '@/components/ui';
import { ManualBlocks } from './ManualBlocks';
import { ManualToc } from './ManualToc';

/* Clears the fixed site header when a heading is scrolled to. */
const HEADING_OFFSET_PX = 112;

const StyledLayout = styled.div`
  max-width: ${props => props.theme.breakpoints.lg};
  margin: 0 auto;
  padding: clamp(1.5rem, 4vw, 3rem) clamp(1rem, 5vw, 4rem) clamp(2.5rem, 6vw, 5rem);

  @media (min-width: ${props => props.theme.breakpoints.md}) {
    display: grid;
    grid-template-columns: minmax(15rem, 18rem) minmax(0, 1fr);
    gap: clamp(2rem, 4vw, 4rem);
    align-items: start;
  }
`;

const StyledSidebar = styled.nav`
  display: none;

  @media (min-width: ${props => props.theme.breakpoints.md}) {
    display: block;
    position: sticky;
    top: 5.5rem;
    max-height: calc(100vh - 7rem);
    overflow-y: auto;
    padding-right: ${props => props.theme.spacing.xs};
  }
`;

const StyledSidebarScroll = styled.div`
  position: relative;
`;

const StyledTocTitle = styled.p`
  display: flex;
  align-items: center;
  gap: ${props => props.theme.spacing.sm};
  margin: 0 0 ${props => props.theme.spacing.sm} 0;
  padding: 0 0.6rem;
  color: ${props => props.theme.colors.textTertiary};
  font-size: ${props => props.theme.typography.fontSize.xs};
  font-weight: ${props => props.theme.typography.fontWeight.semibold};
  letter-spacing: 0.1em;
  text-transform: uppercase;
`;

const StyledMobileToc = styled.details`
  margin-bottom: ${props => props.theme.spacing.xl};
  border: 1px solid ${props => props.theme.colors.border};
  border-radius: ${props => props.theme.borderRadius.lg};
  background-color: ${props => props.theme.colors.backgroundSecondary};

  summary {
    display: flex;
    align-items: center;
    gap: ${props => props.theme.spacing.sm};
    padding: ${props => props.theme.spacing.md};
    font-weight: ${props => props.theme.typography.fontWeight.semibold};
    cursor: pointer;
    list-style: none;
  }

  summary::-webkit-details-marker {
    display: none;
  }

  > div {
    max-height: 60vh;
    overflow-y: auto;
    padding: 0 ${props => props.theme.spacing.sm} ${props => props.theme.spacing.md};
  }

  @media (min-width: ${props => props.theme.breakpoints.md}) {
    display: none;
  }
`;

const StyledContent = styled.article`
  min-width: 0;
  max-width: 60rem;
`;

const StyledChapter = styled.section`
  scroll-margin-top: ${HEADING_OFFSET_PX}px;

  & + & {
    margin-top: clamp(2.5rem, 5vw, 4rem);
    padding-top: clamp(2.5rem, 5vw, 4rem);
    border-top: 1px solid ${props => props.theme.colors.border};
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
`;

const StyledChapterSummary = styled.p`
  margin: 0 0 ${props => props.theme.spacing.xl} 0;
  color: ${props => props.theme.colors.textSecondary};
  font-size: ${props => props.theme.typography.fontSize.lg};
  line-height: ${props => props.theme.typography.lineHeight.relaxed};
  max-width: 68ch;
`;

const StyledSection = styled.section`
  scroll-margin-top: ${HEADING_OFFSET_PX}px;
  margin-top: clamp(1.75rem, 3vw, 2.5rem);
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

StyledLayout.displayName = 'StyledManualLayout';
StyledSidebar.displayName = 'StyledManualSidebar';
StyledSidebarScroll.displayName = 'StyledManualSidebarScroll';
StyledTocTitle.displayName = 'StyledManualTocTitle';
StyledMobileToc.displayName = 'StyledManualMobileToc';
StyledContent.displayName = 'StyledManualContent';
StyledChapter.displayName = 'StyledManualChapter';
StyledChapterEyebrow.displayName = 'StyledManualChapterEyebrow';
StyledChapterTitle.displayName = 'StyledManualChapterTitle';
StyledChapterSummary.displayName = 'StyledManualChapterSummary';
StyledSection.displayName = 'StyledManualSection';
StyledSectionTitle.displayName = 'StyledManualSectionTitle';
StyledAudience.displayName = 'StyledManualAudience';

export const ManualBody = React.memo(({ chapters, figures }) => {
  const ids = useMemo(
    () => chapters.flatMap((chapter) => [chapter.id, ...chapter.sections.map((section) => section.id)]),
    [chapters]
  );
  const [activeId, setActiveId] = useState(ids[0]);
  const sidebarRef = useRef(null);
  const mobileTocRef = useRef(null);

  // The active entry is the last heading that has scrolled past the header.
  useEffect(() => {
    const headings = ids.map((id) => document.getElementById(id)).filter(Boolean);
    let frame = 0;

    const update = () => {
      frame = 0;
      let current = headings[0]?.id;
      for (const heading of headings) {
        if (heading.getBoundingClientRect().top - HEADING_OFFSET_PX - 8 <= 0) {
          current = heading.id;
        } else {
          break;
        }
      }
      setActiveId((previous) => (previous === current ? previous : current));
    };

    const schedule = () => {
      if (!frame) {
        frame = window.requestAnimationFrame(update);
      }
    };

    update();
    window.addEventListener('scroll', schedule, { passive: true });
    window.addEventListener('resize', schedule);
    return () => {
      window.removeEventListener('scroll', schedule);
      window.removeEventListener('resize', schedule);
      if (frame) {
        window.cancelAnimationFrame(frame);
      }
    };
  }, [ids]);

  // Keep the highlighted entry visible inside the sidebar's own scroll area.
  useEffect(() => {
    const container = sidebarRef.current;
    const item = container?.querySelector('[aria-current="location"]');
    if (!container || !item) {
      return;
    }
    const margin = 32;
    const top = item.offsetTop;
    const bottom = top + item.offsetHeight;
    if (top < container.scrollTop + margin) {
      container.scrollTop = Math.max(0, top - margin);
    } else if (bottom > container.scrollTop + container.clientHeight - margin) {
      container.scrollTop = bottom - container.clientHeight + margin;
    }
  }, [activeId]);

  const closeMobileToc = useCallback(() => {
    if (mobileTocRef.current) {
      mobileTocRef.current.open = false;
    }
  }, []);

  return (
    <StyledLayout lang="en" dir="ltr">
      <StyledSidebar ref={sidebarRef} aria-label="User manual contents">
        <StyledSidebarScroll>
          <StyledTocTitle>
            <Icon name="list" size={14} />
            Contents
          </StyledTocTitle>
          <ManualToc chapters={chapters} activeId={activeId} />
        </StyledSidebarScroll>
      </StyledSidebar>

      <StyledContent>
        <StyledMobileToc ref={mobileTocRef}>
          <summary>
            <Icon name="list" size={18} />
            Contents
          </summary>
          <div>
            <nav aria-label="User manual contents">
              <ManualToc chapters={chapters} activeId={activeId} onNavigate={closeMobileToc} />
            </nav>
          </div>
        </StyledMobileToc>

        {chapters.map((chapter) => (
          <StyledChapter key={chapter.id} id={chapter.id} aria-labelledby={`${chapter.id}-title`}>
            <StyledChapterEyebrow>Chapter {chapter.number}</StyledChapterEyebrow>
            <StyledChapterTitle id={`${chapter.id}-title`}>{chapter.title}</StyledChapterTitle>
            {chapter.summary && <StyledChapterSummary>{chapter.summary}</StyledChapterSummary>}

            {chapter.sections.map((section) => (
              <StyledSection key={section.id} id={section.id} aria-labelledby={`${section.id}-title`}>
                <StyledSectionTitle id={`${section.id}-title`}>
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
    </StyledLayout>
  );
});

ManualBody.displayName = 'ManualBody';
