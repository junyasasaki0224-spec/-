import { Race, makeConfig, mulberry32 } from './sim/race.js';
import { VMAX, TILTS } from './sim/physics.js';
import { clamp, LAPS } from './sim/course.js';
import { ROSTER, PLAYER, POINTS, windLabel, randomWeather } from './sim/roster.js';
import { BOAT_CSS, BOAT_TEXT_CSS } from './gfx/common.js';
import { Stage } from './gfx/stage.js';
import { CameraRig, CAM, CAM_NAMES } from './gfx/camera.js';
import { GameAudio } from './audio.js';
import { Hud, fmtTime, chip } from './hud.js';
import { Input } from './input.js';
import { Opening } from './opening.js';

const $ = (id) => document.getElementById(id);
const show = (id, v) => $(id).classList.toggle('hidden', !v);

// ---------------- 設定と記録(ブラウザに保存) ----------------
const KEY = 'minato-gp-v2';
const S = { opening: true, quality: 'auto', volume: 0.8, guide: true, assist: true, shake: true, leverReturn: false, leverUp: 40, tilt: 1, difficulty: 1, env: 'day', lane: 0, mode: 'single', seenHowto: false, rec: { races: 0, wins: 0, bestST: null, bestTime: null, gpWins: 0 } };
try { const o = JSON.parse(localStorage.getItem(KEY) || '{}'); Object.assign(S, o, { rec: Object.assign(S.rec, o.rec || {}) }); } catch (e) { /* 保存データなし */ }
const save = () => { try { localStorage.setItem(KEY, JSON.stringify(S)); } catch (e) { /* 保存できない環境 */ } };
const isTouch = matchMedia('(pointer: coarse)').matches;

// ---------------- 描画・音・入力 ----------------
const stage = new Stage($('gl'));
const camera = stage.camera;
const rig = new CameraRig(camera);
const audio = new GameAudio();
const hud = new Hud();
const input = new Input();
let views;
window.addEventListener('resize', () => { stage.resize(); hud.resize(); });

// ---------------- ゲーム状態 ----------------
const G = {
  state: 'loading',        // loading | title | race | result | replay
  paused: false, race: null, cfg: null, gp: null, replayData: null,
  camMode: CAM.CHASE, replayCam: CAM.TV, follow: -1,
  time: 0, introT: 0, resultT: -1, attractT: 0, replayEndT: -1, lastTick: 0, cheer: 0.25,
  crossed: false, debugInput: null,
};
let program = null;          // 次のレースの番組(シード・モーター抽選・天候)
const GP_TITLES = ['予選 第1走', '予選 第2走', '優勝戦'];

function newProgram(keepMotors) {
  const seed = (Math.random() * 1e9) | 0, rng = mulberry32(seed);
  const motors = keepMotors || {};
  if (!keepMotors) for (const id of ['P', 0, 1, 2, 3, 4, 5]) motors[id] = Math.round((28 + rng() * 20) * 10) / 10;
  program = { seed, motors, weather: randomWeather(rng) };
}

function gpLanes(gp) {
  if (gp.round === 0) return [0, 1, 2, 'P', 3, 4];
  if (gp.round === 1) return [4, 3, 'P', 2, 1, 0];
  // 優勝戦: 得点上位から内枠
  return Object.keys(gp.pts).map((k) => (k === 'P' ? 'P' : +k))
    .sort((a, b) => gp.pts[b] - gp.pts[a] || gp.best[a] - gp.best[b] || String(a).localeCompare(String(b)));
}

function buildCfg() {
  const base = { seed: program.seed, playerTilt: S.tilt, difficulty: S.difficulty, env: S.env, motors: program.motors, weather: program.weather };
  if (S.mode === 'gp') return makeConfig({ ...base, lanes: gpLanes(G.gp), title: GP_TITLES[G.gp.round] });
  return makeConfig({ ...base, playerLane: S.lane, mode: S.mode === 'practice' ? 'practice' : 'race', title: S.mode === 'practice' ? 'スタート練習' : '第12R 優勝戦' });
}

// レースを画面に反映する(環境・天候・レーサー)
function applyRace(race) {
  G.race = race; G.cfg = race.cfg;
  stage.setEnv(race.cfg.env, race.cfg.weather);
  race.boats.forEach((b, i) => views[i].setRacer(b.racer));
  hud.setWeather(race.cfg.weather);
  stage.spray.clear(); rig.reset();
  G.lastTick = -99; G.resultT = -1; G.replayEndT = -1; G.introT = 0; G.crossed = false;
}

