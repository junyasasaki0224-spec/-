// ボートの運動モデル。水面上の2D剛体(位置・向き・速度・角速度)として扱う。
// 前後方向は推力と水の抵抗、横方向は「限界のあるグリップ」で、
// 限界を超えると艇が外へ流れる(慣性ドリフト)。
import { clamp, BOUNDS, M1, M2, POLE, BUOY_R } from './course.js';

export const VMAX = 22.6;          // 約 81 km/h
export const ACC = 7.0;            // 全開時の推力加速度
export const K1 = 0.08;
export const K2 = (ACC - K1 * VMAX) / (VMAX * VMAX);
export const IDLE = 0.08;          // アイドリングでのわずかな前進
export const KLAT = 9.0;           // 横滑り減衰
export const GRIP = 13.5;          // 横グリップ限界 (m/s^2)
export const KDRIFT = 0.3;         // 横滑りによる前進抵抗
export const KWV = 1.3;            // 風見効果の強さ
export const YAW_MAX = 1.6;        // 最大ヨーレート (rad/s)
export const YAW_RESP = 7.0;       // 舵の応答
export const BRAKE = 5.0;
export const CIRC = [-1.05, 0, 1.05];   // 艇体を3つの円で近似
export const CR = 0.68;
const INERTIA = 1.25;
const REST = 0.25;

const smooth = (a, b, x) => { const t = clamp((x - a) / (b - a), 0, 1); return t * t * (3 - 2 * t); };

// チルト角度: 下げると出足と回り足、上げると伸び(最高速)が良くなる
export const TILTS = [
  { deg: -0.5, label: '-0.5°', note: '出足・回り足', acc: 1.085, top: 0.965, grip: 1.065 },
  { deg: 0.0, label: '0°', note: 'バランス', acc: 1.0, top: 1.0, grip: 1.0 },
  { deg: 1.5, label: '+1.5°', note: '伸び寄り', acc: 0.94, top: 1.035, grip: 0.945 },
  { deg: 3.0, label: '+3.0°', note: '伸び特化', acc: 0.88, top: 1.075, grip: 0.89 },
];
// 低〜中速では出足の係数、最高速付近では伸びの係数が効く
const tiltMix = (b, fs) => b.accF + (b.topF - b.accF) * smooth(0.4, 0.975, fs);
export function applyTilt(b, k) { const t = TILTS[k]; b.tilt = k; b.accF = t.acc; b.topF = t.top; b.gripSet = t.grip; }
const WIND_K = 0.045;              // 追い風・向かい風による加速度 (m/s^2 per m/s)


export function makeBoat(i) {
  return {
    i, num: i + 1,
    x: 0, z: 0, h: 0, vx: 0, vz: 0, w: 0,
    throttle: 0, steer: 0, brake: 0,          // 実際の操作量(なめらかに追従)
    cmdThrottle: 0, cmdSteer: 0, cmdBrake: 0, // 入力
    motor: 1, gripF: 1, thrustF: 1, inWake: 0,
    accF: 1, topF: 1, gripSet: 1, chop: 1,   // チルト角度と水面状況による補正
    speed: 0, vf: 0, vl: 0, af: 0, turnInt: 0,
    bump: 0, bumpSide: 0,                     // 衝突の揺れ(表示用)
    isPlayer: false, ai: null,
    trail: [], trailT: 0,
  };
}

