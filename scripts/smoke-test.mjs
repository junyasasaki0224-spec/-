#!/usr/bin/env node
// 各ゲームを実ブラウザ（PC/スマホ幅）で起動し、エラー・はみ出し・入力時の例外を検査する。
// 事前に `node scripts/build.mjs` が必要。
// 使い方: node scripts/smoke-test.mjs [--only <slug>]
// スクリーンショットは artifacts/screens/ に保存される（目視チェック用）。
//
// ゲーム側は window.__GAME_TEST__ を公開できる（日次ルーチンでは両方の実装を必須とする）:
//   selfTest: async () => ({ ok, details })  … 「生成盤面が必ず解ける」「スコア計算が正しい」等のロジック検証
//   autoplay: async () => ({ ok, details })  … 実際の入力処理を通してクリア（または終了）し、結果画面に到達するか
import fs from 'node:fs';
import path from 'node:path';
import { createRequire } from 'node:module';
import { ROOT, DIST, listGames } from './lib.mjs';
import { serve } from './serve.mjs';

const require = createRequire(import.meta.url);
let chromium;
try {
  ({ chromium } = require('playwright'));
} catch {
  try { ({ chromium } = await import('playwright')); } catch {
    console.error('playwright が見つかりません。CI では `npm i --no-save playwright && npx playwright install chromium` を実行してください。');
    process.exit(2);
  }
}

const args = process.argv.slice(2);
const only = args.includes('--only') ? args[args.indexOf('--only') + 1] : null;
if (!fs.existsSync(path.join(DIST, 'index.html'))) {
  console.error('dist/ がありません。先に node scripts/build.mjs を実行してください。');
  process.exit(2);
}

const SHOTS = path.join(ROOT, 'artifacts', 'screens');
fs.mkdirSync(SHOTS, { recursive: true });

const VIEWPORTS = [
  { name: 'pc', viewport: { width: 1280, height: 800 }, isMobile: false, hasTouch: false },
  { name: 'sp', viewport: { width: 390, height: 844 }, isMobile: true, hasTouch: true, deviceScaleFactor: 1 }
];
// 外部への通信（広告・計測）はテストでは遮断
const isExternal = (url) => !url.startsWith('http://127.0.0.1');

const server = await serve(0);
const port = server.address().port;
const browser = await chromium.launch();
const failures = [];
const games = listGames().filter((g) => g.meta && (!only || g.slug === only));
const targets = only ? [] : [{ slug: '(index)', url: '/' }];
for (const g of games) targets.push({ slug: g.slug, url: `/games/${g.slug}/`, game: true });