function closeOverlays() { for (const id of ['title', 'result', 'pause', 'howto', 'settings']) show(id, false); }

function finishOpening(natural = false) {
  if (G.state !== 'opening') return;
  G.opening = null;
  show('opening', false);
  audio.stopOpening(1.5);
  input.clear(true);
  if (natural) G.introT = 99;          // 最後まで見た時は、同じ視点のままレースへつなぐ
  else { stage.spray.clear(); rig.reset(); G.introT = 0; }
  G.state = 'race';
  document.body.classList.add('playing');
  hud.show(true);
  stage.update(0, G.time, G.race, { title: G.cfg.title });
  hud.update(0, G.race, G.race.player, { assist: S.assist, guide: S.guide });
  audio.fanfare();
}

function startRace() {
  audio.init(); audio.click();
  if (!program) newProgram();
  applyRace(new Race(buildCfg()));
  G.state = 'race'; G.paused = false; G.follow = -1;
  input.clear(true);
  closeOverlays();
  hud.show(true);
  document.body.classList.add('playing');
  if (S.opening && S.mode !== 'practice') {
    G.state = 'opening';
    hud.drops.length = 0;
    hud.fctx.clearRect(0, 0, hud.fx.width, hud.fx.height);
    $('opening-phase').textContent = '選手紹介';
    $('opening-entry').classList.remove('hidden');
    G.opening = new Opening(G.race, S.mode === 'gp' && G.gp.round > 0);
    rig.reset();
    hud.show(false);
    document.body.classList.remove('playing');
    $('opening-title').textContent = `みなとグランプリ　${G.cfg.title}`;
    $('opening-entry').innerHTML = G.race.boats.map((b, i) => `<div class="opening-racer" style="--delay:${i * 0.22}s">${chip(i)}<strong>${b.racer.name}</strong><span>${b.racer.cls}</span></div>`).join('');
    show('opening', true);
    audio.startOpening();
  } else audio.fanfare();
  try { if (navigator.wakeLock) navigator.wakeLock.request('screen').catch(() => {}); } catch (e) { /* 非対応 */ }
}

function retry() {
  if (S.mode === 'gp') return;          // グランプリは走り直しなし
  newProgram(); startRace();
}

function toTitle() {
  audio.stopOpening(0);
  G.opening = null;
  show('opening', false);
  if (!program) newProgram();
  if (S.mode === 'gp' && !G.gp) startGp();
  G.state = 'title'; G.paused = false;
  applyRace(new Race(makeConfig({ env: S.env, weather: program.weather })));
  hud.show(false);
  document.body.classList.remove('playing');
  closeOverlays(); show('title', true);
  renderTitle();
}

function startGp() {
  G.gp = { round: 0, pts: { P: 0, 0: 0, 1: 0, 2: 0, 3: 0, 4: 0 }, best: { P: 9, 0: 9, 1: 9, 2: 9, 3: 9, 4: 9 }, hist: [] };
  newProgram();
}

function setPaused(p) {
  if (G.state !== 'race') return;
  G.paused = p; show('pause', p); show('btn-restart', S.mode !== 'gp');
  if (p) input.clear();
}

