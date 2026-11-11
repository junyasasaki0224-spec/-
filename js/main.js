// ============================================================
//  ゲーム進行・入力・HUD・実況
// ============================================================
import { RACES, COURSES, makeField, makeConditions, STYLES, GOING, WEATHER, WAKU_COLORS, WAKU_TEXT, gradeOf, fmtTime, marginText, clamp } from './data.js';
import { Race } from './sim.js';
import { Venue, loadAssets } from './scene.js';
import { Sound } from './audio.js';

for (const r of RACES) r.courseObj = COURSES[r.course];
const $ = (id) => document.getElementById(id);
const venue = new Venue($('view'));
const sound = new Sound();
const isTouch = 'ontouchstart' in window || navigator.maxTouchPoints > 0;
if (isTouch) document.body.classList.add('is-touch');

const G = {
  mode: 'attract', def: null, horses: null, cond: null, seed: 0, pick: -1, diff: 1,
  race: null, acc: 0, paused: false, introT: 0, introDur: 9, gateT: 0, finT: 0,
  coachOn: true, toastT: 0, hudT: 0, flags: {}, pSplitAt: 0, pSplitT: 0, pLap: 0, feel: null, orderT: 0,
};
const keys = { up: false, down: false, left: false, right: false };
const edge = { whip: false, lead: false, go: false };

const KL = isTouch ? { up: '追う', down: '抑える', lr: '◀ ▶', left: '◀', right: '▶', whip: 'ムチ', lead: '手前', go: 'スタート' } : { up: '↑', down: '↓', lr: '← →', left: '←', right: '→', whip: 'SPACE', lead: 'SHIFT', go: 'SPACE' };
const kbd = (k) => `<kbd>${KL[k]}</kbd>`;

// ---- 保存データ ----
const SAVE_KEY = 'turfjockey.v1';
let save = { runs: 0, w: [0, 0, 0], money: 0, best: {} };
try { const s = JSON.parse(localStorage.getItem(SAVE_KEY)); if (s && s.w) save = s; } catch (e) { /* 保存不可の環境 */ }
const store = () => { try { localStorage.setItem(SAVE_KEY, JSON.stringify(save)); } catch (e) { /* noop */ } };

// ---- 画面切替 ----
const SCREENS = ['title', 'select', 'entry', 'intro', 'pause', 'result', 'how', 'opt'];
function show(name) {
  for (const s of SCREENS) $('scr-' + s).classList.toggle('hidden', s !== name);
  $('hud').classList.toggle('hidden', !(G.mode === 'gate' || G.mode === 'race' || G.mode === 'finish') || name === 'result');
}
function overlay(name, on) { $('scr-' + name).classList.toggle('hidden', !on); }
function loading(on, text) { $('loading').classList.toggle('hidden', !on); if (text) $('loading-text').textContent = text; }
const wakuTag = (h) => `<span class="waku" style="background:${WAKU_COLORS[h.waku - 1]};color:${WAKU_TEXT[h.waku - 1]}">${h.num}</span>`;

function renderCareer() {
  $('career').textContent = save.runs ? `通算 ${save.runs}戦 ${save.w[0]}勝 2着${save.w[1]}回 3着${save.w[2]}回 / 獲得賞金 ${save.money.toLocaleString()}万円` : '';
}

// ---- タイトル背景: AI同士のレースを流す ----
function startAttract() {
  const q = new URLSearchParams(location.search); // ?demo=kyoto3000&wx=3 で背景デモの条件を指定可
  const def = RACES.find((r) => r.id === q.get('demo')) || RACES[(Math.random() * RACES.length) | 0];
  const seed = (Math.random() * 1e9) | 0;
  const horses = makeField(def, seed), cond = makeConditions(def, seed);
  if (q.get('wx')) { cond.weather = +q.get('wx'); cond.going = Math.min(3, cond.weather); } else if (cond.weather > 1) cond.weather = 1;
  G.race = new Race({ course: def.courseObj, dist: def.dist, horses, cond, seed, playerIdx: -1 });
  venue.build(def, G.race, cond);
  G.race.openGate(); G.mode = 'attract'; G.acc = 0; G.attractCam = 2; G.attractT = 0; venue.snap = true;
}

// ---- レース選択 ----
function renderRaces() {
  $('race-list').innerHTML = RACES.map((r, i) => `
    <button class="race-card" data-i="${i}">
      <div class="rc-top"><span class="g">${r.grade}</span><span class="nm">${r.name}</span></div>
      <div class="meta">${r.courseObj.name} 芝${r.dist}m ${r.courseObj.dir === 'L' ? '左' : '右'}回り ・ ${r.n}頭 ・ ${r.month}月</div>
      <div class="memo">${r.memo}</div>
      <div class="best">1着賞金 ${r.prize.toLocaleString()}万円${save.best[r.id] ? ' ／ 自己ベスト ' + fmtTime(save.best[r.id]) : ''}</div>
    </button>`).join('');
}
$('race-list').addEventListener('click', (e) => {
  const b = e.target.closest('.race-card'); if (!b) return;
  sound.click(); openEntry(RACES[+b.dataset.i], (Math.random() * 1e9) | 0);
});

