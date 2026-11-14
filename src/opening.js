// オープニング演出(見た目だけ)。Race とその艇には一切書き込まない。
// 待機行動: ピットを出て、スタンド寄りを東へ → 右へUターン → バックストレッチを西へ(2マークの南側)
// → 右へUターン(1〜3コースは2マークのすぐ西、4〜6コースはもっと西)→ 自分のコースに入って東へ進み、スタート前の位置に止まる。
// カメラは自艇の後ろ(main.js 側で追う)。経路はマーク・消波装置・ほかの艇と十分離れる(tools/opening-test.mjs)
import { M2, MARK_UNITS } from './sim/course.js';

const clamp01 = (x) => Math.max(0, Math.min(1, x));
export const PIT_X = -261.8;                       // ピットの前(桟橋の端のすぐ外)
export const pitZ = (i) => -12 + i * 10;           // 艇番表示の真下(柱の間)
const LANE_A = 30;                                 // スタンド寄りを東へ進む時の z
const U1 = { x: -110, r: 21 };                     // 1回目のUターン(2マークの浮きの東端から20m以上東)
const BACK_Z = LANE_A - 2 * U1.r;                  // バックストレッチを戻る時の z(= -12)
const u2x = (i) => (i < 3 ? -178 : -212);          // 2回目のUターンを始める x(スロー: 2マークのすぐ西 / ダッシュ: もっと西)

// 艇 i の通り道を、2m ごとの点の列にする(目標の位置・向き g まで)
function buildRoute(i, g, short) {
  const pts = [[PIT_X, pitZ(i)]];
  const push = (x, z) => pts.push([x, z]);
  if (short) {      // 短い版(グランプリ2走目から): 自分のコースの60m後ろからまっすぐ
    pts[0] = [g.x - 60, g.z];
    for (let x = g.x - 58; x < g.x; x += 2) push(x, g.z);
    push(g.x, g.z);
    const cum = [0]; for (let k = 1; k < pts.length; k++) cum.push(cum[k - 1] + Math.hypot(pts[k][0] - pts[k - 1][0], pts[k][1] - pts[k - 1][1]));
    return { pts, cum, len: cum[cum.length - 1], u2: 0 };
  }
  // ピットを出て、スタンド前の線(z = LANE_A)へなめらかに寄せる
  const x0 = PIT_X, x1 = -150, z0 = pitZ(i);
  for (let k = 1; k <= 60; k++) { const t = k / 60, s = t * t * (3 - 2 * t); push(x0 + (x1 - x0) * t, z0 + (LANE_A - z0) * s); }
  for (let x = x1 + 2; x <= U1.x; x += 2) push(x, LANE_A);
  // 1回目のUターン(右回り: 東 → 南 → 西)
  const c1 = LANE_A - U1.r;
  for (let k = 1; k <= 48; k++) { const a = Math.PI / 2 - Math.PI * k / 48; push(U1.x + U1.r * Math.cos(a), c1 + U1.r * Math.sin(a)); }
  const U2X = u2x(i);
  for (let x = U1.x - 2; x > U2X; x -= 2) push(x, BACK_Z);
  push(U2X, BACK_Z); const u2 = pts.length - 1;
  // 2回目のUターン(右回り: 西 → 北 → 東)。自分のコースの z に出る
  const r2 = (g.z - BACK_Z) / 2, c2 = BACK_Z + r2, n2 = Math.max(16, Math.ceil(Math.PI * r2 / 2));
  for (let k = 1; k <= n2; k++) { const a = -Math.PI / 2 - Math.PI * k / n2; push(U2X + r2 * Math.cos(a), c2 + r2 * Math.sin(a)); }
  for (let x = U2X + 2; x < g.x; x += 2) push(x, g.z);
  push(g.x, g.z);
  // 道のりの累計
  const cum = [0];
  for (let k = 1; k < pts.length; k++) cum.push(cum[k - 1] + Math.hypot(pts[k][0] - pts[k - 1][0], pts[k][1] - pts[k - 1][1]));
  return { pts, cum, len: cum[cum.length - 1], u2 };
}
// 道のり s の位置
function at(route, s) {
  const { pts, cum } = route;
  if (s <= 0) return pts[0];
  if (s >= route.len) return pts[pts.length - 1];
  let lo = 0, hi = cum.length - 1;
  while (hi - lo > 1) { const m = (lo + hi) >> 1; if (cum[m] <= s) lo = m; else hi = m; }
  const f = (s - cum[lo]) / (cum[hi] - cum[lo] || 1);
  return [pts[lo][0] + (pts[hi][0] - pts[lo][0]) * f, pts[lo][1] + (pts[hi][1] - pts[lo][1]) * f];
}

