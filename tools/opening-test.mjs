import assert from 'node:assert/strict';
import { Opening } from '../src/opening.js';
import { Race, makeConfig } from '../src/sim/race.js';
for (const short of [false,true]) {
  const race = new Race(makeConfig({ seed: 42, playerLane: 2 }));
  const original = JSON.stringify(race);
  const opening = new Opening(race,short);
  for (let i=0;i<opening.duration*60;i++) {
    opening.advance(1/60);
    assert.equal(JSON.stringify(race), original, 'presentation must never change simulation');
    for (const b of opening.boats) assert.ok(Number.isFinite(b.x+b.z+b.h+b.speed));
    for (const b of opening.audioBoats) assert.ok(b.speed <= 9 && b.throttle <= 0.25, "engines stay quiet under the music");
  }
  const c = opening.clearance();
  assert.ok(c.obst > 3.5, `boats must stay clear of mark 2 and its boom (${c.obst.toFixed(2)}m)`);
  assert.ok(c.boat > 4, `boats must not overlap (${c.boat.toFixed(2)}m)`);
  assert.ok(c.vmax < 22, `waiting action must not look like racing (${(c.vmax * 3.6).toFixed(0)}km/h)`);
  console.log(short ? 'short' : 'full', `${opening.duration}s`, 'clearance', c.obst.toFixed(1), 'm from mark/boom,', c.boat.toFixed(1), 'm between boats, top speed', (c.vmax * 3.6).toFixed(0), 'km/h');
  opening.advance(1);
  for (let i=0;i<6;i++) {
    const b=opening.boats[i], target=race.boats[i];
    assert.deepEqual([b.x,b.z,b.h,b.speed,b.vx,b.vz], [target.x,target.z,target.h,0,0,0]);
  }
}
console.log('opening timeline and simulation isolation passed');
