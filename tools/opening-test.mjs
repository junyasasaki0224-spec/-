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
    for (const b of opening.audioBoats) assert.ok(b.speed <= 3 && b.throttle <= 0.08, "pit engines stay at low RPM");
  }
  opening.advance(1);
  for (let i=0;i<6;i++) {
    const b=opening.boats[i], target=race.boats[i];
    assert.deepEqual([b.x,b.z,b.h,b.speed,b.vx,b.vz], [target.x,target.z,target.h,0,0,0]);
  }
}
console.log('opening timeline and simulation isolation passed');
