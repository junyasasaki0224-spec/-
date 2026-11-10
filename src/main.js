import * as THREE from 'three';
import { Race } from './sim/race.js';
import { VMAX } from './sim/physics.js';
import { clamp, lerp, LAPS } from './sim/course.js';
import { RACERS, BOAT_CSS, BOAT_TEXT_CSS } from './gfx/common.js';
import { Stage } from './gfx/stage.js';
import { CameraRig, CAM, CAM_NAMES } from './gfx/camera.js';
import { GameAudio } from './audio.js';
import { Hud, fmtTime, chip } from './hud.js';
import { Input } from './input.js';

const $ = (id) => document.getElementById(id);
const RACE_TITLE = '第12R 優勝戦';

// ---------------- 描画 ----------------
const stage = new Stage($('gl'));
const camera = stage.camera;
const rig = new CameraRig(camera);
const audio = new GameAudio();
const hud = new Hud();
const input = new Input();
let spray, venue, views;
let envName = 'day';
function setEnv(name) { envName = name; stage.setEnv(name, { windDir: 0.4, wind: 2, cover: 0.45 }); }
function resize() { stage.resize(); hud.resize(); }
window.addEventListener('resize', resize);

// ---------------- ゲーム状態 ----------------
const G = {
  state: 'title',          // title | race | result
  paused: false,
  race: null,
  playerIndex: 0, difficulty: 1,
  camMode: 0,              // 0 追尾 / 1 接近 / 2 中継 / 3 上空
  time: 0, introT: 0, resultT: -1, attractT: 0, lastTick: 0,
  shake: 0, cheer: 0.25, follow: -1, debugInput: null,
};
function newRace(playerIndex) {
  G.race = new Race({ playerIndex, difficulty: G.difficulty });
  G.lastTick = -99; G.resultT = -1; G.introT = 0; rig.reset(); if (spray) spray.clear();
}

function startRace() {
  audio.init(); audio.click();
  newRace(G.playerIndex);
  G.state = 'race'; G.paused = false;
  $('title').classList.add('hidden'); $('result').classList.add('hidden'); $('pause').classList.add('hidden');
  hud.show(true); hud.rankKey = '';
  document.body.classList.add('playing');
  audio.fanfare();
  hud.say(`${RACE_TITLE}　${G.playerIndex + 1}号艇 ${RACERS[G.playerIndex]}(あなた)`, 5);
}

function toTitle() {
  G.state = 'title'; G.paused = false;
  newRace(-1);
  hud.show(false);
  document.body.classList.remove('playing');
  $('title').classList.remove('hidden'); $('result').classList.add('hidden'); $('pause').classList.add('hidden');
}

function setPaused(p) {
  if (G.state !== 'race') return;
  G.paused = p; $('pause').classList.toggle('hidden', !p);
}

function showResult() {
  const race = G.race, pl = race.player;
  G.state = 'result';
  let head, sub;
  if (pl.flying) { head = 'フライング'; sub = `スタート時刻より ${(-pl.st).toFixed(2)}秒 早くラインを通過 — 失格（F）`; }
  else {
    head = `${pl.place || pl.rank}着`;
    sub = pl.place === 1 ? `おめでとう！ 決まり手: ${race.kimarite || '—'}` : `1着 ${race.order[0].num}号艇 ${RACERS[race.order[0].i]}（決まり手: ${race.kimarite || '—'}）`;
  }
  $('res-head').textContent = head; $('res-head').dataset.p = pl.flying ? 'f' : pl.place;
  $('res-sub').textContent = sub;
  renderResultTable();
  $('result').classList.remove('hidden');
}

function renderResultTable() {
  const race = G.race;
  $('res-table').innerHTML = '<tr><th>着</th><th>艇</th><th>選手</th><th>タイム</th><th>ST</th></tr>' + race.order.map((b, k) =>
    `<tr class="${b.isPlayer ? 'me' : ''}"><td>${b.flying ? 'F' : b.finished ? k + 1 : '…'}</td><td>${chip(b.i)}</td><td>${RACERS[b.i]}${b.isPlayer ? '（あなた）' : ''}</td><td>${b.flying ? '失格' : b.finished ? fmtTime(b.finishTime) : '航走中'}</td><td>${b.st === null ? '—' : (b.st < 0 ? 'F' : '') + Math.abs(b.st).toFixed(2)}</td></tr>`).join('');
}

