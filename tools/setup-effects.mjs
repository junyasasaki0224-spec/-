import { makeBoat, stepBoat, applyTilt, TILTS, timeToCover, GRIP } from '../src/sim/physics.js';
import { Race, makeConfig, DT } from '../src/sim/race.js';
import { motorFactor } from '../src/sim/roster.js';
const top = (b, env) => { b.vx = 15; for (let i = 0; i < 120 * 40; i++) { b.cmdThrottle = 1; b.z = 0; b.h = 0; stepBoat(b, 1 / 120, env); } return b.speed * 3.6; };
const mk = (tilt = 1, motor = 1) => { const b = makeBoat(0); applyTilt(b, tilt); b.motor = motor; return b; };
console.log('== チルト ==');
for (let k = 0; k < 4; k++) {
  const b = mk(k);
  console.log(TILTS[k].label, 'top', top(mk(k)).toFixed(1), 'km/h | 0→110m', timeToCover(110, 0, b).toFixed(2), 's | 0→190m', timeToCover(190, 0, b).toFixed(2), 's | 40→80km/h相当 30m加速', (timeToCover(60, 9, b)).toFixed(2), 's | grip', (TILTS[k].grip * 100).toFixed(0) + '%');
}
console.log('== モーター2連率 ==');
for (const r of [28, 38, 48]) { const m = motorFactor(r), b = mk(1, m); console.log(r + '%', 'factor', m.toFixed(4), 'top', top(mk(1, m)).toFixed(1), '0→110m', timeToCover(110, 0, b).toFixed(2)); }
console.log('== 風 ==');
for (const w of [-6, -3, 0, 3, 6]) { const env = { wx: w, wz: 0 }, b = mk(); console.log((w < 0 ? '向かい風' : w > 0 ? '追い風' : '無風') + Math.abs(w) + 'm', 'ホーム直線top', top(mk(), env).toFixed(1), '0→110m', timeToCover(110, 0, b, env).toFixed(2), '0→190m', timeToCover(190, 0, b, env).toFixed(2)); }
// レース全体での影響: 1号艇だけ条件を変えて同じシードで走らせ、ゴールタイムを比べる
const avg = (fn) => { let s = 0, n = 0; for (let seed = 1; seed <= 14; seed++) { const t = fn(seed); if (t > 0) { s += t; n++; } } return s / n; };
const run = (o) => (seed) => { const c = makeConfig({ seed, difficulty: 2, weather: { wind: 0, windDir: 0, wave: 0, cover: 0.4 }, ...o(seed) }); const r = new Race(c); let t = 0; while (r.state !== 'done' && t < 300) { r.step(DT, null); t += DT; } return r.boats[0].finishTime; };
const N = 40;
const avg2 = (fn) => { let s = 0, n = 0, w = 0; for (let seed = 1; seed <= N; seed++) { const r = fn(seed); if (r.t > 0) { s += r.t; n++; } w += r.win; } return (s / n).toFixed(2) + ' 勝率' + (w / N * 100).toFixed(0) + '%'; };
const run2 = (lane, o) => (seed) => { const c = makeConfig({ seed, difficulty: 2, weather: { wind: 0, windDir: 0, wave: 0, cover: 0.4 }, ...o(seed) }); const r = new Race(c); let t = 0; while (r.state !== 'done' && t < 300) { r.step(DT, null); t += DT; } return { t: r.boats[lane].finishTime, win: r.order[0].i === lane ? 1 : 0 }; };
for (const lane of [0, 4]) { console.log('-- ' + (lane + 1) + 'コース --'); for (let k = 0; k < 4; k++) { const tl = [1, 1, 1, 1, 1, 1]; tl[lane] = k; console.log('tilt', TILTS[k].label, avg2(run2(lane, () => ({ tilts: tl })))); } }
