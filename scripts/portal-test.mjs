#!/usr/bin/env node
// 大手サイト向けパッケージ（portal-dist/）の検査。
// 各サイトのSDKを「記録するだけの偽物」に差し替えて起動し、次を確認する:
//   - エラーなく起動する（PC横長 / スマホ縦長）
//   - 画面に日本語が残っていない（英語版になっている）
//   - SDKの初期化・読み込み完了・プレイ開始/終了の通知が正しい順序で呼ばれる
//   - 外部リンク・外部への通信がない
// あわせて提出用の画面写真を portal-dist/<target>/<slug>-landscape.png / -portrait.png に保存する。
// 事前に `node scripts/build-portal.mjs` が必要。 使い方: node scripts/portal-test.mjs [--only <slug>]
import fs from 'node:fs';
import path from 'node:path';
import { createRequire } from 'node:module';
import { ROOT } from './lib.mjs';
import { serve } from './serve.mjs';

const require = createRequire(import.meta.url);
let chromium;
try { ({ chromium } = require('playwright')); } catch {
  try { ({ chromium } = await import('playwright')); } catch {
    console.error('playwright が見つかりません。'); process.exit(2);
  }
}

const args = process.argv.slice(2);
const only = args.includes('--only') ? args[args.indexOf('--only') + 1] : null;
const PD = path.join(ROOT, 'portal-dist');
if (!fs.existsSync(PD)) { console.error('portal-dist/ がありません。先に node scripts/build-portal.mjs を実行してください。'); process.exit(2); }

// 偽SDK（呼び出しを window.__SDK_CALLS__ に記録。広告は即終了）
const MOCKS = {
  'sdk.crazygames.com': `
    window.__SDK_CALLS__ = [];
    (function () {
      var rec = function (n) { window.__SDK_CALLS__.push(n); };
      window.CrazyGames = { SDK: {
        init: function () { rec('init'); return Promise.resolve(); },
        ad: { requestAd: function (type, cb) { rec('ad:' + type); setTimeout(function () { cb.adStarted && cb.adStarted(); cb.adFinished && cb.adFinished(); }, 10); } },
        game: {
          gameplayStart: function () { rec('gameplayStart'); },
          gameplayStop: function () { rec('gameplayStop'); },
          happytime: function () { rec('happytime'); },
          loadingStart: function () { rec('loadingStart'); },
          loadingStop: function () { rec('loadingStop'); }
        }
      } };
    })();`,
  'game-cdn.poki.com': `
    window.__SDK_CALLS__ = [];
    (function () {
      var rec = function (n) { window.__SDK_CALLS__.push(n); };
      window.PokiSDK = {
        init: function () { rec('init'); return Promise.resolve(); },
        gameLoadingFinished: function () { rec('loadingStop'); },
        gameplayStart: function () { rec('gameplayStart'); },
        gameplayStop: function () { rec('gameplayStop'); },
        commercialBreak: function (f) { rec('ad:midgame'); f && f(); return Promise.resolve(); },
        rewardedBreak: function (f) { rec('ad:rewarded'); f && f(); return Promise.resolve(true); }
      };
    })();`
};

const JA = /[぀-ヿ㐀-鿿！-｠]/; // ひらがな・カタカナ・漢字・全角記号
const server = await serve(0, PD);
const port = server.address().port;
const browser = await chromium.launch();
const failures = [];
let total = 0;