// ---------------- イベント処理 ----------------
function handleEvents() {
  const race = G.race, pl = race.player, playing = G.state !== 'title';
  for (const e of race.events) {
    switch (e.type) {
      case 'go': if (playing) audio.tick(true); break;
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
      case 'hit': {
        const a = race.boats[e.a];
        spray.burst(e.x, e.z, e.power, a.vx, a.vz);
        const d = Math.hypot(e.x - camera.position.x, e.z - camera.position.z), att = 1 / (1 + (d / 25) ** 2);
        if (playing) audio.hit(e.power, att);
        if (pl && (e.a === pl.i || e.b === pl.i)) {
          rig.bump(e.power * 0.22);
          if (e.power > 1.2) { hud.addDrops(6 + e.power * 3, true); hud.say(`接触！ ${race.boats[e.a === pl.i ? e.b : e.a].num}号艇とぶつかった`, 1.8); }
        }
        break;
      }
      case 'wall': {
        spray.burst(e.x, e.z, e.power * 0.6);
        const d = Math.hypot(e.x - camera.position.x, e.z - camera.position.z);
        if (playing) audio.hit(e.power * 0.5, 1 / (1 + (d / 25) ** 2));
        if (pl && e.boat === pl.i) { rig.bump(e.power * 0.1); hud.say('消波装置に接触！', 1.6); }
        break;
      }
      case 'buoy': {
        const b = race.boats[e.boat];
        venue.hitBuoy(e.id, e.nx, e.nz, e.power);
        spray.burst(b.x, b.z, e.power * 0.4, b.vx, b.vz);
        if (playing) audio.buoy(e.power, pl && e.boat === pl.i ? 1 : 0.3);
        if (pl && e.boat === pl.i) { rig.bump(0.3); hud.say(e.id ? 'ターンマークに接触！' : 'センターポールに接触！', 1.6); }
        break;
      }
      case 'lap':
        if (pl && e.boat === pl.i) { hud.message(e.lap === LAPS ? '最終周回！' : `${e.lap}周目`, '', 1.8); audio.tick(false); }
        break;
      case 'lead':
        if (playing) hud.say(pl && e.boat === pl.i ? '先頭に立った！' : `${race.boats[e.boat].num}号艇 ${RACERS[e.boat]} が先頭！`, 2.4);
        break;
      case 'finish':
        if (pl && e.boat === pl.i) {
          hud.message(`ゴール！ ${e.place}着`, e.place === 1 ? '優勝！' : fmtTime(e.time), 3.2, e.place <= 3 ? 'good' : '');
          audio.finishJingle(e.place === 1); G.resultT = 3.4;
        } else if (e.place === 1 && playing) hud.say(`1着 ${race.boats[e.boat].num}号艇 ${RACERS[e.boat]} ゴール！`, 3);
        if (G.state === 'result') renderResultTable();
        break;
      case 'done':
        if (G.state === 'result') renderResultTable();
        else if (G.state === 'title') G.attractT = 7;
        else if (pl && G.resultT < 0) G.resultT = 0.5;
        break;
    }
  }
  race.events.length = 0;
}

// ---------------- カメラ ----------------
function updateCamera(dt) {
  const race = G.race, pl = race.player;
  const target = pl || race.boats[G.follow] || race.order[0];
  let mode = G.camMode;
  if (!pl && G.follow < 0) mode = (Math.floor(G.time / 11) % 3 === 1 || race.state === 'pre') ? CAM.FLY : CAM.TV;
  else if (G.state === 'result') mode = CAM.ORBIT;
  rig.update(dt, G.time, target, views[target.i], mode, pl && G.state === 'race' ? G.introT : -1);
  return target;
}

// ---------------- メインループ ----------------
let last = performance.now(), focus = null;
function frame(now) {
  requestAnimationFrame(frame);
  const raw = (now - last) / 1000, dt = Math.min(0.05, raw);
  last = now;
  step(dt);
  stage.render(focus);
  stage.adapt(raw);
}

