// AI レーサー。スタートは大時計を見て起こしタイミングを合わせ、
// レース中はターンマークごとに「進入 → 旋回円 → 立ち上がり」の走行ラインを組み立てて追従する。
import { PI, clamp, wrapAngle, sm, lerp, M1, M2, BOUNDS, region } from './course.js';
import { timeToCover } from './physics.js';

const DIFF = [
  { motor: [0.90, 0.95], skill: 0.88, st: [0.12, 0.34] },   // 初級
  { motor: [0.955, 0.995], skill: 0.96, st: [0.08, 0.26] }, // 中級
  { motor: [0.99, 1.03], skill: 1.03, st: [0.04, 0.19] },   // 上級
];
const ST_LAG = 0.15;   // レバー操作の遅れぶん早めに起こす

export function initAI(b, rng, difficulty, lane) {
  const D = DIFF[difficulty];
  b.motor = D.motor[0] + (D.motor[1] - D.motor[0]) * rng();
  b.ai = {
    skill: D.skill * (0.97 + 0.06 * rng()),
    stTarget: D.st[0] + (D.st[1] - D.st[0]) * rng(),
    going: false,
    sashi: lane >= 1 && rng() < 0.45,   // 1周目1マーク: 差し狙いか、まくり狙いか
    lane, rng,
    plan: null, planMark: 0, refined: false, firstTurn: true,
    k: 0, dodge: 0, wob: rng() * 10, stuck: 0, off: 0,
  };
}

// 自分より内側で並走している艇の数
function countInside(b, boats, M) {
  let n = 0;
  const d = Math.abs(b.z - M.z);
  for (const o of boats) {
    if (o === b) continue;
    if (Math.abs(o.R - b.R) < 7 && Math.hypot(o.x - b.x, o.z - b.z) < 28 && Math.abs(o.z - M.z) < d) n++;
  }
  return n;
}

// マーク mark(1|2) を回る走行ラインを現在位置から組み立てる
function makePlan(b, mark, boats) {
  const ai = b.ai, r = ai.rng;
  const s = mark === 1 ? 1 : -1, M = mark === 1 ? M1 : M2;
  const u0 = (b.x - M.x) * s, v0 = (b.z - M.z) * s;
  const maxV = (mark === 1 ? BOUNDS.maxZ - M.z : M.z - BOUNDS.minZ) - 5;
  let n = countInside(b, boats, M), dA, c, exit;
  if (ai.firstTurn && mark === 1) {
    // スタート直後は枠なりのまま横一線で1マークへ
    n = Math.max(n, ai.refined ? 0 : ai.lane);
    dA = 8 + 3.4 * ai.lane;
    if (ai.sashi) { c = 3.8 + 1.0 * Math.min(n, 2) + r(); exit = 12 + 2 * n + r() * 4; }
    else { c = 3.8 + 1.7 * n + r(); exit = 14 + 2.4 * n + r() * 4; }
  } else {
    dA = clamp(Math.max(v0, 6), 11 + 1.5 * n, 20 + 2 * n) + (r() - 0.5) * 3;
    c = 3.8 + 2.0 * n + r() * 1.2;
    exit = 14 + 2.8 * n + r() * 6;
  }
  if (ai.refined) dA = clamp(v0, 7, maxV);          // 直前の組み直しは今の位置から
  dA = Math.min(dA, maxV);
  const rho = Math.max(9.3 + r() * 1.2, (dA + c) / 2 + 0.4);
  const dC = dA - rho;
  const ux = -Math.sqrt(Math.max(0, (rho - c) * (rho - c) - dC * dC));
  const xs = [], zs = [];
  const push = (u, v) => { xs.push(M.x + s * u); zs.push(M.z + s * v); };
  // 進入
  if (u0 < ux - 3) {
    const len = ux - u0, steps = Math.max(2, Math.ceil(len / 5));
    for (let i = 0; i < steps; i++) {
      const t = i / steps;
      push(u0 + len * t, lerp(v0, dA, sm(t / 0.75)));
    }
  }
  const kT = xs.length;
  // 旋回円
  for (let i = 0; i <= 14; i++) {
    const th = PI * i / 14;
    push(ux + rho * Math.sin(th), dC + rho * Math.cos(th));
  }
  // 立ち上がり: 外へ流れながらバック(ホーム)ストレッチへ
  const vEnd = dC - rho;
  for (let u = ux - 5; u > -175; u -= 5) push(u, lerp(vEnd, -Math.max(exit, -vEnd), sm((ux - u) / 60)));
  ai.plan = { xs, zs, kT, ux, s, M, vArc: Math.sqrt(11.6 * ai.skill * rho) };
  ai.planMark = mark;
  // 最も近い点から追従を始める
  let best = 1e9, k = 0;
  for (let i = 0; i < xs.length; i++) {
    const d = (xs[i] - b.x) ** 2 + (zs[i] - b.z) ** 2;
    if (d < best) { best = d; k = i; }
  }
  ai.k = k;
}

