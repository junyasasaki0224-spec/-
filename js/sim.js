// ============================================================
//  レースシミュレーション (DOM非依存 / Nodeでも実行可)
//  ・スタミナ: 有酸素速度(vAer)を超えた分の2乗で消耗。坂・馬場・風・コーナー・折り合いで増減
//  ・スリップストリーム、進路妨害(斜行)、前が壁、コーナーの遠心力と距離ロス
//  ・AI騎手: 残りスタミナから逆算したペース配分 + 脚質ごとの位置取り + 進路選択
// ============================================================
import { Track } from './track.js';
import { mulberry32, clamp, lerp } from './data.js';

export const LEN = 2.5; // 馬体長[m]
const K = 0.208, BASE = 0.10; // 消耗 = BASE + K*(超過速度)^1.5
const GO_V = [1, 0.992, 0.98, 0.965];
const GO_PEN = [0, 0.12, 0.3, 0.5];
const LANE_W = 0.95; // 並走に必要な横間隔
const STYLE_F = [0.985, 0.981, 0.976, 0.971];
const STYLE_EARLY = [1.1, 0.55, 0.0, -0.35];
const STYLE_KICK = [0, 520, 620, 680];

// 有酸素速度からの超過 ex[m/s] に対する毎秒のスタミナ消費
function burn(ex) {
  if (ex <= 0) return BASE;
  const hi = ex - 3.2;
  return BASE + K * ex * Math.sqrt(ex) + (hi > 0 ? 0.6 * hi * hi : 0);
}
function derive(h) {
  const c = h.cond.k;
  return {
    vTop: (17.55 + h.spd * 0.018 + h.acc * 0.006) * c,
    vAer: (12.2 + h.sta * 0.016 + h.spd * 0.016) * c,
    aMax: 4.0 + h.acc * 0.04,
    grip: 2.15 + h.nim * 0.011,
    hot: 0.15 + Math.max(0, (72 - h.tmp) / 45), // 気性の激しさ
  };
}

export class Race {
  constructor(cfg) {
    this.cfg = cfg;
    this.track = new Track(cfg.course, cfg.dist);
    this.D = cfg.dist;
    this.rng = mulberry32(cfg.seed || 1);
    this.going = cfg.cond.going;
    this.rough = cfg.cond.rough;
    this.wx = Math.cos(cfg.cond.wind.dir) * cfg.cond.wind.speed;
    this.wz = Math.sin(cfg.cond.wind.dir) * cfg.cond.wind.speed;
    this.diff = cfg.difficulty == null ? 1 : cfg.difficulty;
    this.playerIdx = cfg.playerIdx == null ? -1 : cfg.playerIdx;
    this.state = 'gate'; // gate → run → done
    this.t = 0;
    this.events = [];
    this.splits = []; // 先頭のハロンラップ
    this.finishOrder = [];
    this.falseStart = false;
    this.nextSplit = this.D % 200 === 0 ? 200 : this.D % 200;
    this.lastSplitT = 0;
    this.pass1000 = 0;
    this.paceBias = (this.rng() - 0.42) * 0.04; // その日の先行勢の強気/弱気 (ハイペース⇔スロー)
    this.exEven = Math.pow(85 / (K * this.D / 16.8), 2 / 3); // 平均ペースでの超過速度

    // 坂によるペナルティの残り平均 (AIのペース計算用)
    const n = Math.ceil(this.D) + 1;
    this.hillCum = new Float32Array(n + 1);
    const o = {};
    for (let i = n - 1; i >= 0; i--) {
      const g = this.track.at(i, 0, o).slope;
      this.hillCum[i] = this.hillCum[i + 1] + (g > 0 ? g * 62 * 0.86 : g * 22);
    }

    const biasMul = [2.0, 1.0, 0.5][this.diff];
    this.runners = cfg.horses.map((h, i) => {
      const p = derive(h);
      return {
        i, h, p, isPlayer: i === this.playerIdx,
        s: 0, d: 1.3 + i * 1.18, v: 0, lat: 0, E: 100, ar: 0.12 + p.hot * 0.08,
        phase: this.rng(), geo: {}, k: 0, slope: 0, head: 0, draft: 0, cover: false,
        ahead: null, aheadGap: 1e9, blocked: 0, fight: 0, penNow: 0, penAvg: GO_PEN[this.going] * (1.5 - h.mud * 0.01) - 0.05,
        vCap: p.vTop, started: false, startDelay: 0, fin: false, ft: Infinity, rank: i + 1,
        whipN: 0, whipT: 0, whipQ: 0, whipCd: 0, whipAnim: 0, leadQ: 0, leadDone: false, pushing: 0,
        dist: 0, debt: 0, bumpCd: 0, t600: 0, last3f: 0, duel: false, kick: false, spent: false,
        ai: { lane: 0, tLane: this.rng() * 0.2, target: 0, bias: h.bias * biasMul, nextWhip: 0, leadAt: (this.rng() - 0.3) * 120 * (1.3 - h.jskill), yielded: false },
        // 騎乗内容の記録 (プレイヤー評価用)
        m: { arSum: 0, arT: 0, draftT: 0, cruiseT: 0, emptyRem: -1, bumps: 0, foul: 0, victim: -1, whipGood: 0, blockedT: 0, ang: 0, startDelay: 0, startKind: '', leadKind: '', eFin: 0 },
      };
    });
    this.order = this.runners.slice();
    this.player = this.playerIdx >= 0 ? this.runners[this.playerIdx] : null;
    for (const r of this.runners) this.track.at(r.s, r.d, r.geo);
  }

