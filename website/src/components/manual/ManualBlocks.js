/**
 * ManualBlocks - Renders the content blocks of a user manual section
 *
 * Block types: paragraph, numbered steps (optionally under a screenshot whose
 * markers match the step numbers), standalone figure, note, bullet list and
 * table. See src/lib/userManual.js for the content format.
 *
 * @component
 * @param {Object} props
 * @param {Array<Object>} props.blocks - Section blocks
 * @param {Object} props.figures - Screenshot data keyed by figure id
 * @returns {JSX.Element} Rendered blocks
 * @file src/components/manual/ManualBlocks.js
 */
'use client';

import React from 'react';
import styled from 'styled-components';
import { Icon } from '@/components/ui';
import { ManualFigure } from './ManualFigure';
import { ManualRichText } from './ManualRichText';

const StyledParagraph = styled.p`
  margin: 0 0 ${props => props.theme.spacing.md} 0;
  color: ${props => props.theme.colors.text};
  line-height: ${props => props.theme.typography.lineHeight.relaxed};
  max-width: 76ch;
`;

const StyledSteps = styled.ol`
  list-style: none;
  margin: 0 0 ${props => props.theme.spacing.lg} 0;
  padding: 0;
  display: grid;
  gap: ${props => props.theme.spacing.sm};
  max-width: 76ch;

  li {
    display: grid;
    grid-template-columns: auto minmax(0, 1fr);
    align-items: start;
    gap: ${props => props.theme.spacing.md};
    line-height: ${props => props.theme.typography.lineHeight.relaxed};
  }
`;

const StyledStepNumber = styled.span`
  display: inline-flex;
  align-items: center;
  justify-content: center;
  width: 1.75rem;
  height: 1.75rem;
  margin-top: 0.1rem;
  border-radius: ${props => props.theme.borderRadius.full};
  background-color: ${props => props.theme.colors.secondary};
  color: #FFFFFF;
  font-size: ${props => props.theme.typography.fontSize.sm};
  font-weight: ${props => props.theme.typography.fontWeight.bold};
  line-height: 1;
`;

const StyledList = styled.ul`
  margin: 0 0 ${props => props.theme.spacing.lg} 0;
  padding-left: ${props => props.theme.spacing.lg};
  max-width: 76ch;

  li {
    margin-bottom: ${props => props.theme.spacing.xs};
    line-height: ${props => props.theme.typography.lineHeight.relaxed};
  }

  li::marker {
    color: ${props => props.theme.colors.primary};
  }
`;

const NOTE_TONES = {
  tip: { icon: 'lightbulb', color: 'success', background: 'successLight', label: 'Tip' },
  info: { icon: 'info', color: 'info', background: 'infoLight', label: 'Note' },
  warning: { icon: 'alert', color: 'warning', background: 'warningLight', label: 'Important' },
};

const StyledNote = styled.aside.withConfig({
  shouldForwardProp: (prop) => prop !== '$tone',
})`
  display: grid;
  grid-template-columns: auto minmax(0, 1fr);
  gap: ${props => props.theme.spacing.md};
  margin: 0 0 ${props => props.theme.spacing.lg} 0;
  padding: ${props => props.theme.spacing.md} ${props => props.theme.spacing.lg};
  border: 1px solid ${props => props.theme.colors.border};
  border-left: 4px solid ${props => props.theme.colors[NOTE_TONES[props.$tone].color]};
  border-radius: ${props => props.theme.borderRadius.md};
  background-color: ${props => props.theme.colors[NOTE_TONES[props.$tone].background]};
  max-width: 76ch;

  svg {
    margin-top: 0.15rem;
    color: ${props => props.theme.colors[NOTE_TONES[props.$tone].color]};
  }

  p {
    margin: 0;
    line-height: ${props => props.theme.typography.lineHeight.relaxed};
  }
`;

const StyledNoteTitle = styled.p`
  font-weight: ${props => props.theme.typography.fontWeight.semibold};
  margin-bottom: ${props => props.theme.spacing.xs} !important;
`;

