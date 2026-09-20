/**
 * ManualSearch - Search box and results for the user manual
 *
 * Two placements, one ranking: a large field in the hero for readers who
 * arrive with a task in mind, and a compact field at the top of the contents
 * for readers already moving through the chapters. While a query is active in
 * the contents, the results replace the chapter list so there is only one
 * list to read.
 *
 * Works from the keyboard throughout: "/" or Ctrl/Cmd+K focuses a box from
 * anywhere on the page (unless the parent takes the shortcut), the arrow keys
 * walk the results, Enter opens one and Escape clears. The box is a combobox
 * and the results a listbox, with the highlighted result named by
 * aria-activedescendant. A live region announces how many results there are.
 *
 * @component
 * @param {Object} props
 * @param {Array<Object>} props.index - Entries from buildManualSearchIndex()
 * @param {Function} props.onSelect - Called with a section id to open it
 * @param {string} [props.activeId] - Section being read, shown on its result
 * @param {'sidebar'|'hero'} [props.variant] - Placement and size
 * @param {boolean} [props.shortcut] - Whether this box claims / and Ctrl/Cmd+K
 * @param {Function} [props.onActiveChange] - Called when a query starts or ends
 * @param {Function} [props.onReadyToSearch] - Called just before a shortcut focuses
 * @returns {JSX.Element} Rendered search
 * @file src/components/manual/ManualSearch.js
 */
'use client';

import React, {
  useCallback,
  useEffect,
  useId,
  useImperativeHandle,
  useMemo,
  useRef,
  useState,
} from 'react';
import styled from 'styled-components';
import { Icon } from '@/components/ui';
import { highlightParts, searchManual } from '@/lib/manualSearch';

/* Enough to choose from without turning the results into a second manual. */
const RESULT_LIMIT = 12;

const SUGGESTIONS = [
  'sign in',
  'add staff',
  'register a patient',
  'take a payment',
  'dispense a prescription',
  'run a report',
];

const StyledSearch = styled.div.withConfig({
  shouldForwardProp: (prop) => prop !== '$variant',
})`
  position: relative;

  ${props => props.$variant === 'sidebar' && `
    position: sticky;
    top: 0;
    z-index: 1;
    padding: ${props.theme.spacing.sm} clamp(1rem, 5vw, 4rem);
    background-color: ${props.theme.colors.background};

    @media (min-width: ${props.theme.breakpoints.md}) and (hover: hover) and (pointer: fine) {
      padding: 0.75rem 0.75rem 0.5rem;
      background-color: ${props.theme.colors.backgroundSecondary};

      [data-contents='collapsed'] & {
        padding: 0.75rem 0.5rem;
      }
    }
  `}

  @media print {
    display: none;
  }
`;

const StyledField = styled.div.withConfig({
  shouldForwardProp: (prop) => prop !== '$variant',
})`
  display: flex;
  align-items: center;
  gap: ${props => props.theme.spacing.sm};
  padding: 0 ${props => props.$variant === 'hero' ? props.theme.spacing.md : '0.6rem'};
  border: 1px solid ${props => props.theme.colors.border};
  border-radius: ${props => props.$variant === 'hero'
    ? props.theme.borderRadius.lg
    : props.theme.borderRadius.md};
  background-color: ${props => props.theme.colors.background};
  box-shadow: ${props => props.$variant === 'hero' ? props.theme.shadows.md : 'none'};
  transition: border-color ${props => props.theme.transitions.fast},
              box-shadow ${props => props.theme.transitions.fast};

  &:focus-within {
    border-color: ${props => props.theme.colors.primary};
    box-shadow: 0 0 0 3px ${props => props.theme.colors.primary}22;
  }

  > svg:first-child {
    flex-shrink: 0;
    color: ${props => props.theme.colors.textTertiary};
  }
`;

const StyledInput = styled.input.withConfig({
  shouldForwardProp: (prop) => prop !== '$variant',
})`
  flex: 1;
  min-width: 0;
  min-height: ${props => props.$variant === 'hero' ? '3.25rem' : '2.75rem'};
  padding: 0;
  border: 0;
  background: transparent;
  color: ${props => props.theme.colors.text};
  font: inherit;
  font-size: ${props => props.$variant === 'hero'
    ? props.theme.typography.fontSize.md
    : props.theme.typography.fontSize.sm};
  outline: none;

  &::placeholder {
    color: ${props => props.theme.colors.textTertiary};
  }

  /* The browser's own clear button would duplicate ours. */
  &::-webkit-search-cancel-button {
    display: none;
  }
`;

