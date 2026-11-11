// ガイド(助言)どおりに操作するボットの成績。プレイヤー条件での走りやすさの目安
import { Race, makeConfig, DT } from '../src/sim/race.js';
const lanes = [0, 2, 4]; let out = [];
for (const lane of lanes) {
  let tsum = 0, psum = 0, n = 0, worst = 0;
  for (let seed = 1; seed <= 12; seed++) {
    const r = new Race(makeConfig({ seed, playerLane: lane, difficulty: 1, weather: { wind: 2, windDir: 0, wave: 2, cover: 0.4 } }));
    const pl = r.player; let t = 0;
    while (r.state !== 'done' && t < 300) { const a = pl.advice; r.step(DT, { steer: a.steer, throttle: a.throttle, brake: 0 }); r.events.length = 0; t += DT; }
    if (pl.finishTime > 0) { tsum += pl.finishTime; n++; worst = Math.max(worst, pl.finishTime); }
    psum += pl.place || 6;
  }
  out.push(`${lane + 1}コース: 平均 ${(tsum / n).toFixed(1)}秒 (最遅 ${worst.toFixed(1)}) 平均着順 ${(psum / 12).toFixed(1)} 完走 ${n}/12`);
}
console.log(out.join('\n'));
