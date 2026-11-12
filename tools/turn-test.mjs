// ターンの回り方ごとの比較: 80km/h で直進 → 回り方を変えて180度回り、元の地点を逆向きに通過するまでの時間
//   node tools/turn-test.mjs
import { makeBoat, stepBoat } from '../src/sim/physics.js';
const DT = 1 / 120;
const policies = {
  'レバー全落とし+全切り(最小回り)': (b) => ({ th: 0, st: 1 }),
  'レバー半分+全切り': (b) => ({ th: 0.5, st: 1 }),
  '全開のまま全切り': (b) => ({ th: 1, st: 1 }),
  '0.5秒落としてから全開で全切り': (b, t) => ({ th: t < 0.5 ? 0 : 1, st: 1 }),
  '1秒落としてから全開で全切り': (b, t) => ({ th: t < 1.0 ? 0 : 1, st: 1 }),
};
for (const [name, pol] of Object.entries(policies)) {
  const b = makeBoat(0); b.vx = 22.6; b.throttle = 1;
  let t = 0, turned = false, minV = 99, maxZ = 0, turnT = 0;
  while (t < 20) {
    let c = turned ? { th: 1, st: 0 } : pol(b, t);
    if (turned) { // 180度回ったら真っすぐ戻す
      let e = Math.PI - (b.h % (2 * Math.PI)); c.st = Math.max(-1, Math.min(1, -e * 3));
    }
    b.cmdThrottle = c.th; b.cmdSteer = c.st;
    stepBoat(b, DT); t += DT;
    if (!turned) { minV = Math.min(minV, b.speed); maxZ = Math.max(maxZ, Math.abs(b.z)); }
    if (!turned && Math.abs(b.h) >= Math.PI) { turned = true; turnT = t; }
    if (turned && b.x <= -30) break;
  }
  console.log(`${name.padEnd(22)} 復帰まで ${t.toFixed(2)}秒 | 180度に ${turnT.toFixed(2)}秒 | ターン幅 ${maxZ.toFixed(1)}m | 最低速度 ${(minV * 3.6).toFixed(0)}km/h`);
}
