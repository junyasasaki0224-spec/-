#!/usr/bin/env node
// テンプレートから新しいゲームの雛形を作る。
// 使い方: node scripts/new-game.mjs <slug> "<タイトル>"
import fs from 'node:fs';
import path from 'node:path';
import { ROOT, GAMES } from './lib.mjs';

const [slug, title] = process.argv.slice(2);
if (!slug || !title || !/^[a-z0-9]+(-[a-z0-9]+)*$/.test(slug)) {
  console.error('usage: node scripts/new-game.mjs <slug(英小文字-ハイフン)> "<タイトル>"');
  process.exit(1);
}
const dest = path.join(GAMES, slug);
if (fs.existsSync(dest)) { console.error(`${dest} は既にあります`); process.exit(1); }

const tpl = path.join(ROOT, 'automation', 'templates', 'game');
fs.mkdirSync(dest, { recursive: true });
const jst = new Date(Date.now() + 9 * 3600 * 1000).toISOString().slice(0, 10);
for (const f of fs.readdirSync(tpl)) {
  const src = fs.readFileSync(path.join(tpl, f), 'utf8')
    .replaceAll('__SLUG__', slug)
    .replaceAll('__TITLE__', title)
    .replaceAll('__DATE__', jst);
  fs.writeFileSync(path.join(dest, f), src);
}
console.log(`created site/games/${slug}/ (index.html, game.js, meta.json)`);