export function stepBoat(b, dt, env) {
  // 操作のなまし(スロットルレバー/ハンドル)
  const tr = b.cmdThrottle > b.throttle ? 3.2 : 5.0;
  b.throttle += clamp(b.cmdThrottle - b.throttle, -tr * dt, tr * dt);
  const sr = Math.abs(b.cmdSteer) > Math.abs(b.steer) || b.cmdSteer * b.steer < 0 ? 4.5 : 6.5;
  b.steer += clamp(b.cmdSteer - b.steer, -sr * dt, sr * dt);
  b.brake += clamp(b.cmdBrake - b.brake, -6 * dt, 6 * dt);

  let ch = Math.cos(b.h), sh = Math.sin(b.h);
  const vf0 = b.vx * ch + b.vz * sh;
  const sp = Math.abs(vf0);

  // ヨー: 速度があるほど舵が効く。極低速ではプロペラ推力で向きを変える
  const hull = smooth(0.5, 6, sp);
  const auth = hull * (1 - 0.24 * Math.min(1, sp / VMAX)) + 0.3 * b.throttle * (1 - hull);
  // 風見効果: 艇が進行方向から大きく振れると、水の抵抗で向きが戻される(スピンしすぎない)
  const vl0 = -b.vx * Math.sin(b.h) + b.vz * ch;
  const wT = -b.steer * YAW_MAX * auth * (0.75 + 0.25 * b.gripF) + KWV * vl0 / Math.max(sp, 4) * hull;
  b.w += (wT - b.w) * (1 - Math.exp(-YAW_RESP * dt));
  b.h += b.w * dt;

  ch = Math.cos(b.h); sh = Math.sin(b.h);
  let vf = b.vx * ch + b.vz * sh;
  let vl = -b.vx * sh + b.vz * ch;

  const fs = Math.min(1.2, sp / VMAX);
  const thrust = b.throttle * ACC * b.motor * b.thrustF * tiltMix(b, fs) + IDLE;
  const sgn = vf >= 0 ? 1 : -1;
  let af = thrust - K1 * vf - K2 * vf * Math.abs(vf)
    - sgn * (KDRIFT * Math.abs(vl) + b.brake * BRAKE * smooth(0, 3, sp));
  if (env) af += WIND_K * (env.wx * ch + env.wz * sh) * smooth(2, 10, sp);
  const G = GRIP * b.gripF * b.gripSet;
  const al = -clamp(KLAT * vl, -G, G);
  vf += af * dt;
  vl += al * dt;

  b.vx = vf * ch - vl * sh;
  b.vz = vf * sh + vl * ch;
  b.x += b.vx * dt;
  b.z += b.vz * dt;

  b.vf = vf; b.vl = vl; b.af = af;
  b.speed = Math.hypot(b.vx, b.vz);
  b.turnInt = clamp(Math.abs(vl) / 5 + Math.abs(b.w) * sp / 28, 0, 1);
  b.bump *= Math.exp(-5 * dt);
}

// 全開で dist 進むのにかかる時間(スタートの起こしタイミング予測)
export function timeToCover(dist, v, b, env) {
  if (dist <= 0) return 0;
  const dt = 0.02, wind = env ? WIND_K * env.wx : 0;
  let t = 0, d = 0;
  while (d < dist && t < 30) {
    const fs = Math.min(1.2, v / VMAX);
    v += (ACC * b.motor * tiltMix(b, fs) + IDLE - K1 * v - K2 * v * v + wind * smooth(2, 10, v)) * dt;
    d += v * dt; t += dt;
  }
  return t - (d - dist) / Math.max(v, 0.1);
}

// 艇どうしの衝突。3円×3円で最も深い接触を1つ解決する
export function collideBoats(a, b) {
  const dx0 = b.x - a.x, dz0 = b.z - a.z;
  if (dx0 * dx0 + dz0 * dz0 > 18) return null;
  const ca = Math.cos(a.h), sa = Math.sin(a.h), cb = Math.cos(b.h), sb = Math.sin(b.h);
  let best = 0, nx = 0, nz = 0, pax = 0, paz = 0, pbx = 0, pbz = 0;
  const D = 2 * CR;
  for (let i = 0; i < 3; i++) {
    const ax = a.x + ca * CIRC[i], az = a.z + sa * CIRC[i];
    for (let j = 0; j < 3; j++) {
      const bx = b.x + cb * CIRC[j], bz = b.z + sb * CIRC[j];
      const dx = bx - ax, dz = bz - az, d2 = dx * dx + dz * dz;
      if (d2 < D * D) {
        const d = Math.sqrt(d2) || 1e-4, pen = D - d;
        if (pen > best) { best = pen; nx = dx / d; nz = dz / d; pax = ax; paz = az; pbx = bx; pbz = bz; }
      }
    }
  }
  if (best <= 0) return null;
  // めり込み解消
  const h = best * 0.5;
  a.x -= nx * h; a.z -= nz * h; b.x += nx * h; b.z += nz * h;
  const cx = (pax + pbx) * 0.5, cz = (paz + pbz) * 0.5;
  const rax = cx - a.x, raz = cz - a.z, rbx = cx - b.x, rbz = cz - b.z;
  const vax = a.vx - a.w * raz, vaz = a.vz + a.w * rax;
  const vbx = b.vx - b.w * rbz, vbz = b.vz + b.w * rbx;
  const rvx = vbx - vax, rvz = vbz - vaz;
  const vn = rvx * nx + rvz * nz;
  if (vn >= 0) return { power: 0, x: cx, z: cz };
  const ran = rax * nz - raz * nx, rbn = rbx * nz - rbz * nx;
  const j = -(1 + REST) * vn / (2 + (ran * ran + rbn * rbn) / INERTIA);
  a.vx -= j * nx; a.vz -= j * nz; b.vx += j * nx; b.vz += j * nz;
  a.w -= ran * j / INERTIA; b.w += rbn * j / INERTIA;
  // 接線方向の摩擦(こすれ合い)
  const tx = -nz, tz = nx, vt = rvx * tx + rvz * tz;
  const jt = clamp(-vt * 0.25, -0.35 * j, 0.35 * j);
  a.vx -= jt * tx; a.vz -= jt * tz; b.vx += jt * tx; b.vz += jt * tz;
  a.bump = Math.min(1, a.bump + j * 0.25); b.bump = Math.min(1, b.bump + j * 0.25);
  a.bumpSide = (nx * -sa + nz * ca) > 0 ? 1 : -1;   // +1: 右舷に接触
  b.bumpSide = (nx * -sb + nz * cb) < 0 ? 1 : -1;
  return { power: j, x: cx, z: cz };
}

