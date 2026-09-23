#!/usr/bin/env node

/**
 * diff.js — Compare a pasted JSON config with the current opencode.json
 *
 * Usage:
 *   node diff.js -PasteJson <path> -Current <opencode.json>
 *   node diff.js -PasteJson <path> -Current <opencode.json> -Merge -Out <path>
 *
 * Output:
 *   JSON diff on stdout: {added: [{key, full}], removed: [{key, full}],
 *                         modified: [{key, before, after}]}
 *
 * With -Merge, the merged config is written to -Out. Only the
 * provider.bifrost-litellm.models section is merged; every other top-level
 * section (agent, plugin, mcp, permission, ...) is preserved verbatim.
 *
 * Exit codes:
 *   0 — success
 *   2 — usage error (missing args, I/O error, invalid JSON)
 *   3 — validation error (paste missing required keys)
 */

const fs = require('fs');
const path = require('path');

function parseArgs() {
  const args = process.argv.slice(2);
  const result = { merge: false };
  for (let i = 0; i < args.length; i++) {
    if (args[i] === '-PasteJson' && i + 1 < args.length) {
      result.pasteJson = args[++i];
    } else if (args[i] === '-Current' && i + 1 < args.length) {
      result.current = args[++i];
    } else if (args[i] === '-Merge') {
      result.merge = true;
    } else if (args[i] === '-Out' && i + 1 < args.length) {
      result.out = args[++i];
    }
  }
  return result;
}

function stripBom(text) {
  return text.charCodeAt(0) === 0xFEFF ? text.slice(1) : text;
}

function hasBom(filePath) {
  const fd = fs.openSync(filePath, 'r');
  try {
    const buf = Buffer.alloc(3);
    const read = fs.readSync(fd, buf, 0, 3, 0);
    return read === 3 && buf[0] === 0xEF && buf[1] === 0xBB && buf[2] === 0xBF;
  } finally {
    fs.closeSync(fd);
  }
}

function loadJson(filePath) {
  const raw = fs.readFileSync(filePath, 'utf8');
  const stripped = stripBom(raw);
  return JSON.parse(stripped);
}

function getModels(config, required) {
  const models =
    config &&
    config.provider &&
    config.provider['bifrost-litellm'] &&
    config.provider['bifrost-litellm'].models;
  if (!models || typeof models !== 'object' || Array.isArray(models)) {
    if (required) {
      throw new Error('Paste missing provider.bifrost-litellm.models');
    }
    return {};
  }
  return models;
}

function diffModels(pasteModels, currentModels) {
  const pasteKeys = Object.keys(pasteModels);
  const currentKeys = Object.keys(currentModels);

  const added = [];
  const removed = [];
  const modified = [];

  // Added: in paste but not in current
  for (const key of pasteKeys) {
    if (!currentKeys.includes(key)) {
      added.push({ key, full: pasteModels[key] });
    }
  }

  // Removed: in current but not in paste
  for (const key of currentKeys) {
    if (!pasteKeys.includes(key)) {
      removed.push({ key, full: currentModels[key] });
    }
  }

  // Modified: in both but different
  for (const key of pasteKeys) {
    if (currentKeys.includes(key)) {
      const pasteStr = JSON.stringify(pasteModels[key]);
      const currentStr = JSON.stringify(currentModels[key]);
      if (pasteStr !== currentStr) {
        modified.push({ key, before: currentModels[key], after: pasteModels[key] });
      }
    }
  }

  return { added, removed, modified };
}

/**
 * Merge the pasted models into the current models:
 *  - key in paste only              -> added
 *  - key in both                    -> updated from paste
 *  - key in current only            -> removed
 * Key order of the current section is preserved; added keys are appended.
 */
function mergeModels(pasteModels, currentModels) {
  const merged = {};
  for (const key of Object.keys(currentModels)) {
    if (Object.prototype.hasOwnProperty.call(pasteModels, key)) {
      merged[key] = pasteModels[key];
    }
  }
  for (const key of Object.keys(pasteModels)) {
    if (!Object.prototype.hasOwnProperty.call(merged, key)) {
      merged[key] = pasteModels[key];
    }
  }
  return merged;
}

function applyMerge(currentConfig, mergedModels) {
  // Deep copy so we never mutate the parsed current config in place.
  const out = JSON.parse(JSON.stringify(currentConfig));
  if (!out.provider) out.provider = {};
  if (!out.provider['bifrost-litellm']) out.provider['bifrost-litellm'] = {};
  out.provider['bifrost-litellm'].models = mergedModels;
  return out;
}

function main() {
  const args = parseArgs();

  if (!args.pasteJson || !args.current) {
    console.error('Usage: node diff.js -PasteJson <path> -Current <path> [-Merge -Out <path>]');
    process.exit(2);
  }

  if (args.merge && !args.out) {
    console.error('Usage: -Merge requires -Out <path>');
    process.exit(2);
  }

  try {
    const pasteConfig = loadJson(args.pasteJson);
    const currentConfig = loadJson(args.current);

    const pasteModels = getModels(pasteConfig, true);
    const currentModels = getModels(currentConfig, false);

    const diff = diffModels(pasteModels, currentModels);

    if (args.merge) {
      const mergedModels = mergeModels(pasteModels, currentModels);
      const mergedConfig = applyMerge(currentConfig, mergedModels);
      // Preserve the current file's BOM convention (if any).
      const bom = hasBom(args.current) ? '\uFEFF' : '';
      fs.writeFileSync(args.out, bom + JSON.stringify(mergedConfig, null, 2) + '\n', 'utf8');
    }

    console.log(JSON.stringify(diff, null, 2));
    process.exit(0);
  } catch (err) {
    console.error('ERROR:', err.message);
    if (err.message && err.message.includes('missing provider')) {
      process.exit(3);
    }
    process.exit(2);
  }
}

main();