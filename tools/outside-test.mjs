// 外枠(4・5コース)の艇に「上手い選手の走り」をさせたら勝てるかを測る
import { Race, makeConfig, DT } from '../src/sim/race.js';
const N = 40;
const trial = (lane, mod) => {
  let win = 0, top2 = 0, t1 = 0;
  for (let seed = 1; seed <= N; seed++) {
    const r = new Race(makeConfig({ seed, difficulty: 1, tilts: [1, 1, 1, 1, 1, 1], weather: { wind: 0, windDir: 0, wave: 0, cover: 0.4 } }));
    const b = r.boats[lane]; mod(b);
    let t = 0; while (r.state !== 'done' && t < 300) { r.step(DT, null); r.events.length = 0; t += DT; }
    if (r.order[0].i === lane) win++; if (r.order[0].i === lane || r.order[1].i === lane) top2++;
    if (r.turn1.order[0] === lane) t1++;
  }
  return `1着 ${(win / N * 100).toFixed(0)}%  2着以内 ${(top2 / N * 100).toFixed(0)}%  1マーク先取り ${(t1 / N * 100).toFixed(0)}%`;
};
for (const lane of [3, 4]) {
  console.log(`== ${lane + 1}コース ==`);
  console.log('普通の走り              ', trial(lane, () => {}));
  console.log('ST 0.05(他艇より約0.15速い)', trial(lane, (b) => { b.ai.stTarget = 0.05; }));
  console.log('ST 0.05 + まくり狙い     ', trial(lane, (b) => { b.ai.stTarget = 0.05; b.ai.sashi = false; }));
  console.log('ST 0.05 + 差し狙い       ', trial(lane, (b) => { b.ai.stTarget = 0.05; b.ai.sashi = true; }));
  console.log('ST 0.05 + 腕前上級 + まくり', trial(lane, (b) => { b.ai.stTarget = 0.05; b.ai.sashi = false; b.ai.skill = 1.06; }));
}