/* The shortcut hint doubles as the clear button once there is a query. */
const StyledHint = styled.kbd`
  flex-shrink: 0;
  padding: 0.1rem 0.35rem;
  border: 1px solid ${props => props.theme.colors.border};
  border-radius: ${props => props.theme.borderRadius.sm};
  color: ${props => props.theme.colors.textTertiary};
  font-family: ${props => props.theme.typography.fontFamily.sans};
  font-size: 0.6875rem;
  line-height: 1.4;

  @media (hover: none) {
    display: none;
  }
`;

const StyledClear = styled.button`
  display: inline-flex;
  flex-shrink: 0;
  align-items: center;
  justify-content: center;
  width: 2.25rem;
  height: 2.25rem;
  padding: 0;
  border: 0;
  border-radius: ${props => props.theme.borderRadius.sm};
  background: transparent;
  color: ${props => props.theme.colors.textTertiary};
  cursor: pointer;

  &:hover {
    color: ${props => props.theme.colors.text};
  }

  &:focus-visible {
    outline: 2px solid ${props => props.theme.colors.primary};
    outline-offset: 1px;
  }
`;

const StyledPanel = styled.div.withConfig({
  shouldForwardProp: (prop) => prop !== '$variant',
})`
  ${props => props.$variant === 'hero' && `
    position: absolute;
    top: calc(100% + ${props.theme.spacing.sm});
    right: 0;
    left: 0;
    z-index: ${props.theme.zIndex.dropdown};
    max-height: min(28rem, 60vh);
    overflow-y: auto;
    padding: ${props.theme.spacing.sm};
    border: 1px solid ${props.theme.colors.border};
    border-radius: ${props.theme.borderRadius.lg};
    background-color: ${props.theme.colors.background};
    box-shadow: ${props.theme.shadows.lg};
  `}
`;

const StyledResults = styled.ol`
  list-style: none;
  margin: ${props => props.theme.spacing.sm} 0 0;
  padding: 0;

  ${StyledPanel} > & {
    margin-top: 0;
  }
`;

const StyledResult = styled.li`
  & + & {
    margin-top: 2px;
  }
`;

const StyledResultLink = styled.a.withConfig({
  shouldForwardProp: (prop) => prop !== '$highlighted',
})`
  display: block;
  padding: 0.55rem 0.65rem;
  border-left: 2px solid ${props => props.$highlighted ? props.theme.colors.primary : 'transparent'};
  border-radius: 0 ${props => props.theme.borderRadius.sm} ${props => props.theme.borderRadius.sm} 0;
  background-color: ${props => props.$highlighted ? props.theme.colors.backgroundTertiary : 'transparent'};
  color: inherit;
  text-decoration: none;
  cursor: pointer;

  &:hover {
    background-color: ${props => props.theme.colors.backgroundSecondary};
    text-decoration: none;
  }

  mark {
    padding: 0 0.1em;
    border-radius: 2px;
    background-color: ${props => props.theme.colors.primary}26;
    color: inherit;
    font-weight: ${props => props.theme.typography.fontWeight.semibold};
  }
`;

const StyledResultBreadcrumb = styled.p`
  display: flex;
  align-items: center;
  gap: 0.3rem;
  margin: 0 0 0.15rem;
  color: ${props => props.theme.colors.textTertiary};
  font-size: 0.6875rem;
  font-weight: ${props => props.theme.typography.fontWeight.medium};
  letter-spacing: 0.02em;
  text-transform: uppercase;
`;

const StyledResultTitle = styled.p`
  display: grid;
  grid-template-columns: 2.25rem minmax(0, 1fr);
  gap: ${props => props.theme.spacing.xs};
  margin: 0;
  color: ${props => props.theme.colors.text};
  font-size: ${props => props.theme.typography.fontSize.sm};
  font-weight: ${props => props.theme.typography.fontWeight.semibold};
  line-height: ${props => props.theme.typography.lineHeight.tight};

  > span:first-child {
    color: ${props => props.theme.colors.textTertiary};
    font-variant-numeric: tabular-nums;
  }
`;

