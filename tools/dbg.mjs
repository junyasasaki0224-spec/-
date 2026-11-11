import { RACES, COURSES, makeField, makeConditions, STYLES } from '../js/data.js';
import { Race } from '../js/sim.js';
const race = RACES.find(r => r.id === (process.argv[2] || 'tokyo2400'));
const horses = makeField(race, 100); const cond = makeConditions(race, 500); cond.going = 0; cond.wind.speed = 0; cond.rough = 0;
const r = new Race({ course: COURSES[race.course], dist: race.dist, horses, cond, seed: 1, playerIdx: -1 });
r.openGate(); let next = 0;
const w = [r.runners[0], r.runners[5], r.runners[9]];
while (r.state !== 'done') {
  r.step(1 / 30, null);
  if (w[0].s >= next) { next += 200;
    console.log(w.map(x => `${STYLES[x.h.style][0]} s${x.s.toFixed(0)} v${x.v.toFixed(2)} E${x.E.toFixed(1)} tg${x.ai.target.toFixed(2)} cap${x.vCap.toFixed(2)} pen${x.penNow.toFixed(2)}/${x.penAvg.toFixed(2)} ar${x.ar.toFixed(2)} dr${x.draft.toFixed(2)} d${x.d.toFixed(1)} rk${x.rank}`).join(' | ')); }
}
