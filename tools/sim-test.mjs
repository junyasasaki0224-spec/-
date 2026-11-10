// ヘッドレスでレースを回して AI と物理の挙動を確認する: node tools/sim-test.mjs [回数] [難易度] [svg出力先]
import fs from 'node:fs';
import { Race, DT, makeConfig } from '../src/sim/race.js';
import { M1, M2, BOUNDS } from '../src/sim/course.js';

const N = +(process.argv[2] || 5), diff = +(process.argv[3] || 1), svgOut = process.argv[4];
const wins = [0, 0, 0, 0, 0, 0], kim = {};
let svg = '';
const COL = ['#ccc', '#222', '#e22', '#22e', '#dd0', '#0a0'];
for (let n = 0; n < N; n++) {
  const race = new Race(makeConfig({ difficulty: diff, seed: 1000 + n }));
  const paths = race.boats.map(() => []);
  let hits = 0, walls = 0, buoys = 0, t = 0, maxV = 0, minTurnV = 99;
  while (race.state !== 'done' && t < 400) {
    race.step(DT, null); t += DT;
    for (const e of race.events) { if (e.type === 'hit') hits++; if (e.type === 'wall') walls++; if (e.type === 'buoy') buoys++; }
    race.events.length = 0;
    if (Math.round(t / DT) % 12 === 0) race.boats.forEach((b, i) => paths[i].push(`${b.x.toFixed(1)},${b.z.toFixed(1)}`));
    for (const b of race.boats) { maxV = Math.max(maxV, b.speed); if (b.started && Math.abs(b.x) > 150) minTurnV = Math.min(minTurnV, b.speed); }
  }
  const res = race.order.map((b) => `${b.num}(${b.finishTime ? b.finishTime.toFixed(1) : '--'})`).join(' ') + ` | wind ${race.weather.wind} tilt ${race.cfg.tilts.join('')}`;
  const sts = race.boats.map((b) => (b.st ?? NaN).toFixed(2)).join(' ');
  console.log(`#${n} ${res} | ST ${sts} | ${race.kimarite} | hit ${hits} wall ${walls} buoy ${buoys} | vmax ${(maxV * 3.6).toFixed(0)} minTurn ${(minTurnV * 3.6).toFixed(0)} | t=${t.toFixed(0)}`);
  wins[race.order[0].i]++; kim[race.kimarite] = (kim[race.kimarite] || 0) + 1;
  if (n === 0) svg = paths.map((p, i) => `<polyline points="${p.join(' ')}" fill="none" stroke="${COL[i]}" stroke-width="0.5"/>`).join('\n');
}
console.log('wins by lane:', wins.join(' '), kim);
if (svgOut) {
  const b = BOUNDS;
  fs.writeFileSync(svgOut, `<svg xmlns="http://www.w3.org/2000/svg" viewBox="${b.minX - 5} ${b.minZ - 5} ${b.maxX - b.minX + 10} ${b.maxZ - b.minZ + 10}" width="1600" style="background:#8ab">
<rect x="${b.minX}" y="${b.minZ}" width="${b.maxX - b.minX}" height="${b.maxZ - b.minZ}" fill="#4a8ca8"/>
${svg}
<circle cx="${M1.x}" cy="${M1.z}" r="1.2" fill="red"/><circle cx="${M2.x}" cy="${M2.z}" r="1.2" fill="red"/>
<line x1="0" y1="4" x2="0" y2="58" stroke="#fff" stroke-width="0.4"/></svg>`);
}