// ---------------- タイトル画面 ----------------
function renderTitle() {
  const cfg = buildCfg(), gp = S.mode === 'gp';
  document.querySelectorAll('#modes button').forEach((b) => b.classList.toggle('sel', b.dataset.v === S.mode));
  $('entry-h').innerHTML = gp ? `${GP_TITLES[G.gp.round]} 出走表 <span>枠は得点順・番組で決まります</span>` : '出走表 <span>行を押して乗る艇を選ぶ</span>';
  $('entry').innerHTML = cfg.lanes.map((id, i) => {
    const r = id === 'P' ? PLAYER : ROSTER[id], t = TILTS[cfg.tilts[i]];
    return `<button class="entry${id === 'P' ? ' sel' : ''}${gp ? ' locked' : ''}" data-i="${i}">
      <span class="num" style="background:${BOAT_CSS[i]};color:${BOAT_TEXT_CSS[i]}">${i + 1}</span>
      <span class="nm">${r.name}${id === 'P' ? '' : `<i>${r.cls}</i>`}</span><span class="cs">${i + 1}コース・${i < 3 ? 'スロー' : 'ダッシュ'}</span>
      <span class="st"><span>モーター2連率 <b>${cfg.motors[id].toFixed(1)}%</b></span>${id === 'P' ? '' : `<span>平均ST <b>${r.st.toFixed(2)}</b></span><span>得意 <b>${r.style}</b></span>`}<span>チルト <b>${t.label}</b></span></span></button>`;
  }).join('');
  if (!gp) $('entry').querySelectorAll('.entry').forEach((el) => el.addEventListener('click', () => { S.lane = +el.dataset.i; save(); audio.init(); audio.click(); renderTitle(); }));
  const w = cfg.weather, wx = Math.cos(w.windDir) * w.wind;
  $('wxline').innerHTML = `水面状況　<b>${windLabel(w)}</b>・波高 <b>${w.wave}cm</b>　${wx < -1.5 ? '向かい風で助走が伸びにくい' : wx > 1.5 ? '追い風でスタートが早くなりやすい' : ''}`;
  $('opt-tilt').innerHTML = TILTS.map((t, k) => `<button data-v="${k}" class="${k === S.tilt ? 'sel' : ''}">${t.label}<small>${t.note}</small></button>`).join('');
  $('opt-tilt').querySelectorAll('button').forEach((b) => b.addEventListener('click', () => { S.tilt = +b.dataset.v; save(); audio.init(); audio.click(); renderTitle(); }));
  const pct = (x) => `${x >= 1 ? '+' : '−'}${Math.abs((x - 1) * 100).toFixed(0)}%`, tl = TILTS[S.tilt];
  $('tilt-info').innerHTML = S.tilt === 1 ? '標準。最高速 約82km/h' : `最高速 <b>約${Math.round(81.9 * Math.sqrt(tl.top))}km/h</b>　出足 <b>${pct(tl.acc)}</b>　旋回グリップ <b>${pct(tl.grip)}</b>`;
  for (const [id, v] of [['opt-diff', S.difficulty], ['opt-env', S.env]]) $(id).querySelectorAll('button').forEach((b) => b.classList.toggle('sel', b.dataset.v === String(v)));
  show('gp-box', gp);
  if (gp) $('gp-box').innerHTML = `<h2>グランプリ得点 <span>1着10点・2着8点・3着6点…　優勝戦の1着が優勝</span></h2>${gpTable()}`;
  $('btn-start').textContent = gp ? (G.gp.round === 2 ? '優勝戦 出走' : `${GP_TITLES[G.gp.round]} 出走`) : S.mode === 'practice' ? '練習開始' : '出 走';
  const r = S.rec;
  $('records').textContent = r.races ? `通算 ${r.races}戦 ${r.wins}勝　ベストST ${r.bestST === null ? '—' : r.bestST.toFixed(2)}　ベストタイム ${fmtTime(r.bestTime)}　GP優勝 ${r.gpWins}回` : '';
}

function gpTable() {
  const gp = G.gp, ids = Object.keys(gp.pts).map((k) => (k === 'P' ? 'P' : +k)).sort((a, b) => gp.pts[b] - gp.pts[a] || gp.best[a] - gp.best[b]);
  return '<table>' + ids.map((id, k) => `<tr class="${id === 'P' ? 'me' : ''}"><td>${k + 1}</td><td style="text-align:left">${id === 'P' ? PLAYER.name : ROSTER[id].name}</td>${gp.hist.map((h) => `<td>${h[id] === 0 ? 'F' : h[id] + '着'}</td>`).join('')}<td><b>${gp.pts[id]}点</b></td></tr>`).join('') + '</table>';
}

