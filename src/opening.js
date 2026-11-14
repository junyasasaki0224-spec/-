// オープニング演出(見た目だけ)。Race とその艇には一切書き込まない。
// 6艇がピットを出て、自動操縦でスタート前の位置へ向かう。カメラは自艇の後ろ(main.js 側で追う)。
import { M2, MARK_UNITS } from './sim/course.js';

const clamp01 = (x) => Math.max(0, Math.min(1, x));
const smooth = (x) => x * x * (3 - 2 * x);
export const PIT_X = -261.8;                       // ピットの前(桟橋の端のすぐ外)
export const pitZ = (i) => -12 + i * 10;           // 艇番表示の真下(柱の間)

export class Opening {
  constructor(race, short = false) {
    this.short = short;
    this.intro = short ? 1 : 6;                    // ピットで待つ時間(出走表を出す)
    this.stagger = short ? 0.15 : 0.5;             // 1号艇から順に出る間隔
    this.duration = short ? 10 : 27;
    this.elapsed = 0;
    this.targets = race.boats.map((b) => ({ x: b.x, z: b.z, h: b.h }));
    this.boats = race.boats.map((b) => ({ ...b }));
    this.audioBoats = this.boats.map((b) => ({ ...b }));
    this.race = { ...race, boats: this.boats, order: this.boats };
    this.playerIndex = race.playerIndex >= 0 ? race.playerIndex : 0;
    this.sample(0);
  }
  advance(dt) { this.elapsed = Math.min(this.duration, this.elapsed + dt); this.sample(this.elapsed); return this.elapsed >= this.duration; }
  // 艇 i の時刻 time での位置。ピットをまっすぐ出てから、2マークと消波装置の手前で自分のコースへ寄せる
  pos(i, time) {
    const g = this.targets[i], T = this.duration - this.intro - i * this.stagger - 1;
    const u = clamp01((time - this.intro - i * this.stagger) / T), t = smooth(u), a = 1 - t;
    const x0 = PIT_X, c1 = x0 + 22, c2 = g.x - 25;
    const z0 = pitZ(i);
    return {
      u,
      x: a * a * a * x0 + 3 * a * a * t * c1 + 3 * a * t * t * c2 + t * t * t * g.x,
      z: z0 + (g.z - z0) * smooth(clamp01(t / 0.5)),
    };
  }
  sample(time) {
    for (let i = 0; i < 6; i++) {
      const b = this.boats[i], g = this.targets[i], p = this.pos(i, time), q = this.pos(i, time + 0.05);
      const dx = q.x - p.x, dz = q.z - p.z, d = Math.hypot(dx, dz);
      const moving = p.u > 0 && p.u < 1 && d > 1e-5;
      b.x = p.x; b.z = p.z;
      b.h = moving ? Math.atan2(dz, dx) : p.u >= 1 ? g.h : 0;
      b.speed = moving ? d / 0.05 : 0;
      if (p.u >= 1) { b.x = g.x; b.z = g.z; b.h = g.h; b.speed = 0; }
      b.vx = Math.cos(b.h) * b.speed; b.vz = Math.sin(b.h) * b.speed;
      b.vf = b.speed; b.throttle = b.speed > 0 ? Math.min(0.5, 0.1 + b.speed / 30) : 0;
      b.w = 0; b.af = 0; b.turnInt = 0; b.bump = 0; b.steer = 0;
      Object.assign(this.audioBoats[i], b, { speed: Math.min(b.speed, 3), throttle: b.speed > 0 ? 0.08 : 0 });
    }
  }
  get phase() { return this.elapsed < this.intro ? '選手紹介' : this.elapsed < this.intro + (this.short ? 3 : 8) ? 'ピット離れ' : 'スタート位置へ'; }
  // 経路の安全確認(テスト用): 2マーク・消波装置・ほかの艇との最小距離
  clearance() {
    let obst = 99, boat = 99;
    for (let t = 0; t <= this.duration; t += 1 / 30) {
      const ps = this.targets.map((_, i) => this.pos(i, t));
      for (let i = 0; i < 6; i++) {
        obst = Math.min(obst, Math.hypot(ps[i].x - M2.x, ps[i].z - M2.z));
        for (const u of MARK_UNITS) for (let k = -u.len / 2; k <= u.len / 2; k += 0.5) obst = Math.min(obst, Math.hypot(ps[i].x - (u.x + u.dx * k), ps[i].z - (u.z + u.dz * k)));
        for (let j = i + 1; j < 6; j++) boat = Math.min(boat, Math.hypot(ps[i].x - ps[j].x, ps[i].z - ps[j].z));
      }
    }
    return { obst, boat };
  }
}
