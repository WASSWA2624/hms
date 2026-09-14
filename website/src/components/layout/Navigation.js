/**
 * Navigation - Main navigation component
 *
 * Renders inline horizontal links from the navigation breakpoint (1280px) and
 * a hamburger menu below that. Both are always in the DOM and swapped with CSS
 * media queries, so the server and client render identically.
 *
 * @component
 * @returns {React.ReactElement} Navigation component
 */
'use client';

import React, { useState, useEffect, useRef } from 'react';
import Link from 'next/link';
import { usePathname } from 'next/navigation';
import styled from 'styled-components';
import { NAVIGATION_LINKS } from '@/lib/constants';
import { useTranslation } from '@/hooks';

const StyledNav = styled.nav`
  display: flex;
  align-items: center;
  gap: ${props => props.theme.spacing.xs};
  position: relative;
  flex-shrink: 0;
  z-index: ${props => props.theme.zIndex.dropdown};
  isolation: isolate;
  min-width: 0;
  flex-basis: auto;
  width: 100%;
  justify-content: center;

  /* Small mobile (360px+) */
  @media (min-width: 360px) {
    gap: ${props => props.theme.spacing.sm};
  }

  /* Tablet and up (768px+) */
  @media (min-width: ${props => props.theme.breakpoints.sm}) {
    gap: ${props => props.theme.spacing.md};
  }

  /* Desktop (1024px+) */
  @media (min-width: ${props => props.theme.breakpoints.md}) {
    gap: ${props => props.theme.spacing.lg};
  }

  /* Very small screens */
  @media (max-width: 360px) {
    gap: 2px;
  }

  /* Ensure navigation button doesn't cause overflow on mobile */
  @media (max-width: ${props => props.theme.breakpoints.sm}) {
    flex-shrink: 0;
    flex: 0 0 auto;
    visibility: visible;
    opacity: 1;
    width: auto;
  }
`;

/* Desktop navigation - inline links, shown once the header can fit them all
   beside the logo and the calls to action */
const StyledDesktopList = styled.ul`
  display: none;
  list-style: none;
  margin: 0;
  padding: 0;

  @media (min-width: ${props => props.theme.breakpoints.navigation}) {
    display: flex;
    align-items: center;
    gap: ${props => props.theme.spacing.xs};
  }

  @media (min-width: ${props => props.theme.breakpoints.lg}) {
    gap: ${props => props.theme.spacing.sm};
  }
`;

const StyledDesktopItem = styled.li`
  margin: 0;
`;

const StyledDesktopLink = styled(Link).withConfig({
  shouldForwardProp: (prop) => prop !== '$active',
})`
  position: relative;
  display: block;
  padding: ${props => props.theme.spacing.sm} ${props => props.theme.spacing.md};
  border-radius: ${props => props.theme.borderRadius.md};
  color: ${props => props.$active ? props.theme.colors.primary : props.theme.colors.textSecondary};
  font-size: ${props => props.theme.typography.fontSize.md};
  font-weight: ${props => props.$active
    ? props.theme.typography.fontWeight.semibold
    : props.theme.typography.fontWeight.medium};
  text-decoration: none;
  white-space: nowrap;
  transition: color ${props => props.theme.transitions.fast},
              background-color ${props => props.theme.transitions.fast};

  /* Animated underline that grows from the centre on hover/active */
  &::after {
    content: '';
    position: absolute;
    left: ${props => props.theme.spacing.md};
    right: ${props => props.theme.spacing.md};
    bottom: 6px;
    height: 2px;
    border-radius: ${props => props.theme.borderRadius.sm};
    background-color: ${props => props.theme.colors.primary};
    transform: scaleX(${props => props.$active ? 1 : 0});
    transform-origin: center;
    transition: transform ${props => props.theme.transitions.fast};
  }

  &:hover {
    color: ${props => props.theme.colors.primary};
    background-color: ${props => props.theme.colors.backgroundSecondary};
    text-decoration: none;

    &::after {
      transform: scaleX(1);
    }
  }

  &:focus-visible {
    outline: 2px solid ${props => props.theme.colors.primary};
    outline-offset: 2px;
  }

  @media (prefers-reduced-motion: reduce) {
    &::after {
      transition: none;
    }
  }
`;