// ---- 出馬表 ----
function windText(cond) {
  const sp = cond.wind.speed; if (sp < 1) return '無風';
  const wx = Math.cos(cond.wind.dir) * sp, wz = Math.sin(cond.wind.dir) * sp;
  const dir = Math.abs(wx) >= Math.abs(wz) ? (wx < 0 ? '直線向かい風' : '直線追い風') : '横風';
  return `${dir} ${sp.toFixed(1)}m/s`;
}
function openEntry(def, seed) {
  G.def = def; G.seed = seed; G.pick = -1;
  G.horses = makeField(def, seed); G.cond = makeConditions(def, seed);
  const c = G.cond, co = def.courseObj;
  $('entry-title').textContent = `${def.grade} ${def.name} ― ${co.name} 芝${def.dist}m`;
  const tips = [];
  if (c.going >= 2) tips.push('道悪。パワーと道悪適性のある馬が浮上し、時計がかかる。');
  if (c.rough >= 0.65) tips.push('内側の芝が荒れている。直線は馬場の中ほどから外へ持ち出したい。');
  else if (c.rough < 0.1) tips.push('開幕週で内の芝が絶好。内ラチ沿いと先行馬が有利。');
  const wx = Math.cos(c.wind.dir) * c.wind.speed;
  if (wx < -3) tips.push('直線は強い向かい風。前の馬を風除けに使い、追い出しを我慢。');
  else if (wx > 3) tips.push('直線は追い風。前が止まりにくいので早めに動きたい。');
  if (!tips.length) tips.push('標準的な馬場。実力とペース判断の勝負。');
  $('cond-info').innerHTML = `
    <div class="kv">
      <b>天候</b><span>${WEATHER[c.weather]}</span><b>馬場</b><span>芝・${GOING[c.going]}</span>
      <b>風</b><span>${windText(c)}</span><b>開催</b><span>${c.week}週目(${['内外フラット', '内やや傷み', '内荒れ', '内かなり荒れ'][c.week - 1]})</span>
    </div>
    <div class="feat">${co.feature}</div>
    ${tips.map((t) => `<div class="tip">▶ ${t}</div>`).join('')}`;
  $('pick-info').innerHTML = 'オッズを算出しています…';
  $('btn-go').disabled = true;
  renderEntry();
  show('entry');
  // オッズ: AI同士の模擬レースを繰り返して勝率から算出 (数回に分けて実行)
  const win = new Float32Array(def.n).fill(0.3); let k = 0; const N = 14; const token = (G.oddsToken = Math.random());
  const run = () => {
    if (G.oddsToken !== token) return;
    for (let j = 0; j < 2 && k < N; j++, k++) {
      const race = new Race({ course: co, dist: def.dist, horses: G.horses, cond: c, seed: 7919 * (k + 1), playerIdx: -1 });
      const fo = race.runAll(1 / 20);
      win[fo[0].i] += 1; win[fo[1].i] += 0.4; win[fo[2].i] += 0.2;
    }
    if (k < N) { setTimeout(run, 0); return; }
    let tot = 0; for (const w of win) tot += w;
    G.horses.forEach((h, i) => { h.odds = clamp(Math.round((0.8 / (win[i] / tot)) * 10) / 10, 1.1, 399.9); });
    G.horses.slice().sort((a, b) => a.odds - b.odds).forEach((h, i) => { h.pop = i + 1; });
    renderEntry();
    $('pick-info').innerHTML = '騎乗する馬を出馬表から選んでください。<br>人気薄で勝つほど腕の証明になります。';
  };
  setTimeout(run, 30);
}
function renderEntry() {
  const gr = (v) => `<td class="gr-${gradeOf(v)}">${gradeOf(v)}</td>`;
  $('entry-table').innerHTML = `<thead><tr><th>馬番</th><th>馬名</th><th>性齢</th><th>騎手</th><th>脚質</th><th>調子</th><th>人気</th><th>単勝</th>
    <th>速力</th><th>持久</th><th>瞬発</th><th>パワー</th><th>根性</th><th>気性</th><th>道悪</th><th>器用</th><th>ゲート</th></tr></thead><tbody>` +
    G.horses.map((h, i) => `<tr data-i="${i}" class="${i === G.pick ? 'sel' : ''}"><td>${wakuTag(h)}</td><td class="nm">${h.name}</td><td>${h.sex}${h.age}</td>
      <td>${i === G.pick ? '<b>あなた</b>' : h.jockey}</td><td>${STYLES[h.style]}</td><td class="${h.cond.cls}">${h.cond.sym}</td>
      <td class="${h.pop === 1 ? 'pop1' : ''}">${h.pop || '-'}</td><td>${h.odds ? h.odds.toFixed(1) : '-'}</td>
      ${gr(h.spd)}${gr(h.sta)}${gr(h.acc)}${gr(h.pow)}${gr(h.gut)}${gr(h.tmp)}${gr(h.mud)}${gr(h.nim)}${gr(h.gate)}</tr>`).join('') + '</tbody>';
}
$('entry-table').addEventListener('click', (e) => {
  const tr = e.target.closest('tr[data-i]'); if (!tr || !G.horses[0].odds) return;
  G.pick = +tr.dataset.i; sound.select(); renderEntry();
  const h = G.horses[G.pick];
  const adv = [
    'ハナを切って自分のリズムで。単騎で行ければ折り合いも楽。',
    '好位の内で前を風除けに。直線で早めに抜け出す王道の競馬。',
    '中団で脚を溜め、直線で外へ。前が壁にならない進路取りが鍵。',
    '後方でじっくり。ペースが速くなれば一気。展開待ちの面も。',
  ][h.style];
  const notes = [];
  if (h.tmp < 58) notes.push('気性が激しい: 序盤は前に馬を置いて折り合いに専念');
  if (h.acc >= 82) notes.push('瞬発力◎: 直線まで我慢して切れ味勝負');
  if (h.sta >= 84) notes.push('スタミナ◎: 早めのロングスパートが効く');
  if (h.gate < 58) notes.push('ゲートに難: スタートに集中');
  if (h.nim < 58) notes.push('不器用: コーナーで膨れやすい');
  if (G.cond.going >= 2 && h.mud < 55) notes.push('道悪は苦手');
  $('pick-info').innerHTML = `<b>${wakuTag(h)} ${h.name}</b>　${h.pop}番人気 ${h.odds.toFixed(1)}倍<br>${h.coat.name}・${h.weight}kg(${h.wdiff >= 0 ? '+' : ''}${h.wdiff})・脚質 ${STYLES[h.style]}<br>${adv}${notes.map((n) => '<br>・' + n).join('')}`;
  $('btn-go').disabled = false;
});

// ---- 発走 ----
function startRace() {
  loading(true, '競馬場へ向かっています…');
  G.oddsToken = 0;
  setTimeout(() => {
    const def = G.def;
    G.diff = +document.querySelector('input[name=diff]:checked').value;
    G.race = new Race({ course: def.courseObj, dist: def.dist, horses: G.horses, cond: G.cond, seed: (Math.random() * 1e9) | 0, playerIdx: G.pick, difficulty: G.diff });
    venue.build(def, G.race, G.cond);
    venue.camMode = 0;
    G.mode = 'intro'; G.introT = 0; G.acc = 0; G.flags = {}; G.pSplitAt = 200; G.pSplitT = 0; G.pLap = 0; G.paused = false;
    G.introDur = Math.max(8.5, sound.fanfare());
    $('intro-grade').textContent = `${def.courseObj.name}  ${def.grade}`;
    $('intro-name').textContent = def.name;
    $('intro-sub').textContent = `芝${def.dist}m ${def.courseObj.dir === 'L' ? '左' : '右'}回り ／ ${WEATHER[G.cond.weather]}・${GOING[G.cond.going]} ／ ${def.n}頭`;
    buildMinimap();
    $('h-n').textContent = '/' + def.n;
    $('h-wx').textContent = `${WEATHER[G.cond.weather]}・${GOING[G.cond.going]}　${windText(G.cond)}`;
    $('h-toast').classList.remove('on');
    loading(false); show('intro');
  }, 60);
}
function toGate() {
  G.mode = 'gate'; G.gateT = 2.2 + Math.random() * 2.4; venue.snap = true;
  show('none');
  const gm = $('h-gate'); gm.classList.remove('hidden', 'go');
  gm.innerHTML = `<div class="sig red">待て</div><div class="g1">信号が<span style="color:#6fe08a">緑</span>に変わった瞬間に ${kbd('go')}</div><div class="g2">赤のうちに押すと、馬があおって出遅れます</div>`;
  setWhipLabel('スタート');
  say('各馬ゲートに収まりました。', true);
  sound.stop(); sound.cutFanfare();
  edge.go = edge.whip = edge.lead = false;
}

// ---- 実況 ----
function say() { return true; } // 実況(字幕・読み上げ)は廃止。展開は歓声で表現する
function toast(text, cls) {
  const t = $('h-toast'); t.textContent = text; t.className = 'toast on ' + (cls || ''); G.toastT = 1.5;
}
const nm = (r) => `${r.h.num}番${r.h.name}`;

