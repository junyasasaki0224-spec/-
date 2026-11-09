// 共有ユーティリティ（依存パッケージなし）
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

export const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
export const SITE = path.join(ROOT, 'site');
export const GAMES = path.join(SITE, 'games');
export const DIST = path.join(ROOT, 'dist');

export const GENRES = [
  'puzzle', 'action', 'arcade', 'word', 'quiz', 'typing', 'brain', 'idle',
  'strategy', 'card', 'board', 'rhythm', 'sports', 'simulation', 'toy'
];
export const LANES = ['proven-twist', 'search-demand', 'trend-season', 'experiment'];

export const GENRE_LABELS = {
  puzzle: 'パズル', action: 'アクション', arcade: 'アーケード', word: 'ことば', quiz: 'クイズ',
  typing: 'タイピング', brain: '脳トレ', idle: '放置', strategy: '戦略', card: 'カード',
  board: 'ボード', rhythm: 'リズム', sports: 'スポーツ', simulation: 'シミュレーション', toy: 'あそび'
};

export function readJSON(file) {
  return JSON.parse(fs.readFileSync(file, 'utf8'));
}

export function siteConfig() {
  return readJSON(path.join(ROOT, 'site.config.json'));
}

/** site/games/<slug>/meta.json を全部読む（壊れたものは error 付きで返す） */
export function listGames() {
  if (!fs.existsSync(GAMES)) return [];
  return fs.readdirSync(GAMES, { withFileTypes: true })
    .filter((d) => d.isDirectory())
    .map((d) => {
      const dir = path.join(GAMES, d.name);
      const metaPath = path.join(dir, 'meta.json');
      let meta = null;
      let error = null;
      try { meta = readJSON(metaPath); } catch (e) { error = e.message; }
      return { slug: d.name, dir, meta, error };
    })
    .sort((a, b) => String(b.meta?.created || '').localeCompare(String(a.meta?.created || '')) || a.slug.localeCompare(b.slug));
}

export function walk(dir) {
  const out = [];
  for (const e of fs.readdirSync(dir, { withFileTypes: true })) {
    const p = path.join(dir, e.name);
    if (e.isDirectory()) out.push(...walk(p)); else out.push(p);
  }
  return out;
}

export function escapeHtml(s) {
  return String(s).replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
}

/** 商標・既存作品名のブロックリスト（# はコメント） */
export function blockedTerms() {
  const file = path.join(ROOT, 'automation', 'legal', 'blocked-terms.txt');
  if (!fs.existsSync(file)) return [];
  return fs.readFileSync(file, 'utf8').split('\n')
    .map((l) => l.replace(/#.*/, '').trim())
    .filter(Boolean);
}

export function termRegex(term) {
  const esc = term.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
  // 英数字の語は単語境界で判定（"uno" が "unordered" に当たらないように）
  return /^[\x00-\x7F]+$/.test(term) ? new RegExp(`(^|[^A-Za-z0-9])${esc}(?![A-Za-z0-9])`, 'i') : new RegExp(esc, 'i');
}
