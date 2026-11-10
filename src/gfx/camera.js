// カメラワーク: 追尾 / 接近 / オンボード / 中継(場内の固定カメラを切り替え) / 上空
import * as THREE from 'three';
import { clamp, lerp, BOUNDS, zc } from '../sim/course.js';
import { VMAX } from '../sim/physics.js';

export const CAM_NAMES = ['追尾カメラ', '接近カメラ', 'オンボード', '中継カメラ', '上空カメラ'];
export const CAM = { CHASE: 0, CLOSE: 1, ONBOARD: 2, TV: 3, TOP: 4, FLY: 5, ORBIT: 6 };

// 中継カメラの設置位置: スタンド屋根 / 1マーク奥 / 対岸 / 2マーク奥
const TV = [
  { p: [20, 27, 80], zoom: 13 },
  { p: [BOUNDS.maxX + 5, 8, -14], zoom: 8.5 },
  { p: [44, 12, BOUNDS.minZ - 7], zoom: 12 },
  { p: [BOUNDS.minX - 3, 7.5, 50], zoom: 8.5 },
];
const angLerp = (a, b, t) => { let d = b - a; while (d > Math.PI) d -= Math.PI * 2; while (d < -Math.PI) d += Math.PI * 2; return a + d * t; };

export class CameraRig {
  constructor(camera) {
    this.camera = camera;
    this.dir = 0; this.pos = new THREE.Vector3(0, 30, 120); this.look = new THREE.Vector3();
    this.fov = 62; this.init = false; this.shake = 0; this.shakeOn = true;
    this.tv = -1; this.tvHold = 0;
    this.right = new THREE.Vector3(1, 0, 0);
    this._v = new THREE.Vector3(); this._l = new THREE.Vector3(); this._u = new THREE.Vector3();
  }
  reset() { this.init = false; this.tv = -1; this.shake = 0; }
  bump(s) { this.shake = Math.min(1.4, this.shake + s); }