  roughAt(d) { return this.rough * clamp(1 - d / 7, 0, 1); }

  // ゲートオープン
  openGate() {
    this.state = 'run';
    this.t = 0;
    for (const r of this.runners) {
      if (r.isPlayer) { r.startDelay = this.falseStart ? 0.95 : 1.2; r.m.startKind = this.falseStart ? 'あおって出遅れ' : ''; r.waitPress = !this.falseStart; continue; }
      const g = r.h.gate;
      let dly = 0.05 + (1 - g / 100) * 0.3 * this.rng();
      if (this.rng() < 0.03 + (100 - g) * 0.0012) dly += 0.35 + this.rng() * 0.5;
      r.startDelay = dly;
    }
    this.events.push({ type: 'gate' });
  }

  // ---- 環境: 位置関係・風・スリップストリーム ----
  env(r) {
    const o = this.track.at(r.s, r.d, r.geo);
    r.k = o.k; r.slope = o.slope;
    r.head = -(this.wx * o.hx + this.wz * o.hz);
    let f = 0, ag = 1e9, ah = null;
    const rs = this.runners;
    for (let n = 0; n < rs.length; n++) {
      const j = rs[n]; if (j === r) continue;
      const gap = j.s - r.s - LEN;
      if (gap > -1.2 && gap < 9) {
        const dl = Math.abs(j.d - r.d);
        if (dl < 1.6) { const ff = (1 - dl / 1.6) * (gap < 1 ? 1 : 1 - (gap - 1) / 8) * 0.45; if (ff > f) f = ff; }
        if (dl < LANE_W && gap < ag) { ag = gap; ah = j; }
      }
    }
    r.draft = f; r.cover = f > 0.15; r.ahead = ah; r.aheadGap = ag;
  }