for (const t of targets) {
  for (const vp of VIEWPORTS) {
    const label = `${t.slug} @${vp.name}`;
    const ctx = await browser.newContext({ viewport: vp.viewport, isMobile: vp.isMobile, hasTouch: vp.hasTouch, deviceScaleFactor: vp.deviceScaleFactor || 1 });
    const page = await ctx.newPage();
    const problems = [];
    page.on('pageerror', (e) => problems.push(`pageerror: ${e.message}`));
    page.on('console', (m) => { if (m.type() === 'error') problems.push(`console.error: ${m.text()}`); });
    await page.route('**/*', (route) => (isExternal(route.request().url()) ? route.abort() : route.continue()));
    page.on('requestfailed', (r) => { if (!isExternal(r.url())) problems.push(`requestfailed: ${r.url()}`); });
    page.on('response', (r) => { if (r.status() >= 400 && !isExternal(r.url())) problems.push(`HTTP ${r.status()}: ${r.url()}`); });

    try {
      await page.goto(`http://127.0.0.1:${port}${t.url}`, { waitUntil: 'load' });
      if (t.game) {
        await page.waitForFunction(() => window.__GAME_READY__ === true, null, { timeout: 6000 })
          .catch(() => problems.push('GameKit.ready() が6秒以内に呼ばれませんでした'));
        await page.screenshot({ path: path.join(SHOTS, `${t.slug}-${vp.name}-start.png`) });

        // ゲーム固有の自己テスト
        const self = await page.evaluate(async () => {
          const T = window.__GAME_TEST__;
          if (!T || typeof T.selfTest !== 'function') return null;
          try { return await T.selfTest(); } catch (e) { return { ok: false, details: String(e && e.stack || e) }; }
        });
        if (self && !self.ok) problems.push(`selfTest failed: ${self.details}`);
        if (self && self.ok) console.log(`  selfTest ok: ${self.details || ''}`);

        // ランダム入力（タップ/クリック/キー）で例外が出ないか
        const stage = await page.$('.gk-stage');
        const box = stage ? await stage.boundingBox() : null;
        if (!box) problems.push('.gk-stage が見つかりません');
        else {
          let seed = 7;
          const rnd = () => ((seed = (seed * 16807) % 2147483647) / 2147483647);
          for (let i = 0; i < 40; i++) {
            // モーダルが出たら閉じる（結果画面など）
            const modalBtn = await page.$('.gk-modal .gk-btn--primary');
            if (modalBtn && i % 10 === 9) { await modalBtn.click().catch(() => {}); continue; }
            if (await page.$('.gk-modal')) { await page.keyboard.press('Escape'); }
            const x = box.x + 8 + rnd() * Math.max(1, box.width - 16);
            const y = box.y + 8 + rnd() * Math.max(1, Math.min(box.height, vp.viewport.height - box.y) - 16);
            if (vp.hasTouch) await page.touchscreen.tap(x, y).catch(() => {});
            else await page.mouse.click(x, y).catch(() => {});
            if (i % 4 === 0) await page.keyboard.press(['ArrowLeft', 'ArrowRight', 'ArrowUp', 'ArrowDown', 'Space', 'Enter'][i % 6]);
            await page.waitForTimeout(40);
          }
          await page.waitForTimeout(300);
          await page.evaluate(() => { const s = document.querySelector('.gk-stage'); if (s) s.scrollIntoView({ block: 'center' }); });
          await page.screenshot({ path: path.join(SHOTS, `${t.slug}-${vp.name}-played.png`) });
        }

        // 任意: 実際の入力経路でクリアまで自動プレイし、結果画面に到達するか
        const auto = await page.evaluate(async () => {
          document.querySelectorAll('.gk-modal').forEach((m) => m.remove());
          const T = window.__GAME_TEST__;
          if (!T || typeof T.autoplay !== 'function') return null;
          try { return await T.autoplay(); } catch (e) { return { ok: false, details: String(e && e.stack || e) }; }
        });
        if (auto && !auto.ok) problems.push(`autoplay failed: ${auto.details}`);
        if (auto && auto.ok) {
          console.log(`  autoplay ok: ${auto.details || ''}`);
          await page.waitForTimeout(250);
          await page.screenshot({ path: path.join(SHOTS, `${t.slug}-${vp.name}-result.png`) });
        }
      } else {
        await page.screenshot({ path: path.join(SHOTS, `index-${vp.name}.png`), fullPage: true });
      }
      const overflow = await page.evaluate(() => document.documentElement.scrollWidth - window.innerWidth);
      if (overflow > 1) problems.push(`横スクロールが発生（${overflow}px はみ出し）`);
    } catch (e) {
      problems.push(`exception: ${e.message}`);
    }
    await ctx.close();
    if (problems.length) {
      failures.push(label);
      console.error(`FAIL ${label}\n  - ${[...new Set(problems)].join('\n  - ')}`);
    } else {
      console.log(`ok   ${label}`);
    }
  }
}

await browser.close();
server.close();
console.log(`\n${targets.length * VIEWPORTS.length - failures.length}/${targets.length * VIEWPORTS.length} passed. screenshots: artifacts/screens/`);
process.exit(failures.length ? 1 : 0);
