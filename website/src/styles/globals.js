/**
 * Global Styles
 * 
 * Global styles and CSS reset for the application.
 * Imported in root layout.
 */
import { createGlobalStyle } from 'styled-components';

export const GlobalStyles = createGlobalStyle`
  /* CSS Reset */
  *,
  *::before,
  *::after {
    box-sizing: border-box;
    margin: 0;
    padding: 0;
  }

  html {
    font-size: 16px;
    -webkit-font-smoothing: antialiased;
    -moz-osx-font-smoothing: grayscale;
    scroll-behavior: smooth;
  }

  body {
    font-family: ${props => props.theme.typography.fontFamily.sans};
    font-size: ${props => props.theme.typography.fontSize.md};
    line-height: ${props => props.theme.typography.lineHeight.normal};
    color: ${props => props.theme.colors.text};
    background-color: ${props => props.theme.colors.background};
    transition: background-color ${props => props.theme.transitions.normal},
                color ${props => props.theme.transitions.normal};
    min-height: 100vh;
    /* clip, unlike hidden, does not make body a scroll container, so
       position: sticky keeps working; hidden is the fallback for browsers
       without clip. */
    overflow-x: hidden;
    overflow-x: clip;
  }

  /* Typography */
  h1, h2, h3, h4, h5, h6 {
    font-weight: ${props => props.theme.typography.fontWeight.bold};
    line-height: ${props => props.theme.typography.lineHeight.tight};
    color: ${props => props.theme.colors.text};
    margin-bottom: ${props => props.theme.spacing.md};
  }

  h1 {
    font-size: ${props => props.theme.typography.fontSize['4xl']};
  }

  h2 {
    font-size: ${props => props.theme.typography.fontSize['3xl']};
  }

  h3 {
    font-size: ${props => props.theme.typography.fontSize['2xl']};
  }

  h4 {
    font-size: ${props => props.theme.typography.fontSize.xl};
  }

  h5 {
    font-size: ${props => props.theme.typography.fontSize.lg};
  }

  h6 {
    font-size: ${props => props.theme.typography.fontSize.md};
  }

  p {
    margin-bottom: ${props => props.theme.spacing.md};
    line-height: ${props => props.theme.typography.lineHeight.relaxed};
  }

  a {
    color: ${props => props.theme.colors.link};
    text-decoration: none;
    transition: color ${props => props.theme.transitions.fast};

    &:hover {
      color: ${props => props.theme.colors.linkHover};
      text-decoration: underline;
    }

    &:focus {
      outline: 2px solid ${props => props.theme.colors.primary};
      outline-offset: 2px;
      border-radius: ${props => props.theme.borderRadius.sm};
    }
  }

  /* Lists */
  ul, ol {
    margin-bottom: ${props => props.theme.spacing.md};
    padding-left: ${props => props.theme.spacing.xl};
  }

  /* Images */
  img {
    max-width: 100%;
    height: auto;
    display: block;
  }

  /* Buttons */
  button {
    font-family: inherit;
    cursor: pointer;
    border: none;
    background: none;
    padding: 0;

    &:focus {
      outline: 2px solid ${props => props.theme.colors.primary};
      outline-offset: 2px;
      border-radius: ${props => props.theme.borderRadius.sm};
    }

    &:disabled {
      cursor: not-allowed;
      opacity: 0.6;
    }
  }

  /* Inputs */
  input, textarea, select {
    font-family: inherit;
    font-size: inherit;

    &:focus {
      outline: 2px solid ${props => props.theme.colors.primary};
      outline-offset: 2px;
      border-radius: ${props => props.theme.borderRadius.sm};
    }
  }

  /* Focus styles for keyboard navigation */
  *:focus-visible {
    outline: 2px solid ${props => props.theme.colors.primary};
    outline-offset: 2px;
    border-radius: ${props => props.theme.borderRadius.sm};
  }

  /* Scrollbar styling */
  ::-webkit-scrollbar {
    width: 12px;
    height: 12px;
  }

  ::-webkit-scrollbar-track {
    background: ${props => props.theme.colors.backgroundSecondary};
  }

  ::-webkit-scrollbar-thumb {
    background: ${props => props.theme.colors.borderDark};
    border-radius: ${props => props.theme.borderRadius.md};

    &:hover {
      background: ${props => props.theme.colors.textSecondary};
    }
  }

  /* Selection */
  ::selection {
    background-color: ${props => props.theme.colors.primary};
    color: ${props => props.theme.colors.textInverse};
  }

  /* Main content area - padding for fixed header */
  main {
    /* Base padding-top for mobile header height */
    /* Header: padding (md * 2) + logo (40px) + border (1px) */
    padding-top: calc(${props => props.theme.spacing.md} + ${props => props.theme.spacing.md} + 2.5rem + 1px);

    /* Responsive - adjust for larger screens */
    @media (min-width: ${props => props.theme.breakpoints.sm}) {
      /* Header: padding (md * 2) + logo (50px) + border (1px) */
      padding-top: calc(${props => props.theme.spacing.md} + ${props => props.theme.spacing.md} + 3.125rem + 1px);
    }
  }
`;

