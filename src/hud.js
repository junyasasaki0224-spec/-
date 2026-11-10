// HUD: 順位・周回・前後との差・速度計・ミニマップ・大時計・風・テロップ・レンズの水滴。
import { BOAT_CSS, BOAT_TEXT_CSS } from './gfx/common.js';
import { BOUNDS, M1, M2, LAPS } from './sim/course.js';
import { windLabel } from './sim/roster.js';

const $ = (id) => document.getElementById(id);
export const fmtTime = (t) => {
  if (!t || t <= 0) return '—';
  const m = Math.floor(t / 60), s = t - m * 60;
  return `${m}'${String(Math.floor(s)).padStart(2, '0')}"${Math.floor((s % 1) * 10)}`;
};
export const chip = (i) => `<span class="chip" style="background:${BOAT_CSS[i]};color:${BOAT_TEXT_CSS[i]}">${i + 1}</span>`;

export class Hud {
  constructor() {
    this.el = $('hud');
    this.posN = $('pos-n'); this.lap = $('lap'); this.time = $('time'); this.gap = $('gap');
    this.rank = $('rank'); this.spd = $('spd'); this.thr = $('thr-bar'); this.spdBar = $('spd-bar');
    this.mini = $('minimap'); this.mctx = this.mini.getContext('2d');
    this.startbox = $('startbox'); this.hclock = $('hclock'); this.cctx = this.hclock.getContext('2d');
    this.cd = $('cd'); this.dist = $('dist'); this.assist = $('assist'); this.assistM = $('assist-m'); this.assistT = $('assist-t');
    this.msg = $('msg'); this.ticker = $('ticker'); this.warn = $('warn'); this.lift = $('lift');
    this.wx = $('wx'); this.wxArrow = $('wx-arrow'); this.wxText = $('wx-text');
    this.fx = $('fx'); this.fctx = this.fx.getContext('2d');
    this.msgT = 0; this.tickT = 0; this.rankT = 0; this.rankKey = ''; this.gapT = 0;
    this.drops = [];
    this.resize();
  }

  resize() {
    this.fx.width = Math.floor(window.innerWidth / 2); this.fx.height = Math.floor(window.innerHeight / 2);
  }

  show(v, replay = false) {
    this.el.classList.toggle('hidden', !v);
    this.el.classList.toggle('replay', replay);
    if (!v) { this.msg.className = ''; this.ticker.className = ''; this.warn.className = ''; this.lift.className = ''; }
    this.rankKey = '';
  }

  setWeather(w) {
    this.wxText.textContent = `${windLabel(w)}　波 ${w.wave}cm`;
    // 矢印: ホームストレッチの進行方向(画面右)を基準にした風下の向き
    this.wxArrow.style.transform = `rotate(${w.windDir}rad)`;
    this.wxArrow.style.opacity = w.wind < 0.5 ? 0.25 : 1;
  }

  message(text, sub = '', dur = 2.2, cls = '') {
    this.msg.innerHTML = `<b>${text}</b>${sub ? `<span>${sub}</span>` : ''}`;
    this.msg.className = 'show ' + cls; this.msgT = dur;
  }
  say(text, dur = 3) { this.ticker.textContent = text; this.ticker.className = 'show'; this.tickT = dur; }

  addDrops(n, strong = false) {
    const w = this.fx.width, h = this.fx.height;
    for (let i = 0; i < n && this.drops.length < 70; i++) {
      this.drops.push({ x: Math.random() * w, y: Math.random() * h * (strong ? 1 : 0.8), r: (2 + Math.random() * (strong ? 9 : 5)) * (w / 700), vy: 10 + Math.random() * 50, life: 0.8 + Math.random() * 1.4, max: 2.2 });
    }
  }