for (const target of fs.readdirSync(PD).filter((d) => fs.statSync(path.join(PD, d)).isDirectory())) {
  const dir = path.join(PD, target);
  for (const slug of fs.readdirSync(dir).filter((d) => fs.statSync(path.join(dir, d)).isDirectory())) {
    if (only && slug !== only) continue;
    for (const vp of [
      { name: 'landscape', viewport: { width: 1280, height: 720 }, isMobile: false, hasTouch: false },
      { name: 'portrait', viewport: { width: 720, height: 1280 }, isMobile: true, hasTouch: true }
    ]) {
      total++;
      const label = `${target}/${slug} @${vp.name}`;
      const problems = [];
      const ctx = await browser.newContext({ viewport: vp.viewport, isMobile: vp.isMobile, hasTouch: vp.hasTouch, deviceScaleFactor: 1 });
      const page = await ctx.newPage();
      page.on('pageerror', (e) => problems.push(`pageerror: ${e.message}`));
      page.on('console', (m) => { if (m.type() === 'error') problems.push(`console.error: ${m.text()}`); });
      page.on('popup', () => problems.push('新しいウィンドウ（外部リンク）を開いた'));
      await page.route('**/*', (route) => {
        const url = route.request().url();
        if (url.startsWith(`http://127.0.0.1:${port}/`)) return route.continue();
        const host = new URL(url).host;
        if (MOCKS[host]) return route.fulfill({ status: 200, contentType: 'text/javascript', body: MOCKS[host] });
        problems.push(`外部への通信: ${url}`);
        return route.abort();
      });
      try {
        await page.goto(`http://127.0.0.1:${port}/${target}/${slug}/`, { waitUntil: 'load' });
        await page.waitForFunction(() => window.__GAME_READY__ === true, null, { timeout: 6000 })
          .catch(() => problems.push('GameKit.ready() が呼ばれませんでした'));
        await page.waitForTimeout(200);
        const text = await page.evaluate(() => document.body.innerText + ' ' + document.title);
        const ja = text.match(new RegExp(JA.source + '.{0,15}', 'g'));
        if (ja) problems.push(`日本語が残っています: ${[...new Set(ja)].slice(0, 5).join(' / ')}`);
        await page.screenshot({ path: path.join(dir, `${slug}-${vp.name}.png`) });

        // 自動プレイで結果画面まで進め、結果画面も英語か確認
        const auto = await page.evaluate(async () => {
          const T = window.__GAME_TEST__;
          if (!T || typeof T.autoplay !== 'function') return null;
          try { return await T.autoplay(); } catch (e) { return { ok: false, details: String(e) }; }
        });
        if (auto && !auto.ok) problems.push(`autoplay failed: ${auto.details}`);
        await page.waitForTimeout(150);
        const text2 = await page.evaluate(() => document.body.innerText);
        const ja2 = text2.match(new RegExp(JA.source + '.{0,15}', 'g'));
        if (ja2) problems.push(`結果画面に日本語: ${[...new Set(ja2)].slice(0, 5).join(' / ')}`);

        // SDKの呼び出し順序
        const calls = await page.evaluate(() => window.__SDK_CALLS__ || null);
        if (!calls) problems.push('SDK が読み込まれていません');
        else {
          if (calls[0] !== 'init') problems.push(`最初に init が呼ばれていません: ${calls.join(',')}`);
          if (!calls.includes('loadingStop')) problems.push('読み込み完了（loadingStop / gameLoadingFinished）が呼ばれていません');
          if (!calls.includes('gameplayStart')) problems.push('gameplayStart が呼ばれていません');
          let state = 'stopped';
          for (const c of calls) {
            if (c === 'gameplayStart') { if (state === 'playing') problems.push('gameplayStart が連続しています'); state = 'playing'; }
            if (c === 'gameplayStop') { if (state === 'stopped') problems.push('gameplayStop が連続しています'); state = 'stopped'; }
            if (c.startsWith('ad:') && state === 'playing') problems.push('プレイ中に広告を出しています（先に gameplayStop が必要）');
          }
          if (auto && auto.ok && state !== 'stopped') problems.push('クリア後に gameplayStop が呼ばれていません');
        }
      } catch (e) {
        problems.push(`exception: ${e.message}`);
      }
      await ctx.close();
      if (problems.length) { failures.push(label); console.error(`FAIL ${label}\n  - ${[...new Set(problems)].join('\n  - ')}`); }
      else console.log(`ok   ${label}`);
    }
  }
}

await browser.close();
server.close();
console.log(`\n${total - failures.length}/${total} portal checks passed. screenshots: portal-dist/<target>/<slug>-*.png`);
process.exit(failures.length ? 1 : 0);
