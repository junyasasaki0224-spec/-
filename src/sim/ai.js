// AI レーサー。スタートは大時計を見て起こしタイミングを合わせ、
// レース中はターンマークごとに「進入 → 旋回円 → 立ち上がり」の走行ラインを組み立てて追従する。
import { PI, clamp, wrapAngle, sm, lerp, M1, M2, BOUNDS, region, MARK_UNITS } from './course.js';
import { timeToCover, GRIP } from './physics.js';

const ST_LAG = 0.15;   // レバー操作の遅れぶん早めに起こす
const MAKURI_LEAD = 2.2;
const GRIP_USE = 0.86;   // 横グリップの限界の何割まで使って回るか
const ARC_THR = 0.55;     // 旋回中に保つレバーの開き
const MARK_CLEAR = 2.0;   // ターンマークの中心から最低これだけ離れて通す(m)
const UNIT_CLEAR = 2.6;  // マーク横の消波装置から横にこれだけ離れて走る(m)
const TURN_IN = 9;       // 旋回円に入る何m手前でレバーを握り直すか   // 内の艇の前を横切るのに必要なリード(m)。艇の長さの約3/4

// cfg: { skill, st(狙うスタートタイミング), sashi(差しを狙う確率), lane }
export function initAI(b, rng, cfg) {
  b.ai = {
    skill: cfg.skill * (0.985 + 0.03 * rng()),
    stTarget: Math.max(0.02, cfg.st + (rng() - 0.4) * 0.17),   // スタートのばらつき(まくりが生まれる展開のもと)
    going: false,
    sashi: cfg.lane >= 1 && rng() < cfg.sashi,   // 1周目1マーク: 差し狙いか、まくり狙いか
    lane: cfg.lane, rng,
    plan: null, planMark: 0, refined: false, firstTurn: true, effLane: cfg.lane, makuri: 0,
    k: 0, dodge: 0, wob: rng() * 10, stuck: 0, off: 0,
  };
  b.advice = { steer: 0, throttle: 0, lift: false };
}