  // target: HUD の主役にする艇(自艇、リプレイ中は追っている艇)
  update(dt, race, target, opts) {
    if (this.msgT > 0 && (this.msgT -= dt) <= 0) this.msg.className = '';
    if (this.tickT > 0 && (this.tickT -= dt) <= 0) this.ticker.className = '';
    this._drops(dt);
    if (!target) return;

    this.spd.textContent = Math.round(target.speed * 3.6);
    this.spdBar.style.width = `${Math.min(100, target.speed / 23.5 * 100)}%`;
    this.thr.style.height = `${target.throttle * 100}%`;
    this.posN.textContent = target.started ? target.rank : '–';
    this.posN.parentElement.dataset.p = target.started ? target.rank : 0;
    this.lap.textContent = target.started ? `${Math.min(LAPS, target.lap + 1)} / ${LAPS} 周` : 'スタート前';
    this.time.textContent = race.clock > 0 ? fmtTime(target.finished ? target.finishTime : race.clock) : `0'00"0`;
    this.warn.className = target.offCourse && !target.finished && !opts.replay ? 'show' : '';
    this.lift.className = opts.guide && target.advice && target.advice.lift && target.started && !target.finished && target.throttle > 0.5 ? 'show' : '';

    // 順位表と前後の差
    this.rankT -= dt;
    if (this.rankT <= 0) {
      this.rankT = 0.25;
      const key = race.order.map((b) => b.i).join('') + race.order.map((b) => (b.finished ? 'f' : b.flying ? 'x' : '')).join('') + target.i;
      if (key !== this.rankKey) {
        this.rankKey = key;
        this.rank.innerHTML = race.order.map((b, k) => `<div class="row${b === target ? ' me' : ''}"><em>${b.flying ? 'F' : k + 1}</em>${chip(b.i)}<span>${b.racer.name}</span></div>`).join('');
      }
      let g = '';
      if (target.started && !target.finished && !target.flying && race.mode !== 'practice') {
        const k = target.rank - 1, v = Math.max(target.speed, 8);
        const ahead = k > 0 ? race.order[k - 1] : null, behind = k < 5 ? race.order[k + 1] : null;
        if (ahead && !ahead.flying) g += `<span class="up">前 ${chip(ahead.i)} ${ahead.finished ? 'ゴール' : '+' + ((ahead.R - target.R) / v).toFixed(1) + '秒'}</span>`;
        if (behind && !behind.flying && behind.started) g += `<span class="dn">後 ${chip(behind.i)} -${((target.R - behind.R) / v).toFixed(1)}秒</span>`;
      }
      this.gap.innerHTML = g;
    }

    // スタート前: 大時計と起こしの目安
    const pre = !target.started;
    this.startbox.classList.toggle('hidden', !pre);
    this.el.classList.toggle('pre', pre);
    if (pre) {
      const t = race.clock;
      this._clock(t);
      this.cd.textContent = t < 0 ? `スタートまで ${(-t).toFixed(1)}` : `+${t.toFixed(2)}`;
      this.cd.classList.toggle('hot', t > -3);
      this.dist.textContent = `スタートラインまで ${Math.max(0, -target.x).toFixed(0)} m`;
      const showAssist = opts.assist && !opts.replay;
      this.assist.classList.toggle('hidden', !showAssist);
      if (showAssist) {
        const st = race.predictST(target);
        const p = Math.max(0, Math.min(1, (st + 0.5) / 1.5));          // バーの範囲: -0.5 〜 +1.0 秒
        this.assistM.style.left = `${p * 100}%`;
        this.assistT.textContent = st < 0 ? `全開だと ${(-st).toFixed(2)}秒 早い(フライング)` : st < 0.25 ? `今だ！ 全開で ST ${st.toFixed(2)}` : `全開で ST ${st.toFixed(2)}`;
        this.assistT.className = st < 0 ? 'bad' : st < 0.25 ? 'good' : '';
      }
    }
    this._minimap(race, target);
  }