const StyledTableWrap = styled.div`
  margin: 0 0 ${props => props.theme.spacing.lg} 0;
  overflow-x: auto;
  border: 1px solid ${props => props.theme.colors.border};
  border-radius: ${props => props.theme.borderRadius.md};
`;

const StyledTable = styled.table`
  width: 100%;
  border-collapse: collapse;
  font-size: ${props => props.theme.typography.fontSize.sm};

  th,
  td {
    padding: ${props => props.theme.spacing.sm} ${props => props.theme.spacing.md};
    text-align: left;
    vertical-align: top;
    border-bottom: 1px solid ${props => props.theme.colors.borderLight};
    line-height: ${props => props.theme.typography.lineHeight.normal};
  }

  th {
    background-color: ${props => props.theme.colors.backgroundSecondary};
    color: ${props => props.theme.colors.text};
    font-weight: ${props => props.theme.typography.fontWeight.semibold};
    white-space: nowrap;
  }

  tr:last-child td {
    border-bottom: none;
  }
`;

StyledParagraph.displayName = 'StyledManualParagraph';
StyledSteps.displayName = 'StyledManualSteps';
StyledStepNumber.displayName = 'StyledManualStepNumber';
StyledList.displayName = 'StyledManualList';
StyledNote.displayName = 'StyledManualNote';
StyledNoteTitle.displayName = 'StyledManualNoteTitle';
StyledTableWrap.displayName = 'StyledManualTableWrap';
StyledTable.displayName = 'StyledManualTable';

function Steps({ items }) {
  return (
    <StyledSteps>
      {items.map((item, index) => (
        <li key={index}>
          <StyledStepNumber aria-hidden="true">{index + 1}</StyledStepNumber>
          <span>
            <ManualRichText text={item} />
          </span>
        </li>
      ))}
    </StyledSteps>
  );
}

function Block({ block, figures }) {
  switch (block.type) {
    case 'p':
      return (
        <StyledParagraph>
          <ManualRichText text={block.text} />
        </StyledParagraph>
      );
    case 'steps':
      return (
        <>
          {block.figure && (
            <ManualFigure
              figure={figures[block.figure]}
              number={block.figureNumber}
              caption={block.caption}
            />
          )}
          <Steps items={block.items} />
        </>
      );
    case 'figure':
      return (
        <ManualFigure
          figure={figures[block.figure]}
          number={block.figureNumber}
          caption={block.caption}
        />
      );
    case 'note': {
      const tone = NOTE_TONES[block.tone] ? block.tone : 'info';
      return (
        <StyledNote $tone={tone} aria-label={block.title || NOTE_TONES[tone].label}>
          <Icon name={NOTE_TONES[tone].icon} size={20} />
          <div>
            {block.title && <StyledNoteTitle>{block.title}</StyledNoteTitle>}
            <p>
              <ManualRichText text={block.text} />
            </p>
          </div>
        </StyledNote>
      );
    }
    case 'list':
      return (
        <StyledList>
          {block.items.map((item, index) => (
            <li key={index}>
              <ManualRichText text={item} />
            </li>
          ))}
        </StyledList>
      );
    case 'table':
      return (
        <StyledTableWrap>
          <StyledTable>
            <thead>
              <tr>
                {block.columns.map((column) => (
                  <th key={column} scope="col">{column}</th>
                ))}
              </tr>
            </thead>
            <tbody>
              {block.rows.map((row, rowIndex) => (
                <tr key={rowIndex}>
                  {row.map((cell, cellIndex) => (
                    <td key={cellIndex}>
                      <ManualRichText text={cell} />
                    </td>
                  ))}
                </tr>
              ))}
            </tbody>
          </StyledTable>
        </StyledTableWrap>
      );
    default:
      return null;
  }
}

export const ManualBlocks = React.memo(({ blocks, figures }) => {
  return (
    <>
      {blocks.map((block, index) => (
        <Block key={index} block={block} figures={figures} />
      ))}
    </>
  );
});

ManualBlocks.displayName = 'ManualBlocks';
