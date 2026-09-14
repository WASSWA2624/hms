/**
 * ManualHero - Title, summary and download action at the top of the user manual
 *
 * @component
 * @param {Object} props
 * @param {string} props.eyebrow - Small label above the title
 * @param {string} props.title - Page title
 * @param {string} props.intro - Summary paragraph
 * @param {Array<{icon: string, label: string}>} [props.meta] - Facts about the manual
 * @param {string} props.downloadLabel - Download button text
 * @param {string} props.appHref - Application URL
 * @param {string} props.appLabel - Application link text
 * @returns {JSX.Element} Rendered hero
 * @file src/components/manual/ManualHero.js
 */
'use client';

import React from 'react';
import Image from 'next/image';
import styled from 'styled-components';
import { Icon } from '@/components/ui';
import { ManualDownloadButton } from './ManualDownloadButton';

const StyledHero = styled.section`
  background: linear-gradient(
    135deg,
    ${props => props.theme.colors.backgroundTertiary} 0%,
    ${props => props.theme.colors.background} 72%
  );
  border-bottom: 1px solid ${props => props.theme.colors.border};
`;

const StyledInner = styled.div`
  max-width: ${props => props.theme.breakpoints.lg};
  margin: 0 auto;
  padding: clamp(2.5rem, 6vw, 4.5rem) clamp(1rem, 5vw, 4rem);
  display: grid;
  gap: ${props => props.theme.spacing.xl};

  @media (min-width: ${props => props.theme.breakpoints.md}) {
    grid-template-columns: minmax(0, 1fr) auto;
    align-items: center;
  }
`;

const StyledEyebrow = styled.p`
  margin: 0 0 ${props => props.theme.spacing.sm} 0;
  color: ${props => props.theme.colors.primary};
  font-size: ${props => props.theme.typography.fontSize.sm};
  font-weight: ${props => props.theme.typography.fontWeight.semibold};
  letter-spacing: 0.1em;
  text-transform: uppercase;
`;

const StyledTitle = styled.h1`
  margin: 0 0 ${props => props.theme.spacing.md} 0;
  font-size: clamp(2.25rem, 1.5rem + 3vw, 3.5rem);
  letter-spacing: -0.03em;
  line-height: 1.05;
`;

const StyledIntro = styled.p`
  margin: 0;
  color: ${props => props.theme.colors.textSecondary};
  font-size: clamp(1rem, 0.94rem + 0.3vw, 1.15rem);
  line-height: ${props => props.theme.typography.lineHeight.relaxed};
  max-width: 64ch;
`;

const StyledActions = styled.div`
  display: flex;
  flex-wrap: wrap;
  gap: ${props => props.theme.spacing.md};
  margin-top: ${props => props.theme.spacing.xl};
`;

const StyledAppLink = styled.a`
  display: inline-flex;
  align-items: center;
  justify-content: center;
  gap: ${props => props.theme.spacing.sm};
  min-height: 48px;
  padding: ${props => props.theme.spacing.sm} ${props => props.theme.spacing.lg};
  border: 2px solid ${props => props.theme.colors.border};
  border-radius: ${props => props.theme.borderRadius.md};
  background-color: ${props => props.theme.colors.background};
  color: ${props => props.theme.colors.text};
  font-weight: ${props => props.theme.typography.fontWeight.semibold};
  text-decoration: none;
  white-space: nowrap;
  transition: border-color ${props => props.theme.transitions.fast},
              color ${props => props.theme.transitions.fast};

  &:hover {
    border-color: ${props => props.theme.colors.primary};
    color: ${props => props.theme.colors.primary};
    text-decoration: none;
  }

  &:focus-visible {
    outline: 2px solid ${props => props.theme.colors.primary};
    outline-offset: 3px;
  }
`;

const StyledMeta = styled.ul`
  display: flex;
  flex-wrap: wrap;
  gap: ${props => props.theme.spacing.sm} ${props => props.theme.spacing.lg};
  margin: ${props => props.theme.spacing.lg} 0 0 0;
  padding: 0;
  list-style: none;

  li {
    display: inline-flex;
    align-items: center;
    gap: ${props => props.theme.spacing.xs};
    color: ${props => props.theme.colors.textSecondary};
    font-size: ${props => props.theme.typography.fontSize.sm};
  }

  svg {
    color: ${props => props.theme.colors.primary};
  }
`;

const StyledArt = styled.div`
  display: none;

  @media (min-width: ${props => props.theme.breakpoints.md}) {
    display: block;
    width: clamp(9rem, 14vw, 12rem);

    img {
      width: 100%;
      height: auto;
      filter: drop-shadow(0 18px 30px rgba(0, 121, 253, 0.25));
    }
  }
`;

StyledHero.displayName = 'StyledManualHero';
StyledInner.displayName = 'StyledManualHeroInner';
StyledEyebrow.displayName = 'StyledManualHeroEyebrow';
StyledTitle.displayName = 'StyledManualHeroTitle';
StyledIntro.displayName = 'StyledManualHeroIntro';
StyledActions.displayName = 'StyledManualHeroActions';
StyledAppLink.displayName = 'StyledManualHeroAppLink';
StyledMeta.displayName = 'StyledManualHeroMeta';
StyledArt.displayName = 'StyledManualHeroArt';

export const ManualHero = React.memo(({
  eyebrow,
  title,
  intro,
  meta = [],
  downloadLabel,
  appHref,
  appLabel,
}) => {
  return (
    <StyledHero aria-labelledby="user-manual-title">
      <StyledInner>
        <div>
          <StyledEyebrow>{eyebrow}</StyledEyebrow>
          <StyledTitle id="user-manual-title">{title}</StyledTitle>
          <StyledIntro>{intro}</StyledIntro>
          <StyledActions>
            <ManualDownloadButton label={downloadLabel} />
            <StyledAppLink href={appHref} target="_blank" rel="noopener noreferrer">
              {appLabel}
              <Icon name="external" size={17} />
            </StyledAppLink>
          </StyledActions>
          {meta.length > 0 && (
            <StyledMeta>
              {meta.map((item) => (
                <li key={item.label}>
                  <Icon name={item.icon} size={16} />
                  {item.label}
                </li>
              ))}
            </StyledMeta>
          )}
        </div>
        <StyledArt aria-hidden="true">
          <Image src="/logos/icon-256.png" alt="" width={256} height={256} priority />
        </StyledArt>
      </StyledInner>
    </StyledHero>
  );
});

ManualHero.displayName = 'ManualHero';
