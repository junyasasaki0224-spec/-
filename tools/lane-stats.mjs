// コース別1着・1周1マークを回った後の先頭・決まり手を測る: node tools/lane-stats.mjs . [レース数] [難易度]
import { pathToFileURL } from 'node:url';
import path from 'node:path';
const { Race, DT, makeConfig } = await import(pathToFileURL(path.resolve(process.argv[2] || '.', 'src/sim/race.js')).href);
const N = +(process.argv[3] || 120), diff = +(process.argv[4] || 1);
const wins = [0, 0, 0, 0, 0, 0], t1 = [0, 0, 0, 0, 0, 0], kim = {}; let t1won = 0, bkwon = 0, bk = [0,0,0,0,0,0], sinks = 0, lapT = 0;
for (let n = 0; n < N; n++) {
  const r = new Race(makeConfig({ difficulty: diff, seed: 1000 + n })); let first = -1, back = -1;
  while (r.state !== 'done' && r.clock < 400) { r.step(DT, null); for (const e of r.events) { if (e.type === 'turn1' && first < 0) first = e.boat; if (e.type === 'sink') sinks++; } r.events.length = 0; const L = r.order[0]; if (back < 0 && L.sectorCount >= 2 && L.x < 60) back = L.i; }
  const w = r.order[0].i; wins[w]++; if (first >= 0) { t1[first]++; if (first === w) t1won++; } if (back >= 0) { bk[back]++; if (back === w) bkwon++; } kim[r.kimarite] = (kim[r.kimarite] || 0) + 1; lapT += r.order[0].finishTime;
}
const pct = (a) => a.map((v) => Math.round(v / N * 100)).join('/');
console.log(`wins% ${pct(wins)} | first at M1% ${pct(t1)} | M1 leader wins ${Math.round(t1won / N * 100)}% | backstretch leader% ${pct(bk)} wins ${Math.round(bkwon / N * 100)}% | ${JSON.stringify(kim)} | sinks ${sinks} | win time ${(lapT / N).toFixed(1)}s`);
