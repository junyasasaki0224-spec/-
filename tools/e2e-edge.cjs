// 端の場合のテスト: 何もしない / フライング→リプレイ / 設定や画質の切り替え / 途中でやめる
const { chromium } = require('playwright');
const path = require('path');
(async () => {
  const b = await chromium.launch({ args: ['--use-gl=angle', '--use-angle=swiftshader', '--enable-unsafe-swiftshader', '--ignore-gpu-blocklist'] });
  const p = await b.newPage({ viewport: { width: 1280, height: 720 } });
  const errs = [];
  p.on('console', (m) => { const t = m.text(); if ((m.type() === 'error' || m.type() === 'warning') && !t.includes('Interleaved')) errs.push(m.type() + ': ' + t.slice(0, 300)); });
  p.on('pageerror', (e) => errs.push('PAGEERROR: ' + e.message + ' ' + (e.stack || '').slice(0, 300)));
  await p.goto('file://' + require('path').resolve(__dirname, '../index.html'));
  await p.waitForFunction(() => window.__game, null, { timeout: 150000 });
  await p.evaluate(() => { window.__game.S.opening = false; });   // オープニングは e2e-opening.cjs で確かめる
  await p.evaluate(() => { const g = window.__game; g.S.quality = 'low'; g.stage.autoQuality = false; g.stage.setQuality('low'); g.S.seenHowto = true; document.getElementById('howto').classList.add('hidden'); g.S.mode = 'single'; g.S.lane = 3; });
  const run = (sec, until) => p.evaluate(([sec, until]) => { const g = window.__game; let n = 0; while (n < sec * 60 && !(until && (until === 'replay-end' ? g.G.rp && g.G.race.clock >= g.G.rp.end - 1e-3 : g.G.state === until))) { g.step(1 / 60); n++; } const r = g.race, b = r.player || r.order[0]; return { state: g.G.state, rs: r.state, clock: +r.clock.toFixed(1), place: b.place, st: b.st, rank: b.rank }; }, [sec, until]);
  const txt = (id) => p.evaluate((id) => document.getElementById(id).innerText.replace(/\s+/g, ' ').slice(0, 160), id);
  const input = (fn) => p.evaluate((src) => { window.__game.G.debugInput = eval(src); }, fn);

  // A: 何も操作しない
  await p.click('#btn-start'); await input('(r) => ({ steer: 0, throttle: 0, brake: 0 })');
  console.log('A idle race:', JSON.stringify(await run(400, 'result')), '|', await txt('res-head'), '|', await txt('res-sub'));
  await p.click('#btn-title');
  // B: 練習で何もしない
  await p.click('#modes button[data-v="practice"]'); await p.click('#btn-start'); await input('(r) => ({ steer: 0, throttle: 0, brake: 0 })');
  console.log('B idle practice:', JSON.stringify(await run(60, 'result')), '|', await txt('res-head'), '|', await txt('res-sub'));
  await p.click('#btn-title');
  // C: フライング → リプレイ → 結果に戻る
  await p.click('#modes button[data-v="single"]'); await p.click('#btn-start'); await input('(r) => ({ steer: 0, throttle: 1, brake: 0 })');
  await p.evaluate(() => { const g = window.__game; let n = 0; while (n < 60 * 60 && !g.G.spec) { g.step(1 / 60); n++; } });   // フライング → 観戦
  console.log('C spectate:', await p.evaluate(() => !!window.__game.G.spec)); await p.evaluate(() => document.getElementById('sp-exit').click());
  console.log('C flying:', JSON.stringify(await run(1, 'result')), '|', await txt('res-head'));
  await p.click('#btn-replay');
  await run(6); await p.waitForTimeout(400); await p.screenshot({ path: path.join(process.env.OUT || require('os').tmpdir(), 'r-replay-pre.png'), timeout: 120000 });
  console.log('C replay:', JSON.stringify(await run(120, 'replay-end')), await p.evaluate(() => document.getElementById('btn-replay-end').click()), 'result visible:', await p.evaluate(() => !document.getElementById('result').classList.contains('hidden')));
  // D: 走行中にポーズ・設定・画質・時間帯の切り替え
  await p.click('#btn-next'); await input('(r) => { const a = r.player.advice; return { steer: a.steer, throttle: a.throttle, brake: 0 }; }');
  await run(20);
  await p.keyboard.press('Escape');
  console.log('D paused:', await p.evaluate(() => window.__game.G.paused));
  await p.click('#btn-pause-settings');
  for (const q of ['high', 'medium', 'low', 'auto', 'low']) { await p.selectOption('#set-quality', q); await p.waitForTimeout(200); }
  await p.click('#set-guide'); await p.click('#set-shake'); await p.click('#set-assist');
  console.log('D quality after toggles:', await p.evaluate(() => window.__game.stage.quality + ' ' + JSON.stringify([window.__game.S.guide, window.__game.S.shake])));
  await p.click('#btn-settings-close'); await p.click('#btn-resume');
  console.log('D resumed:', JSON.stringify(await run(15)));
  await p.keyboard.press('KeyC'); await p.keyboard.press('KeyC'); await p.keyboard.press('KeyM'); await p.keyboard.press('KeyM');
  await run(3);
  // E: グランプリを途中でやめる → タイトルで時間帯を切り替える
  await p.keyboard.press('Escape'); await p.click('#btn-quit');
  await p.click('#modes button[data-v="gp"]'); await p.click('#btn-start'); await run(5);
  await p.keyboard.press('Escape'); await p.click('#btn-quit');
  for (const e of ['evening', 'night', 'day']) { await p.click(`#opt-env button[data-v="${e}"]`); await run(1); }
  console.log('E state:', await p.evaluate(() => window.__game.G.state + ' mode=' + window.__game.S.mode + ' gp=' + (window.__game.G.gp ? 'on' : 'off')));
  console.log(errs.slice(0, 10).join('\n') || 'no console errors');
  await b.close();
})();