export class Opening {
  constructor(race, short = false) {
    this.short = short;
    this.intro = short ? 0.5 : 5;                  // ピットで待つ時間(出走表を出す)
    this.stagger = short ? 0.1 : 0.8;              // 1号艇から順に出る間隔(着くのも同じ間隔)
    this.travel = short ? 8 : 27;                  // 各艇がピットを出てからスタート位置に着くまで
    this.duration = this.intro + this.travel + this.stagger * 5 + 1;
    this.elapsed = 0;
    this.targets = race.boats.map((b) => ({ x: b.x, z: b.z, h: b.h }));
    this.routes = this.targets.map((g, i) => buildRoute(i, g, short));
    // 短い版(グランプリ2走目から)は、2回目のUターンの手前から走り出す
    this.from = this.routes.map(() => 0);
    this.boats = race.boats.map((b) => ({ ...b }));
    this.audioBoats = this.boats.map((b) => ({ ...b }));
    this.race = { ...race, boats: this.boats, order: this.boats };
    this.playerIndex = race.playerIndex >= 0 ? race.playerIndex : 0;
    this.prevH = this.targets.map(() => 0);
    this.sample(0, 0);
  }
  advance(dt) { this.elapsed = Math.min(this.duration, this.elapsed + dt); this.sample(this.elapsed, dt); return this.elapsed >= this.duration; }
  // 艇 i の時刻 time での道のり。走り出しは加速、最後の25%で減速して止まる(短い版は走っている所から)
  dist(i, time) {
    const T = this.travel, t = clamp01((time - this.intro - i * this.stagger) / T) * T;
    const L = this.routes[i].len - this.from[i], ta = this.short ? 0 : T * 0.1, td = T * 0.2;
    const V = L / (T - ta / 2 - td / 2);
    let s;
    if (t < ta) s = V * t * t / (2 * ta);
    else if (t < T - td) s = V * (t - ta / 2);
    else s = L - V * (T - t) * (T - t) / (2 * td);
    return { u: t / T, s: this.from[i] + Math.min(L, s), v: t <= 0 || t >= T ? 0 : t < ta ? V * t / ta : t < T - td ? V : V * (T - t) / td };
  }
  pos(i, time) { const d = this.dist(i, time), p = at(this.routes[i], d.s); return { u: d.u, x: p[0], z: p[1], v: d.v }; }
  sample(time, dt) {
    for (let i = 0; i < 6; i++) {
      const b = this.boats[i], g = this.targets[i], p = this.pos(i, time);
      const q = at(this.routes[i], this.dist(i, time).s + 0.6);
      const dx = q[0] - p.x, dz = q[1] - p.z;
      const done = p.u >= 1, moving = p.v > 0.05 && !done;
      b.x = done ? g.x : p.x; b.z = done ? g.z : p.z;
      const h = done ? g.h : Math.hypot(dx, dz) > 1e-4 ? Math.atan2(dz, dx) : this.prevH[i];
      let dh = h - this.prevH[i]; while (dh > Math.PI) dh -= 2 * Math.PI; while (dh < -Math.PI) dh += 2 * Math.PI;
      b.w = dt > 0 && moving ? dh / dt : 0;          // 旋回の速さ(艇を傾ける・しぶきを出すのに使う)
      b.h = h; this.prevH[i] = h;
      b.speed = moving ? p.v : 0;
      b.vx = Math.cos(b.h) * b.speed; b.vz = Math.sin(b.h) * b.speed;
      b.vf = b.speed; b.throttle = moving ? Math.min(0.7, 0.15 + b.speed / 25) : 0;
      b.af = 0; b.turnInt = Math.min(1, Math.abs(b.w) * b.speed / 14); b.bump = 0; b.steer = Math.max(-1, Math.min(1, -b.w * 0.8));
      // 音: 走っている艇は回転を上げるが、曲を消さないよう控えめに
      Object.assign(this.audioBoats[i], b, { speed: Math.min(b.speed, 9), throttle: moving ? 0.25 : 0 });
    }
  }
  get phase() { return this.elapsed < this.intro ? '選手紹介' : this.elapsed < this.intro + (this.short ? 1 : 8) ? 'ピット離れ' : '待機行動'; }
  // 経路の安全確認(テスト用): 2マーク・消波装置・ほかの艇との最小距離、いちばん速い時の速さ
  clearance() {
    let obst = 99, boat = 99, vmax = 0;
    for (let t = 0; t <= this.duration; t += 1 / 30) {
      const ps = this.targets.map((_, i) => this.pos(i, t));
      for (let i = 0; i < 6; i++) {
        vmax = Math.max(vmax, ps[i].v);
        obst = Math.min(obst, Math.hypot(ps[i].x - M2.x, ps[i].z - M2.z));
        for (const u of MARK_UNITS) for (let k = -u.len / 2; k <= u.len / 2; k += 0.5) obst = Math.min(obst, Math.hypot(ps[i].x - (u.x + u.dx * k), ps[i].z - (u.z + u.dz * k)));
        for (let j = i + 1; j < 6; j++) boat = Math.min(boat, Math.hypot(ps[i].x - ps[j].x, ps[i].z - ps[j].z));
      }
    }
    return { obst, boat, vmax };
  }
}
