import * as THREE from 'three';
import { Race } from './sim/race.js';
import { VMAX } from './sim/physics.js';
import { clamp, lerp, LAPS } from './sim/course.js';
import { ENVS, RACERS, BOAT_CSS, BOAT_TEXT_CSS } from './gfx/common.js';
import { createSky, createWater } from './gfx/water.js';
import { Spray, Wakes } from './gfx/spray.js';
import { BoatView } from './gfx/boat.js';
import { createVenue } from './gfx/venue.js';
import { GameAudio } from './audio.js';
import { Hud, fmtTime, chip } from './hud.js';
import { Input } from './input.js';

const $ = (id) => document.getElementById(id);
const RACE_TITLE = '第12R 優勝戦';

// ---------------- レンダラーとシーン ----------------
const canvas = $('gl');
const renderer = new THREE.WebGLRenderer({ canvas, antialias: true, powerPreference: 'high-performance' });
renderer.setPixelRatio(Math.min(window.devicePixelRatio || 1, 2));
renderer.outputColorSpace = THREE.SRGBColorSpace;
renderer.toneMapping = THREE.NeutralToneMapping || THREE.ACESFilmicToneMapping;
const scene = new THREE.Scene();
const camera = new THREE.PerspectiveCamera(62, 1, 0.3, 7000);
const hemi = new THREE.HemisphereLight(0xffffff, 0x888888, 1);
const sun = new THREE.DirectionalLight(0xffffff, 3);
scene.add(hemi, sun, sun.target);

const sky = createSky(scene);
const water = createWater(scene);
const venue = createVenue(scene);
const wakes = new Wakes(scene);
const spray = new Spray(scene);
const views = [];
for (let i = 0; i < 6; i++) views.push(new BoatView(scene, i + 1));

const audio = new GameAudio();
const hud = new Hud();
const input = new Input();

let envName = 'day';
function setEnv(name) {
  envName = name;
  const e = ENVS[name];
  const sd = new THREE.Vector3(...e.sunDir).normalize();
  sky.uniforms.uZenith.value.set(e.zenith); sky.uniforms.uHorizon.value.set(e.horizon);
  sky.uniforms.uSunDir.value.copy(sd); sky.uniforms.uSunCol.value.set(e.sunCol);
  sky.uniforms.uCloud.value.set(e.cloud); sky.uniforms.uNight.value = e.night;
  const wu = water.uniforms;
  wu.uSunDir.value.copy(sd); wu.uSunCol.value.set(e.sunCol); wu.uDeep.value.set(e.deep); wu.uShallow.value.set(e.shallow);
  wu.uHorizon.value.set(e.horizon); wu.uZenith.value.set(e.zenith); wu.uFog.value.set(e.fog); wu.uFogD.value = e.fogD; wu.uNight.value = e.night;
  venue.lightPos.slice(0, 8).forEach((p, i) => wu.uLights.value[i].copy(p));
  scene.fog = new THREE.FogExp2(e.fog, e.fogD);
  hemi.color.set(e.hemiSky); hemi.groundColor.set(e.hemiGround); hemi.intensity = e.hemiInt;
  sun.color.set(e.sunCol); sun.intensity = e.sunInt; sun.position.copy(sd).multiplyScalar(100);
  spray.uniforms.uColor.value.set(e.spray); wakes.uniforms.uColor.value.set(e.spray);
  venue.setEnv(e);
}

function resize() {
  const w = window.innerWidth, h = window.innerHeight;
  renderer.setSize(w, h, false);
  camera.aspect = w / h; camera.updateProjectionMatrix();
  hud.resize();
}
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
const CAM_NAMES = ['追尾カメラ', '接近カメラ', '中継カメラ', '上空カメラ'];
const camState = { dir: 0, pos: new THREE.Vector3(0, 30, 120), look: new THREE.Vector3(), fov: 62, init: false };
const tmpV = new THREE.Vector3(), tmpL = new THREE.Vector3(), camRight = new THREE.Vector3();