function handleEvents() {
  const race = G.race, ev = race.events, pl = race.player;
  for (const e of ev) {
    switch (e.type) {
      case 'false': {
        const sg = document.querySelector('#h-gate .sig'); if (sg) { sg.className = 'sig bad'; sg.textContent = '早い！'; }
        toast('まだ赤信号！ あおって出遅れる', 'bad'); sound.buzz(); break;
      }
      case 'pstart':
        {
          const good = e.kind === '好スタート', ok = e.kind === '五分';
          const rb = $('rb-i'); if (rb) rb.style.left = clamp(e.delay / 0.8, 0, 1) * 100 + '%';
          const sg = document.querySelector('#h-gate .sig');
          if (sg && e.kind !== 'あおって出遅れ') { sg.className = 'sig ' + (good || ok ? 'done' : 'bad'); sg.textContent = e.kind; }
          const g1 = document.querySelector('#h-gate .g1');
          if (g1 && e.kind !== 'あおって出遅れ') g1.innerHTML = `反応 ${e.delay.toFixed(2)}秒 ${good ? '― 一歩前へ！' : ''}　続けて ${kbd('up')} 長押しでダッシュ`;
          G.gateMsgT = 1.6; setWhipLabel('ムチ');
          if (good) sound.chime(92);
        }
        if (e.kind.includes('出遅れ')) sound.gasp(1);
        if (e.kind.includes('出遅れ')) say(`${nm(pl)}、出遅れました！`, true);
        break;
      case 'late': if (!G.flags.late) { G.flags.late = 1; sound.gasp(0.7); say(`${nm(race.runners[e.i])}は出遅れ。`); } break;
      case 'whip':
        sound.whip(e.q > 1.2);
        if (e.dead) toast('もう脚が残っていない…', 'bad'); else if (e.q > 1.2) toast('ナイスムチ！', 'good');
        break;
      case 'lead': toast(e.q === 0 ? '手前替えが早い！外に膨れた' : `手前替え: ${e.kind}`, e.q >= 1 ? 'good' : e.q >= 0.6 ? '' : 'warn'); if (e.q >= 0.6) { sound.whoosh(); sound.chime(); } break;
      case 'bump': toast('接触！', 'bad'); sound.bump(); break;
      case 'foul': toast('斜行！ 後続の進路を塞いだ', 'bad'); sound.buzz(); break;
      case 'empty': if (e.rem > 40) toast('脚が上がった…', 'bad'); break;
      case 'split':
        if (e.at >= 1000 && !G.flags.p1000 && race.D >= 1600) {
          G.flags.p1000 = 1;
          const t1000 = race.pass1000 || e.t;
          const par = (G.def.par / race.D) * 1000 + 1.2;
          const pace = t1000 < par - 0.9 ? 'ハイペース' : t1000 > par + 0.9 ? 'スローペース' : '平均ペース';
          G.flags.pace = pace;
          say(`1000メートル通過は${t1000.toFixed(1)}秒。${pace}です。`);
        }
        break;
      case 'finish': {
        const r = race.runners[e.i];
        if (e.pos === 1) { say(`${nm(r)}、先頭でゴールイン！`, true); sound.intensity = 0; sound.stop(); sound.cheer(1.25, 7); setTimeout(() => sound.applause(7, 1), 2600); }
        if (r.isPlayer) {
          toast(e.pos === 1 ? '1着でゴール！' : `${e.pos}着入線`, e.pos <= 3 ? 'good' : '');
          G.mode = 'finish'; G.finT = 0; sound.jingle(e.pos === 1); venue.camMode = 2;
        }
        break;
      }
    }
  }
  ev.length = 0;
}

function commentary() {
  const race = G.race, tr = race.track, F = G.flags, ld = race.order[0], pl = race.player, D = race.D;
  const rem = D - ld.s;
  if (!F.s && race.t > 0.3) { F.s = 1; say('スタートしました！', true); }
  if (!F.lead && race.t > 6) { F.lead = 1; say(`先手を取ったのは${nm(ld)}。`); F.ldI = ld.i; }
  const c = tr.cornerAt(ld.s);
  if (c !== F.corner) {
    F.corner = c;
    if (rem > tr.straight + 50) {
      if (c === 1) say('各馬、第1コーナーへ向かいます。');
      else if (c === 3) say(G.def.course === 'kyoto' ? '第3コーナー、淀の坂を上っていきます。' : '第3コーナーに差しかかります。');
    }
  }
  if (race.t > 12 && rem > 900 && race.t - (F.sumT || 0) > 17) {
    const o = race.order, gap = (o[0].s - o[1].s) / 2.4;
    const lead = gap < 0.6 ? 'わずかに' : gap > 3 ? `${Math.round(gap)}馬身ほど離して` : `${Math.max(1, Math.round(gap))}馬身のリードで`;
    if (say(`先頭は${nm(o[0])}、${lead}。2番手に${o[1].h.name}、続いて${o[2].h.name}。${pl.rank > 3 ? `${pl.h.name}は現在${pl.rank}番手。` : ''}`)) F.sumT = race.t;
  }
  // 1周目のスタンド前通過: 目の前を馬群が駆け抜けて沸く
  if (!F.pass1 && rem > tr.straight + 500 && ld.s >= tr.chute && tr.uOf(ld.s) > tr.straight - 120 && tr.uOf(ld.s) < tr.straight + 40 && race.t > 8) { F.pass1 = 1; sound.cheer(0.7, 5); }
  // 直線で先頭が入れ替わるたびに、どよめきと歓声
  if (F.str && rem > 0 && ld.i !== F.ldI && race.t - (F.ldT || 0) > 1.6) { F.ldI = ld.i; F.ldT = race.t; sound.gasp(0.8); sound.cheer(0.8, 2.6); }
  // 自分の馬が直線で順位を上げると沸く
  if (F.str && rem > 0 && pl && !pl.fin) { if (F.plRank && pl.rank < F.plRank && pl.rank <= 5 && race.t - (F.upT || 0) > 1.2) { F.upT = race.t; sound.cheer(0.5 + (6 - pl.rank) * 0.1, 2.2); } F.plRank = pl.rank; }
  if (!F.c4 && rem < tr.straight + 260 && rem > tr.straight) { F.c4 = 1; sound.cheer(0.55, 3.5); say('第4コーナーをカーブ、各馬が動き出した！', true); }
  if (!F.str && rem <= tr.straight) {
    sound.cheer(1.0, 5); F.ldI = ld.i; F.ldT = race.t;
    F.str = 1;
    const fl = { tokyo: '525メートルの長い直線！', nakayama: '中山の直線は短いぞ！', kyoto: '坂を下って平坦の直線！', hanshin: '最後に急坂が待つ阪神の直線！' }[G.def.course];
    say(`さあ最後の直線！${fl}先頭は${ld.h.name}！`, true);
  }
  if (!F.r200 && rem <= 200 && rem > 0) {
    sound.cheer(1.1, 4.5);
    F.r200 = 1; const o = race.order;
    const ch = o[1].s > o[0].s - 3 ? `${o[1].h.name}が並びかける！` : o[1].v > o[0].v + 0.25 ? `${o[1].h.name}が迫る！` : 'リードを保っている！';
    say(`残り200！先頭は${o[0].h.name}！${ch}`, true);
  }
  if (F.r200 && !F.r50 && rem <= 60 && rem > 0) { F.r50 = 1; if (race.order[0].s - race.order[1].s < 3) sound.cheer(1.3, 3.5); say(`${race.order[0].h.name}か、${race.order[1].h.name}か！`, true); }
}

