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
  // カメラ: ①向こう岸の上空から会場全体(スタンドを奥に) ②ピットを出る艇を水面の低い位置から横に追う
  // ③向こう岸寄りの水面から、スタート前の位置へ集まる6艇を見る(最後は自艇へ寄る)
  camera(camera) {
    const t = this.elapsed, intro = this.short ? 1 : 8, pitEnd = this.short ? 4 : 17, D = this.duration;
    const portrait = camera.aspect < 1;
    if (t < intro) {
      const k = smooth(clamp01(t / intro));
      camera.position.set(130 - 200 * k, 52 - 14 * k, -66 + 10 * k);   // 水面の上空(建物にかからない高さ)
      camera.lookAt(40 - 170 * k, 0, 30);
    } else if (t < pitEnd) {
      const per = (pitEnd - intro) / 3, idx = Math.min(5, Math.floor((t - intro) / per) * 2);   // 1・3・5号艇を順に
      const b = this.boats[idx], ch = Math.cos(b.h), sh = Math.sin(b.h), k = ((t - intro) % per) / per;
      const side = 6 + 2 * k, back = -11 + 5 * k;      // 艇の斜め前(水面側)から、向かってくる艇を映す
      camera.position.set(b.x - ch * back - sh * side, 2.6, b.z - sh * back + ch * side);
      camera.lookAt(b.x + ch * 3, 0.6, b.z + sh * 3);
    } else {
      const k = smooth(clamp01((t - pitEnd) / (D - pitEnd))), p = this.boats[this.race.playerIndex] || this.boats[0];
      const wide = { x: -122, y: 9, z: -14 }, near = { x: p.x + 18, y: 4, z: p.z - 16 };
      const m = smooth(clamp01((k - 0.62) / 0.38));    // 最後の数秒で自艇へ寄る
      camera.position.set(wide.x + (near.x - wide.x) * m, wide.y + (near.y - wide.y) * m, wide.z + (near.z - wide.z) * m);
      camera.lookAt(-162 + (p.x + 162) * m, 0, 24 + (p.z - 24) * m);
    }
    const fov = portrait ? 74 : 52;
    if (camera.fov !== fov) { camera.fov = fov; camera.updateProjectionMatrix(); }
  }
}