function newRace(playerIndex) {
  G.race = new Race({ playerIndex, difficulty: G.difficulty });
  G.lastTick = -99; G.resultT = -1; G.introT = 0; G.shake = 0; camState.init = false;
  for (const v of views) { v.roll = v.pitch = 0; }
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
          G.shake = Math.min(1.4, G.shake + e.power * 0.22);
          if (e.power > 1.2) { hud.addDrops(6 + e.power * 3, true); hud.say(`接触！ ${race.boats[e.a === pl.i ? e.b : e.a].num}号艇とぶつかった`, 1.8); }
        }
        break;
      }
      case 'wall': {
        spray.burst(e.x, e.z, e.power * 0.6);
        const d = Math.hypot(e.x - camera.position.x, e.z - camera.position.z);
        if (playing) audio.hit(e.power * 0.5, 1 / (1 + (d / 25) ** 2));
        if (pl && e.boat === pl.i) { G.shake = Math.min(1.4, G.shake + e.power * 0.1); hud.say('消波装置に接触！', 1.6); }
        break;
      }
      case 'buoy': {
        const b = race.boats[e.boat];
        venue.hitBuoy(e.id, e.nx, e.nz, e.power);
        spray.burst(b.x, b.z, e.power * 0.4, b.vx, b.vz);
        if (playing) audio.buoy(e.power, pl && e.boat === pl.i ? 1 : 0.3);
        if (pl && e.boat === pl.i) { G.shake = Math.min(1.2, G.shake + 0.3); hud.say(e.id ? 'ターンマークに接触！' : 'センターポールに接触！', 1.6); }
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
function angLerp(a, b, t) { let d = b - a; while (d > Math.PI) d -= Math.PI * 2; while (d < -Math.PI) d += Math.PI * 2; return a + d * t; }

function updateCamera(dt) {
  const race = G.race, pl = race.player;
  const target = pl || race.boats[G.follow] || race.order[0];
  const f = clamp(target.speed / VMAX, 0, 1);
  let mode = G.camMode, fov = 62;
  if (!pl && G.follow < 0) mode = (Math.floor(G.time / 11) % 3 === 1 || race.state === 'pre') ? 4 : 2;      // デモ: 中継と空撮を切り替え
  else if (G.state === 'result') mode = 5;

  if (mode === 0 || mode === 1) {
    // 追尾: 進行方向と艇の向きの中間を見るので、艇が流れると横向きに見える
    const velA = target.speed > 3 ? Math.atan2(target.vz, target.vx) : target.h;
    const want = angLerp(velA, target.h, 0.45);
    if (!camState.init) camState.dir = want;
    camState.dir = angLerp(camState.dir, want, 1 - Math.exp(-dt * 4.2));
    const cx = Math.cos(camState.dir), cz = Math.sin(camState.dir);
    const back = mode === 0 ? 6.6 + 1.6 * f : 4.1, up = mode === 0 ? 2.5 + 0.35 * f : 1.25;
    tmpV.set(target.x - cx * back, up, target.z - cz * back);
    tmpL.set(target.x + cx * 6, mode === 0 ? 1.0 : 0.9, target.z + cz * 6);
    fov = (mode === 0 ? 60 : 70) + 17 * f * f;
    // スタート前の導入: 上空から艇の後ろへ降りてくる
    if (G.introT < 3.2 && pl && G.state === 'race') {
      const k = 1 - Math.pow(1 - clamp(G.introT / 3.2, 0, 1), 3);
      tmpV.set(lerp(target.x - 40, tmpV.x, k), lerp(34, tmpV.y, k), lerp(target.z + 46, tmpV.z, k));
      camState.pos.copy(tmpV); camState.look.lerp(tmpL, k);
      if (!camState.init) camState.look.copy(tmpL);
    } else {
      if (!camState.init) { camState.pos.copy(tmpV); camState.look.copy(tmpL); }
      camState.pos.lerp(tmpV, 1 - Math.exp(-dt * 14));
      camState.look.lerp(tmpL, 1 - Math.exp(-dt * 12));
    }
  } else if (mode === 2) {
    // 中継カメラ: スタンド屋根から望遠で追う
    tmpV.set(clamp(target.x * 0.55, -140, 170), 26, 78);
    tmpL.set(target.x, 0.8, target.z);
    if (!camState.init) camState.look.copy(tmpL);
    camState.pos.lerp(tmpV, 1 - Math.exp(-dt * 2));
    camState.look.lerp(tmpL, 1 - Math.exp(-dt * 6));
    const d = camState.pos.distanceTo(camState.look);
    fov = clamp(2 * Math.atan(13 / d) * 180 / Math.PI, 9, 50);
  } else if (mode === 3) {
    tmpV.set(target.x - 6, 70, target.z + 42);
    tmpL.set(target.x, 0, target.z);
    if (!camState.init) { camState.pos.copy(tmpV); camState.look.copy(tmpL); }
    camState.pos.lerp(tmpV, 1 - Math.exp(-dt * 4)); camState.look.lerp(tmpL, 1 - Math.exp(-dt * 8));
    fov = 48;
  } else if (mode === 4) {
    // 会場をゆっくり見せる空撮
    const a = G.time * 0.07;
    tmpV.set(Math.cos(a) * 210, 34 + Math.sin(G.time * 0.11) * 12, Math.sin(a) * 60 - 20);
    tmpL.set(Math.cos(a + 1.2) * 60, 6, 30);
    camState.pos.lerp(tmpV, camState.init ? 1 - Math.exp(-dt * 1.5) : 1); camState.look.lerp(tmpL, camState.init ? 1 - Math.exp(-dt * 1.5) : 1);
    fov = 55;
  } else {
    // 結果表示中: 自艇の周りを回る
    const a = G.time * 0.35;
    tmpV.set(target.x + Math.cos(a) * 9, 3.2, target.z + Math.sin(a) * 9);
    tmpL.set(target.x, 0.8, target.z);
    camState.pos.lerp(tmpV, 1 - Math.exp(-dt * 3)); camState.look.lerp(tmpL, 1 - Math.exp(-dt * 8));
    fov = 55;
  }
  camState.init = true;
  camState.fov += (fov - camState.fov) * Math.min(1, dt * 5);
  camera.position.copy(camState.pos);
  // 振動: 速度による細かい揺れ + 衝突の衝撃
  if (mode <= 1) {
    const s = 0.012 * f * f + G.shake * 0.16;
    camera.position.x += (Math.random() - 0.5) * s; camera.position.y += (Math.random() - 0.5) * s * 1.4; camera.position.z += (Math.random() - 0.5) * s;
    camera.position.y += views[target.i].poundY * 0.5;
  }
  if (camera.position.y < 0.5) camera.position.y = 0.5;
  camera.lookAt(camState.look);
  if (mode <= 1) camera.rotation.z += clamp(target.w * f * 0.05, -0.08, 0.08) + (Math.random() - 0.5) * G.shake * 0.03;
  if (Math.abs(camera.fov - camState.fov) > 0.01) { camera.fov = camState.fov; camera.updateProjectionMatrix(); }
  G.shake *= Math.exp(-dt * 5);
  camRight.set(1, 0, 0).applyQuaternion(camera.quaternion);
}

// ---------------- メインループ ----------------
let last = performance.now(), ema = 0.016, qT = 0;
function frame(now) {
  requestAnimationFrame(frame);
  const raw = (now - last) / 1000, dt = Math.min(0.05, raw);
  last = now;
  step(dt);
  renderer.render(scene, camera);
  // 重い端末では描画解像度を自動で下げる
  if (raw < 0.5) ema += (raw - ema) * 0.05;
  qT += raw;
  if (qT > 2.5) {
    qT = 0;
    const pr = renderer.getPixelRatio();
    if (ema > 0.03 && pr > 1) { renderer.setPixelRatio(Math.max(1, pr - 0.5)); resize(); ema = 0.02; }
  }
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

    for (let i = 0; i < 6; i++) {
      const b = race.boats[i], v = views[i];
      v.update(b, dt, G.time);
      const d = Math.hypot(b.x - camera.position.x, b.z - camera.position.z);
      spray.emitBoat(b, dt, clamp(1.15 - d / 110, 0.12, 1));
      if (v.slapped > 0) {
        if (b === pl && G.state === 'race') audio.slap(Math.min(0.3, v.slapped * 0.5));
        v.slapped = 0;
      }
    }
    spray.update(dt);
    wakes.update(race.boats, race.clock, G.time);
    venue.update(dt, G.time, race, RACE_TITLE, G.cheer > 0.8 ? 1 : 0);
    updateCamera(dt);

    // レンズの水滴: 旋回で自分のしぶきをかぶる / 他艇の引き波に入る
    if (pl && G.state === 'race' && G.camMode <= 1) {
      const wet = pl.turnInt * 0.6 + pl.inWake * 0.8 * clamp(pl.speed / VMAX, 0, 1);
      if (Math.random() < wet * 14 * dt) hud.addDrops(1);
    }
    sky.uniforms.uTime.value = G.time; water.uniforms.uTime.value = G.time;
    spray.uniforms.uPx.value = renderer.domElement.height / (2 * Math.tan(camera.fov * Math.PI / 360));
  }
  hud.update(running ? dt : 0, race, G.state === 'title' ? null : pl, { assist: G.difficulty < 2 });
  audio.update(dt, race.boats, pl, camera.position, camRight, running && (G.state !== 'title'), G.cheer);
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
function cycleCam() { G.camMode = (G.camMode + 1) % 4; camState.init = G.camMode < 2 ? camState.init : false; if (G.state === 'race') hud.say(CAM_NAMES[G.camMode], 1.2); }
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

setEnv('day');
resize();
buildTitle();
toTitle();
requestAnimationFrame(frame);

// デバッグ/自動テスト用
window.__game = { G, step, startRace, toTitle, setEnv, camera, renderer, get race() { return G.race; } };