const StyledResultSnippet = styled.p`
  margin: 0.2rem 0 0 2.5rem;
  overflow: hidden;
  color: ${props => props.theme.colors.textSecondary};
  font-size: 0.75rem;
  line-height: ${props => props.theme.typography.lineHeight.normal};

  /* Two lines is enough to recognise the passage without crowding the list. */
  display: -webkit-box;
  -webkit-box-orient: vertical;
  -webkit-line-clamp: 2;
`;

const StyledReadingNow = styled.span`
  margin-left: 0.4rem;
  color: ${props => props.theme.colors.primary};
  font-size: 0.625rem;
  font-weight: ${props => props.theme.typography.fontWeight.semibold};
  letter-spacing: 0.04em;
  text-transform: uppercase;
`;

const StyledEmpty = styled.div`
  margin-top: ${props => props.theme.spacing.sm};
  padding: ${props => props.theme.spacing.md} 0.6rem;
  color: ${props => props.theme.colors.textSecondary};
  font-size: ${props => props.theme.typography.fontSize.sm};
  text-align: center;

  p {
    margin: 0;
  }

  p + p {
    margin-top: 0.35rem;
    color: ${props => props.theme.colors.textTertiary};
    font-size: 0.75rem;
  }

  ${StyledPanel} > & {
    margin-top: 0;
  }
`;

const StyledStatus = styled.p`
  margin: ${props => props.theme.spacing.sm} 0 0;
  padding: 0 0.6rem;
  color: ${props => props.theme.colors.textTertiary};
  font-size: 0.6875rem;
  letter-spacing: 0.02em;
  text-transform: uppercase;

  ${StyledPanel} > & {
    margin-top: 0;
    margin-bottom: ${props => props.theme.spacing.xs};
  }
`;

const StyledSuggestions = styled.div`
  display: flex;
  flex-wrap: wrap;
  gap: ${props => props.theme.spacing.sm};
  margin-top: ${props => props.theme.spacing.md};
`;

const StyledSuggestion = styled.button`
  min-height: 2.25rem;
  padding: 0.25rem 0.75rem;
  border: 1px solid ${props => props.theme.colors.border};
  border-radius: ${props => props.theme.borderRadius.full};
  background-color: ${props => props.theme.colors.background};
  color: ${props => props.theme.colors.textSecondary};
  font: inherit;
  font-size: ${props => props.theme.typography.fontSize.sm};
  cursor: pointer;
  transition: border-color ${props => props.theme.transitions.fast},
              color ${props => props.theme.transitions.fast};

  &:hover {
    border-color: ${props => props.theme.colors.primary};
    color: ${props => props.theme.colors.primary};
  }

  &:focus-visible {
    outline: 2px solid ${props => props.theme.colors.primary};
    outline-offset: 2px;
  }
`;

/* Off-screen but readable by assistive technology. */
const StyledLiveRegion = styled.p`
  position: absolute;
  width: 1px;
  height: 1px;
  margin: -1px;
  padding: 0;
  overflow: hidden;
  clip-path: inset(50%);
  white-space: nowrap;
`;

StyledSearch.displayName = 'StyledManualSearch';
StyledField.displayName = 'StyledManualSearchField';
StyledInput.displayName = 'StyledManualSearchInput';
StyledHint.displayName = 'StyledManualSearchHint';
StyledClear.displayName = 'StyledManualSearchClear';
StyledPanel.displayName = 'StyledManualSearchPanel';
StyledResults.displayName = 'StyledManualSearchResults';
StyledResult.displayName = 'StyledManualSearchResult';
StyledResultLink.displayName = 'StyledManualSearchResultLink';
StyledResultBreadcrumb.displayName = 'StyledManualSearchResultBreadcrumb';
StyledResultTitle.displayName = 'StyledManualSearchResultTitle';
StyledResultSnippet.displayName = 'StyledManualSearchResultSnippet';
StyledReadingNow.displayName = 'StyledManualSearchReadingNow';
StyledEmpty.displayName = 'StyledManualSearchEmpty';
StyledStatus.displayName = 'StyledManualSearchStatus';
StyledSuggestions.displayName = 'StyledManualSearchSuggestions';
StyledSuggestion.displayName = 'StyledManualSearchSuggestion';
StyledLiveRegion.displayName = 'StyledManualSearchLiveRegion';

