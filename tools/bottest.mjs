// プレイヤー入力経路の検証: 簡単な操作ボットに騎乗させ、AI騎乗時と着順を比較する
import { RACES, COURSES, makeField, makeConditions, fmtTime } from '../js/data.js';
import { Race } from '../js/sim.js';
const N = +(process.argv[2] || 12), mode = process.argv[3] || 'smart';
for (const race of RACES) {
  let posBot = 0, posAI = 0, empt = 0, fouls = 0, blocked = 0, extra = 0, arAvg = 0;
  for (let k = 0; k < N; k++) {
    const horses = makeField(race, 300 + k), cond = makeConditions(race, 900 + k);
    const pick = k % race.n;
    const mk = (pi) => new Race({ course: COURSES[race.course], dist: race.dist, horses, cond, seed: k + 5, playerIdx: pi, difficulty: 1 });
    const ai = mk(-1); const fa = ai.runAll(1 / 60); posAI += fa.findIndex((r) => r.i === pick) + 1;
    const r = mk(pick), p = r.player, t = r.track; r.openGate();
    let go = true, n = 0, lastWhip = 0;
    while (r.state !== 'done' && n++ < 60 * 400) {
      const rem = r.D - p.s, f = r.feel(p);
      let drive = 0, steer = 0, whip = false, lead = false;
      if (mode === 'dumb') { drive = 1; } // 終始全力で追う
      else if (mode === 'idle') { drive = 0; } // 何もしない
      else {
        const kick = rem < 560;
        const target = kick ? f.ve + 0.15 : f.ve * 0.982 + (p.s < 300 ? 0.5 : 0);
        drive = p.v < target - 0.08 ? 1 : p.v > target + 0.25 ? -1 : 0;
        const wantD = rem < t.straight ? Math.max(p.d, r.rough > 0.5 ? 6 : 1) : 1.0;
        if (p.blocked > 0.2) steer = 1; else if (p.d > wantD + 0.3) steer = -1; else if (p.d < wantD - 0.3) steer = 1;
        if (kick && rem < 380 && r.t - lastWhip > 0.9 && (p.phase % 1 < 0.1 || p.phase % 1 > 0.9)) { whip = true; lastWhip = r.t; }
        if (!p.leadDone && p.s > t.straightStartS + 15) lead = true;
      }
      r.step(1 / 60, { drive, steer, whip, lead, go: go && r.t > 0.12 }); if (r.t > 0.14) go = false;
    }
    const fo = r.finishOrder.slice().sort((a, b) => a.ft - b.ft);
    posBot += fo.indexOf(p) + 1; if (p.m.emptyRem > 25) empt++; fouls += p.m.foul; blocked += p.m.blockedT; extra += p.dist - p.s; arAvg += p.m.arT ? p.m.arSum / p.m.arT : 0;
  }
  console.log(`${race.name.padEnd(12)} 平均着順 bot ${(posBot / N).toFixed(1)} / AI ${(posAI / N).toFixed(1)}  バテ${empt} 斜行${fouls.toFixed(1)} 壁${(blocked / N).toFixed(1)}s ロス${(extra / N).toFixed(0)}m 折合${(arAvg / N).toFixed(2)}`);
}