// 自分より内側で並走している艇の数
function countInside(b, boats, M) {
  let n = 0;
  const d = Math.abs(b.z - M.z);
  for (const o of boats) {
    if (o === b || o.sunk) continue;
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
    // effLane: 内の艇を何艇抜いたかを差し引いた実質のコース(まくりで前に出ると内へ切り込める)
    n = Math.max(n, ai.refined ? 0 : ai.effLane);
    dA = 8 + 3.4 * ai.effLane;
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
  ai.plan = { xs, zs, kT, ux, s, M, vArc: Math.sqrt(GRIP_USE * GRIP * ai.skill * b.gripSet * rho) };
  ai.planMark = mark;
  // 最も近い点から追従を始める
  let best = 1e9, k = 0;
  for (let i = 0; i < xs.length; i++) {
    const d = (xs[i] - b.x) ** 2 + (zs[i] - b.z) ** 2;
    if (d < best) { best = d; k = i; }
  }
  ai.k = k;
}

// apply=false のときは操作せず、助言(b.advice)だけ更新する(プレイヤーのガイド用)
export function updateAI(b, race, dt, apply = true) {
  const ai = b.ai, out = apply ? null : b.advice;
  ai.wob += dt;

  // ---- スタート前: レーンを保ち、起こしのタイミングを計る ----
  if (!b.started) {
    const hd = clamp((b.laneZ - b.z) * 0.05, -0.2, 0.2);
    const st0 = clamp(-(hd - b.h) * 3, -1, 1);
    const remain = -race.clock + ai.stTarget - ST_LAG;
    const tArr = timeToCover(-b.x, Math.max(b.vf, 0), b, race.env);
    let th0 = 0;
    if (!ai.going && tArr >= remain) ai.going = true;
    if (ai.going) th0 = tArr < remain - 0.04 ? 0.5 : 1;
    if (apply) { b.cmdSteer = st0; b.cmdThrottle = th0; b.cmdBrake = 0; }
    else { out.steer = st0; out.throttle = th0; out.lift = false; ai.going = false; }
    return;
  }

  // ---- どのマークへ向かうか ----
  const reg = region(b.x, b.z);
  if (b.offCourse && apply) {
    // 接触などでマークの内側へ押し込まれた場合は、回ったものとして扱って復帰する(AI が立ち往生しないように)
    ai.off += dt;
    if (ai.off > 0.4 && (b.lastValid === 0 || b.lastValid === 2) && reg === b.lastValid + 1) { b.sectorCount++; b.lastValid = reg; ai.off = 0; }
  } else ai.off = 0;
  const lv = b.lastValid;
  const target = lv <= 1 ? 1 : 2;       // 次に回る(いま回っている)マーク
  // 立ち上がってから直線の半ばまでは、回り終えたマークのラインの続き(立ち上がり区間)を追う。
  // ラインを引き直す時は必ず次のマークへ向ける(回り終えたマークへ戻るラインにしない)
  const keepPrev = ai.plan && ai.planMark !== target && ((lv === 2 && b.x > 0) || (lv === 0 && b.x < 0));
  const want = keepPrev ? ai.planMark : target;
  // ---- まくりの判断(1周目1マークの手前) ----
  // 内側の艇より艇首が十分前に出ていれば、その艇の前を横切って内へ切り込む(絞る)
  if (ai.firstTurn && lv === 0 && ai.lane > 0 && b.x > 20 && b.x < 100) {
    let beaten = 0;
    const inner = race.boats.filter((o) => o !== b && !o.out && o.started && o.z < b.z).sort((a, c) => c.z - a.z);   // 近い内側から
    for (const o of inner) { if (b.x - o.x >= MAKURI_LEAD) beaten++; else break; }
    if (beaten > ai.makuri) {
      ai.makuri = beaten; ai.effLane = ai.lane - beaten;
      if (beaten === inner.length) ai.sashi = false;     // 全艇を抜いたなら差しではなくまくりで先に回る
      ai.refined = false; makePlan(b, 1, race.boats);
    }
  }
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
  if (bd > 30 * 30) { ai.refined = false; makePlan(b, target, race.boats); return; }
  if (!apply && bd > 30) {     // プレイヤーがラインを外れたら、今の位置から引き直す
    ai.replanT = (ai.replanT || 0) - dt;
    if (ai.replanT <= 0) {
      ai.replanT = 0.5;
      const M = target === 1 ? M1 : M2, u = (b.x - M.x) * (target === 1 ? 1 : -1);
      ai.refined = u > -42;
      makePlan(b, target, race.boats); return;
    }
  }
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
      if (o === b || o.sunk) continue;
      const rx = o.x - b.x, rz = o.z - b.z;
      const ahead = rx * ch + rz * sh, side = -rx * sh + rz * ch;
      if (ahead > 0.5 && ahead < 12 && Math.abs(side) < 2.4 && sp > o.speed - 1) dodgeT = side > 0 ? -3.2 : 3.2;
    }
  }
  ai.dodge += clamp(dodgeT - ai.dodge, -7 * dt, 7 * dt);
  tx += -sh * ai.dodge; tz += ch * ai.dodge;
  tz = clamp(tz, BOUNDS.minZ + 4, BOUNDS.maxZ - 4);
  tx = clamp(tx, BOUNDS.minX + 4, BOUNDS.maxX - 4);

  // ターンマークをよける: 狙う向きがマークの手前(外側)を MARK_CLEAR 以上あけて通るように、向きを外へ寄せる。
  // 先読みで旋回円の内側を突くと、マークに正面から当たって沈没するため
  {
    const ox = b.x + ch * 1.05, oz = b.z + sh * 1.05;   // 艇首(最初に当たる所)を基準にする
    const mx = P.M.x - ox, mz = P.M.z - oz, dM = Math.hypot(mx, mz);
    if (uNow < 1.5 && dM > MARK_CLEAR && dM < 45) {
      const al = Math.asin(MARK_CLEAR / dM), beta = Math.atan2(mz, mx);
      const d0 = wrapAngle(Math.atan2(tz - oz, tx - ox) - beta);
      if (d0 < al && d0 > -al * 0.5) {
        const th = beta + al, L2 = Math.hypot(tx - ox, tz - oz);
        tx = ox + Math.cos(th) * L2; tz = oz + Math.sin(th) * L2;
      }
    }
  }
  // マーク横の細長い消波装置をよける: 狙う点が浮きの近く(横 UNIT_CLEAR 以内)なら、艇がいる側へ押し出す
  for (const u of MARK_UNITS) {
    const rx = tx - u.x, rz = tz - u.z, al = rx * u.dx + rz * u.dz;
    if (Math.abs(al) > u.len / 2 + 2) continue;
    const lat = -rx * u.dz + rz * u.dx, side = (-(b.x - u.x) * u.dz + (b.z - u.z) * u.dx) >= 0 ? 1 : -1;
    if (lat * side < UNIT_CLEAR) { const push = UNIT_CLEAR * side - lat; tx += -u.dz * push; tz += u.dx * push; }
  }
  const dx = tx - b.x, dz = tz - b.z, dist = Math.hypot(dx, dz) || 1;
  const err = wrapAngle(Math.atan2(dz, dx) - b.h);
  const noise = Math.sin(ai.wob * 2.3 + b.i) * 0.03 * (1.15 - ai.skill * 0.6);
  const steer = clamp(-(err + noise) * 3.2, -1, 1);

  // ---- スロットル ----
  // 旋回に必要な横Gから目標速度を決め、超えていればレバーを落とす
  const kappa = 2 * Math.sin(Math.min(Math.abs(err), PI / 2)) / dist;
  const aLim = GRIP_USE * GRIP * ai.skill * b.gripF * b.gripSet;
  const vT = Math.max(9.5, Math.sqrt(aLim / Math.max(kappa, 1e-4)));
  let thr = clamp(0.55 + (vT - sp) * 0.45, 0.1, 1);
  // ターン進入前の減速(少しオーバースピード気味に入って艇を流す)
  const dT = P.ux - uNow;
  if (dT > 0 && dT < 60) {
    let vIn = P.vArc * 1.16;
    if (ai.firstTurn && ai.sashi) vIn *= 0.93;      // 差しは一呼吸おいて内を突く
    if (sp * sp - vIn * vIn > 2 * 6.2 * dT) thr = dT > TURN_IN ? 0.05 : ARC_THR;   // 切り込む直前にはレバーを握り直す(落としたままだとハンドルが効かない)
  }
  // 前を横切られたら(まくられたら)レバーを落として譲る。突っ込むと接触して両方失速する
  if (reg === 0 || reg === 2) {
    for (const o of race.boats) {
      if (o === b || o.sunk) continue;
      const rx = o.x - b.x, rz = o.z - b.z;
      const ahead = rx * ch + rz * sh, side = -rx * sh + rz * ch;
      if (ahead > 0.3 && ahead < 6 && Math.abs(side) < 2.3) thr = Math.min(thr, 0.25 + 0.1 * ahead);
    }
  }
  // 旋回中はレバーを握ったまま回る(モンキーターン)
  if (k >= P.kT - 1 && k <= P.kT + 12) thr = Math.max(thr, ARC_THR);
  // 壁などに引っかかった時の復帰
  if (sp < 1.5) { ai.stuck += dt; if (ai.stuck > 1.2) thr = 1; } else ai.stuck = 0;
  if (apply) { b.cmdSteer = steer; b.cmdThrottle = thr; b.cmdBrake = 0; }
  else { out.steer = steer; out.throttle = thr; out.lift = thr < 0.5 && sp > 11; }
}