// ---------------- 結果 ----------------
function showResult() {
  const race = G.race, pl = race.player, practice = race.mode === 'practice', gp = S.mode === 'gp';
  G.state = 'result';
  G.replayData = { cfg: race.cfg, inputs: Int8Array.from(race.rec) };
  let head, sub, p = 'x';
  const stWord = (st) => (st <= 0.1 ? 'トップスタート級！' : st <= 0.2 ? 'ナイススタート' : st <= 0.45 ? 'まずまず' : st <= 1 ? '遅れ気味' : '出遅れ');
  if (pl.sunk) { head = '沈没'; p = 'f'; sub = `${SINK_WORD[pl.sinkCause]}に衝突 — ${practice ? '本番なら失格' : '失格'}`; }
  else if (pl.flying) { head = 'フライング'; p = 'f'; sub = `スタート時刻より ${(-pl.st).toFixed(2)}秒 早くラインを通過 — ${practice ? '本番なら失格' : '失格（F）'}`; }
  else if (practice && pl.st === null) { head = '出遅れ'; sub = 'スタートラインを通過できませんでした。助走をつけて、針が0を指す瞬間を狙いましょう'; }
  else if (practice) { head = `ST ${pl.st.toFixed(2)}`; p = pl.st <= 0.2 ? '1' : 'x'; sub = `${stWord(pl.st)}　${race.boats.filter((b) => b.st !== null && b.st >= 0 && b.st < pl.st).length + 1}番目のスタート`; }
  else {
    const place = pl.place || pl.rank;
    head = `${place}着`; p = String(place);
    sub = place === 1 ? `おめでとう！ 決まり手: ${race.kimarite || '—'}` : `1着 ${race.order[0].num}号艇 ${race.order[0].racer.name}（決まり手: ${race.kimarite || '—'}）`;
  }
  // 記録
  const rec = S.rec, tags = [];
  if (!pl.flying && pl.st !== null) {
    tags.push(`スタート <b>${pl.st.toFixed(2)}</b> ${stWord(pl.st)}`);
    if (rec.bestST === null || pl.st < rec.bestST) { rec.bestST = pl.st; tags.push('<b>ベストST更新！</b>'); }
  }
  if (!practice) {
    rec.races++;
    if (pl.place === 1) rec.wins++;
    if (pl.lapTimes.length) tags.push(`ベストラップ <b>${Math.min(...pl.lapTimes).toFixed(1)}秒</b>`);
    if (pl.finished && pl.finishTime > 0 && (rec.bestTime === null || pl.finishTime < rec.bestTime)) { rec.bestTime = pl.finishTime; tags.push('<b>ベストタイム更新！</b>'); }
  }
  let extra = tags.map((t) => `<span class="tag">${t}</span>`).join('');
  // グランプリの得点
  let last = false;
  if (gp) {
    const g = G.gp, h = {};
    race.order.forEach((b, k) => {
      const id = b.isPlayer ? 'P' : b.racer.id, place = b.out ? 0 : k + 1;
      h[id] = place; if (place) { g.pts[id] += POINTS[k]; g.best[id] = Math.min(g.best[id], place); }
    });
    g.hist.push(h);
    last = g.round === 2;
    if (last) {
      if (!pl.out && (pl.place || pl.rank) === 1) { head = '優勝！'; p = '1'; sub = 'みなとグランプリ制覇！ おめでとうございます'; rec.gpWins++; }
      else sub = `優勝は ${race.order[0].num}号艇 ${race.order[0].racer.name}`;
    }
    extra += `<h2>グランプリ得点</h2>${gpTable()}`;
  }
  save();
  $('res-head').textContent = head; $('res-head').dataset.p = p;
  $('res-sub').textContent = sub;
  $('res-extra').innerHTML = extra;
  renderResultTable();
  $('btn-next').textContent = gp ? (last ? 'タイトルへ' : '次のレースへ') : practice ? 'もう一度' : 'もう一度走る';
  show('btn-title', !(gp && last));
  show('result', true);
  if (last && p === '1') audio.finishJingle(true);
}

const SINK_WORD = { mark: 'ターンマーク', unit: 'ターンマーク横の消波装置', pole: 'センターポール', wall: '外周の消波装置' };

function renderResultTable() {
  const race = G.race, practice = race.mode === 'practice';
  const rows = practice ? race.boats.slice().sort((a, b) => (a.st === null ? 9 : a.st < 0 ? 8 : a.st) - (b.st === null ? 9 : b.st < 0 ? 8 : b.st)) : race.order;
  $('res-table').innerHTML = `<tr><th>${practice ? 'ST順' : '着'}</th><th>艇</th><th>選手</th>${practice ? '' : '<th>タイム</th>'}<th>ST</th></tr>` + rows.map((b, k) =>
    `<tr class="${b.isPlayer ? 'me' : ''}"><td>${b.sunk ? '沈' : b.flying ? 'F' : practice || b.finished ? k + 1 : '…'}</td><td>${chip(b.i)}</td><td>${b.racer.name}</td>${practice ? '' : `<td>${b.sunk ? '沈没' : b.flying ? '失格' : b.finished ? fmtTime(b.finishTime) : '航走中'}</td>`}<td>${b.st === null ? '—' : (b.st < 0 ? 'F' : '') + Math.abs(b.st).toFixed(2)}</td></tr>`).join('');
}

