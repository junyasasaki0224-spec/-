#!/usr/bin/env node
// 全ゲームの構造・メタデータ・法務ガード（商標語/外部素材）をチェックする。
// 使い方: node scripts/validate.mjs [--only <slug>]
import fs from 'node:fs';
import path from 'node:path';
import { GAMES, GENRES, LANES, listGames, walk, blockedTerms, termRegex } from './lib.mjs';

const args = process.argv.slice(2);
const only = args.includes('--only') ? args[args.indexOf('--only') + 1] : null;

const MAX_GAME_BYTES = 400 * 1024; // 1ゲーム400KBまで（モバイル回線でも一瞬で開く）
const REQUIRED_FILES = ['index.html', 'game.js', 'meta.json'];
const ALLOWED_URL = /^https?:\/\/www\.w3\.org\//; // SVG名前空間など
const terms = blockedTerms().map((t) => ({ t, re: termRegex(t) }));

const errors = [];
const warnings = [];
const err = (slug, msg) => errors.push(`[${slug}] ${msg}`);
const warn = (slug, msg) => warnings.push(`[${slug}] ${msg}`);

const games = listGames();
const titles = new Map();

for (const g of games) {
  const { slug, dir, meta } = g;
  if (!/^[a-z0-9]+(-[a-z0-9]+)*$/.test(slug)) err(slug, 'ディレクトリ名は英小文字・数字・ハイフンのみ');
  for (const f of REQUIRED_FILES) if (!fs.existsSync(path.join(dir, f))) err(slug, `${f} がありません`);
  if (g.error) { err(slug, `meta.json を読めません: ${g.error}`); continue; }
  if (!meta) continue;

  // 重複タイトルは全ゲームで検査（--only でも）
  if (titles.has(meta.title)) err(slug, `タイトル「${meta.title}」が ${titles.get(meta.title)} と重複`);
  titles.set(meta.title, slug);
  if (only && slug !== only) continue;

  // ---- meta.json ----
  const need = ['slug', 'title', 'description', 'genre', 'lane', 'lineage', 'twist', 'controls', 'session_minutes', 'retention_hooks', 'tags', 'created', 'legal_check', 'score'];
  for (const k of need) if (meta[k] === undefined || meta[k] === '') err(slug, `meta.${k} がありません`);
  if (meta.slug !== slug) err(slug, `meta.slug (${meta.slug}) がディレクトリ名と不一致`);
  if (meta.genre && !GENRES.includes(meta.genre)) err(slug, `meta.genre は ${GENRES.join('/')} のいずれか`);
  if (meta.lane && !LANES.includes(meta.lane)) err(slug, `meta.lane は ${LANES.join('/')} のいずれか`);
  if (meta.created && !/^\d{4}-\d{2}-\d{2}$/.test(meta.created)) err(slug, 'meta.created は YYYY-MM-DD');
  if (meta.description && meta.description.length > 120) warn(slug, 'meta.description は120字以内推奨（検索結果で切れる）');
  if (meta.title && meta.title.length > 20) warn(slug, 'タイトルは20字以内推奨');
  if (!Array.isArray(meta.controls) || !meta.controls.length) err(slug, 'meta.controls は配列');
  if (Array.isArray(meta.controls) && !meta.controls.some((c) => c === 'tap' || c === 'touch')) err(slug, 'スマホ操作（tap/touch）に対応していません');
  const lc = meta.legal_check || {};
  for (const k of ['no_copied_assets', 'no_trademarks_in_name', 'not_a_specific_game_clone', 'no_real_people_or_brands', 'no_gambling_or_prizes']) {
    if (lc[k] !== true) err(slug, `meta.legal_check.${k} が true ではありません（LEGAL.md のチェックを実施）`);
  }
  if (typeof meta.score !== 'number') err(slug, 'meta.score は数値（企画スコア）');
  // 大手サイト提出用の英語情報
  const JA = /[\u3040-\u30ff\u3400-\u9fff]/;
  for (const k of ['title_en', 'description_en', 'howto_en', 'twist_en']) {
    if (!meta[k]) err(slug, `meta.${k} がありません（大手サイト提出用の英語）`);
    else if (JA.test(meta[k])) err(slug, `meta.${k} に日本語が含まれています`);
  }
  if (meta.description_en && meta.description_en.length > 300) warn(slug, 'meta.description_en は300字以内推奨');

  // ---- index.html ----
  const htmlPath = path.join(dir, 'index.html');
  if (fs.existsSync(htmlPath)) {
    const html = fs.readFileSync(htmlPath, 'utf8');
    const checks = [
      [/<html[^>]*lang="ja"/, '<html lang="ja"> が必要'],
      [new RegExp(`<html[^>]*data-slug="${slug}"`), `<html data-slug="${slug}"> が必要`],
      [/<meta name="viewport"/, 'viewport meta が必要'],
      [/<title>[^<]+<\/title>/, '<title> が必要'],
      [/<meta name="description" content="[^"]+"/, 'meta description が必要'],
      [/assets\/core\.css/, 'assets/core.css を読み込んでいません'],
      [/assets\/config\.js/, 'assets/config.js を読み込んでいません'],
      [/assets\/core\.js/, 'assets/core.js を読み込んでいません'],
      [/class="gk-howto"/, '遊び方セクション (.gk-howto) が必要']
    ];
    for (const [re, msg] of checks) if (!re.test(html)) err(slug, msg);
    const howto = html.match(/<article class="gk-howto"[\s\S]*?<\/article>/);
    if (howto) {
      const text = howto[0].replace(/<[^>]+>/g, '').replace(/\s+/g, '');
      if (text.length < 250) err(slug, `遊び方の本文が短すぎます（${text.length}字 / 250字以上）。広告審査とSEOのため独自の説明文を書く`);
    }
  }

  // ---- 全ファイル：外部URL・サイズ・商標語 ----
  let bytes = 0;
  for (const f of walk(dir)) {
    bytes += fs.statSync(f).size;
    const ext = path.extname(f);
    if (!['.html', '.js', '.css', '.json', '.svg'].includes(ext)) {
      warn(slug, `${path.relative(dir, f)}: 画像・音声ファイルは原則使わない（自作・ライセンス明記なら可）`);
      continue;
    }
    const src = fs.readFileSync(f, 'utf8');
    if (/\bTODO\b/.test(src)) err(slug, `${path.relative(dir, f)}: TODO が残っています`);
    for (const m of src.matchAll(/https?:\/\/[^\s"'`)<>]+/g)) {
      if (!ALLOWED_URL.test(m[0])) err(slug, `${path.relative(dir, f)}: 外部URL ${m[0]} を参照しています（素材・ライブラリはすべて同梱・自作）`);
    }
    for (const { t, re } of terms) {
      if (re.test(src)) err(slug, `${path.relative(dir, f)}: 商標・既存作品名「${t}」を含みます（ジャンル一般名に言い換える）`);
    }
  }
  if (bytes > MAX_GAME_BYTES) err(slug, `サイズ ${Math.round(bytes / 1024)}KB > ${MAX_GAME_BYTES / 1024}KB`);
}

if (only && !games.some((g) => g.slug === only)) errors.push(`--only ${only}: そのゲームはありません`);

for (const w of warnings) console.warn('WARN ', w);
for (const e of errors) console.error('ERROR', e);
console.log(`\n${games.length} games checked: ${errors.length} error(s), ${warnings.length} warning(s)`);
process.exit(errors.length ? 1 : 0);