// ---- ミニマップ ----
const mm = { pts: [], sx: 1, ox: 0, oz: 0 };
function buildMinimap() {
  const tr = G.race.track, pts = [], o = {};
  let x0 = 1e9, x1 = -1e9, z0 = 1e9, z1 = -1e9;
  for (let u = 0; u <= tr.lap; u += 12) { tr.point(u, tr.W / 2, o); pts.push([o.x, o.z]); }
  if (tr.chute > 0) { tr.at(0, tr.W / 2, o); mm.ch = [o.x, o.z]; tr.at(tr.chute, tr.W / 2, o); mm.ch2 = [o.x, o.z]; pts.push(mm.ch); } else mm.ch = null;
  for (const p of pts) { x0 = Math.min(x0, p[0]); x1 = Math.max(x1, p[0]); z0 = Math.min(z0, p[1]); z1 = Math.max(z1, p[1]); }
  if (mm.ch) pts.pop();
  const cv = $('minimap'), s = Math.min((cv.width - 24) / (x1 - x0), (cv.height - 24) / (z1 - z0));
  mm.pts = pts; mm.s = s; mm.ox = (cv.width - (x1 - x0) * s) / 2 - x0 * s; mm.oz = (cv.height - (z1 - z0) * s) / 2 - z0 * s;
  tr.point(tr.straight, tr.W / 2, o); mm.goal = [o.x, o.z];
}
function drawMinimap() {
  const cv = $('minimap'), x = cv.getContext('2d'), race = G.race;
  const X = (p) => p[0] * mm.s + mm.ox, Z = (p) => p[1] * mm.s + mm.oz;
  x.clearRect(0, 0, cv.width, cv.height);
  x.strokeStyle = '#3f9a4a'; x.lineWidth = 7; x.lineJoin = 'round'; x.beginPath();
  mm.pts.forEach((p, i) => (i ? x.lineTo(X(p), Z(p)) : x.moveTo(X(p), Z(p)))); x.closePath(); x.stroke();
  if (mm.ch) { x.beginPath(); x.moveTo(X(mm.ch), Z(mm.ch)); x.lineTo(X(mm.ch2), Z(mm.ch2)); x.stroke(); }
  x.fillStyle = '#ff4a3a'; x.fillRect(X(mm.goal) - 1.5, Z(mm.goal) - 7, 3, 14);
  for (const r of race.runners) {
    if (r.isPlayer) continue;
    x.fillStyle = WAKU_COLORS[r.h.waku - 1]; x.strokeStyle = '#000'; x.lineWidth = 0.6;
    x.beginPath(); x.arc(r.geo.x * mm.s + mm.ox, r.geo.z * mm.s + mm.oz, 2.6, 0, 6.3); x.fill(); x.stroke();
  }
  const p = race.player; if (p) { x.fillStyle = '#ffe14a'; x.strokeStyle = '#000'; x.lineWidth = 1.5; x.beginPath(); x.arc(p.geo.x * mm.s + mm.ox, p.geo.z * mm.s + mm.oz, 4.5, 0, 6.3); x.fill(); x.stroke(); }
  // 風向き
  const w = G.cond.wind; if (w.speed >= 1) {
    const cx = 22, cy = cv.height - 20, a = w.dir, L = 6 + w.speed * 1.2;
    x.strokeStyle = '#9fd0ff'; x.fillStyle = '#9fd0ff'; x.lineWidth = 2; x.beginPath(); x.moveTo(cx - Math.cos(a) * L, cy - Math.sin(a) * L); x.lineTo(cx + Math.cos(a) * L, cy + Math.sin(a) * L); x.stroke();
    x.beginPath(); x.arc(cx + Math.cos(a) * L, cy + Math.sin(a) * L, 3, 0, 6.3); x.fill();
    x.font = '10px sans-serif'; x.fillText('風', cx + 14, cy + 4);
  }
}

