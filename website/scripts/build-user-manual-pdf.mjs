/**
 * Build the downloadable user manual PDF
 *
 * Renders src/lib/userManual.js with the screenshots in public/images/user-manual
 * into a print layout (cover, contents, chapters), prints it with a locally
 * installed Chrome or Edge over the DevTools protocol, and writes:
 *   - public/downloads/hosspi-user-manual.pdf
 *   - src/lib/userManualPdf.json (page count and size, shown on the page)
 *
 * Contents page numbers take two passes: the first print is read back to find
 * the page each chapter and section starts on, the second prints with those
 * numbers filled in. The contents links and the PDF bookmarks both jump to the
 * same headings.
 *
 * Usage: npm run manual:pdf
 * Set CHROME_PATH when Chrome or Edge is not in a standard location.
 *
 * @file scripts/build-user-manual-pdf.mjs
 */

import { spawn } from 'node:child_process';
import { existsSync, mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { setTimeout as sleep } from 'node:timers/promises';

const ROOT = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const fromRoot = (...parts) => join(ROOT, ...parts);
const fileUrl = (...parts) => pathToFileURL(fromRoot(...parts)).href;

const { USER_MANUAL, numberUserManual } = await import(fileUrl('src/lib/userManual.js'));
const { theme } = await import(fileUrl('src/styles/theme.js'));
const figures = JSON.parse(readFileSync(fromRoot('src/lib/userManualFigures.json'), 'utf8'));

const OUTPUT_PDF = fromRoot('public/downloads/hosspi-user-manual.pdf');
const OUTPUT_INFO = fromRoot('src/lib/userManualPdf.json');
const DEBUG_PORT = 9555;

/* Screenshots print at one scale so on-screen text is the same size in every
   figure, capped at the text width. */
const MM_PER_PIXEL = 0.19;
const CONTENT_WIDTH_MM = 176;

const BROWSER_CANDIDATES = [
  process.env.CHROME_PATH,
  'C:/Program Files/Google/Chrome/Application/chrome.exe',
  'C:/Program Files (x86)/Google/Chrome/Application/chrome.exe',
  'C:/Program Files (x86)/Microsoft/Edge/Application/msedge.exe',
  'C:/Program Files/Microsoft/Edge/Application/msedge.exe',
  '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome',
  '/usr/bin/google-chrome',
  '/usr/bin/chromium',
  '/usr/bin/chromium-browser',
].filter(Boolean);

/* ------------------------------------------------------------------ *
 * Rendering
 * ------------------------------------------------------------------ */

const escapeHtml = (value) => String(value ?? '')
  .replace(/&/g, '&amp;')
  .replace(/</g, '&lt;')
  .replace(/>/g, '&gt;')
  .replace(/"/g, '&quot;');

const INLINE_TOKEN = /(\*\*[^*]+\*\*|\[[^\]]+\]\(#[a-z0-9-]+\))/g;
const INLINE_LINK = /^\[([^\]]+)\]\((#[a-z0-9-]+)\)$/;

function rich(text) {
  return String(text ?? '')
    .split(INLINE_TOKEN)
    .filter(Boolean)
    .map((part) => {
      if (part.startsWith('**') && part.endsWith('**')) {
        return `<strong>${escapeHtml(part.slice(2, -2))}</strong>`;
      }
      const link = part.match(INLINE_LINK);
      if (link) {
        return `<a href="${link[2]}">${escapeHtml(link[1])}</a>`;
      }
      return escapeHtml(part);
    })
    .join('');
}

function formatDate(isoDate) {
  return new Intl.DateTimeFormat('en-GB', {
    day: 'numeric',
    month: 'long',
    year: 'numeric',
    timeZone: 'UTC',
  }).format(new Date(`${isoDate}T00:00:00Z`));
}

function markerPosition({ x, y, w = 0, h = 0, side }) {
  switch (side) {
    case 'right':
      return { left: x + w, top: y + h / 2 };
    case 'top':
      return { left: x + w / 2, top: y };
    case 'bottom':
      return { left: x + w / 2, top: y + h };
    default:
      return { left: x < 2 ? x + 1.5 : x, top: y + h / 2 };
  }
}

function renderFigure(block) {
  const figure = figures[block.figure];
  if (!figure) {
    console.warn(`Missing figure "${block.figure}"`);
    return '';
  }
  const widthMm = Math.min(CONTENT_WIDTH_MM, figure.width * MM_PER_PIXEL).toFixed(1);
  const imagePath = fromRoot('public', ...figure.src.split('/').filter(Boolean));
  const markers = (figure.markers || []).map((marker) => {
    const position = markerPosition(marker);
    const outline = marker.w > 0 && marker.h > 0
      ? `<span class="highlight" style="left:${marker.x}%;top:${marker.y}%;width:${marker.w}%;height:${marker.h}%"></span>`
      : '';
    return `${outline}<span class="marker" style="left:${position.left}%;top:${position.top}%">${marker.n}</span>`;
  }).join('');

  return `
    <figure style="width:${widthMm}mm">
      <div class="frame">
        <img src="${pathToFileURL(imagePath).href}" width="${figure.width}" height="${figure.height}" alt="${escapeHtml(figure.alt)}">
        ${markers}
      </div>
      <figcaption><strong>Figure ${block.figureNumber}.</strong> ${escapeHtml(block.caption || figure.alt)}</figcaption>
    </figure>`;
}

const NOTE_LABELS = { tip: 'Tip', info: 'Note', warning: 'Important' };

function renderBlock(block) {
  switch (block.type) {
    case 'p':
      return `<p>${rich(block.text)}</p>`;
    case 'steps':
      return `
        ${block.figure ? renderFigure(block) : ''}
        <ol class="steps">
          ${block.items.map((item, index) => `<li><span class="step-number">${index + 1}</span><span>${rich(item)}</span></li>`).join('')}
        </ol>`;
    case 'figure':
      return renderFigure(block);
    case 'note': {
      const tone = NOTE_LABELS[block.tone] ? block.tone : 'info';
      return `
        <aside class="note note-${tone}">
          <p class="note-label">${escapeHtml(block.title || NOTE_LABELS[tone])}</p>
          <p>${rich(block.text)}</p>
        </aside>`;
    }
    case 'list':
      return `<ul>${block.items.map((item) => `<li>${rich(item)}</li>`).join('')}</ul>`;
    case 'table':
      return `
        <table>
          <thead><tr>${block.columns.map((column) => `<th>${escapeHtml(column)}</th>`).join('')}</tr></thead>
          <tbody>${block.rows.map((row) => `<tr>${row.map((cell) => `<td>${rich(cell)}</td>`).join('')}</tr>`).join('')}</tbody>
        </table>`;
    default:
      return '';
  }
}

function tocRow(id, number, title, level, pages) {
  return `
    <a class="toc-row toc-${level}" href="#${id}">
      <span class="toc-number">${escapeHtml(number)}</span>
      <span class="toc-title">${escapeHtml(title)}</span>
      <span class="toc-leader"></span>
      <span class="toc-page">${pages.get(id) ?? ''}</span>
    </a>`;
}

function renderHtml(chapters, pages) {
  const c = theme.colors;
  const font = '"Segoe UI", Roboto, "Helvetica Neue", Arial, sans-serif';
  const updated = formatDate(USER_MANUAL.updated);

  const contents = chapters.map((chapter) => `
    <li class="toc-chapter-item">
      ${tocRow(chapter.id, `${chapter.number}`, chapter.title, 'chapter', pages)}
      <ol>
        ${chapter.sections.map((section) => `<li>${tocRow(section.id, section.number, section.title, 'section', pages)}</li>`).join('')}
      </ol>
    </li>`).join('');

  const body = chapters.map((chapter) => `
    <section class="chapter" id="${chapter.id}">
      <header class="chapter-head">
        <p class="chapter-eyebrow">Chapter ${chapter.number}</p>
        <h2>${escapeHtml(chapter.title)}</h2>
        ${chapter.summary ? `<p class="chapter-summary">${escapeHtml(chapter.summary)}</p>` : ''}
      </header>
      ${chapter.sections.map((section) => {
        // The heading travels with its first block as one unbreakable unit.
        // Chrome duplicates a heading's bookmark when break-after: avoid
        // pushes it to the next page on its own.
        const [firstBlock, ...otherBlocks] = section.blocks;
        return `
        <section class="section" id="${section.id}">
          <div class="section-lead">
            <h3><span class="section-number">${section.number}</span> ${escapeHtml(section.title)}</h3>
            ${section.audience ? `<p class="audience">Who: ${escapeHtml(section.audience)}</p>` : ''}
            ${firstBlock ? renderBlock(firstBlock) : ''}
          </div>
          ${otherBlocks.map(renderBlock).join('')}
        </section>`;
      }).join('')}
    </section>`).join('');

  return `<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<title>${escapeHtml(USER_MANUAL.title)}</title>
<style>
  @page {
    size: A4;
    margin: 18mm 17mm 20mm 17mm;
    @bottom-left {
      content: "HOSSPI HMS User Manual \\2014  Version ${escapeHtml(USER_MANUAL.version)}";
      font: 500 7.5pt ${font};
      color: ${c.textTertiary};
    }
    @bottom-right {
      content: "Page " counter(page) " of " counter(pages);
      font: 600 7.5pt ${font};
      color: ${c.textSecondary};
    }
  }
  @page cover {
    margin: 0;
    @bottom-left { content: none; }
    @bottom-right { content: none; }
  }

  * { box-sizing: border-box; }
  html {
    font-family: ${font};
    font-size: 10pt;
    line-height: 1.55;
    color: ${c.text};
    -webkit-print-color-adjust: exact;
    print-color-adjust: exact;
  }
  body { margin: 0; }
  a { color: ${c.primary}; text-decoration: none; }
  strong { font-weight: 650; }

  /* Cover */
  .cover {
    page: cover;
    position: relative;
    width: 210mm;
    height: 297mm;
    overflow: hidden;
    break-after: page;
    background: linear-gradient(160deg, ${c.backgroundTertiary} 0%, #FFFFFF 58%);
  }
  .cover-brand {
    position: absolute; top: 22mm; left: 22mm;
    display: flex; align-items: center; gap: 4mm;
  }
  .cover-brand img { width: 15mm; height: 15mm; }
  .cover-brand strong { display: block; font-size: 17pt; line-height: 1; color: ${c.primary}; letter-spacing: 0.02em; }
  .cover-brand span { display: block; margin-top: 1.2mm; font-size: 7.5pt; font-weight: 600; letter-spacing: 0.16em; text-transform: uppercase; color: ${c.textTertiary}; }
  .cover-art {
    position: absolute; right: -30mm; top: 56mm;
    width: 122mm; height: 122mm; opacity: 0.95;
    filter: drop-shadow(0 12mm 16mm rgba(0, 121, 253, 0.22));
  }
  .cover-main { position: absolute; left: 22mm; top: 92mm; width: 96mm; }
  .cover-eyebrow { margin: 0 0 4mm; font-size: 10pt; font-weight: 700; letter-spacing: 0.18em; text-transform: uppercase; color: ${c.secondary}; }
  .cover h1 { margin: 0 0 6mm; font-size: 40pt; line-height: 1.02; letter-spacing: -0.02em; color: ${c.text}; }
  .cover h1 span { display: block; }
  .cover-subtitle { margin: 0 0 9mm; font-size: 13pt; line-height: 1.45; color: ${c.textSecondary}; }
  .cover-topics { margin: 0; padding: 0; list-style: none; display: flex; flex-wrap: wrap; gap: 2mm; }
  .cover-topics li { padding: 1.2mm 3.2mm; border: 0.3mm solid ${c.border}; border-radius: 10mm; background: #FFFFFF; font-size: 8pt; font-weight: 600; color: ${c.primaryDark}; }
  .cover-band {
    position: absolute; left: 0; right: 0; bottom: 0; height: 44mm;
    padding: 12mm 22mm; display: flex; gap: 16mm;
    background: ${c.primary}; color: #FFFFFF;
  }
  .cover-band div span { display: block; font-size: 7.5pt; letter-spacing: 0.14em; text-transform: uppercase; opacity: 0.8; }
  .cover-band div strong { display: block; margin-top: 1.5mm; font-size: 12pt; }

  /* Contents */
  .contents { break-after: page; }
  .contents h2 { margin: 0 0 2mm; font-size: 24pt; letter-spacing: -0.02em; }
  .contents-intro { margin: 0 0 7mm; color: ${c.textSecondary}; }
  .contents ol { margin: 0; padding: 0; list-style: none; }
  .toc-chapter-item { margin: 0 0 2.6mm; break-inside: avoid; }
  .toc-row { display: flex; align-items: baseline; gap: 2mm; padding: 0.7mm 0; color: ${c.text}; }
  .toc-chapter { font-size: 10.5pt; font-weight: 700; border-bottom: 0.3mm solid ${c.borderLight}; padding-bottom: 1.2mm; margin-bottom: 0.6mm; }
  .toc-section { padding-left: 9mm; font-size: 9pt; color: ${c.textSecondary}; }
  .toc-number { min-width: 9mm; color: ${c.primary}; font-variant-numeric: tabular-nums; font-weight: 700; }
  .toc-section .toc-number { font-weight: 600; }
  .toc-leader { flex: 1; border-bottom: 0.35mm dotted ${c.textTertiary}; transform: translateY(-1mm); opacity: 0.7; }
  .toc-chapter .toc-leader { border-bottom-color: transparent; }
  .toc-page { min-width: 9mm; text-align: right; font-variant-numeric: tabular-nums; font-weight: 600; color: ${c.text}; }

  /* Chapters */
  .chapter { break-before: page; }
  .chapter-head { margin: 0 0 7mm; padding: 0 0 6mm; border-bottom: 0.6mm solid ${c.primary}; }
  .chapter-eyebrow { margin: 0 0 1.5mm; font-size: 9pt; font-weight: 700; letter-spacing: 0.16em; text-transform: uppercase; color: ${c.primary}; }
  .chapter h2 { margin: 0 0 2.5mm; font-size: 25pt; line-height: 1.1; letter-spacing: -0.02em; }
  .chapter-summary { margin: 0; font-size: 11pt; color: ${c.textSecondary}; }

  .section { margin: 0 0 7mm; }
  h3 { margin: 0 0 3mm; font-size: 13.5pt; line-height: 1.25; }
  .section-lead { break-inside: avoid; }
  .section-number { display: inline-block; min-width: 10mm; color: ${c.primary}; }
  p { margin: 0 0 3mm; orphans: 3; widows: 3; }
  .audience {
    display: inline-block; margin: 0 0 3mm; padding: 0.5mm 3mm;
    border-radius: 10mm; background: ${c.backgroundTertiary};
    font-size: 8pt; font-weight: 600; color: ${c.primaryDark};
  }
  ul { margin: 0 0 4mm; padding-left: 5.5mm; }
  ul li { margin: 0 0 1.4mm; }
  ul li::marker { color: ${c.primary}; }

  figure { margin: 3mm auto 4mm; break-inside: avoid; break-after: avoid; max-width: 100%; }
  .frame { position: relative; line-height: 0; }
  .frame img { width: 100%; height: auto; border: 0.3mm solid ${c.border}; border-radius: 2mm; }
  .highlight {
    position: absolute; border: 0.55mm solid ${c.secondary}; border-radius: 1.2mm;
    background: rgba(226, 58, 46, 0.07);
  }
  .marker {
    position: absolute; transform: translate(-50%, -50%);
    width: 5.4mm; height: 5.4mm; border-radius: 50%;
    display: flex; align-items: center; justify-content: center;
    background: ${c.secondary}; color: #FFFFFF; border: 0.55mm solid #FFFFFF;
    box-shadow: 0 0.4mm 1.2mm rgba(13, 39, 68, 0.35);
    font-size: 7.5pt; font-weight: 700; line-height: 1;
  }
  figcaption { margin-top: 2mm; font-size: 8pt; line-height: 1.4; color: ${c.textSecondary}; }
  figcaption strong { color: ${c.text}; }

  .steps { margin: 0 0 4mm; padding: 0; list-style: none; }
  .steps li { display: flex; gap: 3mm; margin: 0 0 2mm; break-inside: avoid; }
  .step-number {
    flex: none; width: 5.6mm; height: 5.6mm; margin-top: 0.3mm; border-radius: 50%;
    display: flex; align-items: center; justify-content: center;
    background: ${c.secondary}; color: #FFFFFF; font-size: 7.5pt; font-weight: 700; line-height: 1;
  }

  .note { margin: 0 0 4mm; padding: 3mm 4mm; border-left: 1.2mm solid; border-radius: 1.5mm; break-inside: avoid; }
  .note p { margin: 0; }
  .note-label { margin-bottom: 1mm !important; font-size: 8pt; font-weight: 700; letter-spacing: 0.06em; text-transform: uppercase; }
  .note-tip { background: ${c.successLight}; border-color: ${c.success}; }
  .note-tip .note-label { color: ${c.success}; }
  .note-info { background: ${c.infoLight}; border-color: ${c.info}; }
  .note-info .note-label { color: ${c.info}; }
  .note-warning { background: ${c.warningLight}; border-color: ${c.warning}; }
  .note-warning .note-label { color: ${c.warning}; }

  table { width: 100%; margin: 0 0 4mm; border-collapse: collapse; font-size: 8.8pt; }
  th, td { padding: 1.8mm 2.5mm; border-bottom: 0.3mm solid ${c.border}; text-align: left; vertical-align: top; }
  th { background: ${c.backgroundSecondary}; font-weight: 700; }
  tr { break-inside: avoid; }
</style>
</head>
<body>
  <section class="cover">
    <div class="cover-brand">
      <img src="${fileUrl('public/logos/icon-256.png')}" alt="">
      <div><strong>HOSSPI</strong><span>Hospital Management System</span></div>
    </div>
    <img class="cover-art" src="${fileUrl('public/logos/icon-512.png')}" alt="">
    <div class="cover-main">
      <p class="cover-eyebrow">User manual</p>
      <h1><span>HOSSPI HMS</span> <span>User Manual</span></h1>
      <p class="cover-subtitle">${escapeHtml(USER_MANUAL.subtitle)}</p>
      <ul class="cover-topics">
        ${chapters.slice(1, 9).map((chapter) => `<li>${escapeHtml(chapter.title)}</li>`).join('')}
      </ul>
    </div>
    <div class="cover-band">
      <div><span>Version</span><strong>${escapeHtml(USER_MANUAL.version)}</strong></div>
      <div><span>Updated</span><strong>${escapeHtml(updated)}</strong></div>
      <div><span>Open the app</span><strong>app.hosspi.com</strong></div>
    </div>
  </section>

  <nav class="contents" aria-label="Contents">
    <h2>Contents</h2>
    <p class="contents-intro">Select any entry to go straight to it. Your PDF reader's bookmarks list the same chapters and topics.</p>
    <ol>${contents}</ol>
  </nav>

  ${body}
</body>
</html>`;
}

/* ------------------------------------------------------------------ *
 * Browser
 * ------------------------------------------------------------------ */

async function openBrowser() {
  const executable = BROWSER_CANDIDATES.find((candidate) => existsSync(candidate));
  if (!executable) {
    throw new Error('Chrome or Edge was not found. Set CHROME_PATH to its executable.');
  }
  const profile = mkdtempSync(join(tmpdir(), 'hosspi-manual-profile-'));
  const browser = spawn(executable, [
    '--headless=new',
    `--remote-debugging-port=${DEBUG_PORT}`,
    `--user-data-dir=${profile}`,
    '--no-first-run',
    '--no-default-browser-check',
    '--disable-extensions',
    '--allow-file-access-from-files',
    'about:blank',
  ], { stdio: 'ignore' });

  let target;
  for (let attempt = 0; attempt < 100 && !target; attempt++) {
    try {
      const list = await (await fetch(`http://127.0.0.1:${DEBUG_PORT}/json/list`)).json();
      target = list.find((entry) => entry.type === 'page');
    } catch {
      // Not listening yet.
    }
    if (!target) {
      await sleep(150);
    }
  }
  if (!target) {
    browser.kill();
    throw new Error('The browser did not open its debugging port.');
  }

  const socket = new WebSocket(target.webSocketDebuggerUrl);
  await new Promise((resolveOpen, rejectOpen) => {
    socket.onopen = resolveOpen;
    socket.onerror = rejectOpen;
  });

  let nextId = 0;
  const pending = new Map();
  const listeners = new Set();
  socket.onmessage = (event) => {
    const message = JSON.parse(event.data);
    if (message.id && pending.has(message.id)) {
      const { resolveCall, rejectCall, method } = pending.get(message.id);
      pending.delete(message.id);
      if (message.error) {
        rejectCall(new Error(`${method}: ${message.error.message}`));
      } else {
        resolveCall(message.result);
      }
    } else if (message.method) {
      listeners.forEach((listener) => listener(message));
    }
  };

  const send = (method, params = {}) => new Promise((resolveCall, rejectCall) => {
    const id = ++nextId;
    pending.set(id, { resolveCall, rejectCall, method });
    socket.send(JSON.stringify({ id, method, params }));
  });

  const waitFor = (method, timeoutMs = 60000) => new Promise((resolveWait, rejectWait) => {
    const timer = setTimeout(() => {
      listeners.delete(listener);
      rejectWait(new Error(`Timed out waiting for ${method}`));
    }, timeoutMs);
    const listener = (message) => {
      if (message.method === method) {
        clearTimeout(timer);
        listeners.delete(listener);
        resolveWait(message.params);
      }
    };
    listeners.add(listener);
  });

  const close = async () => {
    socket.close();
    browser.kill();
    await sleep(500);
    rmSync(profile, { recursive: true, force: true, maxRetries: 5, retryDelay: 200 });
  };

  await send('Page.enable');
  await send('Runtime.enable');
  return { send, waitFor, close };
}

async function printHtml(browser, htmlPath) {
  const loaded = browser.waitFor('Page.loadEventFired');
  await browser.send('Page.navigate', { url: pathToFileURL(htmlPath).href });
  await loaded;
  await browser.send('Runtime.evaluate', {
    expression: 'Promise.all([document.fonts.ready, ...Array.from(document.images).map((image) => image.decode().catch(() => null))]).then(() => true)',
    awaitPromise: true,
  });
  const { data } = await browser.send('Page.printToPDF', {
    printBackground: true,
    preferCSSPageSize: true,
    generateDocumentOutline: true,
    generateTaggedPDF: true,
    marginTop: 0,
    marginBottom: 0,
    marginLeft: 0,
    marginRight: 0,
    transferMode: 'ReturnAsBase64',
  });
  return Buffer.from(data, 'base64');
}

/* ------------------------------------------------------------------ *
 * Reading page numbers back from the PDF
 * ------------------------------------------------------------------ */

const decodePdfName = (name) => name.replace(/#([0-9A-Fa-f]{2})/g, (_, hex) => String.fromCharCode(parseInt(hex, 16)));

/** Indirect objects by number, as latin1 text (one character per byte). */
function parseObjects(source) {
  const objects = new Map();
  for (const match of source.matchAll(/(\d+) 0 obj\b([\s\S]*?)endobj/g)) {
    objects.set(Number(match[1]), match[2]);
  }
  return objects;
}

/**
 * Page on which each named destination (element id) lands, from the catalog's
 * destination dictionary or name tree, following the page tree order.
 *
 * @param {Buffer} pdf - Printed document
 * @returns {{pages: Map<string, number>, pageCount: number}} Destinations and page count
 */
function readDestinations(pdf) {
  const source = pdf.toString('latin1');
  const objects = parseObjects(source);

  const catalog = [...objects.values()].find((body) => /\/Type\s*\/Catalog\b/.test(body)) || '';
  const pagesRoot = catalog.match(/\/Pages\s+(\d+)\s+0\s+R/);
  const order = [];
  const walk = (objectNumber) => {
    const node = objects.get(objectNumber) || '';
    const kids = node.match(/\/Kids\s*\[([^\]]*)\]/);
    if (/\/Type\s*\/Pages\b/.test(node) && kids) {
      for (const kid of kids[1].matchAll(/(\d+)\s+0\s+R/g)) {
        walk(Number(kid[1]));
      }
    } else {
      order.push(objectNumber);
    }
  };
  if (pagesRoot) {
    walk(Number(pagesRoot[1]));
  }
  const pageNumberOf = new Map(order.map((objectNumber, index) => [objectNumber, index + 1]));

  const destinations = new Map();
  const resolveBody = (reference) => objects.get(Number(reference)) || '';

  // Dictionary form: /Dests << /name [12 0 R /XYZ ...] >> (inline or referenced).
  const destsReference = catalog.match(/\/Dests\s+(\d+)\s+0\s+R/);
  const destsInline = catalog.match(/\/Dests\s*(<<[\s\S]*?>>)/);
  const dictionary = destsReference ? resolveBody(destsReference[1]) : destsInline?.[1] || '';
  for (const entry of dictionary.matchAll(/\/([^\s/[\]<>()]+)\s*\[\s*(\d+)\s+0\s+R/g)) {
    destinations.set(decodePdfName(entry[1]), pageNumberOf.get(Number(entry[2])));
  }

  // Name tree form: /Names [(name) [12 0 R /XYZ ...] ...] in any object.
  if (destinations.size === 0) {
    for (const body of objects.values()) {
      for (const entry of body.matchAll(/\(([^()]+)\)\s*\[\s*(\d+)\s+0\s+R\s*\/XYZ/g)) {
        destinations.set(entry[1], pageNumberOf.get(Number(entry[2])));
      }
    }
  }

  return { pages: destinations, pageCount: order.length };
}

/* ------------------------------------------------------------------ *
 * Bookmarks
 * ------------------------------------------------------------------ */

/** PDF text string in UTF-16BE hex form, safe for any title. */
function pdfTextString(text) {
  let hex = 'FEFF';
  for (const character of text) {
    const code = character.codePointAt(0);
    if (code > 0xffff) {
      const offset = code - 0x10000;
      hex += (0xd800 + Math.floor(offset / 0x400)).toString(16).padStart(4, '0');
      hex += (0xdc00 + (offset % 0x400)).toString(16).padStart(4, '0');
    } else {
      hex += code.toString(16).padStart(4, '0');
    }
  }
  return `<${hex.toUpperCase()}>`;
}

const bookmarkTitles = (chapters) => [
  USER_MANUAL.title,
  'Contents',
  ...chapters.flatMap((chapter) => [
    `${chapter.number}. ${chapter.title}`,
    ...chapter.sections.map((section) => `${section.number} ${section.title}`),
  ]),
];

/**
 * Give every bookmark the manual's own heading text.
 *
 * Chrome builds bookmarks from heading text and sometimes repeats a heading's
 * text, or runs a line break together. Its outline follows document order, so
 * items are matched one-to-one with the expected titles and rewritten as an
 * incremental update appended to the file; the printed bytes stay untouched.
 *
 * @param {Buffer} pdf - Printed document
 * @param {string[]} titles - Expected titles in document order
 * @returns {Buffer} Document with corrected bookmarks, or the input unchanged
 */
function rewriteBookmarks(pdf, titles) {
  const source = pdf.toString('latin1');
  const objects = parseObjects(source);
  const catalog = [...objects.values()].find((body) => /\/Type\s*\/Catalog\b/.test(body)) || '';
  const outlinesReference = catalog.match(/\/Outlines\s+(\d+)\s+0\s+R/);
  const firstReference = outlinesReference && (objects.get(Number(outlinesReference[1])) || '').match(/\/First\s+(\d+)\s+0\s+R/);
  if (!firstReference) {
    console.warn('Bookmarks: no outline found; left as generated.');
    return pdf;
  }

  const items = [];
  const visit = (objectNumber) => {
    let current = objectNumber;
    while (current) {
      items.push(current);
      const body = objects.get(current) || '';
      const child = body.match(/\/First\s+(\d+)\s+0\s+R/);
      if (child) {
        visit(Number(child[1]));
      }
      const next = body.match(/\/Next\s+(\d+)\s+0\s+R/);
      current = next ? Number(next[1]) : 0;
    }
  };
  visit(Number(firstReference[1]));

  if (items.length !== titles.length) {
    console.warn(`Bookmarks: expected ${titles.length} headings but the outline has ${items.length}; left as generated.`);
    return pdf;
  }

  // Root, Info and ID come from the last trailer, or the cross-reference stream.
  let dictionary = source.slice(source.lastIndexOf('trailer'), source.lastIndexOf('startxref'));
  if (!/\/Root/.test(dictionary)) {
    const crossReference = [...objects.values()].reverse().find((body) => /\/Type\s*\/XRef\b/.test(body)) || '';
    dictionary = crossReference.split('stream')[0];
  }
  const root = dictionary.match(/\/Root\s+(\d+\s+\d+\s+R)/);
  const info = dictionary.match(/\/Info\s+(\d+\s+\d+\s+R)/);
  const identifier = dictionary.match(/\/ID\s*(\[[^\]]*\])/);
  const previous = source.match(/startxref\s+(\d+)\s+%%EOF\s*$/);
  if (!root || !previous) {
    console.warn('Bookmarks: document trailer not recognised; left as generated.');
    return pdf;
  }

  let update = '\n';
  const entries = [];
  items.forEach((objectNumber, index) => {
    const body = objects.get(objectNumber).replace(
      /\/Title\s*(\((?:\\.|[^\\)])*\)|<[0-9A-Fa-f\s]*>)/,
      `/Title ${pdfTextString(titles[index])}`,
    );
    entries.push([objectNumber, pdf.length + update.length]);
    update += `${objectNumber} 0 obj${body}endobj\n`;
  });

  const crossReferenceOffset = pdf.length + update.length;
  update += 'xref\n';
  for (const [objectNumber, offset] of entries.sort((a, b) => a[0] - b[0])) {
    update += `${objectNumber} 1\n${String(offset).padStart(10, '0')} 00000 n \n`;
  }
  update += 'trailer\n<< ';
  update += `/Size ${Math.max(...objects.keys()) + 1} /Root ${root[1]} `;
  update += info ? `/Info ${info[1]} ` : '';
  update += identifier ? `/ID ${identifier[1]} ` : '';
  update += `/Prev ${previous[1]} >>\nstartxref\n${crossReferenceOffset}\n%%EOF\n`;

  return Buffer.concat([pdf, Buffer.from(update, 'latin1')]);
}

/* ------------------------------------------------------------------ *
 * Build
 * ------------------------------------------------------------------ */

const chapters = numberUserManual(USER_MANUAL);
const headingIds = chapters.flatMap((chapter) => [chapter.id, ...chapter.sections.map((section) => section.id)]);
const workDir = mkdtempSync(join(tmpdir(), 'hosspi-manual-html-'));
const htmlPath = join(workDir, 'hosspi-user-manual.html');
const browser = await openBrowser();

try {
  let pages = new Map();
  let pdf = null;
  let pageCount = 0;

  for (let pass = 1; pass <= 3; pass++) {
    writeFileSync(htmlPath, renderHtml(chapters, pages));
    pdf = await printHtml(browser, htmlPath);
    const read = readDestinations(pdf);
    pageCount = read.pageCount;
    const missing = headingIds.filter((id) => !read.pages.get(id));
    if (missing.length) {
      console.warn(`Contents: no page found for ${missing.length} heading(s): ${missing.slice(0, 6).join(', ')}`);
    }
    const settled = headingIds.every((id) => pages.get(id) === read.pages.get(id));
    pages = read.pages;
    if (settled) {
      break;
    }
  }

  pdf = rewriteBookmarks(pdf, bookmarkTitles(chapters));

  mkdirSync(dirname(OUTPUT_PDF), { recursive: true });
  writeFileSync(OUTPUT_PDF, pdf);
  writeFileSync(OUTPUT_INFO, `${JSON.stringify({
    pages: pageCount,
    bytes: pdf.length,
    generatedAt: new Date().toISOString(),
  }, null, 2)}\n`);

  console.log(`Wrote public/downloads/hosspi-user-manual.pdf: ${pageCount} pages, ${(pdf.length / (1024 * 1024)).toFixed(1)} MB`);
} finally {
  await browser.close();
  rmSync(workDir, { recursive: true, force: true });
}
