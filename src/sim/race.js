// レース進行: フライングスタート、周回判定、順位、引き波、衝突イベント、入力の記録(リプレイ用)。
import {
  clamp, M1, M2, START_X, LAP_S, LAPS, zc, region, sOf,
} from './course.js';
import {
  makeBoat, stepBoat, collideBoats, collideWalls, collideObstacles, timeToCover, applyTilt, SINK_V, SINK_WALL_V,
} from './physics.js';
import { initAI, updateAI } from './ai.js';
import { ROSTER, PLAYER, DIFFS, motorFactor, randomWeather } from './roster.js';

export const DT = 1 / 120;
export const PRE_TIME = 14;          // 発走までの秒数(大時計の針が回る)
const TRAIL_DT = 0.06;
export const TRAIL_MAX = 80;

export function mulberry32(a) {
  return function () {
    a |= 0; a = (a + 0x6D2B79F5) | 0;
    let t = Math.imul(a ^ (a >>> 15), 1 | a);
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

// レースの設定を作る。lanes[枠] = レーサー('P' がプレイヤー)。同じ設定からは同じレースが再現される
export function makeConfig(o = {}) {
  const seed = o.seed ?? ((Math.random() * 1e9) | 0);
  const rng = mulberry32(seed ^ 0x5bd1e995);
  const playerLane = o.playerLane ?? -1;
  let lanes = o.lanes;
  if (!lanes) {
    const pool = ROSTER.map((r) => r.id);
    for (let i = pool.length - 1; i > 0; i--) { const j = (rng() * (i + 1)) | 0; [pool[i], pool[j]] = [pool[j], pool[i]]; }
    lanes = [];
    for (let i = 0; i < 6; i++) lanes.push(i === playerLane ? 'P' : pool.pop());
  }
  const motors = o.motors || {};        // レーサー id → 2連率
  const rate = (id) => motors[id] ?? (motors[id] = Math.round((28 + rng() * 20) * 10) / 10);
  lanes.forEach(rate);
  // 相手のチルト: 外枠ほど伸び型を選びやすい
  const tilts = o.tilts || lanes.map((id, i) => (id === 'P' ? (o.playerTilt ?? 1) : (rng() < 0.12 + i * 0.07 ? 2 : rng() < 0.3 ? 0 : 1)));
  return {
    seed, mode: o.mode || 'race', difficulty: o.difficulty ?? 1, lanes, motors, tilts,
    weather: o.weather || randomWeather(rng), env: o.env || 'day', title: o.title || '第12R 優勝戦',
  };
}

export class Race {
  constructor(cfg, replayInputs = null) {
    this.cfg = cfg;
    this.rng = mulberry32(cfg.seed);
    this.difficulty = cfg.difficulty;
    this.mode = cfg.mode;
    this.weather = cfg.weather;
    this.env = { wx: Math.cos(cfg.weather.windDir) * cfg.weather.wind, wz: Math.sin(cfg.weather.windDir) * cfg.weather.wind, chop: 1 + cfg.weather.wave * 0.12 };
    this.playerIndex = cfg.lanes.indexOf('P');
    this.clock = -PRE_TIME;         // 0 = スタート時刻
    this.acc = 0;
    this.events = [];
    this.state = 'pre';             // pre → racing → done / flying
    this.endTimer = 0;
    this.finishCount = 0;
    this.leader = -1;
    this.turn1 = { order: [], r: {} };   // 決まり手判定用
    this.kimarite = '';
    this.replay = replayInputs;     // リプレイ時は記録済みの入力を使う
    this.rec = replayInputs ? null : [];
    this.stepN = 0;
    this.boats = [];
    const D = DIFFS[cfg.difficulty];
    for (let i = 0; i < 6; i++) {
      const b = makeBoat(i), id = cfg.lanes[i];
      b.racer = id === 'P' ? PLAYER : ROSTER[id];
      b.motorRate = cfg.motors[id];
      // 枠なり進入: 1〜3コースはスロー(助走約110m)、4〜6コースはダッシュ(約190m)
      b.x = i < 3 ? -106 - i * 4 : -182 - (i - 3) * 5;
      b.laneZ = zc(0) + 7 + 5.5 * i;
      b.z = b.laneZ;
      b.isPlayer = id === 'P';
      b.lastValid = region(b.x, b.z);
      b.sectorCount = b.lastValid === 0 ? 0 : -1;
      b.sHold = sOf(b.x, b.z, b.lastValid);
      b.R = b.x; b.lap = 0; b.rank = i + 1;
      b.started = false; b.st = null; b.flying = false; b.late = false;
      b.sunk = false; b.sinkT = 0; b.out = false;   // out: 失格(フライングか沈没)
      b.finished = false; b.finishTime = 0; b.place = 0; b.offCourse = false;
      b.lapTimes = []; b.lastLapClock = 0;
      b.chop = this.env.chop;
      applyTilt(b, cfg.tilts[i]);
      b.gripSet *= 1 - cfg.weather.wave * 0.006;
      if (b.isPlayer) {
        b.motor = motorFactor(b.motorRate);
        initAI(b, () => 0.5, { skill: 1.0, st: 0.12, sashi: 0, lane: i });    // ガイドライン用(乱数なし: 引き直してもラインが揺れない)
      } else {
        b.motor = motorFactor(b.motorRate) + D.motor;
        initAI(b, this.rng, { skill: b.racer.skill * D.skill, st: b.racer.st + D.st, sashi: b.racer.sashi, lane: i });
      }
      this.boats.push(b);
    }
    this.order = this.boats.slice();
  }

  get player() { return this.playerIndex >= 0 ? this.boats[this.playerIndex] : null; }

  // プレイヤーが今から全開にした場合の予想スタートタイミング
  predictST(b) {
    if (b.started) return b.st;
    return this.clock + timeToCover(START_X - b.x, Math.max(b.vf, 0), b, this.env);
  }

  update(dtFrame, input) {
    this.acc += Math.min(dtFrame, 0.1);
    while (this.acc >= DT) { this.step(DT, input); this.acc -= DT; }
  }

  step(dt, input) {
    const boats = this.boats;
    this.clock += dt;
    if (this.state === 'pre' && this.clock >= 0) { this.state = 'racing'; this.events.push({ type: 'go' }); }

    for (const b of boats) {
      if (b.isPlayer) {
        // 入力はステップごとに記録し、リプレイでは同じ値を流し込む
        let st = 0, th = 0, br = 0;
        if (this.replay) { const k = this.stepN * 3; st = (this.replay[k] || 0) / 127; th = (this.replay[k + 1] || 0) / 127; br = (this.replay[k + 2] || 0) / 127; }
        else if (input) { st = Math.round(input.steer * 127) / 127; th = Math.round(input.throttle * 127) / 127; br = Math.round(input.brake * 127) / 127; }
        if (this.rec) this.rec.push(Math.round(st * 127), Math.round(th * 127), Math.round(br * 127));
        updateAI(b, this, dt, false);
        if (b.finished || b.out) {       // ゴール後・失格後は流す
          b.cmdThrottle = b.out ? 0 : 0.25; b.cmdSteer = this._cruiseSteer(b); b.cmdBrake = 0;
        } else { b.cmdThrottle = th; b.cmdSteer = st; b.cmdBrake = br; }
      } else {
        updateAI(b, this, dt);
        if (b.finished) b.cmdThrottle = Math.min(b.cmdThrottle, 0.45);
      }
      const px = b.x;
      if (b.sunk) {            // 沈んだ艇: 止まって沈んでいく。ほかの艇や障害物には当たらない
        b.sinkT += dt; b.cmdThrottle = 0; b.cmdSteer = 0; b.cmdBrake = 0;
        stepBoat(b, dt, this.env);
        const k = Math.exp(-2.2 * dt); b.vx *= k; b.vz *= k; b.w *= k;
        collideWalls(b);
        continue;
      }
      stepBoat(b, dt, this.env);
      const w = collideWalls(b);
      if (w > 2.5) this.events.push({ type: 'wall', boat: b.i, power: w, x: b.x, z: b.z });
      const o = collideObstacles(b);
      if (o && o.power > 1) this.events.push({ type: 'buoy', boat: b.i, id: o.id, power: o.power, nx: o.nx, nz: o.nz });
      // 強くぶつかったら沈没(失格)。ゴール後の艇は対象外
      if (!b.finished && !b.out) {
        if (o && o.power >= SINK_V) this._sink(b, o.id === 0 ? 'pole' : o.id >= 3 ? 'unit' : 'mark', o.power);
        else if (w >= SINK_WALL_V) this._sink(b, 'wall', w);
      }
      this._progress(b, px);
      this._trail(b, dt);
    }
    this.stepN++;
    for (let i = 0; i < 6; i++) for (let j = i + 1; j < 6; j++) {
      if (boats[i].sunk || boats[j].sunk) continue;
      const c = collideBoats(boats[i], boats[j]);
      if (c && c.power > 0.35) this.events.push({ type: 'hit', a: i, b: j, power: c.power, x: c.x, z: c.z });
    }
    this._wakes(dt);
    this._ranking();

    const pl = this.player;
    if (this.mode === 'practice') {
      // スタート練習: スタートラインを通過したら少し走って終了
      if (pl && this.state !== 'done' && (pl.started || this.clock > 8)) {       // 8秒たっても通過しなければ打ち切り
        this.endTimer += dt;
        if (this.endTimer > 2.2 || !pl.started) { this.state = 'done'; this.events.push({ type: 'done' }); }
      }
    } else if (this.state === 'racing' || this.state === 'flying') {
      if (this.finishCount + boats.filter((b) => b.out).length >= 6) this._end();
      else if (this.finishCount > 0) {
        // 先頭のゴールから一定時間で打ち切る(自艇がまだ走っている間は長めに待つ)
        this.endTimer += dt;
        if (this.endTimer > (pl && !pl.finished && !pl.out ? 50 : 25)) this._end();
      } else if (this.clock > 300) this._end();
    }
  }

  _sink(b, cause, power) {
    b.sunk = true; b.out = true; b.sinkT = 0; b.sinkCause = cause;
    this.events.push({ type: 'sink', boat: b.i, cause, power, x: b.x, z: b.z });
    if (b.isPlayer && this.state !== 'done' && this.mode !== 'practice') this.state = 'flying';   // 自艇の失格(レースは続く)
  }

  _end() {
    if (this.state === 'done') return;
    // 未ゴール艇は現在の位置関係で着順を確定
    for (const b of this.order) if (!b.finished && !b.out) { b.finished = true; b.place = ++this.finishCount; b.finishTime = 0; }
    this.state = 'done';
    this.events.push({ type: 'done' });
  }

  _cruiseSteer(b) {
    // ゴール後は緩くコースなりに
    const reg = region(b.x, b.z);
    let hd;
    if (reg === 0) hd = clamp((zc(b.x) + 28 - b.z) * 0.03, -0.3, 0.3);
    else if (reg === 2) hd = Math.PI - clamp((zc(b.x) - 28 - b.z) * 0.03, -0.3, 0.3);
    else { const m = reg === 1 ? M1 : M2; hd = Math.atan2(b.z - m.z, b.x - m.x) - Math.PI / 2; }
    let e = hd - b.h; while (e > Math.PI) e -= 2 * Math.PI; while (e < -Math.PI) e += 2 * Math.PI;
    return clamp(-e * 2, -1, 1);
  }

  _progress(b, px) {
    // スタートライン通過
    if (!b.started && px < START_X && b.x >= START_X) {
      const f = (START_X - px) / Math.max(b.x - px, 1e-6);
      b.st = this.clock - DT * (1 - f);
      b.started = true; b.lastLapClock = b.st;
      if (b.st < 0) { b.flying = true; b.out = true; this.events.push({ type: 'flying', boat: b.i, st: b.st }); if (b.isPlayer) this.state = 'flying'; }
      else { b.late = b.st > 1.0; this.events.push({ type: 'cross', boat: b.i, st: b.st, late: b.late }); }
    }
    // 区間の順送り。区間 L: 0 ホーム / 1 1マーク旋回 / 2 バック / 3 2マーク旋回。
    // 見るのは「マークの外側を回ったか」だけ: マークの真横の線(x=±150)を、正しい側で越えた時に次の区間へ進む。
    // 直線の途中で2つのマークを結ぶ線をまたいでも(接触で押されても)区間は変わらない
    const reg = region(b.x, b.z);
    let L = b.lastValid;
    if (px < M1.x && b.x >= M1.x) {                 // 1マークの線を奥へ越えた
      if (L === 0 && b.z > M1.z) { L = 1; b.sectorCount++; } else if (L === 2 && b.z < M1.z) { L = 1; b.sectorCount--; }
    } else if (px >= M1.x && b.x < M1.x) {          // 1マークの線を手前へ戻った
      if (L === 1 && b.z < M1.z) { L = 2; b.sectorCount++; } else if (L === 1) { L = 0; b.sectorCount--; }
    }
    if (px > M2.x && b.x <= M2.x) {                 // 2マークの線を奥へ越えた
      if (L === 2 && b.z < M2.z) { L = 3; b.sectorCount++; } else if (L === 0 && b.z > M2.z) { L = 3; b.sectorCount--; }
    } else if (px <= M2.x && b.x > M2.x) {          // 2マークの線を手前へ戻った
      if (L === 3 && b.z > M2.z) { L = 0; b.sectorCount++; } else if (L === 3) { L = 2; b.sectorCount--; }
    }
    b.lastValid = L;
    // マークの内側を抜けた(線を正しくない側で越えた)状態
    b.offCourse = L === 1 ? b.x < M1.x : L === 3 ? b.x > M2.x : (b.x > M1.x || b.x < M2.x);
    if (!b.offCourse) b.sHold = sOf(b.x, b.z, L);
    const R = Math.floor(b.sectorCount / 4) * LAP_S + b.sHold - 150;
    b.R = b.started ? R : b.x;
    if (b.started && !b.finished && !b.out) {
      const lap = Math.floor(b.R / LAP_S);
      if (lap > b.lap) {
        b.lap = lap;
        b.lapTimes.push(this.clock - b.lastLapClock); b.lastLapClock = this.clock;
        if (lap >= LAPS) {
          b.finished = true; b.place = ++this.finishCount; b.finishTime = this.clock;
          if (b.place === 1) this._kimarite(b);
          this.events.push({ type: 'finish', boat: b.i, place: b.place, time: b.finishTime });
        } else this.events.push({ type: 'lap', boat: b.i, lap: lap + 1 });
      }
      // 1周目1マークの回り方を記録
      if (b.lap === 0 && reg === 1 && this.turn1.r[b.i] === undefined && b.z < M1.z) {
        this.turn1.r[b.i] = Math.hypot(b.x - M1.x, b.z - M1.z);
        this.turn1.order.push(b.i);
        if (this.turn1.order.length === 1) this.events.push({ type: 'turn1', boat: b.i });
      }
    }
  }

  _kimarite(w) {
    const t = this.turn1, first = t.order[0];
    if (first === undefined) { this.kimarite = ''; return; }
    if (w.i !== first) { this.kimarite = '抜き'; return; }
    if (w.i === 0) { this.kimarite = '逃げ'; return; }
    const rw = t.r[w.i], r1 = t.r[0];
    if (r1 === undefined || rw > r1) { this.kimarite = 'まくり'; return; }
    let outsideOfSomeone = false;
    for (let j = 1; j < w.i; j++) if (t.r[j] !== undefined && t.r[j] < rw) outsideOfSomeone = true;
    this.kimarite = outsideOfSomeone ? 'まくり差し' : '差し';
  }

  _trail(b, dt) {
    b.trailT += dt;
    if (b.trailT >= TRAIL_DT) {
      b.trailT = 0;
      if (b.speed > 2.5) {
        const ch = Math.cos(b.h), sh = Math.sin(b.h);
        b.trail.push({ x: b.x - ch * 1.5, z: b.z - sh * 1.5, t: this.clock, s: clamp(b.speed / 20, 0.2, 1) + b.turnInt * 0.5 });
        if (b.trail.length > TRAIL_MAX) b.trail.shift();
      }
    }
    while (b.trail.length && this.clock - b.trail[0].t > TRAIL_DT * TRAIL_MAX) b.trail.shift();
  }

  // 引き波: 他艇の航跡に乗るとプロペラが空転気味になり、グリップと推力が落ちる
  _wakes(dt) {
    this._wakeT = (this._wakeT || 0) + dt;
    if (this._wakeT < 1 / 30) return;
    const step = this._wakeT; this._wakeT = 0;
    for (const b of this.boats) {
      let inW = 0;
      for (const o of this.boats) {
        if (o === b) continue;
        const tr = o.trail;
        for (let k = tr.length - 1; k >= 0; k -= 2) {
          const p = tr[k], age = this.clock - p.t;
          if (age < 0.25) continue;
          if (age > 2.6) break;
          const dx = p.x - b.x, dz = p.z - b.z, r = 1.1 + age * 0.45;
          if (dx * dx + dz * dz < r * r) { inW = 1; break; }
        }
        if (inW) break;
      }
      b.inWake += clamp(inW - b.inWake, -step * 4, step * 6);
      b.gripF = 1 - 0.22 * b.inWake;
      // 後続艇はわずかに伸びる(集団がばらけすぎないように)
      const gap = this.order[0].R - b.R;
      const chase = b.isPlayer || !b.started ? 0 : clamp((gap - 15) / 120, 0, 1) * 0.035;
      b.thrustF = 1 - 0.05 * b.inWake + chase;
    }
  }

  _ranking() {
    this.order.sort((a, b) => {
      if (a.out !== b.out) return a.out ? 1 : -1;
      if (a.finished && b.finished) return a.place - b.place;
      if (a.finished !== b.finished) return a.finished ? -1 : 1;
      return b.R - a.R;
    });
    for (let k = 0; k < 6; k++) this.order[k].rank = k + 1;
    const lead = this.order[0];
    if (this.state === 'racing' && lead.started && lead.R > 60 && lead.i !== this.leader) {
      if (this.leader >= 0) this.events.push({ type: 'lead', boat: lead.i });
      this.leader = lead.i;
    }
  }
}