// ---- HUD ----
function updateHud(dt) {
  const race = G.race, p = race.player, tr = race.track; if (!p) return;
  const rem = Math.max(0, race.D - p.s), kmh = p.v * 3.6;
  $('b-spd').style.width = clamp((kmh - 48) / 26, 0, 1) * 100 + '%';
  $('b-sta').style.width = clamp(p.E, 0, 100) + '%';
  $('b-ar').style.width = clamp(p.ar, 0, 1) * 100 + '%';
  const ph = p.phase % 1, off = Math.min(ph, 1 - ph);
  const ring = $('h-ring'); ring.classList.toggle('hit', off < 0.1 && p.v > 8);
  ring.firstElementChild.style.transform = `scale(${0.25 + (1 - Math.min(1, off * 3.2)) * 0.75})`;
  // 自分のラップ
  if (p.s >= G.pSplitAt && race.state === 'run') { G.pLap = race.t - G.pSplitT; G.pSplitT = race.t; G.pSplitAt += 200; }
  G.hudT -= dt; if (G.hudT > 0) return; G.hudT = 0.1;
  $('h-rank').textContent = p.fin ? race.finishOrder.indexOf(p) + 1 : p.rank;
  $('h-rem').textContent = Math.round(rem);
  $('h-time').textContent = fmtTime(p.fin ? p.ft : race.t);
  $('h-spd').textContent = kmh.toFixed(1);
  $('h-lap').textContent = G.pLap ? `前の200m ${G.pLap.toFixed(1)}秒` : '';
  $('h-whip').textContent = p.whipN;
  const cn = tr.cornerAt(p.s);
  $('h-loc').textContent = rem <= 0 ? 'ゴール' : rem <= tr.straight ? '最後の直線' : cn ? `第${cn}コーナー` : p.s < tr.chute ? 'ポケット' : (tr.uOf(p.s) < tr.L ? 'スタンド前' : '向正面');
  const f = race.feel(p); G.feel = f;
  const guide = $('b-guide');
  if (G.diff < 2 && rem > 30 && race.state === 'run') { guide.style.display = ''; guide.style.left = clamp((f.ve * 3.6 - 48) / 26, 0, 1) * 100 + '%'; } else guide.style.display = 'none';
  const fe = $('h-feel');
  if (p.E <= 0) { fe.textContent = '一杯'; fe.style.color = 'var(--bad)'; }
  else if (f.ratio > 1.7) { fe.textContent = '手応え抜群'; fe.style.color = 'var(--good)'; }
  else if (f.ratio > 1.2) { fe.textContent = '余力あり'; fe.style.color = 'var(--good)'; }
  else if (f.ratio > 0.97) { fe.textContent = 'ちょうど'; fe.style.color = '#fff'; }
  else if (f.ratio > 0.8) { fe.textContent = 'やや速い'; fe.style.color = 'var(--warn)'; }
  else { fe.textContent = 'オーバーペース'; fe.style.color = 'var(--bad)'; }
  $('b-sta').parentElement.classList.toggle('low', p.E < 15);
  const ar = $('h-ar');
  if (rem < 700) { ar.textContent = '―'; ar.style.color = 'var(--sub)'; }
  else if (p.ar > 0.6) { ar.textContent = '掛かっている！'; ar.style.color = 'var(--bad)'; }
  else if (p.ar > 0.3) { ar.textContent = '行きたがる'; ar.style.color = 'var(--warn)'; }
  else { ar.textContent = '折り合い◎'; ar.style.color = 'var(--good)'; }
  const b = [];
  if (p.blocked > 0.3) b.push('<span class="b">前が壁！</span>');
  if (p.draft > 0.15) b.push('<span class="g">風除け(スリップ)</span>');
  if (p.slope > 0.006) b.push('<span class="w">上り坂</span>'); else if (p.slope < -0.006) b.push('<span class="g">下り坂</span>');
  if (p.head > 2.5 && p.draft < 0.15) b.push('<span class="w">向かい風</span>'); else if (p.head < -2.5) b.push('<span class="g">追い風</span>');
  if (race.roughAt(p.d) > 0.3) b.push('<span class="w">荒れた芝</span>');
  if (p.k > 0 && p.d > 6.5) b.push('<span class="w">外々で距離ロス</span>');
  if (p.duel) b.push('<span class="g">叩き合い</span>');
  // 斜行注意: すぐ斜め後ろに馬がいる側へは寄れない
  for (const j of race.runners) {
    if (j === p || j.fin) continue;
    const ds = p.s - j.s, dd = j.d - p.d;
    if (ds > 2.2 && ds < 4.1 && Math.abs(dd) >= 0.9 && Math.abs(dd) < 2.6) {
      const right = (dd > 0) === (tr.t < 0);
      b.push(`<span class="b">⚠ ${right ? '右' : '左'}後ろに馬(斜行注意)</span>`); break;
    }
  }
  $('h-badges').innerHTML = b.join('');
  const ls = p.s - tr.straightStartS;
  $('h-lead').classList.toggle('hidden', p.leadDone || ls < -70 || ls > 230);
  G.orderT -= 0.1; if (G.orderT <= 0) {
    G.orderT = 0.5;
    const o = race.order, rows = [];
    for (let i = 0; i < Math.min(5, o.length); i++) rows.push(`<div class="${o[i].isPlayer ? 'me' : ''}">${wakuTag(o[i].h)}${o[i].h.name}</div>`);
    if (p.rank > 5) rows.push(`<div class="me">${wakuTag(p.h)}${p.rank}番手</div>`);
    $('h-order').innerHTML = rows.join('');
  }
  drawMinimap();
}

// ---- 騎乗アドバイス: 状況に応じて「次に押すキー」を示す ----
function setWhipLabel(t) {
  const b = document.querySelector('#touch .t-whip'); if (b) b.textContent = t;
  $('k-whip-l').textContent = t;
}
function coachAdvice() {
  const race = G.race, p = race.player, tr = race.track, n = race.runners.length;
  if (G.mode === 'gate') return { k: ['whip'], t: '', c: 'hidden' };
  if (G.mode !== 'race') return null;
  if (!p.started) return { k: ['whip'], t: '', c: 'hidden' };
  const rem = race.D - p.s, f = G.feel || race.feel(p), st = p.h.style;
  const inKey = tr.t < 0 ? 'left' : 'right', outKey = tr.t < 0 ? 'right' : 'left';
  if (p.E <= 0 && rem > 30) return { k: [], t: '脚が上がった…。次はもう少し我慢してから追い出そう', c: 'warn' };
  // スタートダッシュ
  if (p.s < 320 && race.t < 26) {
    const band = [[1, 1], [2, 5], [Math.round(n * 0.35), Math.round(n * 0.65)], [Math.round(n * 0.6), n]][st];
    if (p.rank > band[1]) return { k: ['up'], t: `スタートダッシュ: ${kbd('up')} 長押しで ${band[0] === band[1] ? '先頭' : band[0] + '〜' + band[1] + '番手'}(${STYLES[st]})へ`, c: 'act' };
    if (p.v > f.ve + 0.5) return { k: [], t: `位置は取れた。${kbd('up')} を離すと今の速度のまま走る(持ったまま)`, c: '' };
    if (p.rank < band[0] && st >= 2) return { k: ['down'], t: `前に行きすぎ。${kbd('down')} で控えて脚を溜める`, c: 'warn' };
    return { k: [], t: 'いい位置。何も押さなければ速度は維持される', c: '' };
  }
  if (p.blocked > 0.3) return { k: ['lr'], t: `前が壁！ ${kbd('lr')} で空いた進路へ(斜め後ろの馬に注意)`, c: 'warn' };
  if (rem > 700) {
    if (p.ar > 0.45) return p.cover ? { k: [], t: '掛かり気味。前の馬の真後ろのまま我慢させる', c: 'warn' } : { k: ['lr'], t: `掛かっている！ ${kbd('lr')} で前の馬の真後ろに入れて落ち着かせる`, c: 'warn' };
    if (f.ratio < 0.86) return { k: ['down'], t: `ペースが速い。${kbd('down')} で金色の印(適正ペース)まで落とす`, c: 'warn' };
    if (f.ratio > 1.55 && p.v < f.ve - 0.35) return { k: ['up'], t: `余力十分。${kbd('up')} で金色の印まで上げてよい`, c: '' };
    if (p.k > 0 && p.d > 6) return { k: ['lr'], t: `外を回って距離ロス。${kbd(inKey)} で内へ`, c: 'warn' };
    if (!p.cover && p.rank > 1 && (p.head > 2 || p.ar > 0.3)) return { k: ['lr'], t: `${kbd('lr')} で前の馬の真後ろへ。風除けになりスタミナを温存`, c: '' };
    return { k: [], t: '折り合って追走中。金色の印より速くしないこと', c: '' };
  }
  const ls = p.s - tr.straightStartS;
  if (!p.leadDone && ls > -45 && ls < 160) return { k: ['lead'], t: `直線入口！ ${kbd('lead')} で手前替え`, c: 'act' };
  if (rem < 430 || f.ratio > 1.05) {
    if (race.roughAt(p.d) > 0.35 && ls > 0) return { k: ['up', 'lr'], t: `${kbd('up')} で追いながら ${kbd(outKey)} で荒れていない外へ`, c: 'act' };
    return rem < 380 ? { k: ['up', 'whip'], t: `追え！ ${kbd('up')} 長押し ＋ リングが光る瞬間に ${kbd('whip')}`, c: 'act' } : { k: ['up'], t: `スパート！ ${kbd('up')} 長押し`, c: 'act' };
  }
  return { k: [], t: 'まだ我慢。追い出しは残り400mあたりから', c: '' };
}
function updateCoach(dt) {
  G.coachT = (G.coachT || 0) - dt; if (G.coachT > 0) return; G.coachT = 0.25;
  const el = $('h-coach'), a = G.coachOn && G.diff < 2 ? coachAdvice() : null;
  for (const s of document.querySelectorAll('#h-keys span[data-k]')) s.classList.toggle('hint', !!a && a.k.includes(s.dataset.k));
  for (const b of document.querySelectorAll('#touch button')) {
    const k = b.dataset.k, kk = k === 'left' || k === 'right' ? 'lr' : k;
    b.classList.toggle('hint', !!a && a.k.includes(kk));
  }
  if (!a) { el.classList.add('hidden'); return; }
  if (a.t !== G.coachTxt) { G.coachTxt = a.t; $('h-coach-t').innerHTML = '💡 ' + a.t; }
  el.className = 'coach ' + a.c;
}

