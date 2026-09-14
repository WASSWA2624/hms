/**
 * Theme Configuration
 *
 * Central theme configuration for the entire application.
 * All styling values must come from this theme object - no hardcoded values.
 *
 * Colours mirror the HOSSPI HMS application palette so the site and the product
 * read as one brand: brand primary #0079FD ("logo window cyan"), azure tints,
 * porcelain surfaces, and ink text. The logo's red is kept as an accent.
 */

export const theme = {
  colors: {
    // Primary colors - HOSSPI brand azure
    primary: '#0079FD',
    primaryHover: '#0267D9',
    primaryLight: '#52A4FE',
    primaryDark: '#0455B4',

    // Secondary colors - the medical cross red from the logo
    secondary: '#E23A2E',
    secondaryHover: '#C42B20',
    secondaryLight: '#F26055',
    secondaryDark: '#A02017',

    // Background colors - porcelain, tinted from the brand rather than flat grey
    background: '#FFFFFF',
    backgroundSecondary: '#F1F8FF',
    backgroundTertiary: '#E8F3FF',

    // Text colors
    text: '#0D2744',
    textSecondary: '#4F6B88',
    textTertiary: '#7d93aa',
    textInverse: '#FFFFFF',

    // Border colors
    border: '#D0E3F7',
    borderLight: '#E8F1FA',
    borderDark: '#ADD4FE',

    // Status colors
    success: '#1C844A',
    successLight: '#E6F5EC',
    error: '#CE2F2F',
    errorLight: '#FBEAEA',
    warning: '#BB6209',
    warningLight: '#FFF2E0',
    info: '#0079FD',
    infoLight: '#EBF4FF',

    // Interactive colors
    link: '#0079FD',
    linkHover: '#0267D9',

    // Overlay
    overlay: 'rgba(13, 39, 68, 0.55)',
    overlayLight: 'rgba(13, 39, 68, 0.3)',
  },
  
  colorsDark: {
    // Primary colors - lifted azure so it holds contrast on deep navy
    primary: '#5C93F5',
    primaryHover: '#83B0FF',
    primaryLight: '#AECBFF',
    primaryDark: '#1E4F9E',

    // Secondary colors - the logo red, softened for dark surfaces
    secondary: '#F26055',
    secondaryHover: '#F7847B',
    secondaryLight: '#FAA9A2',
    secondaryDark: '#C42B20',

    // Background colors - navy-inked rather than flat black
    background: '#081422',
    backgroundSecondary: '#0F2032',
    backgroundTertiary: '#16386F',

    // Text colors
    text: '#EAF2FB',
    textSecondary: '#A8C0D8',
    textTertiary: '#7791AC',
    textInverse: '#081422',

    // Border colors
    border: '#1D3A57',
    borderLight: '#152A40',
    borderDark: '#2C4A6B',

    // Status colors
    success: '#4ADE80',
    successLight: '#12321F',
    error: '#F87171',
    errorLight: '#3A1A1A',
    warning: '#FBBF24',
    warningLight: '#3A2A10',
    info: '#5C93F5',
    infoLight: '#16386F',

    // Interactive colors
    link: '#5C93F5',
    linkHover: '#83B0FF',

    // Overlay
    overlay: 'rgba(4, 12, 22, 0.8)',
    overlayLight: 'rgba(4, 12, 22, 0.6)',
  },
  
  spacing: {
    xs: '0.25rem',
    sm: '0.5rem',
    md: '1rem',
    lg: '1.5rem',
    xl: '2rem',
    xxl: '3rem',
  },
  
  breakpoints: {
    xs: '320px',
    sm: '768px',
    md: '1024px',
    // Width at which the header has room for every navigation link inline,
    // beside the logo and the calls to action.
    navigation: '1280px',
    lg: '1440px',
    xl: '1920px',
  },
  
  typography: {
    fontFamily: {
      sans: '-apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, "Helvetica Neue", Arial, sans-serif',
      serif: 'Georgia, "Times New Roman", serif',
      mono: 'Menlo, Monaco, "Courier New", monospace',
    },
    fontSize: {
      xs: '0.75rem',
      sm: '0.875rem',
      md: '1rem',
      lg: '1.125rem',
      xl: '1.25rem',
      '2xl': '1.5rem',
      '3xl': '1.875rem',
      '4xl': '2.25rem',
      '5xl': '3rem',
    },
    lineHeight: {
      tight: '1.25',
      normal: '1.5',
      relaxed: '1.75',
      loose: '2',
    },
    fontWeight: {
      normal: 400,
      medium: 500,
      semibold: 600,
      bold: 700,
    },
  },
  
  borderRadius: {
    none: '0',
    sm: '0.25rem',
    md: '0.5rem',
    lg: '0.75rem',
    xl: '1rem',
    full: '9999px',
  },
  
  shadows: {
    sm: '0 1px 2px 0 rgba(0, 0, 0, 0.05)',
    md: '0 4px 6px -1px rgba(0, 0, 0, 0.1), 0 2px 4px -1px rgba(0, 0, 0, 0.06)',
    lg: '0 10px 15px -3px rgba(0, 0, 0, 0.1), 0 4px 6px -2px rgba(0, 0, 0, 0.05)',
    xl: '0 20px 25px -5px rgba(0, 0, 0, 0.1), 0 10px 10px -5px rgba(0, 0, 0, 0.04)',
    inner: 'inset 0 2px 4px 0 rgba(0, 0, 0, 0.06)',
    none: 'none',
  },
  
  transitions: {
    fast: '150ms ease-in-out',
    normal: '250ms ease-in-out',
    slow: '350ms ease-in-out',
  },
  
  zIndex: {
    dropdown: 1000,
    sticky: 1020,
    fixed: 1030,
    modalBackdrop: 1040,
    modal: 1050,
    popover: 1060,
    tooltip: 1070,
  },
};

