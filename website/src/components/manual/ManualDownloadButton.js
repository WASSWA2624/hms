/**
 * ManualDownloadButton - Downloads the user manual PDF
 *
 * A plain link to the PDF, so the download works before hydration and without
 * JavaScript. On click the saved file is renamed hosspi-DDMMYYYYHHmm.pdf using
 * the visitor's local 24-hour time.
 *
 * @component
 * @param {Object} props
 * @param {string} props.label - Button text
 * @param {'primary'|'outline'} [props.variant] - Visual weight
 * @returns {JSX.Element} Rendered download link
 * @file src/components/manual/ManualDownloadButton.js
 */
'use client';

import React, { useCallback } from 'react';
import styled from 'styled-components';
import { Icon } from '@/components/ui';
import { USER_MANUAL_PDF_PATH, userManualFileName } from '@/lib/userManual';

const StyledLink = styled.a.withConfig({
  shouldForwardProp: (prop) => prop !== '$variant',
})`
  display: inline-flex;
  align-items: center;
  justify-content: center;
  gap: ${props => props.theme.spacing.sm};
  min-height: 48px;
  padding: ${props => props.theme.spacing.sm} ${props => props.theme.spacing.lg};
  border: 2px solid ${props => props.theme.colors.primary};
  border-radius: ${props => props.theme.borderRadius.md};
  background-color: ${props => props.$variant === 'outline' ? 'transparent' : props.theme.colors.primary};
  color: ${props => props.$variant === 'outline' ? props.theme.colors.primary : props.theme.colors.textInverse};
  font-size: ${props => props.theme.typography.fontSize.md};
  font-weight: ${props => props.theme.typography.fontWeight.semibold};
  text-decoration: none;
  white-space: nowrap;
  transition: background-color ${props => props.theme.transitions.fast},
              color ${props => props.theme.transitions.fast},
              transform ${props => props.theme.transitions.fast},
              box-shadow ${props => props.theme.transitions.fast};

  &:hover {
    background-color: ${props => props.$variant === 'outline' ? props.theme.colors.backgroundTertiary : props.theme.colors.primaryHover};
    color: ${props => props.$variant === 'outline' ? props.theme.colors.primary : props.theme.colors.textInverse};
    text-decoration: none;
    transform: translateY(-1px);
    box-shadow: ${props => props.theme.shadows.md};
  }

  &:focus-visible {
    outline: 2px solid ${props => props.theme.colors.primary};
    outline-offset: 3px;
  }
`;

StyledLink.displayName = 'StyledManualDownloadLink';

export const ManualDownloadButton = React.memo(({ label, variant = 'primary' }) => {
  const handleClick = useCallback((event) => {
    event.currentTarget.setAttribute('download', userManualFileName(new Date()));
  }, []);

  return (
    <StyledLink
      href={USER_MANUAL_PDF_PATH}
      download="hosspi-user-manual.pdf"
      type="application/pdf"
      onClick={handleClick}
      $variant={variant}
    >
      <Icon name="download" size={18} />
      {label}
    </StyledLink>
  );
});

ManualDownloadButton.displayName = 'ManualDownloadButton';
