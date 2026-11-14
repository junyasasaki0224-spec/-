// Visual-only choreography. Never write to a Race or its boats.
const clamp01 = (x) => Math.max(0, Math.min(1, x));
const smooth = (x) => x * x * (3 - 2 * x);
export class Opening {
  constructor(race, short = false) {
    this.duration = short ? 10 : 30;
    this.elapsed = 0;
    this.short = short;
    this.targets = race.boats.map((b) => ({ x: b.x, z: b.z, h: b.h }));
    this.boats = race.boats.map((b) => ({ ...b }));
    this.audioBoats = this.boats.map((b) => ({ ...b }));
    this.race = { ...race, boats: this.boats, order: this.boats };
    this.sample(0);
  }
  advance(dt) { this.elapsed = Math.min(this.duration, this.elapsed + dt); this.sample(this.elapsed); return this.elapsed >= this.duration; }
  sample(time) {
    const intro = this.short ? 1 : 8;
    const stagger = this.short ? 0.18 : 0.65;
    for (let i = 0; i < 6; i++) {
      const b = this.boats[i], target = this.targets[i];
      const u = clamp01((time - intro - i * stagger) / (this.duration - intro - i * stagger - 1));
      const t = smooth(u), startX = -267, startZ = -17 + i * 10;
      // Cubic route leaves the six slips eastward, then fans out to the assigned lanes.
      const a = 1 - t, c1x = -240, c2x = target.x - 25;
      b.x = a*a*a*startX + 3*a*a*t*c1x + 3*a*t*t*c2x + t*t*t*target.x;
      b.z = startZ + (target.z-startZ)*t*t*(3-2*t);
      const dx = 3*a*a*(c1x-startX) + 6*a*t*(c2x-c1x) + 3*t*t*(target.x-c2x);
      const dz = (target.z-startZ)*6*t*(1-t);
      b.h = u === 1 ? target.h : Math.atan2(dz,dx);
      b.speed = u > 0 && u < 1 ? Math.hypot(dx,dz)*6*u*(1-u)/(this.duration-intro-i*stagger-1) : 0;
      b.vx = Math.cos(b.h)*b.speed; b.vz = Math.sin(b.h)*b.speed;
      b.vf = b.speed; b.throttle = b.speed > 0 ? 0.12 : 0;
      b.w = 0; b.af = 0; b.turnInt = 0; b.bump = 0;
      if (u === 1) { b.x=target.x; b.z=target.z; }
      Object.assign(this.audioBoats[i], b, { speed: Math.min(b.speed, 3), throttle: b.speed > 0 ? 0.08 : 0 });
    }
  }
  get phase() { return this.elapsed < (this.short ? 1 : 8) ? '選手紹介' : this.elapsed < (this.short ? 3 : 14) ? 'ピット離れ' : 'スタート位置へ'; }
  camera(camera) {
    const t = this.elapsed, b = this.boats[Math.min(5,Math.floor(Math.max(0,t-8)/3))];
    if (t < (this.short ? 1 : 8)) {
      camera.position.set(-80 + t*3, 115-t*2, 115);
      camera.lookAt(-90,0,12);
    } else if (t < (this.short ? 4 : 17)) {
      camera.position.set(b.x+12,6,b.z+18); camera.lookAt(b.x,0,b.z);
    } else {
      camera.position.set(-180+(t/this.duration)*40,55,95); camera.lookAt(-155,0,24);
    }
    camera.fov=55; camera.updateProjectionMatrix();
  }
}