// 消波装置(外周)との衝突
export function collideWalls(b) {
  const m = 1.0;
  let power = 0;
  if (b.x < BOUNDS.minX + m) { b.x = BOUNDS.minX + m; if (b.vx < 0) { power = -b.vx; b.vx *= -0.3; b.vz *= 0.8; } }
  else if (b.x > BOUNDS.maxX - m) { b.x = BOUNDS.maxX - m; if (b.vx > 0) { power = b.vx; b.vx *= -0.3; b.vz *= 0.8; } }
  if (b.z < BOUNDS.minZ + m) { b.z = BOUNDS.minZ + m; if (b.vz < 0) { power = Math.max(power, -b.vz); b.vz *= -0.3; b.vx *= 0.8; } }
  else if (b.z > BOUNDS.maxZ - m) { b.z = BOUNDS.maxZ - m; if (b.vz > 0) { power = Math.max(power, b.vz); b.vz *= -0.3; b.vx *= 0.8; } }
  if (power > 0) b.bump = Math.min(1, b.bump + power * 0.1);
  return power;
}

// ターンマーク/センターポールとの接触。ブイは浮いているので柔らかく押し返す
const OBST = [
  { x: M1.x, z: M1.z, r: BUOY_R, id: 1, soft: 0.55 },
  { x: M2.x, z: M2.z, r: BUOY_R, id: 2, soft: 0.55 },
  { x: POLE.x, z: POLE.z, r: POLE.r, id: 0, soft: 1 },
];
export function collideObstacles(b) {
  let hit = null;
  const ch = Math.cos(b.h), sh = Math.sin(b.h);
  for (const o of OBST) {
    const ddx = b.x - o.x, ddz = b.z - o.z;
    if (ddx * ddx + ddz * ddz > 9) continue;
    for (let i = 0; i < 3; i++) {
      const px = b.x + ch * CIRC[i], pz = b.z + sh * CIRC[i];
      const dx = px - o.x, dz = pz - o.z, R = CR + o.r, d2 = dx * dx + dz * dz;
      if (d2 < R * R) {
        const d = Math.sqrt(d2) || 1e-4, nx = dx / d, nz = dz / d, pen = R - d;
        b.x += nx * pen * o.soft; b.z += nz * pen * o.soft;
        const vn = b.vx * nx + b.vz * nz;
        if (vn < 0) {
          const k = (o.id === 0 ? 1.2 : 0.6) * vn;   // ブイは浮いているので弾かれにくい
          b.vx -= k * nx; b.vz -= k * nz;
          b.w += (CIRC[i] * (ch * nz - sh * nx)) * (-vn) * 0.25;
          b.vx *= 0.985; b.vz *= 0.985;
          b.bump = Math.min(1, b.bump + -vn * 0.08);
          if (!hit || -vn > hit.power) hit = { id: o.id, power: -vn, nx, nz };
        }
      }
    }
  }
  return hit;
}