function nextAfterResult() {
  audio.click();
  if (S.mode === 'gp') {
    if (G.gp.round >= 2) { G.gp = null; program = null; S.mode = 'single'; save(); toTitle(); return; }
    G.gp.round++; newProgram(program.motors); toTitle();
  } else retry();
}

// ---------------- リプレイ ----------------
function startReplay() {
  if (!G.replayData) return;
  audio.click();
  applyRace(new Race(G.replayData.cfg, G.replayData.inputs));
  G.state = 'replay'; G.paused = false; G.follow = G.race.playerIndex;
  closeOverlays(); hud.show(true, true);
  document.body.classList.remove('playing');
  hud.say('リプレイ　C: カメラ切替　1〜6: 追う艇を変える', 4);
}
function endReplay() {
  if (G.state !== 'replay') return;
  G.state = 'result'; hud.show(false); show('result', true);
}

// ---------------- イベント処理 ----------------
function handleEvents() {
  const race = G.race, live = G.state === 'race', audible = G.state !== 'title';
  const pl = live ? race.player : null, watch = G.state === 'replay' ? race.boats[G.follow] : pl;
  for (const e of race.events) {
    switch (e.type) {
      case 'go': if (audible) audio.tick(true); break;
      case 'cross':
        if (pl && e.boat === pl.i) {
          const st = e.st;
          const word = st <= 0.1 ? 'トップスタート！' : st <= 0.2 ? 'ナイススタート！' : st <= 0.45 ? 'まずまずのスタート' : st <= 1 ? 'スタート遅れ…' : '出遅れ！';
          hud.message(`ST ${st.toFixed(2)}`, word, 2.6, st <= 0.2 ? 'good' : '');
        }
        break;
      case 'flying':
        if (pl && e.boat === pl.i) { audio.buzzer(); hud.message('フライング！', 'スタート時刻より早くラインを通過', 3.5, 'bad'); G.resultT = 3.2; }
        break;
      case 'sink': {
        const b = race.boats[e.boat];
        stage.spray.burst(e.x, e.z, 9, b.vx, b.vz);
        const d = Math.hypot(e.x - camera.position.x, e.z - camera.position.z);
        if (audible) audio.hit(Math.min(8, e.power * 0.6), 1 / (1 + (d / 25) ** 2));
        if (watch && e.boat === watch.i) rig.bump(1);
        if (pl && e.boat === pl.i) { audio.buzzer(); hud.message('沈没', `${SINK_WORD[e.cause]}に衝突 — 失格`, 3.5, 'bad'); if (race.mode !== 'practice') G.resultT = 3.6; }
        break;
      }
      case 'hit': {
        const a = race.boats[e.a];
        stage.spray.burst(e.x, e.z, e.power, a.vx, a.vz);
        const d = Math.hypot(e.x - camera.position.x, e.z - camera.position.z), att = 1 / (1 + (d / 25) ** 2);
        if (audible) audio.hit(e.power, att);
        if (watch && (e.a === watch.i || e.b === watch.i)) {
          rig.bump(e.power * 0.22);
          if (e.power > 1.2) {
            hud.addDrops(6 + e.power * 3, true);
            if (pl) { hud.say(`接触！ ${race.boats[e.a === pl.i ? e.b : e.a].num}号艇とぶつかった`, 1.8); try { if (navigator.vibrate) navigator.vibrate(40); } catch (err) { /* 非対応 */ } }
          }
        }
        break;
      }
      case 'wall': {
        stage.spray.burst(e.x, e.z, e.power * 0.6);
        const d = Math.hypot(e.x - camera.position.x, e.z - camera.position.z);
        if (audible) audio.hit(e.power * 0.5, 1 / (1 + (d / 25) ** 2));
        if (watch && e.boat === watch.i) { rig.bump(e.power * 0.1); if (pl) hud.say('消波装置に接触！', 1.6); }
        break;
      }
      case 'buoy': {
        const b = race.boats[e.boat];
        stage.venue.hitBuoy(e.id, e.nx, e.nz, e.power);
        stage.spray.burst(b.x, b.z, e.power * 0.4, b.vx, b.vz);
        if (audible) audio.buoy(e.power, watch && e.boat === watch.i ? 1 : 0.3);
        if (watch && e.boat === watch.i) { rig.bump(0.3); if (pl) hud.say(e.id >= 3 ? '消波装置に接触！' : e.id ? 'ターンマークに接触！' : 'センターポールに接触！', 1.6); }
        break;
      }
      case 'lap':
        if (pl && e.boat === pl.i) { hud.message(e.lap === LAPS ? '最終周回！' : `${e.lap}周目`, '', 1.8); audio.tick(false); }
        break;
      case 'finish':
        if (pl && e.boat === pl.i) {
          hud.message(`ゴール！ ${e.place}着`, e.place === 1 ? '1着！' : fmtTime(e.time), 3.2, e.place <= 3 ? 'good' : '');
          audio.finishJingle(e.place === 1); G.resultT = 3.6;
        }
        if (G.state === 'result') renderResultTable();
        break;
      case 'done':
        if (G.state === 'result') renderResultTable();
        else if (G.state === 'title') G.attractT = 7;
        else if (G.state === 'replay') G.replayEndT = 2.5;
        else if (pl && G.resultT < 0) G.resultT = race.mode === 'practice' ? 0.9 : 0.5;
        break;
    }
  }
  race.events.length = 0;
}

