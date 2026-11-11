// AIのみでレースを回し、走破タイム・ラップ・脚質別成績を検証する
import { RACES, COURSES, makeField, makeConditions, fmtTime, STYLES, GOING } from '../js/data.js';
import { Race } from '../js/sim.js';
const N = +(process.argv[2] || 20);
for (const race of RACES) {
  const styleWin = [0, 0, 0, 0], styleCnt = [0, 0, 0, 0];
  let tSum = 0, l3 = 0, cnt = 0, eSum = 0, spentN = 0; let sample = '';
  const t0 = Date.now();
  for (let k = 0; k < N; k++) {
    const horses = makeField(race, 100 + k);
    const cond = makeConditions(race, 500 + k);
    if (process.argv[3] === 'good') { cond.going = 0; cond.wind.speed = 0; cond.rough = 0; }
    const r = new Race({ course: COURSES[race.course], dist: race.dist, horses, cond, seed: k + 1, playerIdx: -1 });
    const fo = r.runAll(1 / 30);
    if (cond.going === 0) { tSum += fo[0].ft; l3 += fo[0].last3f; cnt++; }
    styleWin[fo[0].h.style]++;
    for (const h of horses) styleCnt[h.style]++;
    for (const x of fo) { eSum += x.m.eFin; if (x.m.emptyRem > 30) spentN++; }
    if (k === 0) sample = `  例: ${fmtTime(fo[0].ft)} (${GOING[cond.going]}) 上がり${fo[0].last3f.toFixed(1)} 1000m${r.pass1000.toFixed(1)} ラップ ${r.splits.map(x => x.toFixed(1)).join('-')}\n   着順脚質 ${fo.map(x => STYLES[x.h.style][0]).join('')} 着差(最後尾) ${(fo[fo.length - 1].ft - fo[0].ft).toFixed(1)}s 2着差 ${(fo[1].ft - fo[0].ft).toFixed(2)}s`;
  }
  console.log(`${race.name} ${race.dist}m par ${fmtTime(race.par)}: 良平均 ${fmtTime(tSum / cnt)} 上がり ${(l3 / cnt).toFixed(1)}  脚質勝率 ${styleWin.map((w, i) => STYLES[i] + ' ' + w + '/' + (styleCnt[i] / N).toFixed(1)).join(' ')}  残E ${(eSum / N / race.n).toFixed(1)} バテ ${(spentN / N).toFixed(1)}頭  ${(Date.now() - t0) / N | 0}ms/race`);
  console.log(sample);
}
