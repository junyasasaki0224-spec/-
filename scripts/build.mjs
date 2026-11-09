#!/usr/bin/env node
// site/ → dist/ を生成する。トップページ・sitemap・robots・config.js を自動生成。
// 使い方: node scripts/build.mjs
import fs from 'node:fs';
import path from 'node:path';
import { SITE, DIST, listGames, siteConfig, escapeHtml, GENRE_LABELS } from './lib.mjs';

const cfg = siteConfig();
const base = (cfg.baseUrl || '').replace(/\/$/, '');
const games = listGames().filter((g) => g.meta && !g.error && !g.meta.hidden);

fs.rmSync(DIST, { recursive: true, force: true });
fs.cpSync(SITE, DIST, { recursive: true });

// 公開用設定（広告IDなど公開して問題ない値だけ）
const publicCfg = { siteName: cfg.siteName, baseUrl: base, adsense: cfg.adsense, analytics: cfg.analytics };
fs.writeFileSync(path.join(DIST, 'assets', 'config.js'), `window.SITE_CONFIG = ${JSON.stringify(publicCfg, null, 2)};\n`);

// HTML内のプレースホルダ置換 + canonical / OGP 付与
function finalizeHtml(file, relUrl, meta) {
  let html = fs.readFileSync(file, 'utf8');
  html = html.replaceAll('%SITE_NAME%', escapeHtml(cfg.siteName));
  const extra = [];
  if (base) extra.push(`<link rel="canonical" href="${base}/${relUrl}">`);
  if (meta) {
    extra.push(`<meta property="og:type" content="website">`);
    extra.push(`<meta property="og:title" content="${escapeHtml(meta.title)} | ${escapeHtml(cfg.siteName)}">`);
    extra.push(`<meta property="og:description" content="${escapeHtml(meta.description)}">`);
    extra.push(`<meta name="twitter:card" content="summary">`);
  }
  if (extra.length) html = html.replace('</head>', `${extra.join('\n')}\n</head>`);
  // フッター（全ページ共通）
  const foot = `<footer class="gk-foot"><a href="${meta ? '../../' : './'}">${escapeHtml(cfg.siteName)}</a> ・ <a href="${meta ? '../../' : ''}about.html">このサイトについて</a> ・ <a href="${meta ? '../../' : ''}privacy.html">プライバシーポリシー</a></footer>`;
  if (!html.includes('class="gk-foot"')) html = html.replace('</body>', `${foot}\n</body>`);
  fs.writeFileSync(file, html);
}

for (const g of games) finalizeHtml(path.join(DIST, 'games', g.slug, 'index.html'), `games/${g.slug}/`, g.meta);
for (const p of ['about.html', 'privacy.html']) finalizeHtml(path.join(DIST, p), p, null);