// ---------------- メインループ ----------------
let last = performance.now(), focus = null;
const upd = { race: null, names: null, title: '', cheer: 0, guideBoat: null, guide: false };   // 毎フレーム使い回す
function frame(now) {
  requestAnimationFrame(frame);
  const raw = (now - last) / 1000, dt = Math.min(0.05, raw);
  last = now;
  step(dt);
  stage.render(focus);
  if (!G.paused) stage.adapt(raw);
}

function step(dt) {
  if (G.state === 'opening') {
    if (document.hidden) return;
    G.time += dt;
    const opening = G.opening;
    if (opening.advance(dt)) { finishOpening(true); return; }
    $('opening-phase').textContent = opening.phase;
    $('opening-entry').classList.toggle('hidden', opening.elapsed >= (opening.short ? 1 : 8));
    for (const v of views) v.setFirstPerson(false);
    stage.update(dt, G.time, opening.race, { title: G.cfg.title });
    // 自艇の後ろから見る(自動操縦でスタート前の位置へ向かう)
    focus = opening.boats[opening.playerIndex];
    rig.shakeOn = false;
    rig.update(dt, G.time, focus, views[opening.playerIndex], CAM.CHASE, -1);
    audio.update(dt, opening.audioBoats, null, camera.position, rig.right, true, 0.25);
    return;
  }
  const race = G.race, live = G.state === 'race', replay = G.state === 'replay';
  const pl = race.player;
  const target = replay ? race.boats[G.follow] || race.order[0] : pl || race.order[0];
  if (!G.paused) {
    G.time += dt; G.introT += dt;
    race.update(dt, live ? (G.debugInput ? G.debugInput(race) : input.get()) : null);
    handleEvents();

    if ((live || replay) && race.clock < 0) {      // カウントダウン音
      const s = Math.ceil(-race.clock);
      if (s <= 3 && s !== G.lastTick) { G.lastTick = s; audio.tick(false); }
    }
    if (G.resultT >= 0 && live) { G.resultT -= dt; if (G.resultT < 0) showResult(); }
    if (G.state === 'title' && race.state === 'done') { G.attractT -= dt; if (G.attractT <= 0) applyRace(new Race(makeConfig({ env: S.env, weather: program.weather }))); }
    if (replay) {
      if (G.replayEndT < 0 && pl && (pl.out || pl.finished) && race.mode !== 'practice') G.replayEndT = pl.out ? 4 : 5;
      if (G.replayEndT >= 0) { G.replayEndT -= dt; if (G.replayEndT < 0) endReplay(); }
    }

    // 観客の盛り上がり
    const lead = race.order[0];
    let cheer = 0.25;
    if (race.clock > -2 && race.clock < 7) cheer = 0.85;
    if (lead.lap === LAPS - 1 && lead.R % 720 > 520) cheer = 1;
    if (race.finishCount > 0 && race.state !== 'done') cheer = 1;
    G.cheer = cheer;

    if (race !== upd.race) { upd.race = race; upd.names = race.boats.map((b) => b.racer.name); upd.title = race.cfg.title; }
    upd.cheer = cheer > 0.8 ? 1 : 0; upd.guideBoat = pl; upd.guide = S.guide && live;
    stage.update(dt, G.time, race, upd);
    for (let i = 0; i < 6; i++) {
      const v = views[i];
      if (v.slapped > 0) { if (race.boats[i] === target && (live || replay)) audio.slap(Math.min(0.3, v.slapped * 0.5)); v.slapped = 0; }
    }

    // カメラ
    let mode;
    if (G.state === 'title') mode = (Math.floor(G.time / 11) % 3 === 1 || race.state === 'pre') ? CAM.FLY : CAM.TV;
    else if (G.state === 'result') mode = CAM.ORBIT;
    else if (target.sunk) mode = CAM.ORBIT;        // 沈んだ艇は少し離れて回りから映す
    else mode = replay ? G.replayCam : G.camMode;
    rig.shakeOn = S.shake;
    for (let i = 0; i < 6; i++) views[i].setFirstPerson(mode === CAM.ONBOARD && i === target.i);
    rig.update(dt, G.time, target, views[target.i], mode, live ? G.introT : -1);
    focus = target;

    // レンズの水滴: 旋回で自分のしぶきをかぶる / 他艇の引き波に入る
    if (live && mode <= CAM.ONBOARD) {
      const wet = target.turnInt * 1.0 + target.inWake * 0.8 * clamp(target.speed / VMAX, 0, 1);
      if (Math.random() < wet * 14 * dt) hud.addDrops(1);
    }
  }
  hud.update(G.paused ? 0 : dt, race, G.state === 'title' || G.state === 'result' ? null : target, { assist: S.assist, guide: S.guide, replay });
  audio.update(dt, race.boats, live || replay ? target : null, camera.position, rig.right, !G.paused && G.state !== 'title', G.cheer);
}