  update(dt, time, b, view, mode, intro = -1) {
    const cam = this.camera, f = clamp(b.speed / VMAX, 0, 1);
    const V = this._v, Lk = this._l;
    let fov = 62, onboard = false;
    if (mode === CAM.CHASE || mode === CAM.CLOSE) {
      // 進行方向と艇の向きの中間を見るので、艇が流れると横向きに見える
      const velA = b.speed > 3 ? Math.atan2(b.vz, b.vx) : b.h;
      const want = angLerp(velA, b.h, 0.45);
      if (!this.init) this.dir = want;
      this.dir = angLerp(this.dir, want, 1 - Math.exp(-dt * 4.2));
      const cx = Math.cos(this.dir), cz = Math.sin(this.dir);
      const back = mode === CAM.CHASE ? 6.4 + 1.5 * f : 4.0, up = mode === CAM.CHASE ? 2.35 + 0.3 * f : 1.3;
      V.set(b.x - cx * back, up, b.z - cz * back);
      Lk.set(b.x + cx * 6, mode === CAM.CHASE ? 1.0 : 0.85, b.z + cz * 6);
      fov = (mode === CAM.CHASE ? 58 : 68) + 17 * f * f;
      if (intro >= 0 && intro < 3.2) {
        // 発走前の導入: 上空から艇の後ろへ降りてくる
        const k = 1 - Math.pow(1 - clamp(intro / 3.2, 0, 1), 3);
        V.set(lerp(b.x - 40, V.x, k), lerp(34, V.y, k), lerp(b.z + 46, V.z, k));
        if (!this.init) this.look.copy(Lk);
        this.pos.copy(V); this.look.lerp(Lk, k);
      } else {
        if (!this.init) { this.pos.copy(V); this.look.copy(Lk); }
        this.pos.lerp(V, 1 - Math.exp(-dt * 14));
        this.look.lerp(Lk, 1 - Math.exp(-dt * 12));
      }
    } else if (mode === CAM.ONBOARD) {
      onboard = true;
      // レーサーの目の位置(頭部はゲーム側で非表示にする)
      view.root.updateMatrixWorld(true);
      this.pos.set(0.6, 0.52, 0).applyMatrix4(view.upper.matrixWorld);
      this.look.set(8, 0.75, 0).applyMatrix4(view.tilt.matrixWorld);
      fov = 74 + 12 * f * f;
    } else if (mode === CAM.TV) {
      let want = b.x > 96 ? 1 : b.x < -96 ? 3 : b.z >= zc(b.x) ? 0 : 2;
      this.tvHold -= dt;
      if (this.tv < 0 || (want !== this.tv && this.tvHold <= 0)) {
        this.tv = want; this.tvHold = 2.2;
        this.pos.set(...TV[want].p); this.look.set(b.x, 0.8, b.z);
      }
      const c = TV[this.tv];
      Lk.set(b.x + b.vx * 0.25, 0.8, b.z + b.vz * 0.25);
      this.look.lerp(Lk, 1 - Math.exp(-dt * 5));
      const d = this.pos.distanceTo(this.look);
      fov = clamp(2 * Math.atan(c.zoom / d) * 180 / Math.PI, 7, 46);
    } else if (mode === CAM.TOP) {
      V.set(b.x - 6, 64, b.z + 40); Lk.set(b.x, 0, b.z);
      if (!this.init) { this.pos.copy(V); this.look.copy(Lk); }
      this.pos.lerp(V, 1 - Math.exp(-dt * 4)); this.look.lerp(Lk, 1 - Math.exp(-dt * 8));
      fov = 46;
    } else if (mode === CAM.FLY) {
      // 会場をゆっくり見せる空撮
      const a = time * 0.07;
      V.set(Math.cos(a) * 205, 30 + Math.sin(time * 0.11) * 11, Math.sin(a) * 58 - 16);
      Lk.set(Math.cos(a + 1.2) * 60, 5, 28);
      const k = this.init ? 1 - Math.exp(-dt * 1.5) : 1;
      this.pos.lerp(V, k); this.look.lerp(Lk, k);
      fov = 54;
    } else {
      // 自艇の周りを回る
      const a = time * 0.3;
      V.set(b.x + Math.cos(a) * 8, 2.6, b.z + Math.sin(a) * 8); Lk.set(b.x, 0.7, b.z);
      if (!this.init) { this.pos.copy(V); this.look.copy(Lk); }
      this.pos.lerp(V, 1 - Math.exp(-dt * 3)); this.look.lerp(Lk, 1 - Math.exp(-dt * 8));
      fov = 52;
    }
    this.init = true;
    // 縦長の画面では横の視野が狭くなるので、少し広げて艇が大きく映りすぎないようにする
    if (cam.aspect < 1.2 && mode !== CAM.TV) fov *= 1 + 0.32 * clamp((1.2 - cam.aspect) / 0.7, 0, 1);
    this.fov += (fov - this.fov) * Math.min(1, dt * (mode === CAM.TV ? 3 : 5));
    cam.position.copy(this.pos);
    const player = mode <= CAM.ONBOARD;
    if (player && this.shakeOn) {
      // 速度による細かい揺れ + 衝突の衝撃
      const s = 0.012 * f * f + this.shake * 0.16;
      cam.position.x += (Math.random() - 0.5) * s; cam.position.y += (Math.random() - 0.5) * s * 1.4; cam.position.z += (Math.random() - 0.5) * s;
      if (!onboard) cam.position.y += view.poundY * 0.5;
    }
    if (cam.position.y < 0.45) cam.position.y = 0.45;
    if (onboard) { cam.up.set(0, 1, 0).transformDirection(view.tilt.matrixWorld); } else cam.up.set(0, 1, 0);
    cam.lookAt(this.look);
    if (player && !onboard) cam.rotation.z += clamp(b.w * f * 0.05, -0.08, 0.08) + (this.shakeOn ? (Math.random() - 0.5) * this.shake * 0.03 : 0);
    if (Math.abs(cam.fov - this.fov) > 0.01) { cam.fov = this.fov; cam.updateProjectionMatrix(); }
    this.shake *= Math.exp(-dt * 5);
    cam.updateMatrixWorld();
    this.right.set(1, 0, 0).applyQuaternion(cam.quaternion);
  }
}
