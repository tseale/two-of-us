// Sky lab → Swift: what the fixture exporters share.
//
// Each exporter that imports this file (night, season, colour, air, look, palette) runs the lab's OWN
// modules, collects their answers as tables, and writes one generated Swift file into TwoOfUsTests/: an
// enum namespace holding each table as a multi-line CSV string, and nothing else. Tables are text, not
// array literals: a few thousand numeric literals in one expression is more than Swift's type checker
// will take. Numbers are written as JavaScript prints them (the shortest text that reads back to the
// same double), so the Swift side compares against the lab's values to the lab's own precision.
//
// The generated files hold DATA ONLY. The code that reads them is written by hand, once, in
// TwoOfUsTests/SkyCoreFixture.swift — for these tables and for the word tables moment.mjs and stars.mjs
// write — so regenerating a fixture can never change how it is read.
//
// Every exporter takes `--check`: write nothing, and exit 1 if the file on disk is not what the lab
// says today (`published` below; moment.mjs and stars.mjs do the same in their own last step).
//
// Nothing here is typed by hand into the Swift: change the lab, run the exporter, commit both.

import { readFileSync, writeFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, resolve, relative } from 'node:path';

const HERE = dirname(fileURLToPath(import.meta.url));
/** The repository's root (…/design/sky-lab/tools/swift-fixtures → four up). */
export const REPO = resolve(HERE, '../../../..');

/** One number as the lab has it: the shortest text that reads back to the same double. */
export const num = (x) => {
  if (typeof x !== 'number' || !Number.isFinite(x)) throw new TypeError(`fixture: not a finite number: ${x}`);
  return Object.is(x, -0) ? '0' : String(x);
};

/** One CSV cell: a number, or a plain word (no comma, quote, backslash or newline). */
const cell = (v) => {
  if (typeof v === 'number') return num(v);
  const s = String(v);
  if (/[,"\\\n]/.test(s)) throw new TypeError(`fixture: a cell cannot hold ${JSON.stringify(s)}`);
  return s;
};

/**
 * A table: its Swift name, what it holds (the doc comment: say which lab function gave the numbers),
 * the column names, and the rows.
 * @param {string} name
 * @param {string} about
 * @param {string[]} columns
 * @param {Array<Array<number|string>>} rows
 */
export function table(name, about, columns, rows) {
  for (const row of rows) {
    if (row.length !== columns.length) throw new RangeError(`fixture ${name}: a row of ${row.length} cells under ${columns.length} columns`);
  }
  return { name, about, columns, rows: rows.map((row) => row.map(cell).join(',')) };
}

/**
 * Puts a generated file where it belongs — or, under `--check`, only compares: nothing is written, and
 * the process exits 1 if the file on disk is stale. Returns whether the file on disk was already this text.
 * @param {string} path  absolute
 * @param {string} text  the whole file
 * @param {string} script  absolute path of the exporter, for the message
 */
export function published(path, text, script) {
  let before = null;
  try { before = readFileSync(path, 'utf8'); } catch { /* not there yet */ }
  const same = before === text;
  if (process.argv.includes('--check')) {
    if (!same) {
      process.stderr.write(`${relative(REPO, path)} is stale: run node ${relative(REPO, script)}\n`);
      process.exit(1);
    }
    return same;
  }
  writeFileSync(path, text);
  return same;
}

/**
 * Writes TwoOfUsTests/<file>.swift: `enum <file>` with one static string per table.
 * @param {{ file: string, script: string, sources: string[], tables: ReturnType<typeof table>[] }} spec
 */
export function writeSwift({ file, script, sources, tables }) {
  const command = `node ${relative(REPO, script)}`;
  const out = [];
  out.push('// GENERATED FILE — do not edit by hand.');
  out.push('//');
  out.push('// Numbers exported from the sky lab\'s own modules, so the Swift is tested against what the');
  out.push('// signed-off mockup really computes:');
  for (const source of sources) out.push(`//     ${source}`);
  out.push('// To regenerate, from the repository\'s root:');
  out.push(`//     ${command}`);
  out.push('// (`--check` only compares.) It rewrites this whole file; a hand edit here is lost, and is a lie');
  out.push('// about the lab.');
  out.push('');
  out.push('import Foundation');
  out.push('');
  out.push('/// The lab\'s numbers as comma-separated tables, one row a line: data only. They are read with');
  out.push('/// `SkyCoreFixture.rows` and `SkyCoreFixture.number` (TwoOfUsTests/SkyCoreFixture.swift).');
  out.push(`enum ${file} {`);
  for (const t of tables) {
    for (const line of t.about.split('\n')) out.push(`    /// ${line}`.trimEnd());
    out.push('    ///');
    out.push(`    /// Columns: ${t.columns.join(', ')}.`);
    out.push(`    static let ${t.name} = """`);
    out.push(...t.rows);
    out.push('"""');
    if (t !== tables[tables.length - 1]) out.push('');
  }
  out.push('}');
  out.push('');
  const path = resolve(REPO, 'TwoOfUsTests', `${file}.swift`);
  const text = out.join('\n');
  const same = published(path, text, script);
  const kb = (Buffer.byteLength(text) / 1024).toFixed(1);
  const what = process.argv.includes('--check') ? 'up to date' : same ? 'unchanged' : 'written';
  console.log(`${relative(REPO, path)}: ${tables.length} tables, ${tables.reduce((n, t) => n + t.rows.length, 0)} rows, ${kb} KB (${what})`);
  return path;
}

// ── a named time zone, for the dates a test builds with a Calendar ───────
// The lab itself never reads a zone (it takes `tz`, hours from UTC). The app's rules run on a Calendar,
// so the exporters need "18:00 on 21 Nov 2026 in Chicago" as an instant, and the lab's `tz` for a date.

/** Minutes east of UTC in `zone` at the instant `utcMs`. */
export function offsetMinutes(zone, utcMs) {
  const parts = new Intl.DateTimeFormat('en-US', {
    timeZone: zone, hourCycle: 'h23', year: 'numeric', month: '2-digit', day: '2-digit',
    hour: '2-digit', minute: '2-digit', second: '2-digit',
  }).formatToParts(new Date(utcMs));
  const get = (type) => Number(parts.find((p) => p.type === type).value);
  const asUTC = Date.UTC(get('year'), get('month') - 1, get('day'), get('hour'), get('minute'), get('second'));
  return Math.round((asUTC - Math.floor(utcMs / 1000) * 1000) / 60_000);
}

/** The instant (epoch ms) of a wall-clock time in `zone`. (Not for a time the clocks skip or repeat.) */
export function zoned(zone, year, month, day, hour = 0, minute = 0, second = 0) {
  const wall = Date.UTC(year, month - 1, day, hour, minute, second);
  let utc = wall - offsetMinutes(zone, wall) * 60_000;
  utc = wall - offsetMinutes(zone, utc) * 60_000;
  return utc;
}

/** 'YYYY-MM-DD' for a UTC-midnight day number. */
export const isoDay = (ms) => new Date(ms).toISOString().slice(0, 10);
