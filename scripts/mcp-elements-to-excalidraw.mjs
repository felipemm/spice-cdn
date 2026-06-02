#!/usr/bin/env node
/**
 * Convert Excalidraw MCP checkpoint elements to a standard .excalidraw JSON file.
 * Usage: node scripts/mcp-elements-to-excalidraw.mjs < input.json > output.excalidraw
 *    or: node scripts/mcp-elements-to-excalidraw.mjs input.json output.excalidraw
 */

import { readFileSync, writeFileSync } from 'node:fs';
import { randomBytes } from 'node:crypto';

const SKIP_TYPES = new Set(['cameraUpdate', 'restoreCheckpoint', 'delete']);

function seed() {
  return Math.floor(Math.random() * 2 ** 31);
}

function baseFields(el, type) {
  const id = el.id || `gen-${randomBytes(4).toString('hex')}`;
  return {
    id,
    type,
    x: el.x ?? 0,
    y: el.y ?? 0,
    width: el.width ?? 0,
    height: el.height ?? 0,
    angle: 0,
    strokeColor: el.strokeColor ?? '#1e1e1e',
    backgroundColor: el.backgroundColor ?? 'transparent',
    fillStyle: el.fillStyle ?? 'solid',
    strokeWidth: el.strokeWidth ?? 2,
    strokeStyle: el.strokeStyle ?? 'solid',
    roughness: el.roughness ?? 1,
    opacity: el.opacity ?? 100,
    groupIds: [],
    frameId: null,
    index: 'a0',
    roundness: el.roundness ?? null,
    seed: seed(),
    version: 1,
    versionNonce: seed(),
    isDeleted: false,
    boundElements: [],
    updated: Date.now(),
    link: null,
    locked: false,
  };
}

function textForContainer(shapeId, shape, label) {
  const fontSize = label.fontSize ?? 16;
  const lines = String(label.text).split('\n');
  const text = lines.join('\n');
  const lineHeight = fontSize * 1.25;
  const height = Math.max(shape.height, lines.length * lineHeight + 8);
  const width = shape.width;
  const id = `${shapeId}-label`;
  return {
    ...baseFields({ id, x: shape.x, y: shape.y, width, height }, 'text'),
    text,
    rawText: text,
    fontSize,
    fontFamily: 1,
    textAlign: 'center',
    verticalAlign: 'middle',
    containerId: shapeId,
    originalText: text,
    autoResize: true,
    lineHeight,
  };
}

function convertElement(el) {
  if (SKIP_TYPES.has(el.type)) return [];

  const out = [];

  if (el.type === 'text') {
    const fontSize = el.fontSize ?? 16;
    const text = el.text ?? '';
    const width = Math.max(100, text.length * fontSize * 0.5);
    const height = fontSize * 1.4;
    out.push({
      ...baseFields({ ...el, width, height }, 'text'),
      text,
      rawText: text,
      fontSize,
      fontFamily: 1,
      textAlign: 'left',
      verticalAlign: 'top',
      containerId: null,
      originalText: text,
      autoResize: true,
      lineHeight: fontSize * 1.25,
    });
    return out;
  }

  if (el.type === 'arrow') {
    const id = el.id || `arrow-${seed()}`;
    const arrow = {
      ...baseFields({ ...el, id }, 'arrow'),
      points: el.points ?? [
        [0, 0],
        [el.width ?? 0, el.height ?? 0],
      ],
      lastCommittedPoint: null,
      startBinding: el.startBinding ?? null,
      endBinding: el.endBinding ?? null,
      startArrowhead: el.startArrowhead ?? null,
      endArrowhead: el.endArrowhead ?? 'arrow',
    };
    if (el.label?.text) {
      arrow.label = {
        text: el.label.text,
        fontSize: el.label.fontSize ?? 14,
        fontFamily: 1,
      };
    }
    out.push(arrow);
    return out;
  }

  if (['rectangle', 'ellipse', 'diamond'].includes(el.type)) {
    const id = el.id || `shape-${seed()}`;
    const shape = { ...baseFields({ ...el, id }, el.type) };
    if (el.label?.text) {
      const textEl = textForContainer(id, shape, el.label);
      shape.boundElements = [{ id: textEl.id, type: 'text' }];
      out.push(shape, textEl);
    } else {
      out.push(shape);
    }
    return out;
  }

  return [];
}

function convert(checkpoint) {
  const raw = checkpoint.elements ?? checkpoint;
  const elements = [];
  for (const el of raw) {
    elements.push(...convertElement(el));
  }
  // Re-index for stable ordering
  elements.forEach((e, i) => {
    e.index = `a${i}`;
  });
  return {
    type: 'excalidraw',
    version: 2,
    source: 'https://github.com/felipemm/spice-cdn',
    elements,
    appState: {
      gridSize: 20,
      gridStep: 5,
      gridModeEnabled: false,
      viewBackgroundColor: '#ffffff',
      scrollX: 0,
      scrollY: 0,
      zoom: { value: 0.5 },
    },
    files: {},
  };
}

export { convert };

import { fileURLToPath } from 'node:url';

const isMain = process.argv[1] === fileURLToPath(import.meta.url);

if (isMain) {
const args = process.argv.slice(2);
let input;
if (args.length >= 2) {
  input = JSON.parse(readFileSync(args[0], 'utf8'));
  const doc = convert(input);
  writeFileSync(args[1], JSON.stringify(doc, null, 2) + '\n');
  console.error(`Wrote ${args[1]} (${doc.elements.length} elements)`);
} else if (args.length === 1) {
  input = JSON.parse(readFileSync(args[0], 'utf8'));
  const doc = convert(input);
  const outPath = args[0].replace(/\.(source\.)?json$/, '.excalidraw');
  writeFileSync(outPath, JSON.stringify(doc, null, 2) + '\n');
  console.error(`Wrote ${outPath} (${doc.elements.length} elements)`);
} else {
  const chunks = [];
  for await (const c of process.stdin) chunks.push(c);
  const doc = convert(JSON.parse(Buffer.concat(chunks).toString('utf8')));
  process.stdout.write(JSON.stringify(doc, null, 2) + '\n');
}
}