  // 有酸素速度を下げる要因の合計 [m/s]
  pen(r, v, noFight) {
    const h = r.h, g = r.slope;
    let p = g > 0 ? g * 62 * (1.35 - h.pow * 0.007) : g * 22;
    p += GO_PEN[this.going] * (1.5 - h.mud * 0.01);
    p += this.roughAt(r.d) * 0.32 * (1.3 - h.pow * 0.004);
    if (v > 5) { const q = 1 + r.head / v; p += 0.38 * ((1 - r.draft) * q * q - 1); }
    if (r.k > 0) p += 0.035 * v * v * r.k / (1 + r.d * r.k);
    if (r.whipT > 0) p -= 0.18 * r.whipQ; // ムチに応えて底力を出す
    if (!noFight) p += r.fight;
    return p;
  }
  drain(r, v) {
    const ex = v - (r.p.vAer - r.penNow);
    return burn(ex);
  }
  // 残りスタミナをちょうど使い切る一定速度
  vEven(r, rem, E) {
    const si = Math.min(this.hillCum.length - 1, Math.max(0, r.s | 0));
    const hill = rem > 1 ? this.hillCum[si] / rem : 0;
    const va = r.p.vAer - r.penAvg - hill;
    let lo = va - 1.5, hi = r.p.vTop + 0.6;
    for (let i = 0; i < 13; i++) {
      const v = (lo + hi) / 2, ex = v - va;
      if (burn(ex) * rem / v > E) hi = v; else lo = v;
    }
    return lo;
  }
  capOf(r) {
    const h = r.h, p = r.p, sl = r.slope;
    let v = p.vTop * (1 - (1 - GO_V[this.going]) * (1.5 - h.mud * 0.01));
    v *= sl > 0 ? 1 - sl * (2.4 - h.pow * 0.014) : 1 - sl * 0.5;
    if (r.E < 12) v *= lerp(0.935 + h.gut * 0.0004, 1, Math.max(0, r.E) / 12);
    if (r.whipT > 0) v *= 1 + 0.011 * r.whipQ;
    if (r.leadQ > 0) v *= 1 + 0.004 * r.leadQ;
    if (r.duel) v *= 1 + h.gut * 0.00011;
    if (r.E <= 0) v = Math.min(v, p.vAer + 0.6 - r.penNow + (h.gut - 50) * 0.008 - Math.min(3, r.debt * 0.14));
    return v;
  }

  // ---- AI騎手 ----
  ai(r, dt) {
    const h = r.h, a = r.ai, D = this.D, rem = D - r.s, n = this.runners.length;
    const leader = this.order[0];
    const kickDist = Math.min(STYLE_KICK[h.style], D * 0.36);
    const margin = [5, 1.5, 0.8][this.diff] * (1.4 - h.jskill * 0.6);
    const ve = this.vEven(r, Math.max(rem, 5), Math.max(0.5, r.E - margin)) * (1 + (rem > 300 ? a.bias : a.bias * 0.3));
    let target;
    r.kick = rem <= kickDist || (h.style === 0 && rem < 400);
    if (!r.kick) {
      target = ve * STYLE_F[h.style];
      if (r.s < 350) target += STYLE_EARLY[h.style] * (1 - r.s / 350) * (0.6 + h.gate * 0.006);
      if (h.style <= 1 && r.rank <= 5) target *= 1 + this.paceBias * (h.style === 0 ? 1 : 0.7) * (1.5 - h.jskill);
      if (h.style === 0) {
        // 逃げ: ハナを主張。競り負けたら番手に控える
        if (r.rank > 1 && !a.yielded) {
          if (r.s < 450) target = Math.max(target, Math.min(leader.v + 0.4, ve + 0.7));
          else a.yielded = true;
        }
        if (r.rank > 1 && a.yielded && leader.s - r.s < 6) target = Math.min(target, leader.v + 0.05);
      } else if (h.style === 1) {
        const gap = leader.s - r.s;
        if (gap > 14) target += 0.2;
        if (gap < 22 && this.paceBias > 0) target = Math.max(target, Math.min(leader.v - 0.2, ve * (1 + this.paceBias))); // 速い流れに付き合ってしまう
        if (r.rank === 1 && r.s > 200 && this.order[1].v > r.v - 0.5) target -= 0.15; // ハナには行きたくない
        else if (gap < 3.5 + LEN && leader !== r && leader.v > ve * 0.94) target = Math.min(target, leader.v + 0.05);
      } else {
        const band = h.style === 2 ? n * 0.38 : n * 0.68;
        const maxGap = h.style === 2 ? 22 : 34;
        if (r.rank < band && r.s > 150) target = Math.min(target, leader.v - 0.25);
        if (leader.s - r.s > maxGap) target = Math.max(target, leader.v + 0.05);
      }
      // 前の馬の直後につけて風除けにする
      if (r.ahead && r.aheadGap < 10 && r.s > 120 && Math.abs(r.ahead.v - target) < 0.55) {
        target = clamp(r.ahead.v + (r.aheadGap - 1.2) * 0.2, target - 0.4, target + 0.4);
      }
      // 掛かった馬は抑えきれない
      const x = clamp((r.ar - 0.3) / 0.7, 0, 1);
      r.fight = x * 0.45;
      target += x * 0.45;
    } else {
      r.fight = 0;
      target = ve + 0.12;
      if (rem < 60) target = r.vCap + 1;
      // ムチ
      if (rem < 380 && r.E > 2 && this.t > a.nextWhip && r.whipCd <= 0) {
        this.whip(r, 0.75 + this.rng() * 0.5 * h.jskill + (h.jskill - 0.5) * 0.3);
        a.nextWhip = this.t + 0.9 + this.rng() * 0.7;
      }
      // 手前替え
      if (!r.leadDone && r.s > this.track.straightStartS + 10 + a.leadAt) this.leadChange(r);
    }
    a.target = target;

    // 進路選択
    a.tLane -= dt;
    if (a.tLane <= 0) {
      a.tLane = 0.18 + this.rng() * 0.08;
      a.lane = this.pickLane(r, target);
    }
    const dl = a.lane - r.d;
    r.cmdLat = Math.abs(dl) < 0.08 ? 0 : clamp(dl * 2.5, -1.5, 1.5);

    // 加減速
    const aAvail = Math.max(0, 1 - r.v / r.vCap) * r.p.aMax * (r.whipT > 0 ? 1.35 : 1);
    r.cmdA = clamp((target - r.v) * 1.6, -1.4, aAvail);
    r.pushing = r.kick && target > r.v - 0.1 ? 1 : 0;
  }