const StyledNavLink = styled(Link).withConfig({
  shouldForwardProp: (prop) => prop !== 'active',
})`
  color: ${props => props.theme.colors.text};
  text-decoration: none;
  font-weight: ${props => props.$active ? props.theme.typography.fontWeight.semibold : props.theme.typography.fontWeight.normal};
  padding: ${props => props.theme.spacing.sm} ${props => props.theme.spacing.md};
  border-radius: ${props => props.theme.borderRadius.md};
  transition: all ${props => props.theme.transitions.fast};
  position: relative;

  ${props => props.$active && `
    color: ${props.theme.colors.primary};
    background-color: ${props.theme.colors.backgroundSecondary};

    &::after {
      content: '';
      position: absolute;
      bottom: 0;
      left: ${props.theme.spacing.md};
      right: ${props.theme.spacing.md};
      height: 2px;
      background-color: ${props.theme.colors.primary};
      border-radius: ${props.theme.borderRadius.sm};
    }
  `}

  &:hover {
    color: ${props => props.theme.colors.primary};
    background-color: ${props => props.theme.colors.backgroundSecondary};
    text-decoration: none;
  }

  &:focus-visible {
    outline: 2px solid ${props => props.theme.colors.primary};
    outline-offset: 2px;
  }
`;

const StyledMenuButton = styled.button`
  display: flex;
  align-items: center;
  justify-content: center;
  gap: ${props => props.theme.spacing.xs};
  background-color: ${props => props.theme.colors.backgroundSecondary};
  border: 1px solid ${props => props.theme.colors.border};
  border-radius: ${props => props.theme.borderRadius.md};
  padding: ${props => props.theme.spacing.xs};
  min-width: 40px;
  min-height: 40px;
  color: ${props => props.theme.colors.text};
  font-size: ${props => props.theme.typography.fontSize.md};
  transition: all ${props => props.theme.transitions.fast};
  cursor: pointer;
  white-space: nowrap;
  flex-shrink: 0;
  box-sizing: border-box;
  -webkit-tap-highlight-color: transparent;

  @media (min-width: ${props => props.theme.breakpoints.sm}) {
    font-size: ${props => props.theme.typography.fontSize.lg};
    gap: ${props => props.theme.spacing.sm};
    padding: ${props => props.theme.spacing.sm} ${props => props.theme.spacing.md};
    min-width: 44px;
    min-height: 44px;
  }

  /* Wide screens use inline links instead of the hamburger */
  @media (min-width: ${props => props.theme.breakpoints.navigation}) {
    display: none;
  }

  @media (max-width: 360px) {
    min-width: 36px;
    min-height: 36px;
    padding: 2px;
    font-size: ${props => props.theme.typography.fontSize.sm};
  }

  &:hover {
    background-color: ${props => props.theme.colors.backgroundTertiary};
    color: ${props => props.theme.colors.primary};
  }

  &:focus-visible {
    outline: 2px solid ${props => props.theme.colors.primary};
    outline-offset: 2px;
  }

  &:active {
    transform: scale(0.98);
  }
`;

const StyledMenuText = styled.span`
  display: none;
  font-size: ${props => props.theme.typography.fontSize.sm};
  font-weight: ${props => props.theme.typography.fontWeight.semibold};
  color: inherit;
  text-transform: uppercase;
  letter-spacing: 0.1em;
  transition: color ${props => props.theme.transitions.fast};
  user-select: none;

  @media (min-width: ${props => props.theme.breakpoints.md}) {
    display: block;
  }
`;