// ---------------- UI ----------------
let appliedQuality = null;
function applySettings() {
  // 画質の設定そのものを変えた時だけ切り替える(自動調整で下がった画質を、他の設定変更で戻さない)
  stage.autoQuality = S.quality === 'auto';
  if (appliedQuality !== S.quality) { appliedQuality = S.quality; stage.setQuality(S.quality === 'auto' ? (isTouch ? 'medium' : 'high') : S.quality); }
  audio.setVolume(S.volume);
  input.holdThrottle = !S.leverReturn;
  document.documentElement.style.setProperty('--lv-up', `${S.leverUp}px`);
}

function bindUi() {
  const click = (id, fn) => $(id).addEventListener('click', fn);
  document.querySelectorAll('#modes button').forEach((b) => b.addEventListener('click', () => {
    audio.init(); audio.click();
    S.mode = b.dataset.v; save();
    if (S.mode === 'gp') { if (!G.gp) startGp(); } else G.gp = null;
    renderTitle();
  }));
  $('opt-diff').querySelectorAll('button').forEach((b) => b.addEventListener('click', () => { S.difficulty = +b.dataset.v; save(); audio.init(); audio.click(); renderTitle(); }));
  $('opt-env').querySelectorAll('button').forEach((b) => b.addEventListener('click', () => {
    S.env = b.dataset.v; save(); audio.init(); audio.click();
    stage.setEnv(S.env, G.cfg.weather); G.cfg.env = S.env; renderTitle();
  }));
  click('btn-start', startRace);
  click('btn-opening-mute', toggleMute);
  $('opening').addEventListener('click', (e) => { if (!e.target.closest('#btn-opening-mute')) finishOpening(); });
  click('btn-next', nextAfterResult);
  click('btn-replay', startReplay);
  click('btn-replay-end', endReplay);
  click('btn-title', () => { audio.click(); if (S.mode === 'gp') { G.gp = null; program = null; S.mode = 'single'; save(); } else newProgram(); toTitle(); });
  click('btn-resume', () => setPaused(false));
  click('btn-restart', () => { if (S.mode === 'gp') { setPaused(false); return; } retry(); });
  click('btn-quit', () => { audio.click(); G.gp = null; if (S.mode === 'gp') { S.mode = 'single'; save(); } newProgram(); toTitle(); });
  click('btn-pause', () => setPaused(!G.paused));
  click('btn-cam', cycleCam);
  click('btn-mute', toggleMute);
  click('btn-howto', () => { audio.init(); audio.click(); show('howto', true); });
  click('btn-howto-close', () => { audio.init(); audio.click(); show('howto', false); S.seenHowto = true; save(); });
  const openSettings = () => {
    audio.init(); audio.click();
    $('set-quality').value = S.quality; $('set-volume').value = Math.round(S.volume * 100);
    $('set-opening').checked = S.opening; $('set-guide').checked = S.guide; $('set-assist').checked = S.assist; $('set-shake').checked = S.shake; $('set-hold').checked = S.leverReturn; $('set-leverup').value = S.leverUp;
    show('settings', true);
  };
  click('btn-settings', openSettings); click('btn-pause-settings', openSettings);
  click('btn-settings-close', () => { audio.click(); show('settings', false); });
  $('set-quality').addEventListener('change', (e) => { S.quality = e.target.value; save(); applySettings(); });
  $('set-volume').addEventListener('input', (e) => { S.volume = e.target.value / 100; save(); applySettings(); });
  $('set-leverup').addEventListener('input', (e) => { S.leverUp = +e.target.value; save(); applySettings(); });
  for (const [id, k] of [['set-opening', 'opening'], ['set-guide', 'guide'], ['set-assist', 'assist'], ['set-shake', 'shake'], ['set-hold', 'leverReturn']]) {
    $(id).addEventListener('change', (e) => { S[k] = e.target.checked; save(); applySettings(); });
  }
}
function cycleCam() {
  if (G.state === 'replay') { G.replayCam = G.replayCam === CAM.TV ? CAM.CHASE : G.replayCam === CAM.CHASE ? CAM.TOP : CAM.TV; rig.reset(); hud.say(CAM_NAMES[G.replayCam], 1.2); return; }
  G.camMode = (G.camMode + 1) % 5; rig.reset();
  if (G.state === 'race') hud.say(CAM_NAMES[G.camMode], 1.2);
}
function toggleMute() { audio.init(); audio.setMuted(!audio.muted); $('btn-mute').textContent = audio.muted ? '🔇' : '🔊'; $('btn-opening-mute').textContent = audio.muted ? '音を出す' : '消音'; }

