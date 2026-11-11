import { makeBoat, stepBoat } from '../src/sim/physics.js';
for (const [name, thr, brake] of [['レバーを全部落とす', 0, 0], ['半開(0.5)に戻す', 0.5, 0], ['減速キー(↓)', 0, 1]]) {
  const b = makeBoat(0); b.vx = 22.6; b.throttle = 1; let t = 0, d = 0; const marks = {};
  while (t < 12) {
    b.cmdThrottle = thr; b.cmdBrake = brake; b.z = 0; b.h = 0;
    stepBoat(b, 1 / 120); t += 1 / 120; d += b.speed / 120;
    const k = b.speed * 3.6;
    for (const m of [70, 60, 50, 40, 30, 20, 10]) if (k <= m && marks[m] === undefined) marks[m] = `${t.toFixed(2)}s/${d.toFixed(0)}m`;
    if (t > 0.49 && t < 0.51) marks.g05 = (-b.af / 9.8).toFixed(2) + 'G';
  }
  console.log(name, '| 0.5秒後の減速', marks.g05, '| 80km/hから:', Object.entries(marks).filter(([k]) => k !== 'g05').map(([k, v]) => `${k}km/h ${v}`).join('  '), '| 12秒後', (b.speed * 3.6).toFixed(0), 'km/h');
}