export function updateAI(b, race, dt) {
  const ai = b.ai;
  ai.wob += dt;

  // ---- スタート前: レーンを保ち、起こしのタイミングを計る ----
  if (!b.started) {
    const hd = clamp((b.laneZ - b.z) * 0.05, -0.2, 0.2);
    b.cmdSteer = clamp(-(hd - b.h) * 3, -1, 1);
    const remain = -race.clock + ai.stTarget - ST_LAG;
    const tArr = timeToCover(-b.x, Math.max(b.vf, 0), b.motor);
    if (!ai.going) {
      if (tArr >= remain) ai.going = true;
      b.cmdThrottle = 0;
    }
    if (ai.going) b.cmdThrottle = tArr < remain - 0.04 ? 0.5 : 1;
    b.cmdBrake = 0;
    return;
  }

  // ---- どのマークへ向かうか ----
  const reg = region(b.x, b.z);
  if (b.offCourse) {
    // 接触などでマークの内側へ押し込まれた場合は周回扱いにして復帰する
    ai.off += dt;
    if (ai.off > 0.4 && (reg + 2) % 4 === b.lastValid) { b.sectorCount += 2; b.lastValid = reg; ai.off = 0; }
  } else ai.off = 0;
  const lv = b.lastValid;
  const want = (lv === 0 && b.x >= 0) || lv === 1 || (lv === 2 && b.x > 0) ? 1 : 2;
  if (want !== ai.planMark || !ai.plan) { ai.refined = false; makePlan(b, want, race.boats); }
  let P = ai.plan;
  const uNow = (b.x - P.M.x) * P.s;
  if (!ai.refined && uNow > -42 && uNow < P.ux - 8) { ai.refined = true; makePlan(b, want, race.boats); P = ai.plan; }
  if (ai.firstTurn && lv === 2) ai.firstTurn = false;

  // ---- ライン追従(ピュアパシュート) ----
  const xs = P.xs, zs = P.zs, N = xs.length, sp = b.speed;
  let k = ai.k, bd = (xs[k] - b.x) ** 2 + (zs[k] - b.z) ** 2;
  for (let i = k + 1; i < Math.min(N, k + 8); i++) {
    const d = (xs[i] - b.x) ** 2 + (zs[i] - b.z) ** 2;
    if (d < bd) { bd = d; k = i; }
  }
  ai.k = k;
  if (bd > 30 * 30) { makePlan(b, want, race.boats); return; }
  const L = 6.5 + sp * 0.5;
  let j = k, tx = xs[k], tz = zs[k];
  while (j < N - 1) {
    const d = Math.hypot(xs[j + 1] - b.x, zs[j + 1] - b.z);
    if (d >= L) {
      const d0 = Math.hypot(xs[j] - b.x, zs[j] - b.z);
      const t = d0 >= L ? 0 : (L - d0) / Math.max(d - d0, 1e-3);
      tx = lerp(xs[j], xs[j + 1], t); tz = lerp(zs[j], zs[j + 1], t);
      break;
    }
    j++; tx = xs[j]; tz = zs[j];
  }

  // 直線では前の艇を避けて進路をずらす
  let dodgeT = 0;
  const ch = Math.cos(b.h), sh = Math.sin(b.h);
  if (reg === 0 || reg === 2) {
    for (const o of race.boats) {
      if (o === b) continue;
      const rx = o.x - b.x, rz = o.z - b.z;
      const ahead = rx * ch + rz * sh, side = -rx * sh + rz * ch;
      if (ahead > 0.5 && ahead < 12 && Math.abs(side) < 2.4 && sp > o.speed - 1) dodgeT = side > 0 ? -3.2 : 3.2;
    }
  }
  ai.dodge += clamp(dodgeT - ai.dodge, -7 * dt, 7 * dt);
  tx += -sh * ai.dodge; tz += ch * ai.dodge;
  tz = clamp(tz, BOUNDS.minZ + 4, BOUNDS.maxZ - 4);
  tx = clamp(tx, BOUNDS.minX + 4, BOUNDS.maxX - 4);

  const dx = tx - b.x, dz = tz - b.z, dist = Math.hypot(dx, dz) || 1;
  const err = wrapAngle(Math.atan2(dz, dx) - b.h);
  const noise = Math.sin(ai.wob * 2.3 + b.i) * 0.03 * (1.15 - ai.skill * 0.6);
  b.cmdSteer = clamp(-(err + noise) * 3.2, -1, 1);

  // ---- スロットル ----
  // 旋回に必要な横Gから目標速度を決め、超えていればレバーを落とす
  const kappa = 2 * Math.sin(Math.min(Math.abs(err), PI / 2)) / dist;
  const aLim = 11.6 * ai.skill * b.gripF;
  const vT = Math.max(9.5, Math.sqrt(aLim / Math.max(kappa, 1e-4)));
  let thr = clamp(0.55 + (vT - sp) * 0.45, 0.1, 1);
  // ターン進入前の減速(少しオーバースピード気味に入って艇を流す)
  const dT = P.ux - uNow;
  if (dT > 0 && dT < 60) {
    let vIn = P.vArc * 1.16;
    if (ai.firstTurn && ai.sashi) vIn *= 0.93;      // 差しは一呼吸おいて内を突く
    if (sp * sp - vIn * vIn > 2 * 6.2 * dT) thr = 0.05;
  }
  b.cmdThrottle = thr;
  b.cmdBrake = 0;

  // 壁などに引っかかった時の復帰
  if (sp < 1.5) { ai.stuck += dt; if (ai.stuck > 1.2) b.cmdThrottle = 1; } else ai.stuck = 0;
}
