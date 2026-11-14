// 新UIの通しテスト。AI の助言(b.advice)をそのまま入力に使うボットで走る。
const { chromium } = require('playwright');
const path = require('path');
const S = process.env.OUT || require('os').tmpdir();   // スクリーンショットの保存先
(async () => {
  const b = await chromium.launch({ executablePath: process.env.CHROME_PATH || undefined, args: ['--use-gl=angle', '--use-angle=swiftshader', '--enable-unsafe-swiftshader', '--ignore-gpu-blocklist'] });
  const vp = process.env.VP ? process.env.VP.split('x').map(Number) : [1280, 720];
  const p = await b.newPage({ viewport: { width: vp[0], height: vp[1] }, deviceScaleFactor: 1, hasTouch: !!process.env.TOUCH, isMobile: !!process.env.TOUCH });
  const errs = [];
  p.on('console', (m) => { const t = m.text(); if ((m.type() === 'error' || m.type() === 'warning') && !t.includes('Interleaved')) errs.push(m.type() + ': ' + t.slice(0, 400)); });
  p.on('pageerror', (e) => errs.push('PAGEERROR: ' + e.message + '\n' + (e.stack || '').slice(0, 500)));
  await p.addInitScript((e) => { window.__ENV = e; }, process.env.ENV || ''); await p.goto(require('url').pathToFileURL(path.resolve(__dirname, '../index.html')).href);
  await p.waitForFunction(() => window.__game, null, { timeout: 150000 });
  const Q = process.env.Q || 'low';
  await p.evaluate((Q) => { const g = window.__game; g.S.quality = Q; g.stage.autoQuality = false; g.stage.setQuality(Q); }, Q);
  const shot = async (n) => { await p.waitForTimeout(300); await p.screenshot({ path: path.join(S, `u-${n}.png`), timeout: 300000 }); console.log('shot', n); };
  const bot = () => p.evaluate(() => { window.__game.G.debugInput = (race) => { const a = race.player.advice; return { steer: a.steer, throttle: a.throttle, brake: 0 }; }; });
  const run = (sec, until) => p.evaluate(([sec, until]) => {
    const g = window.__game; let n = 0;
    while (n < sec * 60 && !(until && (until === 'replay-end' ? g.G.rp && g.G.race.clock >= g.G.rp.end - 1e-3 : g.G.state === until))) { g.step(1 / 60); n++; }
    const r = g.race, b = r.player || r.order[0];
    return { state: g.G.state, rs: r.state, clock: +r.clock.toFixed(2), lap: b.lap, rank: b.rank, st: b.st === null ? null : +b.st.toFixed(3), x: +b.x.toFixed(2), z: +b.z.toFixed(2), place: b.place, fin: +b.finishTime.toFixed(3), lift: b.advice && b.advice.lift };
  }, [sec, until]);
  const txt = (id) => p.evaluate((id) => document.getElementById(id).innerText.replace(/\s+/g, ' ').slice(0, 400), id);
  const scen = process.argv[2] || 'all';

  if (scen === 'title') { await shot('howto'); await p.click('#btn-howto-close'); await shot('title'); await p.click('#btn-settings'); await shot('settings'); }
  if (scen === 'single' || scen === 'all') {
    await p.evaluate(() => { const g = window.__game; g.S.seenHowto = true; document.getElementById('howto').classList.add('hidden'); g.S.mode = 'single'; g.S.lane = 2; if (window.__ENV) g.S.env = window.__ENV; });
    await p.evaluate(() => document.getElementById('btn-start').click()); await bot();
    if (process.env.CAM) await p.evaluate((c) => { window.__game.G.camMode = +c; }, process.env.CAM);
    console.log('pre', JSON.stringify(await run(8)));
    if (process.env.SHOT) await shot('pre');
    console.log('t1', JSON.stringify(await run(13.6)));
    if (process.env.SHOT) await shot('turn');
    const end = await run(200, 'result'); console.log('end', JSON.stringify(end));
    console.log('RESULT:', await txt('res-head'), '|', await txt('res-sub'), '|', await txt('res-table'), '|', await txt('res-extra'));
    if (process.env.SHOT) await shot('result');
    // リプレイが同じ結果になるか
    await p.click('#btn-replay');
    if (process.env.SHOT) { await run(22); await shot('replay'); }
    const rp = await run(300, 'replay-end'); console.log('replay end', JSON.stringify(rp));
    await p.evaluate(() => document.getElementById('btn-replay-end').click());
    require('assert/strict').equal(await p.evaluate(() => window.__game.G.state), 'result', 'replay end button returns to the result');
    require('assert/strict').equal(rp.fin, end.fin, 'replay finish time must match');
    require('assert/strict').equal(rp.st, end.st, 'replay start time must match');
    const same = await p.evaluate(() => { const r = window.__game.race; return r.order.map((b) => `${b.num}:${b.finishTime.toFixed(3)}`).join(' '); });
    console.log('replay order', same);
  }
  if (scen === 'practice' || scen === 'all') {
    await p.evaluate(() => { const g = window.__game; g.S.seenHowto = true; document.getElementById('howto').classList.add('hidden'); document.getElementById('btn-title').click(); });
    await p.evaluate(() => document.querySelector('#modes button[data-v="practice"]').click());
    await p.evaluate(() => document.getElementById('btn-start').click()); await bot();
    console.log('practice', JSON.stringify(await run(60, 'result')), '|', await txt('res-head'), '|', await txt('res-sub'), '|', await txt('res-table'));
    if (process.env.SHOT) await shot('practice');
    await p.click('#btn-title');
  }
  if (scen === 'gp' || scen === 'all') {
    await p.evaluate(() => { const g = window.__game; g.S.seenHowto = true; document.getElementById('howto').classList.add('hidden'); });
    await p.evaluate(() => document.querySelector('#modes button[data-v="gp"]').click());
    if (process.env.SHOT) await shot('gp-title');
    for (let r = 0; r < 3; r++) {
      console.log('GP entry', r, await txt('entry-h'), '|', await p.evaluate(() => [...document.querySelectorAll('#entry .nm')].map((e) => e.innerText.trim()).join(',')));
      await p.evaluate(() => document.getElementById('btn-start').click()); await bot();
      const e = await run(240, 'result');
      console.log('GP round', r, JSON.stringify(e), '|', await txt('res-head'), '|', await txt('res-sub'), '|', await txt('res-extra'));
      if (process.env.SHOT && r === 2) await shot('gp-final');
      await p.click('#btn-next');
    }
    console.log('after gp state', await p.evaluate(() => window.__game.G.state + ' ' + window.__game.S.mode + ' ' + JSON.stringify(window.__game.S.rec)));
  }
  console.log(errs.slice(0, 12).join('\n') || 'no console errors');
  await b.close();
})();