/** Wraps the words that matched in <mark>, leaving the rest as written. */
function Highlighted({ text, words }) {
  return (
    <>
      {highlightParts(text, words).map((part, index) => (
        part.match
          ? <mark key={index}>{part.text}</mark>
          : <React.Fragment key={index}>{part.text}</React.Fragment>
      ))}
    </>
  );
}

/** "Ctrl" everywhere except Apple keyboards, where it is the command key. */
function shortcutLabel() {
  if (typeof navigator === 'undefined') {
    return 'Ctrl K';
  }
  const platform = navigator.userAgentData?.platform || navigator.platform || '';
  return /mac|iphone|ipad|ipod/i.test(platform) ? '⌘ K' : 'Ctrl K';
}

function isTypingInField(target) {
  return target instanceof HTMLElement && (
    target.isContentEditable
    || ['INPUT', 'TEXTAREA', 'SELECT'].includes(target.tagName)
  );
}

export const ManualSearch = React.memo(React.forwardRef(({
  index,
  onSelect,
  activeId,
  variant = 'sidebar',
  shortcut = true,
  onActiveChange,
  onReadyToSearch,
}, ref) => {
  const [query, setQuery] = useState('');
  const [highlighted, setHighlighted] = useState(0);
  /* Server and first client render agree on "Ctrl K" until the platform is known. */
  const [hint, setHint] = useState('Ctrl K');

  const inputRef = useRef(null);
  const resultsRef = useRef(null);
  const listboxId = `${useId()}-results`;

  const results = useMemo(
    () => searchManual(index, query, { limit: RESULT_LIMIT }),
    [index, query]
  );

  const trimmed = query.trim();
  const isSearching = trimmed.length > 0;
  const tooShort = isSearching && trimmed.length < 2;

  useImperativeHandle(ref, () => ({
    focus() {
      inputRef.current?.focus();
      inputRef.current?.select();
    },
    isActive() {
      return query.trim().length > 0;
    },
  }), [query]);

  useEffect(() => setHint(shortcutLabel()), []);

  /* A new query starts at the top result rather than keeping a stale position. */
  useEffect(() => setHighlighted(0), [query]);

  useEffect(() => {
    onActiveChange?.(isSearching);
  }, [isSearching, onActiveChange]);

  const clear = useCallback(() => {
    setQuery('');
    inputRef.current?.focus();
  }, []);

  const open = useCallback((result) => {
    if (!result) {
      return;
    }
    onSelect(result.id);
    setQuery('');
    /* Let the chapter take focus; keeping it in the box would trap the reader. */
    inputRef.current?.blur();
  }, [onSelect]);

  useEffect(() => {
    if (!shortcut) {
      return undefined;
    }
    const handleKeyDown = (event) => {
      if ((event.ctrlKey || event.metaKey) && event.key.toLowerCase() === 'k') {
        event.preventDefault();
        onReadyToSearch?.();
        inputRef.current?.focus();
        inputRef.current?.select();
        return;
      }
      if (event.key === '/' && !isTypingInField(event.target) && !event.ctrlKey && !event.metaKey && !event.altKey) {
        event.preventDefault();
        onReadyToSearch?.();
        inputRef.current?.focus();
      }
    };

    document.addEventListener('keydown', handleKeyDown);
    return () => document.removeEventListener('keydown', handleKeyDown);
  }, [onReadyToSearch, shortcut]);

  // Keep the highlighted result inside the contents' scroll area.
  useEffect(() => {
    if (!results.length) {
      return;
    }
    resultsRef.current
      ?.querySelector(`[data-result-index="${highlighted}"]`)
      ?.scrollIntoView({ block: 'nearest' });
  }, [highlighted, results]);

  const handleKeyDown = useCallback((event) => {
    if (event.key === 'Escape') {
      if (query) {
        event.preventDefault();
        clear();
      }
      return;
    }
    if (!results.length) {
      return;
    }
    if (event.key === 'ArrowDown') {
      event.preventDefault();
      setHighlighted((current) => (current + 1) % results.length);
    } else if (event.key === 'ArrowUp') {
      event.preventDefault();
      setHighlighted((current) => (current - 1 + results.length) % results.length);
    } else if (event.key === 'Home') {
      event.preventDefault();
      setHighlighted(0);
    } else if (event.key === 'End') {
      event.preventDefault();
      setHighlighted(results.length - 1);
    } else if (event.key === 'Enter') {
      event.preventDefault();
      open(results[highlighted]);
    }
  }, [clear, highlighted, open, query, results]);

  const announcement = !isSearching
    ? ''
    : tooShort
      ? 'Keep typing to search the manual.'
      : results.length
        ? `${results.length} ${results.length === 1 ? 'topic' : 'topics'} found for ${trimmed}.`
        : `No topics found for ${trimmed}.`;

  const placeholder = variant === 'hero'
    ? 'Search for a task, for example take a payment'
    : 'Search the manual';

  const showPanel = isSearching;
  const body = showPanel
    ? (
      tooShort ? (
        <StyledEmpty>
          <p>Keep typing</p>
          <p>Two letters or more.</p>
        </StyledEmpty>
      ) : results.length ? (
        <>
          <StyledStatus aria-hidden="true">
            {results.length} {results.length === 1 ? 'topic' : 'topics'}
          </StyledStatus>
          <StyledResults
            id={listboxId}
            ref={resultsRef}
            role="listbox"
            aria-label="Search results"
          >
            {results.map((result, position) => (
              <StyledResult key={result.id}>
                <StyledResultLink
                  id={`${listboxId}-${position}`}
                  href={`#${result.id}`}
                  role="option"
                  aria-selected={position === highlighted}
                  $highlighted={position === highlighted}
                  data-result-index={position}
                  onMouseEnter={() => setHighlighted(position)}
                  onClick={(event) => {
                    event.preventDefault();
                    open(result);
                  }}
                >
                  <StyledResultBreadcrumb>
                    <Icon name="book" size={11} aria-hidden="true" />
                    {result.chapterNumber}. {result.chapterTitle}
                  </StyledResultBreadcrumb>
                  <StyledResultTitle>
                    <span>{result.number}</span>
                    <span>
                      <Highlighted text={result.title} words={result.hits} />
                      {result.id === activeId && (
                        <StyledReadingNow>Reading</StyledReadingNow>
                      )}
                    </span>
                  </StyledResultTitle>
                  {result.snippet && (
                    <StyledResultSnippet>
                      <Highlighted text={result.snippet} words={result.hits} />
                    </StyledResultSnippet>
                  )}
                </StyledResultLink>
              </StyledResult>
            ))}
          </StyledResults>
        </>
      ) : (
        <StyledEmpty>
          <p>No topics match &ldquo;{trimmed}&rdquo;</p>
          <p>Try a task, such as &ldquo;take a payment&rdquo; or &ldquo;add staff&rdquo;.</p>
        </StyledEmpty>
      )
    )
    : null;

  return (
    <StyledSearch $variant={variant}>
      <StyledField $variant={variant}>
        <Icon name="find" size={variant === 'hero' ? 20 : 16} aria-hidden="true" />
        <StyledInput
          ref={inputRef}
          $variant={variant}
          type="search"
          value={query}
          role="combobox"
          aria-expanded={isSearching && results.length > 0}
          aria-controls={listboxId}
          aria-autocomplete="list"
          aria-activedescendant={
            results.length ? `${listboxId}-${highlighted}` : undefined
          }
          aria-label="Search the user manual"
          placeholder={placeholder}
          autoComplete="off"
          spellCheck="false"
          onChange={(event) => setQuery(event.target.value)}
          onKeyDown={handleKeyDown}
        />
        {isSearching ? (
          <StyledClear type="button" onClick={clear} aria-label="Clear search">
            <Icon name="close" size={16} aria-hidden="true" />
          </StyledClear>
        ) : (
          <StyledHint aria-hidden="true">{hint}</StyledHint>
        )}
      </StyledField>

      <StyledLiveRegion role="status" aria-live="polite">{announcement}</StyledLiveRegion>

      {showPanel && (
        variant === 'hero' ? <StyledPanel $variant="hero">{body}</StyledPanel> : body
      )}

      {variant === 'hero' && !isSearching && (
        <StyledSuggestions>
          {SUGGESTIONS.map((suggestion) => (
            <StyledSuggestion
              key={suggestion}
              type="button"
              onClick={() => {
                setQuery(suggestion);
                inputRef.current?.focus();
              }}
            >
              {suggestion}
            </StyledSuggestion>
          ))}
        </StyledSuggestions>
      )}
    </StyledSearch>
  );
}));

ManualSearch.displayName = 'ManualSearch';