// ---- 結果 ----
function showResult() {
  const race = G.race, def = G.def, p = race.player;
  let guard = 0; while (race.state !== 'done' && guard++ < 30 * 120) race.step(1 / 30, null);
  race.events.length = 0;
  const fo = race.finishOrder.slice().sort((a, b) => a.ft - b.ft);
  // 審議: 斜行で被害馬より先着していれば降着
  let shingi = '', demoted = false;
  const vic = p.m.victim >= 0 ? race.runners[p.m.victim] : null;
  if (vic && p.m.foul >= 2.2) {
    const pi = fo.indexOf(p), vi = fo.indexOf(vic);
    if (pi < vi) { fo.splice(pi, 1); fo.splice(fo.indexOf(vic) + 1, 0, p); demoted = true; shingi = `審議の結果、${p.h.num}番は${vic.h.num}番の進路を妨害したため ${pi + 1}位入線→${fo.indexOf(p) + 1}着に降着。`; }
    else shingi = `審議: ${p.h.num}番の斜行について過怠金。着順の変更なし。`;
  } else if (p.m.foul > 0.6) shingi = '戒告: 進路の取り方に注意。';
  const pos = fo.indexOf(p) + 1, win = fo[0];
  const prize = Math.round(def.prize * ([1, 0.4, 0.25, 0.15, 0.1][pos - 1] || 0));
  save.runs++; if (pos <= 3) save.w[pos - 1]++; save.money += prize;
  if (pos === 1 && (!save.best[def.id] || p.ft < save.best[def.id])) save.best[def.id] = p.ft;
  store(); renderCareer();

  $('res-title').textContent = `${def.name} 結果`;
  const lamp = $('res-lamp'); lamp.textContent = shingi && p.m.foul >= 2.2 ? '審議 → 確定' : '確定'; lamp.className = 'lamp ' + (demoted ? 'shingi' : 'kakutei');
  $('res-head').innerHTML = `<div class="pos">${pos}<small>着</small></div><div class="hn">${wakuTag(p.h)} ${p.h.name}（${p.h.pop}番人気）</div>
    <div class="pz">${fmtTime(p.ft)}　上がり3F ${p.last3f.toFixed(1)}　${prize ? '賞金 +' + prize.toLocaleString() + '万円' : '賞金なし'}</div>${shingi ? `<div class="tip" style="color:var(--warn);font-size:12px;margin-top:4px">${shingi}</div>` : ''}`;

  // 騎乗評価
  const m = p.m, rv = [];
  const sS = m.startKind === '好スタート' ? 100 : m.startKind === '五分' ? 80 : m.startKind === 'やや出遅れ' ? 50 : 20;
  rv.push(['スタート', sS, `${m.startKind}${m.startDelay ? `（反応 ${m.startDelay.toFixed(2)}秒）` : ''}`]);
  const avgAr = m.arT > 1 ? m.arSum / m.arT : 0;
  if (m.arT > 5) rv.push(['折り合い', clamp(100 - Math.max(0, avgAr - 0.12) * 190, 0, 100), avgAr < 0.2 ? '終始リラックスして運べた' : avgAr < 0.4 ? '行きたがる場面があった' : '掛かり通しで消耗した']);
  const avgD = m.ang > 0.2 ? (p.dist - p.s) / m.ang : 0;
  rv.push(['コース取り', clamp(100 - (avgD - 1.6) * 8, 0, 100), `距離ロス +${Math.max(0, p.dist - p.s).toFixed(1)}m（コーナー平均 ラチから${avgD.toFixed(1)}m）`]);
  if (m.cruiseT > 5) rv.push(['風除け', clamp((m.draftT / m.cruiseT) * 125, 0, 100), `道中の ${Math.round((m.draftT / m.cruiseT) * 100)}% を他馬の後ろで温存`]);
  let sP, tP;
  if (m.emptyRem > 25) { sP = clamp(100 - m.emptyRem * 0.55, 0, 100); tP = `残り${Math.round(m.emptyRem)}mで脚が上がった（仕掛けが早い／前半飛ばしすぎ）`; }
  else { sP = clamp(100 - m.eFin * 4.5, 0, 100); tP = m.eFin < 4 ? 'スタミナをきっちり使い切った' : `余力を${Math.round(m.eFin)}%残してゴール（脚を余した）`; }
  rv.push(['ペース配分', sP, tP]);
  rv.push(['手前替え', { 完璧: 100, 良: 78, 遅れ: 45, 馬任せ: 25 }[m.leadKind] ?? 25, m.leadKind || '行わなかった']);
  if (p.whipN) rv.push(['ムチ', clamp((m.whipGood / p.whipN) * 110 + 10 - Math.max(0, p.whipN - 14) * 5, 0, 100), `${p.whipN}発中 ${m.whipGood}発が完歩にぴったり`]);
  let total = rv.reduce((a, b) => a + b[1], 0) / rv.length - m.bumps * 4 - (m.foul >= 2.2 ? 20 : m.foul > 0.6 ? 6 : 0) - Math.min(15, m.blockedT * 1.5);
  total = clamp(total, 0, 100);
  const grade = total >= 88 ? 'S' : total >= 76 ? 'A' : total >= 62 ? 'B' : total >= 48 ? 'C' : 'D';
  const extra = [];
  if (m.blockedT > 1.5) extra.push(`前が壁になった時間 ${m.blockedT.toFixed(1)}秒`);
  if (m.bumps) extra.push(`接触 ${m.bumps}回`);
  $('res-review').innerHTML = rv.map(([k, s, t]) => `<div class="rv"><span>${k}</span><div class="bar"><i style="width:${s}%"></i></div><span>${Math.round(s)}</span><em>${t}</em></div>`).join('') +
    (extra.length ? `<div style="color:var(--warn);margin-top:4px">${extra.join(' ／ ')}</div>` : '') + `<div class="total">騎乗評価<b>${grade}</b></div>`;

  $('res-table').innerHTML = '<thead><tr><th>着</th><th>馬番</th><th>馬名</th><th>騎手</th><th>タイム</th><th>着差</th><th>上がり</th><th>脚質</th><th>人気</th></tr></thead><tbody>' +
    fo.map((r, i) => `<tr class="${r.isPlayer ? 'me' : ''}"><td>${i + 1}</td><td>${wakuTag(r.h)}</td><td class="nm">${r.h.name}</td><td>${r.isPlayer ? 'あなた' : r.h.jockey}</td>
      <td>${fmtTime(r.ft)}</td><td>${i === 0 ? '' : marginText(Math.abs(r.ft - fo[i - 1].ft) * 17)}</td><td>${r.last3f.toFixed(1)}</td><td>${STYLES[r.h.style]}</td><td>${r.h.pop}</td></tr>`).join('') + '</tbody>';
  $('res-laps').innerHTML = `ラップ: ${race.splits.map((s) => s.toFixed(1)).join(' - ')}${G.flags.pace ? `　(${G.flags.pace})` : ''}<br>勝ち馬 ${win.h.name}（${STYLES[win.h.style]}・${win.h.pop}番人気） ${fmtTime(win.ft)}`;
  sound.silence(); sound.intensity = 0; sound.play(pos === 1 ? 'title' : 'paddock');
  $('h-coach').classList.add('hidden');
  G.mode = 'result'; show('result');
}

