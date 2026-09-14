/**
 * ManualFigure - Application screenshot with numbered step markers
 *
 * Marker N sits on the control used in step N of the list that follows the
 * figure, with an outline around that control. Positions are stored as
 * percentages of the screenshot, so they stay aligned at any width. The
 * markers are decorative for assistive technology: the numbered steps carry
 * the same information in text.
 *
 * @component
 * @param {Object} props
 * @param {{src: string, width: number, height: number, alt: string, markers?: Array<{n: number, x: number, y: number, w: number, h: number, side?: 'left'|'right'|'top'|'bottom'}>}} props.figure - Screenshot and markers
 * @param {string} props.number - Figure number, e.g. "2.3"
 * @param {string} [props.caption] - Caption text
 * @returns {JSX.Element|null} Rendered figure
 * @file src/components/manual/ManualFigure.js
 */
'use client';

import React from 'react';
import styled from 'styled-components';

/* Never wider than the screenshot itself, so narrow crops stay sharp. The side
   padding leaves room for markers that sit just outside the screenshot edge. */
const StyledFigure = styled.figure`
  margin: ${props => props.theme.spacing.lg} 0;
  padding: 0 clamp(1rem, 2.5vw, 2rem);
  max-width: 100%;
  box-sizing: border-box;
`;

const StyledFrame = styled.div`
  position: relative;
  line-height: 0;

  img {
    width: 100%;
    height: auto;
    border: 1px solid ${props => props.theme.colors.border};
    border-radius: ${props => props.theme.borderRadius.lg};
    box-shadow: ${props => props.theme.shadows.md};
    background-color: ${props => props.theme.colors.backgroundSecondary};
  }
`;

const StyledHighlight = styled.span`
  position: absolute;
  border: 2px solid ${props => props.theme.colors.secondary};
  border-radius: ${props => props.theme.borderRadius.md};
  background-color: ${props => props.theme.colors.secondary}14;
  pointer-events: none;
`;

const StyledMarker = styled.span`
  position: absolute;
  display: inline-flex;
  align-items: center;
  justify-content: center;
  width: clamp(1.15rem, 0.8rem + 1.1vw, 1.75rem);
  height: clamp(1.15rem, 0.8rem + 1.1vw, 1.75rem);
  border-radius: ${props => props.theme.borderRadius.full};
  background-color: ${props => props.theme.colors.secondary};
  color: #FFFFFF;
  border: 2px solid #FFFFFF;
  box-shadow: ${props => props.theme.shadows.md};
  font-size: clamp(0.62rem, 0.5rem + 0.4vw, 0.85rem);
  font-weight: ${props => props.theme.typography.fontWeight.bold};
  line-height: 1;
  pointer-events: none;
`;

const StyledCaption = styled.figcaption`
  display: flex;
  flex-wrap: wrap;
  justify-content: space-between;
  gap: ${props => props.theme.spacing.xs} ${props => props.theme.spacing.md};
  margin-top: ${props => props.theme.spacing.sm};
  color: ${props => props.theme.colors.textSecondary};
  font-size: ${props => props.theme.typography.fontSize.sm};
  line-height: ${props => props.theme.typography.lineHeight.normal};

  strong {
    color: ${props => props.theme.colors.text};
  }

  a {
    white-space: nowrap;
  }
`;

StyledFigure.displayName = 'StyledManualFigure';
StyledFrame.displayName = 'StyledManualFigureFrame';
StyledHighlight.displayName = 'StyledManualFigureHighlight';
StyledMarker.displayName = 'StyledManualFigureMarker';
StyledCaption.displayName = 'StyledManualFigureCaption';

/* Where a badge is anchored, in percent of the screenshot, and how it sits
   against that point. Badges sit just outside the outlined control - to its
   left unless the capture chose another side - so they never cover the
   control's own label. */
function markerPlacement({ x, y, w = 0, h = 0, side }) {
  switch (side) {
    case 'right':
      return { left: x + w, top: y + h / 2, transform: 'translate(4px, -50%)' };
    case 'top':
      return { left: x + w / 2, top: y, transform: 'translate(-50%, calc(-100% - 4px))' };
    case 'bottom':
      return { left: x + w / 2, top: y + h, transform: 'translate(-50%, 4px)' };
    default:
      return { left: x, top: y + h / 2, transform: 'translate(calc(-100% - 4px), -50%)' };
  }
}

export const ManualFigure = React.memo(({ figure, number, caption }) => {
  if (!figure?.src) {
    return null;
  }

  const markers = figure.markers || [];

  return (
    <StyledFigure style={{ width: `${figure.width}px` }}>
      <StyledFrame>
        <img
          src={figure.src}
          width={figure.width}
          height={figure.height}
          alt={figure.alt}
          loading="lazy"
          decoding="async"
        />
        {markers.map((marker) => {
          const placement = markerPlacement(marker);
          return (
            <React.Fragment key={marker.n}>
              {marker.w > 0 && marker.h > 0 && (
                <StyledHighlight
                  aria-hidden="true"
                  style={{
                    left: `${marker.x}%`,
                    top: `${marker.y}%`,
                    width: `${marker.w}%`,
                    height: `${marker.h}%`,
                  }}
                />
              )}
              <StyledMarker
                aria-hidden="true"
                style={{
                  left: `${placement.left}%`,
                  top: `${placement.top}%`,
                  transform: placement.transform,
                }}
              >
                {marker.n}
              </StyledMarker>
            </React.Fragment>
          );
        })}
      </StyledFrame>
      <StyledCaption>
        <span>
          <strong>Figure {number}.</strong> {caption || figure.alt}
        </span>
        <a href={figure.src} target="_blank" rel="noopener noreferrer">
          Open full size
        </a>
      </StyledCaption>
    </StyledFigure>
  );
});

ManualFigure.displayName = 'ManualFigure';