  pickLane(r, target) {
    const tr = this.track, W = tr.W, rs = this.runners;
    const rem = this.D - r.s;
    const inStraight = r.s >= tr.straightStartS;
    const dc = tr.distToCurve(r.s);
    let wIn = r.k > 0 ? 0.13 : dc < 180 ? 0.09 : 0.035;
    if (inStraight) wIn = 0.004;
    if (r.s < 60) wIn *= r.s / 60; // ゲート直後はまっすぐ
    const cur = r.d;
    let best = cur, bestC = 1e9;
    const steps = [0, -1.2, 1.2, -2.4, 2.4];
    for (let q = 0; q < steps.length; q++) {
      const c = clamp(cur + steps[q], 0.75, W - 0.75);
      if (q > 0 && Math.abs(c - cur) < 0.3) continue;
      let cost = c * wIn + this.roughAt(c) * (inStraight ? 2.2 : 0.9) + Math.abs(c - cur) * 0.06;
      let ok = true;
      const lo = Math.min(c, cur) - LANE_W, hi = Math.max(c, cur) + LANE_W;
      for (let n = 0; n < rs.length; n++) {
        const j = rs[n]; if (j === r) continue;
        const ds = j.s - r.s;
        // 移動先に馬がいる(並走/すぐ後ろ)なら動けない
        if (q > 0 && j.d > lo && j.d < hi && ds > -(LEN + 2.4) && ds < LEN + 0.7 && Math.abs(j.d - cur) >= LANE_W * 0.98) { ok = false; break; }
        if (Math.abs(j.d - c) < LANE_W) {
          const gap = ds - LEN;
          if (gap > -0.5 && gap < 12) {
            const closing = target - j.v;
            if (closing > -0.15) cost += (closing + 0.3) * (1 - gap / 12) * (r.kick ? 3.2 : 1.8);
            else if (!r.kick && gap > 0.3 && gap < 8) cost -= 0.5; // 風除けに入る
          }
        }
      }
      if (!ok) continue;
      if (cost < bestC) { bestC = cost; best = c; }
    }
    return best;
  }