// ---- トップページ ----
function card(g, isNew) {
  const m = g.meta;
  const tags = [GENRE_LABELS[m.genre] || m.genre, ...(m.tags || []).slice(0, 2)].map((t) => `<span class="tag">${escapeHtml(t)}</span>`).join('');
  return `<a class="card" href="games/${g.slug}/">
  <span class="card__icon" aria-hidden="true">${escapeHtml(m.icon || '🎮')}</span>
  <span class="card__body">
    <span class="card__title">${escapeHtml(m.title)}${isNew ? '<span class="new">NEW</span>' : ''}</span>
    <span class="card__desc">${escapeHtml(m.description)}</span>
    <span class="card__tags">${tags}</span>
  </span>
</a>`;
}
const newest = games[0];
const genresUsed = [...new Set(games.map((g) => g.meta.genre))];
const indexHtml = `<!doctype html>
<html lang="ja" data-slug="site">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>${escapeHtml(cfg.siteName)} | 登録不要の無料ミニゲーム</title>
<meta name="description" content="${escapeHtml(cfg.siteDescription)}">
${base ? `<link rel="canonical" href="${base}/">` : ''}
<link rel="stylesheet" href="assets/core.css">
<style>
  .hero { padding: 28px 0 8px; }
  .hero h1 { margin: 0; font-size: clamp(24px, 6vw, 34px); }
  .hero p { margin: 6px 0 0; color: var(--muted); }
  .filters { display: flex; gap: 6px; flex-wrap: wrap; margin: 18px 0 12px; }
  .filters button { border: 1px solid var(--line); background: var(--surface); color: var(--text); border-radius: 999px; padding: 6px 12px; font: inherit; font-size: 13px; cursor: pointer; }
  .filters button[aria-pressed="true"] { background: var(--text); color: var(--bg); border-color: var(--text); }
  .grid { display: grid; gap: 12px; grid-template-columns: repeat(auto-fill, minmax(280px, 1fr)); }
  .card { display: flex; gap: 14px; align-items: flex-start; padding: 16px; background: var(--surface); border: 1px solid var(--line); border-radius: var(--radius); text-decoration: none; color: var(--text); transition: transform .15s, box-shadow .15s; }
  .card:hover { transform: translateY(-2px); box-shadow: var(--shadow); }
  .card__icon { font-size: 34px; line-height: 1; }
  .card__body { display: grid; gap: 4px; min-width: 0; }
  .card__title { font-weight: 700; font-size: 16px; }
  .card__desc { font-size: 13px; color: var(--muted); line-height: 1.5; }
  .card__tags { display: flex; gap: 4px; flex-wrap: wrap; }
  .tag { font-size: 11px; padding: 1px 8px; border-radius: 999px; background: var(--surface-2); color: var(--muted); }
  .new { margin-left: 6px; font-size: 10px; font-weight: 800; color: var(--accent-ink); background: var(--accent); border-radius: 4px; padding: 1px 5px; vertical-align: 2px; }
  .featured { margin: 18px 0 4px; }
  .featured .card { border-color: var(--accent); }
  .empty { color: var(--muted); }
</style>
</head>
<body>
<main class="gk-page" style="max-width: 980px">
  <section class="hero">
    <h1>${escapeHtml(cfg.siteName)}</h1>
    <p>${escapeHtml(cfg.siteDescription)}</p>
  </section>
  ${newest ? `<section class="featured" aria-label="今日の新作">${card(newest, true)}</section>` : '<p class="empty">ゲームは準備中です。</p>'}
  ${games.length > 1 ? `<nav class="filters" aria-label="ジャンル">
    <button type="button" data-g="" aria-pressed="true">すべて</button>
    ${genresUsed.map((g) => `<button type="button" data-g="${g}" aria-pressed="false">${escapeHtml(GENRE_LABELS[g] || g)}</button>`).join('\n    ')}
  </nav>
  <section class="grid" id="grid">
    ${games.slice(1).map((g) => card(g, false).replace('<a class="card"', `<a class="card" data-genre="${g.meta.genre}"`)).join('\n    ')}
  </section>` : ''}
  <div class="gk-ad-slot" data-ad-slot-name="indexInFeed"></div>
</main>
<script src="assets/config.js"></script>
<script src="assets/core.js"></script>
<script>
  document.querySelectorAll('.filters button').forEach(function (b) {
    b.addEventListener('click', function () {
      document.querySelectorAll('.filters button').forEach(function (x) { x.setAttribute('aria-pressed', String(x === b)); });
      var g = b.dataset.g;
      document.querySelectorAll('#grid .card').forEach(function (c) { c.hidden = !!g && c.dataset.genre !== g; });
    });
  });
</script>
</body>
</html>
`;
fs.writeFileSync(path.join(DIST, 'index.html'), indexHtml);
finalizeHtml(path.join(DIST, 'index.html'), '', null);

// ---- sitemap / robots / 404 ----
if (base) {
  const urls = ['', 'about.html', 'privacy.html', ...games.map((g) => `games/${g.slug}/`)];
  fs.writeFileSync(path.join(DIST, 'sitemap.xml'),
    `<?xml version="1.0" encoding="UTF-8"?>\n<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">\n${urls.map((u) => `  <url><loc>${base}/${u}</loc></url>`).join('\n')}\n</urlset>\n`);
}
fs.writeFileSync(path.join(DIST, 'robots.txt'), `User-agent: *\nAllow: /\n${base ? `Sitemap: ${base}/sitemap.xml\n` : ''}`);
fs.writeFileSync(path.join(DIST, '.nojekyll'), '');

console.log(`built ${games.length} game(s) → dist/`);
