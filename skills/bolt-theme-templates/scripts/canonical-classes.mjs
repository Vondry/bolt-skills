#!/usr/bin/env node
// Reports (or rewrites) Tailwind classes in the theme's Twig templates that have a canonical,
// shorter form — the same hint IntelliJ / PhpStorm and the Tailwind CSS IntelliSense extension
// show as "The class `rounded-[var(--radius-card)]` can be written as `rounded-card`".
//
// The suggestions come from the theme's own Tailwind design system (`tailwindcss canonicalize`,
// Tailwind CSS v4.3+), so project tokens are known: `rounded-[var(--radius-btn)]` → `rounded-btn`,
// `text-[0.9375rem]` → `text-meta` when `--text-meta: 0.9375rem`, `w-[1.5rem]` → `w-6`.
// Unlike the IDE inspection it also sees classes inside Twig strings and interpolated attributes
// (`{{ big ? 'col-span-2' : '' }}`, `class: '…'` include parameters, variant maps).
//
// Usage (from the Bolt project root):
//   node canonical-classes.mjs            report, exit 1 when a class can be shortened
//   node canonical-classes.mjs --fix      rewrite the templates in place
//   node canonical-classes.mjs --theme public/theme/<name>
//
// Exit codes: 0 = every class canonical (or all fixed), 1 = non-canonical classes found,
//             2 = cannot run (no theme, no Tailwind CLI with `canonicalize`).

import { spawnSync } from 'node:child_process';
import { existsSync, readdirSync, readFileSync, statSync, writeFileSync } from 'node:fs';
import { join, relative, resolve } from 'node:path';

const args = process.argv.slice(2);
const fix = args.includes('--fix');
const themeArg = args.indexOf('--theme');

function activeThemeDir() {
    if (themeArg !== -1 && args[themeArg + 1]) {
        return args[themeArg + 1];
    }
    const config = 'config/bolt/config.yaml';
    const match = existsSync(config) && readFileSync(config, 'utf8').match(/^theme:\s*['"]?([\w-]+)/m);
    return match ? join('public/theme', match[1]) : null;
}

const themeDir = activeThemeDir();
const cssEntry = themeDir && join(themeDir, 'css/tailwind/index.css');
const cli = themeDir && resolve(themeDir, 'node_modules/.bin/tailwindcss');

if (!themeDir || !existsSync(cssEntry)) {
    console.error('SKIPPED: theme or css/tailwind/index.css not found (run from the Bolt project root or pass --theme).');
    process.exit(2);
}
if (!existsSync(cli)) {
    console.error(`SKIPPED: ${cli} not found — run npm install in ${themeDir}.`);
    process.exit(2);
}

function twigFiles(dir) {
    return readdirSync(dir).flatMap((name) => {
        const path = join(dir, name);
        if (name === 'node_modules') {
            return [];
        }
        if (statSync(path).isDirectory()) {
            return twigFiles(path);
        }
        return name.endsWith('.twig') ? [path] : [];
    });
}

// Classes never contain whitespace or quotes, so splitting on them yields every class token,
// whether it sits in a class="" attribute, a Twig string or a ternary. Tokens with Twig
// delimiters or no letters are not class candidates.
const SPLIT = /[\s"'`]+/;
const isCandidate = (token) => /[a-z]/.test(token) && !/[{}|<>;]/.test(token) && token.length <= 200;

const files = twigFiles(themeDir).map((path) => ({ path, lines: readFileSync(path, 'utf8').split('\n') }));
const candidates = new Set();
for (const { lines } of files) {
    for (const line of lines) {
        line.split(SPLIT).filter(isCandidate).forEach((token) => candidates.add(token));
    }
}

// One candidate per line keeps each result independent (a group would also be re-sorted).
const result = spawnSync(cli, ['canonicalize', '--stream', '--css', 'css/tailwind/index.css', '--format', 'jsonl'], {
    cwd: themeDir,
    input: [...candidates].join('\n') + '\n',
    encoding: 'utf8',
    maxBuffer: 64 * 1024 * 1024,
});
if (result.status !== 0) {
    console.error('SKIPPED: `tailwindcss canonicalize` failed (needs Tailwind CSS v4.3+):');
    console.error((result.error?.message || result.stderr || result.stdout || '').trim());
    process.exit(2);
}

const canonical = new Map();
for (const row of result.stdout.split('\n').filter((line) => line.startsWith('{'))) {
    const { input, output, changed } = JSON.parse(row);
    if (changed && output && !/\s/.test(output)) {
        canonical.set(input, output);
    }
}

const escape = (value) => value.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
let found = 0;

for (const file of files) {
    let dirty = false;
    file.lines = file.lines.map((line, index) => {
        let next = line;
        for (const token of new Set(line.split(SPLIT))) {
            const replacement = canonical.get(token);
            if (!replacement) {
                continue;
            }
            found++;
            console.log(`${relative('.', file.path)}:${index + 1}: ${token} → ${replacement}`);
            next = next.replace(new RegExp(`(?<=^|[\\s"'\`])${escape(token)}(?=$|[\\s"'\`])`, 'g'), replacement);
        }
        dirty ||= next !== line;
        return next;
    });
    if (fix && dirty) {
        writeFileSync(file.path, file.lines.join('\n'));
    }
}

if (found === 0) {
    console.log(`All Tailwind classes in ${themeDir} are canonical.`);
    process.exit(0);
}
console.log(fix
    ? `Rewrote ${found} class(es) to their canonical form. Rebuild the CSS (npm run prod).`
    : `${found} class(es) can be written shorter. Run with --fix to rewrite them.`);
process.exit(fix ? 0 : 1);