const StyledMenu = styled.div.withConfig({
  shouldForwardProp: (prop) => prop !== 'isOpen',
})`
  display: ${props => props.$isOpen ? 'block' : 'none'};
  position: absolute;
  top: calc(100% + ${props => props.theme.spacing.xs});
  right: 0;
  min-width: 240px;
  max-width: calc(100vw - ${props => props.theme.spacing.md} * 2);
  background-color: ${props => props.theme.colors.background};
  border: 1px solid ${props => props.theme.colors.border};
  border-radius: ${props => props.theme.borderRadius.lg};
  box-shadow: ${props => props.theme.shadows.xl};
  padding: ${props => props.theme.spacing.md};
  z-index: ${props => props.theme.zIndex.modal};
  animation: ${props => props.$isOpen ? 'slideDown' : 'slideUp'} ${props => props.theme.transitions.normal};
  opacity: ${props => props.$isOpen ? 1 : 0};
  visibility: ${props => props.$isOpen ? 'visible' : 'hidden'};

  @keyframes slideDown {
    from {
      opacity: 0;
      transform: translateY(-10px);
    }
    to {
      opacity: 1;
      transform: translateY(0);
    }
  }

  @keyframes slideUp {
    from {
      opacity: 1;
      transform: translateY(0);
    }
    to {
      opacity: 0;
      transform: translateY(-10px);
    }
  }

  /* Mobile - full width with margins */
  @media (max-width: ${props => props.theme.breakpoints.sm}) {
    position: fixed;
    left: ${props => props.theme.spacing.sm};
    right: ${props => props.theme.spacing.sm};
    top: calc(48px + ${props => props.theme.spacing.xs});
    min-width: auto;
    width: calc(100% - ${props => props.theme.spacing.sm} * 2);
    max-height: calc(100vh - 48px - ${props => props.theme.spacing.xs} - ${props => props.theme.spacing.md});
    overflow-y: auto;
    -webkit-overflow-scrolling: touch;
  }

  /* Very small screens */
  @media (max-width: 360px) {
    left: ${props => props.theme.spacing.xs};
    right: ${props => props.theme.spacing.xs};
    width: calc(100% - ${props => props.theme.spacing.xs} * 2);
    padding: ${props => props.theme.spacing.sm};
    top: calc(44px + ${props => props.theme.spacing.xs});
    max-height: calc(100vh - 44px - ${props => props.theme.spacing.xs} - ${props => props.theme.spacing.sm});
  }

  /* Tablet - adjust positioning */
  @media (min-width: ${props => props.theme.breakpoints.sm}) {
    min-width: 280px;
    max-width: 400px;
  }

  /* Wide screens use inline links instead of the dropdown */
  @media (min-width: ${props => props.theme.breakpoints.navigation}) {
    display: none;
  }

  ul {
    list-style: none;
    margin: 0;
    padding: 0;
    display: flex;
    flex-direction: column;
    gap: ${props => props.theme.spacing.xs};
  }

  li {
    margin: 0;
  }

  a {
    display: block;
    padding: ${props => props.theme.spacing.md};
    border-radius: ${props => props.theme.borderRadius.md};
    transition: all ${props => props.theme.transitions.fast};
    min-height: 44px;
    display: flex;
    align-items: center;

    @media (max-width: 360px) {
      padding: ${props => props.theme.spacing.sm};
      min-height: 40px;
    }
  }
`;

const StyledMenuHeader = styled.div`
  display: flex;
  align-items: center;
  justify-content: space-between;
  margin-bottom: ${props => props.theme.spacing.md};
  padding-bottom: ${props => props.theme.spacing.md};
  border-bottom: 1px solid ${props => props.theme.colors.border};
`;

const StyledMenuTitle = styled.h2`
  font-size: ${props => props.theme.typography.fontSize.lg};
  font-weight: ${props => props.theme.typography.fontWeight.semibold};
  color: ${props => props.theme.colors.text};
  margin: 0;
`;

const StyledCloseButton = styled.button`
  display: flex;
  align-items: center;
  justify-content: center;
  background-color: ${props => props.theme.colors.backgroundSecondary};
  border: 1px solid ${props => props.theme.colors.border};
  border-radius: ${props => props.theme.borderRadius.md};
  padding: ${props => props.theme.spacing.sm};
  min-width: 44px;
  min-height: 44px;
  color: ${props => props.theme.colors.text};
  font-size: ${props => props.theme.typography.fontSize.xl};
  transition: all ${props => props.theme.transitions.fast};
  cursor: pointer;

  &:hover {
    background-color: ${props => props.theme.colors.backgroundTertiary};
    color: ${props => props.theme.colors.primary};
  }

  &:focus-visible {
    outline: 2px solid ${props => props.theme.colors.primary};
    outline-offset: 2px;
  }
`;

StyledDesktopList.displayName = 'StyledDesktopList';
StyledDesktopItem.displayName = 'StyledDesktopItem';
StyledDesktopLink.displayName = 'StyledDesktopLink';
StyledMenuButton.displayName = 'StyledMenuButton';
StyledMenuText.displayName = 'StyledMenuText';
StyledMenu.displayName = 'StyledMenu';
StyledMenuHeader.displayName = 'StyledMenuHeader';
StyledMenuTitle.displayName = 'StyledMenuTitle';
StyledCloseButton.displayName = 'StyledCloseButton';