function step(dt) {
  const race = G.race, pl = race.player;
  const running = !G.paused;
  if (running) {
    G.time += dt; G.introT += dt;
    race.update(dt, G.state === 'race' ? (G.debugInput ? G.debugInput(race) : input.get()) : null);
    handleEvents();

    // カウントダウン音
    if (G.state === 'race' && race.clock < 0) {
      const s = Math.ceil(-race.clock);
      if (s <= 3 && s !== G.lastTick) { G.lastTick = s; audio.tick(false); }
    }
    if (G.resultT >= 0 && G.state === 'race') { G.resultT -= dt; if (G.resultT < 0) showResult(); }
    if (G.state === 'title' && race.state === 'done') { G.attractT -= dt; if (G.attractT <= 0) newRace(-1); }

    // 観客の盛り上がり
    const lead = race.order[0];
    let cheer = 0.25;
    if (race.clock > -2 && race.clock < 7) cheer = 0.85;
    if (lead.lap === LAPS - 1 && lead.R % 720 > 520) cheer = 1;
    if (race.finishCount > 0 && race.state !== 'done') cheer = 1;
    G.cheer = cheer;

    stage.update(dt, G.time, race, { title: RACE_TITLE, cheer: G.cheer > 0.8 ? 1 : 0 });
    for (let i = 0; i < 6; i++) {
      const v = views[i];
      if (v.slapped > 0) { if (race.boats[i] === pl && G.state === 'race') audio.slap(Math.min(0.3, v.slapped * 0.5)); v.slapped = 0; }
    }
    focus = updateCamera(dt);

    // レンズの水滴: 旋回で自分のしぶきをかぶる / 他艇の引き波に入る
    if (pl && G.state === 'race' && G.camMode <= 1) {
      const wet = pl.turnInt * 0.6 + pl.inWake * 0.8 * clamp(pl.speed / VMAX, 0, 1);
      if (Math.random() < wet * 14 * dt) hud.addDrops(1);
    }
  }
  hud.update(running ? dt : 0, race, G.state === 'title' ? null : pl, { assist: G.difficulty < 2 });
  audio.update(dt, race.boats, pl, camera.position, rig.right, running && (G.state !== 'title'), G.cheer);
}

// ---------------- UI ----------------
function buildTitle() {
  const list = $('entry');
  list.innerHTML = RACERS.map((n, i) => `<button class="entry${i === G.playerIndex ? ' sel' : ''}" data-i="${i}">
    <span class="num" style="background:${BOAT_CSS[i]};color:${BOAT_TEXT_CSS[i]}">${i + 1}</span>
    <span class="nm">${n}</span><span class="cs">${i + 1}コース・${i < 3 ? 'スロー' : 'ダッシュ'}</span></button>`).join('');
  list.querySelectorAll('.entry').forEach((el) => el.addEventListener('click', () => {
    G.playerIndex = +el.dataset.i; audio.init(); audio.click();
    list.querySelectorAll('.entry').forEach((x) => x.classList.toggle('sel', x === el));
  }));
  const seg = (id, get, set) => {
    const box = $(id);
    box.querySelectorAll('button').forEach((b) => {
      b.classList.toggle('sel', b.dataset.v === String(get()));
      b.addEventListener('click', () => { set(b.dataset.v); audio.init(); audio.click(); box.querySelectorAll('button').forEach((x) => x.classList.toggle('sel', x === b)); });
    });
  };
  seg('opt-diff', () => G.difficulty, (v) => { G.difficulty = +v; });
  seg('opt-env', () => envName, (v) => setEnv(v));
  $('btn-start').addEventListener('click', startRace);
  $('btn-retry').addEventListener('click', startRace);
  $('btn-title').addEventListener('click', () => { audio.click(); toTitle(); });
  $('btn-resume').addEventListener('click', () => setPaused(false));
  $('btn-restart').addEventListener('click', startRace);
  $('btn-quit').addEventListener('click', () => { audio.click(); toTitle(); });
  $('btn-pause').addEventListener('click', () => setPaused(!G.paused));
  $('btn-cam').addEventListener('click', cycleCam);
  $('btn-mute').addEventListener('click', toggleMute);
}
function cycleCam() { G.camMode = (G.camMode + 1) % 5; rig.reset(); if (G.state === 'race') hud.say(CAM_NAMES[G.camMode], 1.2); }
function toggleMute() { audio.init(); audio.setMuted(!audio.muted); $('btn-mute').textContent = audio.muted ? '🔇' : '🔊'; }

input.onKey = (code) => {
  if (code === 'KeyC') cycleCam();
  else if (code === 'KeyM') toggleMute();
  else if (code === 'Escape' || code === 'KeyP') setPaused(!G.paused);
  else if (code === 'KeyR' && G.state !== 'title') startRace();
  else if (code === 'Enter') { if (G.state === 'title' || G.state === 'result') startRace(); else if (G.paused) setPaused(false); }
};
document.addEventListener('visibilitychange', () => { if (document.hidden && G.state === 'race') setPaused(true); });
if (matchMedia('(pointer: coarse)').matches) document.body.classList.add('touch');

stage.init().then(() => {
  spray = stage.spray; venue = stage.venue; views = stage.views;
  stage.setQuality(matchMedia('(pointer: coarse)').matches ? 'medium' : 'high');
  setEnv('day');
  buildTitle();
  toTitle();
  requestAnimationFrame(frame);
  window.__game = { G, step, startRace, toTitle, setEnv, camera, stage, rig, get race() { return G.race; } };
});