// ---- メインループ ----
let last = performance.now();
function inputNow() {
  const t = G.race.track.t;
  const steerScreen = (keys.right ? 1 : 0) - (keys.left ? 1 : 0);
  return { drive: keys.up ? 1 : keys.down ? -1 : 0, steer: steerScreen * (t < 0 ? 1 : -1), whip: edge.whip, lead: edge.lead, go: edge.go };
}
function stepSim(dt, withInput) {
  const race = G.race; G.acc += dt; let n = 0;
  while (G.acc >= 1 / 60 && n++ < 5) {
    race.step(1 / 60, withInput ? inputNow() : null);
    edge.whip = edge.lead = edge.go = false; G.acc -= 1 / 60;
  }
  if (n >= 5) G.acc = 0;
}
function audioFrame() {
  const race = G.race, tr = race.track, cond = race.cfg.cond;
  if (G.mode === 'attract' || G.mode === 'result') { // タイトル・結果画面: 場内のざわめきだけ
    sound.update({ crowd: 0.16, roar: 0, wind: 0, rain: cond.weather >= 2 ? 0.3 : 0, rumble: 0, speed: 0, phase: 0, effort: 0 });
    return;
  }
  const p = race.player || race.order[0];
  const rem = race.D - race.order[0].s;
  const u = p.s >= tr.chute ? tr.uOf(p.s) : -1;
  const nearStand = u >= 0 && u < tr.L ? 1 : 0.22;       // スタンド前は歓声が近い
  const hot = race.state === 'run' && rem < tr.straight + 120 && race.finishOrder.length < 4 ? 1 : 0;
  const build = race.state === 'run' ? clamp(1 - rem / (tr.straight + 500), 0, 1) : 0;   // 直線に向けて徐々に高まる
  // 周囲の馬: 近い順に12頭まで (馬群の足音・息づかい)
  const near = [];
  for (const r of race.runners) {
    if (r === p || !r.started) continue;
    const ds = r.s - p.s, dd = r.d - p.d, dist = Math.hypot(ds, dd);
    if (dist < 45) near.push({ id: r.i, phase: r.phase, dist, side: clamp((dd * (tr.t < 0 ? 1 : -1)) / 5, -0.9, 0.9), v: r.fin && r.v < 6 ? 0 : r.v });
  }
  near.sort((a, b) => a.dist - b.dist); near.length = Math.min(near.length, 12);
  const effort = clamp((p.v - 13) / 6, 0, 1) * 0.5 + (p.pushing ? 0.3 : 0) + (p.E < 15 ? 0.3 : 0);
  sound.update({
    crowd: (race.state === 'gate' ? 0.75 : 0.3 + build * 0.3) * (0.5 + nearStand * 0.5) + hot * 0.25,
    roar: hot * (0.45 + nearStand * 0.55) * (1 + (race.order.length > 1 && race.order[0].s - race.order[1].s < 2.5 ? 0.35 : 0)) + build * 0.12 * nearStand,
    wind: clamp(p.v / 19, 0, 1), rain: cond.weather >= 2 ? (cond.weather === 3 ? 1 : 0.5) : 0,
    rumble: 0, speed: p.fin && p.v < 6 ? 0 : p.v, phase: p.phase, wet: cond.going >= 2, effort, near,
    echo: nearStand === 1 ? 1 : 0, gate: race.state === 'gate',
  });
}
function frame(now) {
  requestAnimationFrame(frame);
  const rawDt = Math.min(1, (now - last) / 1000), dt = Math.min(0.1, rawDt); last = now;
  if (G.paused || !G.race) return;
  const race = G.race;
  if (G.toastT > 0) { G.toastT -= dt; if (G.toastT <= 0) $('h-toast').classList.remove('on'); }
  switch (G.mode) {
    case 'attract': {
      stepSim(dt, false); race.events.length = 0;
      G.attractT += dt; if (G.attractT > 9) { G.attractT = 0; G.attractCam = G.attractCam === 2 ? 3 : G.attractCam === 3 ? 0 : 2; venue.snap = true; }
      const focus = race.order[Math.min(2, race.order.length - 1)];
      venue.frame(dt, { cam: G.attractCam, focus }); audioFrame();
      if (race.state === 'done' || race.finishOrder.length > 3) startAttract();
      break;
    }
    case 'result':
      venue.frame(dt, { cam: 4, focus: race.order[0] }); audioFrame();
      break;
    case 'intro':
      G.introT += rawDt; // ファンファーレ(実時間)と映像を合わせる
      venue.introCam(G.introT, G.introDur);
      venue.frame(dt, { intro: true });
      if (G.introT >= G.introDur) toGate();
      break;
    case 'gate':
      race.step(dt, inputNow()); edge.go = edge.whip = edge.lead = false;
      handleEvents();
      G.gateT -= dt;
      if (G.gateT <= 0) {
        race.openGate(); sound.gate(); G.mode = 'race'; G.acc = 0;
        const gm = $('h-gate'); G.gateMsgT = 0;
        if (race.falseStart) gm.innerHTML = '<div class="sig bad">あおった</div><div class="g1">早押しで出遅れ…</div><div class="g2">次は緑を見てから押す</div>';
        else gm.innerHTML = `<div class="sig green">GO!</div><div class="g1">今だ！ ${kbd('go')}</div><div class="rbar"><i id="rb-i"></i></div><div class="rbar-l"><span>好スタート</span><span>五分</span><span>出遅れ</span></div>`;
        if (sound.raceBgm) { sound.intensity = 0; sound.play('race'); }
      }
      updateHud(dt); audioFrame(); updateCoach(dt);
      venue.frame(dt);
      break;
    case 'race':
    case 'finish':
      stepSim(dt, G.mode === 'race');
      handleEvents();
      if (G.mode === 'race') commentary();
      if (G.gateMsgT > 0) { G.gateMsgT -= dt; if (G.gateMsgT <= 0) $('h-gate').classList.add('hidden'); }
      else if (race.player.waitPress) { const rb = $('rb-i'); if (rb) rb.style.left = clamp(race.t / 0.8, 0, 1) * 100 + '%'; }
      updateCoach(dt);
      {
        const rem = race.D - race.player.s;
        sound.intensity = rem < race.track.straight + 80 ? 2 : race.t > 14 ? 1 : 0;
      }
      updateHud(dt); audioFrame();
      venue.frame(dt);
      if (G.mode === 'finish') { G.finT += dt; if (G.finT > 5.5 || race.state === 'done') showResult(); }
      break;
  }
}

