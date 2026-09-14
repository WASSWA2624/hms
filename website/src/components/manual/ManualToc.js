/**
 * ManualToc - Table of contents for the user manual
 *
 * Chapters and their sections as in-page links. The section currently being
 * read is marked with aria-current and highlighted, and its chapter stays
 * emphasised, so the list doubles as a "you are here" indicator.
 *
 * @component
 * @param {Object} props
 * @param {Array<Object>} props.chapters - Numbered chapters
 * @param {string} [props.activeId] - Id of the chapter or section in view
 * @param {Function} [props.onNavigate] - Called after a link is chosen
 * @returns {JSX.Element} Rendered table of contents
 * @file src/components/manual/ManualToc.js
 */
'use client';

import React from 'react';
import styled from 'styled-components';

const StyledList = styled.ol`
  list-style: none;
  margin: 0;
  padding: 0;
`;

const StyledChapter = styled.li`
  margin: 0 0 ${props => props.theme.spacing.xs} 0;
`;

const StyledLink = styled.a.withConfig({
  shouldForwardProp: (prop) => prop !== '$level' && prop !== '$active' && prop !== '$inChapter',
})`
  display: grid;
  grid-template-columns: ${props => props.$level === 1 ? '1.75rem' : '2.25rem'} minmax(0, 1fr);
  gap: ${props => props.theme.spacing.xs};
  padding: ${props => props.$level === 1 ? '0.4rem 0.6rem' : '0.3rem 0.6rem'};
  border-left: 2px solid ${props => props.$active ? props.theme.colors.primary : 'transparent'};
  border-radius: 0 ${props => props.theme.borderRadius.sm} ${props => props.theme.borderRadius.sm} 0;
  background-color: ${props => props.$active ? props.theme.colors.backgroundTertiary : 'transparent'};
  color: ${props => (props.$active || (props.$level === 1 && props.$inChapter))
    ? props.theme.colors.primary
    : props.$level === 1 ? props.theme.colors.text : props.theme.colors.textSecondary};
  font-size: ${props => props.$level === 1 ? props.theme.typography.fontSize.sm : '0.8125rem'};
  font-weight: ${props => props.$level === 1
    ? props.theme.typography.fontWeight.semibold
    : props.$active ? props.theme.typography.fontWeight.semibold : props.theme.typography.fontWeight.normal};
  line-height: ${props => props.theme.typography.lineHeight.tight};
  text-decoration: none;
  transition: color ${props => props.theme.transitions.fast},
              background-color ${props => props.theme.transitions.fast};

  &:hover {
    color: ${props => props.theme.colors.primary};
    background-color: ${props => props.theme.colors.backgroundSecondary};
    text-decoration: none;
  }

  span:first-child {
    font-variant-numeric: tabular-nums;
    color: ${props => props.$active ? props.theme.colors.primary : props.theme.colors.textTertiary};
  }
`;

const StyledSections = styled.ol`
  list-style: none;
  margin: 0 0 ${props => props.theme.spacing.xs} 0;
  padding: 0 0 0 ${props => props.theme.spacing.sm};
`;

StyledList.displayName = 'StyledManualTocList';
StyledChapter.displayName = 'StyledManualTocChapter';
StyledLink.displayName = 'StyledManualTocLink';
StyledSections.displayName = 'StyledManualTocSections';

export const ManualToc = React.memo(({ chapters, activeId, onNavigate }) => {
  return (
    <StyledList>
      {chapters.map((chapter) => {
        const inChapter = activeId === chapter.id
          || chapter.sections.some((section) => section.id === activeId);
        return (
          <StyledChapter key={chapter.id}>
            <StyledLink
              href={`#${chapter.id}`}
              $level={1}
              $active={activeId === chapter.id}
              $inChapter={inChapter}
              aria-current={activeId === chapter.id ? 'location' : undefined}
              onClick={onNavigate}
            >
              <span>{chapter.number}.</span>
              <span>{chapter.title}</span>
            </StyledLink>
            <StyledSections>
              {chapter.sections.map((section) => (
                <li key={section.id}>
                  <StyledLink
                    href={`#${section.id}`}
                    $level={2}
                    $active={activeId === section.id}
                    aria-current={activeId === section.id ? 'location' : undefined}
                    onClick={onNavigate}
                  >
                    <span>{section.number}</span>
                    <span>{section.title}</span>
                  </StyledLink>
                </li>
              ))}
            </StyledSections>
          </StyledChapter>
        );
      })}
    </StyledList>
  );
});

ManualToc.displayName = 'ManualToc';