export const Navigation = React.memo(() => {
  const [isMenuOpen, setIsMenuOpen] = useState(false);
  const pathname = usePathname();
  const { t } = useTranslation('navigation');
  const { t: tCommon } = useTranslation('common');
  const navRef = useRef(null);

  const toggleMenu = () => {
    setIsMenuOpen(!isMenuOpen);
  };

  const closeMenu = () => {
    setIsMenuOpen(false);
  };

  // Close menu when clicking outside
  useEffect(() => {
    if (!isMenuOpen) return;

    const handleClickOutside = (event) => {
      if (navRef.current && !navRef.current.contains(event.target)) {
        closeMenu();
      }
    };

    // Use setTimeout to avoid closing immediately when opening
    const timeoutId = setTimeout(() => {
      document.addEventListener('mousedown', handleClickOutside);
      document.addEventListener('touchstart', handleClickOutside);
    }, 0);

    return () => {
      clearTimeout(timeoutId);
      document.removeEventListener('mousedown', handleClickOutside);
      document.removeEventListener('touchstart', handleClickOutside);
    };
  }, [isMenuOpen]);

  // Close menu on escape key
  useEffect(() => {
    const handleEscape = (event) => {
      if (event.key === 'Escape' && isMenuOpen) {
        closeMenu();
      }
    };

    if (isMenuOpen) {
      document.addEventListener('keydown', handleEscape);
    }

    return () => {
      document.removeEventListener('keydown', handleEscape);
    };
  }, [isMenuOpen]);

  // Close menu when route changes
  useEffect(() => {
    closeMenu();
  }, [pathname]);

  const navLinks = NAVIGATION_LINKS;

  return (
    <StyledNav role="navigation" aria-label={t('nav.mainNavigation') || 'Main navigation'} ref={navRef}>
      {/* Inline links - desktop (1024px+) */}
      <StyledDesktopList>
        {navLinks.map((link) => {
          const isActive = pathname === link.href;
          return (
            <StyledDesktopItem key={link.href}>
              <StyledDesktopLink
                href={link.href}
                $active={isActive}
                aria-current={isActive ? 'page' : undefined}
              >
                {link.labelKey ? t(link.labelKey) : link.label}
              </StyledDesktopLink>
            </StyledDesktopItem>
          );
        })}
      </StyledDesktopList>

      {/* Hamburger menu - below 1024px */}
      <StyledMenuButton
        type="button"
        aria-label={isMenuOpen ? tCommon('close') : tCommon('openMenu') || 'Open menu'}
        aria-expanded={isMenuOpen}
        aria-controls="navigation-menu"
        onClick={toggleMenu}
      >
        <span aria-hidden="true">{isMenuOpen ? '✕' : '☰'}</span>
        <StyledMenuText>{t('nav.menu') || 'MENU'}</StyledMenuText>
      </StyledMenuButton>

      {/* Menu - Unified for all screen sizes */}
      {isMenuOpen && (
        <StyledMenu 
          id="navigation-menu" 
          $isOpen={isMenuOpen}
          aria-hidden={!isMenuOpen}
        >
          <StyledMenuHeader>
            <StyledMenuTitle>{t('nav.menu') || 'Menu'}</StyledMenuTitle>
            <StyledCloseButton
              type="button"
              aria-label={tCommon('close')}
              onClick={closeMenu}
            >
              <span aria-hidden="true">✕</span>
            </StyledCloseButton>
          </StyledMenuHeader>
          <ul>
            {navLinks.map((link) => {
              const isActive = pathname === link.href;
              return (
                <li key={link.href}>
                  <StyledNavLink
                    href={link.href}
                    $active={isActive}
                    onClick={closeMenu}
                    aria-current={isActive ? 'page' : undefined}
                  >
                    {link.labelKey ? t(link.labelKey) : link.label}
                  </StyledNavLink>
                </li>
              );
            })}
          </ul>
        </StyledMenu>
      )}
    </StyledNav>
  );
});

Navigation.displayName = 'Navigation';