  whip(r, q) {
    if (r.whipCd > 0 || r.fin) return 0;
    r.whipCd = 0.65; r.whipAnim = 0.5; r.whipN++;
    const resp = Math.max(0.15, 1 - (r.whipN - 1) * 0.07) * q * (r.E > 0 ? 1 : 0.15);
    const early = this.D - r.s > 700 ? 0.3 : 1; // 早すぎるムチは効果が薄い
    r.whipT = 1.5; r.whipQ = resp * early;
    r.ar = Math.min(1, r.ar + 0.03);
    return resp * early;
  }
  leadChange(r, q) {
    if (r.leadDone) return;
    r.leadDone = true;
    if (q == null) {
      const off = Math.abs(r.s - (this.track.straightStartS + 20));
      q = off < 30 ? 1 : off < 70 ? 0.6 : 0.25;
    }
    r.leadQ = q; r.E += 3.5 * q;
  }

  // ---- プレイヤー入力 ----
  playerCtl(r, inp, dt) {
    const rem = this.D - r.s;
    const x = rem > 700 ? clamp((r.ar - 0.3) / 0.7, 0, 1) : 0;
    const aAvail = Math.max(0, 1 - r.v / r.vCap) * r.p.aMax * (r.whipT > 0 ? 1.35 : 1);
    let a = 0;
    r.fight = 0;
    if (inp.drive > 0) { a = aAvail * inp.drive; r.pushing = 1; }
    else {
      r.pushing = 0;
      if (inp.drive < 0) {
        a = -1.3 * (1 - 0.55 * x) * -inp.drive;
        r.fight = x * 0.9; // 掛かった馬を力で抑えると消耗する
      } else {
        a = -9.8 * r.slope * 0.35; // 持ったまま: 坂の影響を受ける
        const want = r.p.vAer + this.exEven * 0.9 + x * 1.5;
        if (x > 0 && r.v < want) a += x * 1.1; // 掛かって行きたがる
      }
      if (r.v < 13.5 && inp.drive >= 0 && r.s < 250) a = Math.max(a, aAvail * 0.55); // ゲートを出た馬は自然に加速
      if (r.v < 11 && a < 0) a = 0;
    }
    r.cmdA = a;
    r.cmdLat = inp.steer * 2.1;
    if (inp.whip) {
      // ストライドに合わせると効果大 (着地の瞬間 phase≈0)
      const ph = r.phase % 1, off = Math.min(ph, 1 - ph);
      const q = off < 0.1 ? 1.3 : off < 0.2 ? 1.0 : 0.72;
      const res = this.whip(r, q);
      if (res > 0 || r.whipCd === 0.65) {
        if (q > 1.2) r.m.whipGood++;
        this.events.push({ type: 'whip', q, n: r.whipN, dead: r.E <= 0 });
      }
    }
    if (inp.lead && !r.leadDone) {
      const off = r.s - (this.track.straightStartS + 20);
      let q, kind;
      if (off < -90) { q = 0; kind = '早すぎ'; r.leadDone = false; r.lat += 0.8; r.v -= 0.15; this.events.push({ type: 'lead', q: 0, kind }); }
      else {
        const ao = Math.abs(off);
        if (ao < 30) { q = 1; kind = '完璧'; } else if (ao < 75) { q = 0.6; kind = '良'; } else { q = 0.25; kind = '遅れ'; }
        this.leadChange(r, q); r.m.leadKind = kind;
        this.events.push({ type: 'lead', q, kind });
      }
    }
    // 押さなければ遅れて勝手に替える
    if (!r.leadDone && r.s > this.track.straightStartS + 230) { this.leadChange(r, 0.15); r.m.leadKind = '馬任せ'; this.events.push({ type: 'lead', q: 0.15, kind: '馬任せ' }); }
  }