input.onKey = (code) => {
  const overlay = !$('howto').classList.contains('hidden') || !$('settings').classList.contains('hidden');
  if (code === 'Escape' && overlay) { show('howto', false); show('settings', false); return; }
  if (overlay || G.state === 'loading') return;
  if (G.state === 'opening') { if (code === 'KeyM') toggleMute(); else if (code === 'Enter' || code === 'Escape' || code === 'Space') finishOpening(); return; }
  if (code === 'KeyC') cycleCam();
  else if (code === 'KeyM') toggleMute();
  else if (code === 'Escape' || code === 'KeyP') { if (G.state === 'replay') endReplay(); else setPaused(!G.paused); }
  else if (code === 'KeyR' && (G.state === 'race' || G.state === 'result')) retry();
  else if (code === 'Enter') { if (G.state === 'title') startRace(); else if (G.state === 'result') nextAfterResult(); else if (G.paused) setPaused(false); }
  else if (G.state === 'replay' && /^Digit[1-6]$/.test(code)) { G.follow = +code.slice(5) - 1; rig.reset(); }
};
document.addEventListener('visibilitychange', () => { if (document.hidden) { audio.suspend(); if (G.state === 'race') setPaused(true); } });
// どこを触っても音を出せるようにする(iPhone は操作の中でしか音を始められない)
for (const ev of ['pointerdown', 'touchend', 'keydown']) window.addEventListener(ev, () => { if (G.state !== 'loading') audio.init(); }, { capture: true, passive: true });
if (isTouch) document.body.classList.add('touch');

stage.init().then(() => {
  views = stage.views;
  bindUi();
  applySettings();
  newProgram();
  toTitle();
  stage.precompile();
  show('loading', false);
  if (!S.seenHowto) show('howto', true);
  requestAnimationFrame(frame);
  // デバッグ/自動テスト用
  window.__game = { G, S, audio, step, finishOpening, startRace, toTitle, startReplay, showResult, stage, rig, camera, get race() { return G.race; } };
}).catch((e) => {
  console.error(e);
  $('loading').innerHTML = '<div><b>読み込みに失敗しました</b><span>WebGL2 に対応したブラウザで開いてください</span></div>';
});