// ---- 入力 ----
const KEYMAP = { ArrowUp: 'up', KeyW: 'up', ArrowDown: 'down', KeyS: 'down', ArrowLeft: 'left', KeyA: 'left', ArrowRight: 'right', KeyD: 'right' };
function press(k) {
  if (k === 'whip') { const pl = G.race && G.race.player; if (pl && pl.started) edge.whip = true; else edge.go = true; } // 発走前はスタート、発走後はムチ
  else if (k === 'lead') edge.lead = true;
  else { keys[k] = true; if (k === 'up' && isTouch) edge.go = true; }
}
window.addEventListener('keydown', (e) => {
  if (e.repeat) { if (KEYMAP[e.code] || e.code === 'Space') e.preventDefault(); return; }
  const inRace = G.mode === 'gate' || G.mode === 'race' || G.mode === 'finish';
  if (KEYMAP[e.code]) { keys[KEYMAP[e.code]] = true; if (inRace) e.preventDefault(); }
  else if (e.code === 'Space' || e.code === 'Enter') { if (G.mode === 'intro') toGate(); else if (inRace) press('whip'); if (inRace || G.mode === 'intro') e.preventDefault(); }
  else if (e.code === 'ShiftLeft' || e.code === 'ShiftRight' || e.code === 'KeyE') press('lead');
  else if (e.code === 'KeyC' && inRace) cycleCam();
  else if ((e.code === 'KeyP' || e.code === 'Escape') && inRace) togglePause();
});
window.addEventListener('keyup', (e) => { if (KEYMAP[e.code]) keys[KEYMAP[e.code]] = false; });
window.addEventListener('blur', () => { keys.up = keys.down = keys.left = keys.right = false; });
for (const b of document.querySelectorAll('#touch button')) {
  const k = b.dataset.k;
  const down = (e) => { e.preventDefault(); b.classList.add('on'); press(k); };
  const up = (e) => { e.preventDefault(); b.classList.remove('on'); if (keys[k] !== undefined) keys[k] = false; };
  b.addEventListener('pointerdown', down); b.addEventListener('pointerup', up); b.addEventListener('pointercancel', up); b.addEventListener('pointerleave', up);
  b.addEventListener('contextmenu', (e) => e.preventDefault());
}
function cycleCam() { venue.camMode = (venue.camMode + 1) % 4; toast(['後方視点', '騎手視点', '中継カメラ', '俯瞰視点'][venue.camMode]); }
function togglePause() {
  G.paused = !G.paused; overlay('pause', G.paused);
  if (G.paused) { sound.silence(); sound.hush(); if (sound.ctx) sound.ctx.suspend(); } else { sound.unlock(); last = performance.now(); }
}
function toTitle() {
  if (sound.ctx) sound.ctx.resume();
  G.paused = false; overlay('pause', false); sound.hush(); sound.silence(); sound.intensity = 0;
  startAttract(); show('title'); sound.play('title');
}

// ---- ボタン ----
// ブラウザは操作なしに音を出せないため、あらゆる操作のたびに音声の起動を試みる
function soundStatus() {
  const el = $('snd-status'); if (!el) return;
  el.textContent = sound.running ? '🔊 サウンド ON（聞こえない場合は端末の音量を上げてください）' : '🔇 画面をタップ / クリックするとサウンドが始まります';
  el.classList.toggle('on', sound.running);
}
const gesture = () => {
  const was = sound.running; sound.unlock();
  if (!G.paused && !sound.song && !sound.pending && G.mode === 'attract') sound.play('title');
  if (!was) setTimeout(soundStatus, 250);
};
for (const ev of ['pointerdown', 'pointerup', 'touchend', 'click', 'keydown']) window.addEventListener(ev, gesture, true);
sound.play('title'); // 起動後、最初の操作で鳴り始める
setInterval(soundStatus, 1500);
$('btn-start').onclick = () => { sound.unlock(); sound.select(); sound.play('paddock'); renderRaces(); show('select'); };
$('btn-how').onclick = () => { sound.click(); overlay('how', true); };
$('btn-how-close').onclick = () => overlay('how', false);
$('btn-opt').onclick = () => { sound.init(); overlay('opt', true); };
$('btn-opt-close').onclick = () => overlay('opt', false);
$('o-music').onchange = (e) => { sound.init(); sound.setMusic(e.target.checked); };
$('o-racebgm').onchange = (e) => { sound.raceBgm = e.target.checked; };
$('o-sfx').onchange = (e) => { sound.sfxOn = e.target.checked; };
for (const k of ['master', 'music', 'sfx']) $('v-' + k).oninput = (e) => { sound.unlock(); sound.setVolume(k, +e.target.value / 100); };
$('btn-sndtest').onclick = () => { sound.unlock(); sound.confirm(); setTimeout(() => sound.cheer(0.8, 2.5), 300); setTimeout(soundStatus, 300); };
$('o-coach').onchange = (e) => { G.coachOn = e.target.checked; };
{
  let q = isTouch ? 1 : 2;
  try { const sv = localStorage.getItem('turfjockey.quality'); if (sv !== null) q = +sv; } catch (e) { /* noop */ }
  venue.setQuality(q); $('o-quality').value = String(q);
  $('o-quality').onchange = (e) => { venue.setQuality(+e.target.value); try { localStorage.setItem('turfjockey.quality', e.target.value); } catch (er) { /* noop */ } };
}
for (const b of document.querySelectorAll('[data-back]')) b.onclick = () => { sound.click(); G.oddsToken = 0; if (b.dataset.back === 'title') sound.play('title'); show(b.dataset.back); };
$('btn-go').onclick = () => { sound.unlock(); sound.confirm(); startRace(); };
$('btn-skip').onclick = () => { if (G.mode === 'intro') toGate(); };
$('btn-cam').onclick = cycleCam;
$('btn-pause').onclick = togglePause;
$('btn-resume').onclick = togglePause;
$('btn-retire').onclick = toTitle;
$('btn-again').onclick = () => { sound.click(); show('none'); startRace(); };
$('btn-next').onclick = () => { sound.click(); sound.play('paddock'); startAttract(); renderRaces(); show('select'); };
window.addEventListener('resize', () => venue.resize());
document.addEventListener('visibilitychange', () => { if (document.hidden && (G.mode === 'race' || G.mode === 'gate') && !G.paused) togglePause(); });

// ---- 起動 ----
renderCareer();
show('title');
loading(true, '馬と騎手のモデルを読み込んでいます…');
loadAssets().then(() => { loading(false); startAttract(); requestAnimationFrame(frame); })
  .catch((e) => { $('loading-text').textContent = 'モデルの読み込みに失敗しました: ' + e.message; });
window.__game = { G, venue, sound, keys, edge }; // デバッグ・自動テスト用