  // ---- 1ステップ ----
  step(dt, inp) {
    if (this.state === 'gate') {
      if (inp && inp.go && !this.falseStart) { this.falseStart = true; this.events.push({ type: 'false' }); }
      return;
    }
    this.t += dt;
    const rs = this.runners, tr = this.track, D = this.D;
    const ord = this.order;
    ord.sort((a, b) => b.s - a.s);
    for (let i = 0; i < ord.length; i++) ord[i].rank = i + 1;
    const leader = ord[0];

    for (let n = 0; n < rs.length; n++) this.env(rs[n]);

    for (let n = 0; n < rs.length; n++) {
      const r = rs[n];
      // スタート
      if (!r.started) {
        if (r.isPlayer && r.waitPress && inp && inp.go) {
          r.waitPress = false; r.startDelay = Math.max(0.02, this.t);
          r.m.startKind = this.t < 0.16 ? '好スタート' : this.t < 0.4 ? '五分' : this.t < 0.7 ? 'やや出遅れ' : '出遅れ';
        }
        if (this.t >= r.startDelay) {
          r.started = true; r.waitPress = false;
          if (r.isPlayer && r.m.startKind === '好スタート') r.v = 3.2; // 好スタートは一完歩ぶん速く出る
          if (r.isPlayer) { r.m.startDelay = r.startDelay; if (!r.m.startKind) r.m.startKind = '出遅れ'; this.events.push({ type: 'pstart', kind: r.m.startKind, delay: r.startDelay }); }
          else if (r.startDelay > 0.45) this.events.push({ type: 'late', i: r.i });
        } else { r.cmdA = 0; r.cmdLat = 0; continue; }
      }
      // 競り合い (根性)
      const rem = D - r.s;
      r.duel = false;
      if (rem < 420 && rem > 0) {
        for (let m = 0; m < rs.length; m++) {
          const j = rs[m];
          if (j !== r && Math.abs(j.s - r.s) < 3 && Math.abs(j.d - r.d) < 2.2) { r.duel = true; break; }
        }
      }
      r.penNow = this.pen(r, Math.max(r.v, 8));
      r.vCap = this.capOf(r);
      if (r.fin) { r.cmdA = clamp((9 - r.v) * 0.25, -0.9, 0); r.cmdLat = 0; r.pushing = 0; continue; }
      if (r.isPlayer && inp) this.playerCtl(r, inp, dt); else this.ai(r, dt);
    }

    // 積分
    for (let n = 0; n < rs.length; n++) {
      const r = rs[n];
      if (!r.started) continue;
      let a = r.cmdA;
      if (r.v > r.vCap) a = Math.min(a, -Math.min(1.3, (r.v - r.vCap) * 1.6 + 0.1));
      const v0 = r.v;
      r.v = Math.max(0, r.v + a * dt);
      // 横移動 + 遠心力による膨れ
      const ac = r.v * r.v * r.k / (1 + r.d * r.k);
      const grip = r.p.grip * (this.going >= 2 ? 0.92 : 1);
      const drift = r.fin ? 0 : Math.max(0, ac - grip) * 0.5;
      r.lat += clamp(r.cmdLat - r.lat, -9 * dt, 9 * dt);
      let nd = r.d + (r.lat + drift) * dt;
      nd = clamp(nd, 0.65, tr.W - 0.65);
      if (!r.fin) {
        for (let m = 0; m < rs.length; m++) {
          const j = rs[m]; if (j === r) continue;
          const ds = r.s - j.s; // 自分が前なら正
          if (Math.abs(ds) < LEN) {
            const sep = nd - j.d, asep = Math.abs(sep);
            if (asep < LANE_W) {
              const side = r.d >= j.d ? 1 : -1;
              const want = j.d + side * LANE_W;
              if (Math.abs(r.lat) > 0.7 && Math.abs(r.d - j.d) >= LANE_W - 0.02 && (r.lat > 0) !== (side > 0)) {
                // 接触
                if (r.bumpCd <= 0) {
                r.bumpCd = 0.9; r.v -= 0.12; j.v -= 0.08; j.ar = Math.min(1, j.ar + 0.06 * j.p.hot); r.ar = Math.min(1, r.ar + 0.08 * r.p.hot);
                if (r.isPlayer) { r.m.bumps++; this.events.push({ type: 'bump', i: j.i }); }
                }
                r.lat = 0;
              }
              nd = Math.abs(want - nd) < 0.5 ? want : nd + clamp(want - nd, -2.5 * dt, 2.5 * dt);
            }
          } else if (r.isPlayer && ds >= LEN && ds < LEN + 1.5 && Math.abs(r.lat) > 0.4) {
            // 斜行: 後続の進路に十分な間隔なく入った
            if (Math.abs(r.d - j.d) >= LANE_W && Math.abs(nd - j.d) < LANE_W && j.v > r.v - 0.1 && !j.fin) {
              const sev = (LEN + 1.5 - ds) / 1.5 * (rem(D, r) < 600 ? 2 : 1) * (1 + Math.max(0, j.v - r.v));
              r.m.foul += sev; r.m.victim = j.i;
              j.v = Math.min(j.v, r.v - 0.35); j.ar = Math.min(1, j.ar + 0.1);
              this.events.push({ type: 'foul', i: j.i, sev });
            }
          }
        }
        nd = clamp(nd, 0.65, tr.W - 0.65);
      }
      r.d = nd;
      const vm = (v0 + r.v) * 0.5;
      r.s += vm * dt / (1 + r.d * r.k);
      r.dist += vm * dt;
      if (r.isPlayer && !r.fin) r.m.ang += vm * dt * r.k / (1 + r.d * r.k);
      r.phase += dt * (0.9 + r.v * 0.085);
      if (r.whipT > 0) r.whipT -= dt;
      if (r.whipCd > 0) r.whipCd -= dt;
      if (r.whipAnim > 0) r.whipAnim -= dt;
      // スタミナ
      if (!r.fin) {
        r.E -= (this.drain(r, vm) + (a > 0 ? 0.035 * a * vm : 0)) * dt;
        if (r.E <= 0) r.debt += dt;
        if (r.bumpCd > 0) r.bumpCd -= dt;
        if (r.E <= 0) { r.E = 0; if (!r.spent) { r.spent = true; if (r.m.emptyRem < 0) r.m.emptyRem = D - r.s; if (r.isPlayer) this.events.push({ type: 'empty', rem: D - r.s }); } }
        else if (r.E > 3) r.spent = false;
        const pn = this.pen(r, Math.max(r.v, 8)) - (r.slope > 0 ? r.slope * 62 * (1.35 - r.h.pow * 0.007) : r.slope * 22);
        r.penAvg += (pn - r.penAvg) * dt / 8;
      }
    }

    // 前が壁: 同じ進路の前の馬には追突できない
    for (let n = 1; n < ord.length; n++) {
      const r = ord[n];
      if (!r.started) continue;
      let hit = false;
      for (let m = 0; m < rs.length; m++) {
        const j = rs[m]; if (j === r) continue;
        if (Math.abs(j.d - r.d) >= LANE_W) continue;
        const gap = j.s - LEN - r.s;
        if (gap < -LEN * 0.6 || gap > 3) continue;
        const lim = j.v + Math.max(0, gap) * 0.8;
        if (r.v > lim) { r.v = lim; hit = true; }
        if (gap < 0.05 && gap > -1.0) r.s = j.s - LEN - 0.05;
      }
      if (hit && (r.cmdA > 0.05 || r.kick)) { r.blocked = Math.min(1, r.blocked + dt * 3); if (r.isPlayer) r.m.blockedT += dt; }
      else r.blocked = Math.max(0, r.blocked - dt * 2);
    }

    // 折り合い
    for (let n = 0; n < rs.length; n++) {
      const r = rs[n];
      if (!r.started || r.fin) continue;
      const rem = D - r.s, h = r.h, hot = r.p.hot;
      if (rem > 700) {
        let stim = 0;
        if (r.s < 500) stim += 0.22;
        const clearLead = r.rank === 1 && r.s - this.order[1].s > LEN + 1.5; // 単騎で楽に行けている
        if (!r.cover && !clearLead) stim += 0.1;
        if (r.slope < -0.006) stim += 0.1;
        if (r.v < r.p.vAer + this.exEven * 0.72 && r.s > 150) stim += 0.25; // スローで行きたがる
        if (h.style === 0 && r.rank > 2 && r.cover) stim += 0.15; // 逃げ馬は揉まれると嫌がる
        // 1周目スタンド前の大歓声
        if (this.track.chute <= r.s) { const u = tr.uOf(r.s); if (u > tr.straight - 250 && u < tr.straight + 80) stim += 0.22; }
        const calm = 0.1 + (r.cover ? 0.2 : 0) + (clearLead ? 0.12 : 0) + (r.v > r.p.vAer + this.exEven * 1.02 ? 0.1 : 0);
        r.ar = clamp(r.ar + (stim * hot - calm * (0.5 + h.tmp / 100)) * dt * 0.3, 0, 1);
        if (r.isPlayer) { r.m.arSum += r.ar * dt; r.m.arT += dt; r.m.cruiseT += dt; if (r.cover) r.m.draftT += dt; }
      } else r.ar = Math.max(0, r.ar - dt * 0.2);
      if (!r.t600 && rem <= 600) r.t600 = this.t - (600 - rem) / Math.max(1, r.v);
      // ゴール
      if (r.s >= D) {
        r.fin = true;
        r.ft = this.t - (r.s - D) / Math.max(1, r.v);
        r.last3f = r.ft - r.t600;
        r.m.eFin = r.E;
        this.finishOrder.push(r);
        this.events.push({ type: 'finish', i: r.i, pos: this.finishOrder.length });
      }
    }

    // ラップ計時
    if (leader.s >= this.nextSplit && this.nextSplit <= D) {
      const tt = this.t - (leader.s - this.nextSplit) / Math.max(1, leader.v);
      this.splits.push(tt - this.lastSplitT);
      this.lastSplitT = tt;
      this.events.push({ type: 'split', at: this.nextSplit, lap: this.splits[this.splits.length - 1], t: tt });
      if (!this.pass1000 && this.nextSplit >= 1000) { this.pass1000 = tt - (this.nextSplit - 1000) / Math.max(1, leader.v); }
      this.nextSplit += 200;
    }
    if (this.finishOrder.length === rs.length) this.state = 'done';
  }