  _clock(t) {
    const c = this.cctx, w = this.hclock.width, r = w / 2;
    c.clearRect(0, 0, w, w);
    c.fillStyle = '#fbfbf6'; c.beginPath(); c.arc(r, r, r - 3, 0, 7); c.fill();
    c.fillStyle = 'rgba(40,180,90,0.45)'; c.beginPath(); c.moveTo(r, r); c.arc(r, r, r - 12, -Math.PI / 2, -Math.PI / 2 + Math.PI / 6); c.closePath(); c.fill();
    c.strokeStyle = '#111'; c.lineWidth = 5; c.beginPath(); c.arc(r, r, r - 4, 0, 7); c.stroke();
    for (let i = 0; i < 12; i++) {
      const a = i / 12 * Math.PI * 2;
      c.lineWidth = i === 0 ? 6 : 3; c.beginPath();
      c.moveTo(r + Math.sin(a) * (r - 8), r - Math.cos(a) * (r - 8)); c.lineTo(r + Math.sin(a) * (r - 24), r - Math.cos(a) * (r - 24)); c.stroke();
    }
    c.fillStyle = '#111'; c.font = `900 ${Math.round(w * 0.11)}px sans-serif`; c.textAlign = 'center'; c.textBaseline = 'middle';
    for (const i of [0, 3, 6, 9]) { const a = i / 12 * Math.PI * 2; c.fillText(String(i), r + Math.sin(a) * (r - 40), r - Math.cos(a) * (r - 40)); }
    const a = (t / 12) * Math.PI * 2;               // 12秒針: 0秒で真上
    c.strokeStyle = '#f4a300'; c.lineWidth = 7; c.lineCap = 'round'; c.beginPath();
    c.moveTo(r - Math.sin(a) * 12, r + Math.cos(a) * 12); c.lineTo(r + Math.sin(a) * (r - 18), r - Math.cos(a) * (r - 18)); c.stroke();
    c.fillStyle = '#222'; c.beginPath(); c.arc(r, r, 7, 0, 7); c.fill();
  }

  _minimap(race, player) {
    const c = this.mctx, w = this.mini.width, h = this.mini.height, B = BOUNDS;
    const sx = w / (B.maxX - B.minX), sz = h / (B.maxZ - B.minZ);
    const X = (x) => (x - B.minX) * sx, Z = (z) => (z - B.minZ) * sz;
    c.clearRect(0, 0, w, h);
    c.fillStyle = 'rgba(8,40,60,0.72)'; c.beginPath(); c.roundRect(0, 0, w, h, 10); c.fill();
    c.strokeStyle = 'rgba(255,255,255,0.55)'; c.lineWidth = 1.5; c.stroke();
    c.strokeStyle = 'rgba(255,255,255,0.7)'; c.setLineDash([4, 3]); c.beginPath(); c.moveTo(X(0), Z(4)); c.lineTo(X(0), Z(B.maxZ)); c.stroke(); c.setLineDash([]);
    for (const m of [M1, M2]) { c.fillStyle = '#ff4b3e'; c.beginPath(); c.arc(X(m.x), Z(m.z), 4, 0, 7); c.fill(); c.strokeStyle = '#fff'; c.lineWidth = 1; c.stroke(); }
    for (const b of race.boats) {
      if (b === player) continue;
      c.fillStyle = BOAT_CSS[b.i]; c.strokeStyle = '#fff'; c.lineWidth = 1;
      c.beginPath(); c.arc(X(b.x), Z(b.z), 4.5, 0, 7); c.fill(); c.stroke();
    }
    const px = X(player.x), pz = Z(player.z);
    c.save(); c.translate(px, pz); c.rotate(player.h);
    c.fillStyle = BOAT_CSS[player.i]; c.strokeStyle = '#ffe14d'; c.lineWidth = 2.5;
    c.beginPath(); c.moveTo(9, 0); c.lineTo(-6, -5.5); c.lineTo(-6, 5.5); c.closePath(); c.fill(); c.stroke();
    c.restore();
  }

  // カメラレンズに付く水滴
  _drops(dt) {
    const c = this.fctx, w = this.fx.width, h = this.fx.height;
    if (!this.drops.length && !this._dirty) return;
    c.clearRect(0, 0, w, h);
    this._dirty = this.drops.length > 0;
    for (let i = this.drops.length - 1; i >= 0; i--) {
      const d = this.drops[i];
      d.life -= dt; d.y += d.vy * dt * (d.r / 6);
      if (d.life <= 0 || d.y > h + 20) { this.drops.splice(i, 1); continue; }
      const a = Math.min(1, d.life / 0.6) * 0.5;
      const g = c.createRadialGradient(d.x - d.r * 0.3, d.y - d.r * 0.3, d.r * 0.1, d.x, d.y, d.r);
      g.addColorStop(0, `rgba(255,255,255,${a})`); g.addColorStop(0.6, `rgba(210,232,245,${a * 0.35})`); g.addColorStop(1, `rgba(255,255,255,${a * 0.6})`);
      c.fillStyle = g; c.beginPath(); c.ellipse(d.x, d.y, d.r, d.r * 1.25, 0, 0, 7); c.fill();
    }
  }
}