  // 全馬AIで最後まで走らせる (オッズ算出・検証用)
  runAll(dt) {
    this.openGate();
    let guard = 0;
    while (this.state !== 'done' && guard++ < 60 * 400) this.step(dt, null);
    this.finishOrder.sort((a, b) => a.ft - b.ft);
    return this.finishOrder;
  }

  // プレイヤー向け: 手応え (今の速度で残り距離をもつか)
  feel(r) {
    const rem = Math.max(1, this.D - r.s);
    const ve = this.vEven(r, rem, Math.max(0.5, r.E));
    return { ve, ratio: (r.E / this.drain(r, Math.max(r.v, 10)) * Math.max(r.v, 10)) / rem };
  }
}
function rem(D, r) { return D - r.s; }

// モンテカルロでオッズを算出
export function computeOdds(cfgBase, trials) {
  const n = cfgBase.horses.length;
  const win = new Float32Array(n).fill(0.25);
  for (let k = 0; k < trials; k++) {
    const race = new Race({ ...cfgBase, playerIdx: -1, seed: 7919 * (k + 1) });
    const fo = race.runAll(1 / 15);
    win[fo[0].i] += 1; win[fo[1].i] += 0.35; win[fo[2].i] += 0.15;
  }
  let tot = 0; for (let i = 0; i < n; i++) tot += win[i];
  const res = [];
  for (let i = 0; i < n; i++) {
    const p = win[i] / tot;
    res.push(clamp(Math.round(0.8 / p * 10) / 10, 1.1, 399.9));
  }
  return res;
}
