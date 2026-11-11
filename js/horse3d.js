// ============================================================
//  競走馬 + 騎手の3Dモデル (プリミティブから手続き生成) と襲歩アニメーション
//  ローカル座標: +x 前方, +y 上, +z 右
// ============================================================
import * as THREE from '../vendor/three.module.min.js';
import { WAKU_COLORS, WAKU_TEXT, clamp } from './data.js';

let G = null;
function geos() {
  if (G) return G;
  const cyl = (rt, rb, len, seg = 7) => { const g = new THREE.CylinderGeometry(rt, rb, len, seg); g.translate(0, -len / 2, 0); return g; };
  G = {
    sph: new THREE.SphereGeometry(1, 14, 10),
    neck: (() => { const g = new THREE.CylinderGeometry(0.105, 0.21, 0.84, 9); g.translate(0, 0.42, 0); return g; })(),
    head: (() => { const g = new THREE.CylinderGeometry(0.065, 0.125, 0.54, 8); g.translate(0, 0.25, 0); return g; })(),
    ear: new THREE.ConeGeometry(0.035, 0.13, 5),
    mane: new THREE.BoxGeometry(0.07, 0.78, 0.035),
    tail: (() => { const g = new THREE.CylinderGeometry(0.03, 0.075, 0.62, 6); g.translate(0, 0.31, 0); return g; })(),
    foreU: cyl(0.085, 0.052, 0.5), foreL: cyl(0.045, 0.036, 0.52),
    hindU: cyl(0.12, 0.06, 0.55), hindL: cyl(0.048, 0.036, 0.52),
    hoof: (() => { const g = new THREE.CylinderGeometry(0.045, 0.06, 0.09, 7); g.translate(0, -0.045, 0); return g; })(),
    torso: (() => { const g = new THREE.CapsuleGeometry(0.15, 0.34, 3, 8); g.translate(0, 0.22, 0); return g; })(),
    arm: cyl(0.045, 0.035, 0.42, 6),
    thigh: new THREE.BoxGeometry(0.4, 0.13, 0.11),
    boot: new THREE.BoxGeometry(0.11, 0.3, 0.1),
    whip: cyl(0.012, 0.006, 0.6, 4),
    cloth: new THREE.BoxGeometry(0.62, 0.03, 0.7),
    panel: new THREE.PlaneGeometry(0.5, 0.34),
    shadow: (() => { const g = new THREE.CircleGeometry(1, 16); g.rotateX(-Math.PI / 2); g.scale(1.5, 1, 0.55); return g; })(),
  };
  return G;
}

const numTexCache = {};
function numTex(num, waku) {
  const key = num + '_' + waku;
  if (numTexCache[key]) return numTexCache[key];
  const c = document.createElement('canvas'); c.width = 96; c.height = 64;
  const x = c.getContext('2d');
  x.fillStyle = '#f7f7f2'; x.fillRect(0, 0, 96, 64);
  x.fillStyle = WAKU_COLORS[waku - 1]; x.fillRect(0, 0, 96, 9);
  x.fillStyle = '#111'; x.font = 'bold 50px sans-serif'; x.textAlign = 'center'; x.textBaseline = 'middle';
  x.fillText(String(num), 48, 39);
  const t = new THREE.CanvasTexture(c); t.colorSpace = THREE.SRGBColorSpace;
  return (numTexCache[key] = t);
}
let shadowMat = null, darkMat = null, whiteMat = null, skinMat = null, hoofMat = null;

export class Horse3D {
  constructor(h) {
    const g = geos();
    if (!shadowMat) {
      shadowMat = new THREE.MeshBasicMaterial({ color: 0x000000, transparent: true, opacity: 0.32, depthWrite: false });
      darkMat = new THREE.MeshLambertMaterial({ color: 0x18181c });
      whiteMat = new THREE.MeshLambertMaterial({ color: 0xf2f2ee });
      skinMat = new THREE.MeshLambertMaterial({ color: 0xe0b090 });
      hoofMat = new THREE.MeshLambertMaterial({ color: 0x1d1a18 });
    }
    const coat = new THREE.MeshLambertMaterial({ color: h.coat.body });
    const mane = new THREE.MeshLambertMaterial({ color: h.coat.mane });
    const silk1 = new THREE.MeshLambertMaterial({ color: h.silk1 });
    const silk2 = new THREE.MeshLambertMaterial({ color: h.silk2 });
    const cap = new THREE.MeshLambertMaterial({ color: new THREE.Color(WAKU_COLORS[h.waku - 1]) });
    const M = (geo, mat, x = 0, y = 0, z = 0, sx = 1, sy = 1, sz = 1) => { const m = new THREE.Mesh(geo, mat); m.position.set(x, y, z); m.scale.set(sx, sy, sz); return m; };

    this.root = new THREE.Group(); // 位置・向き
    this.root.rotation.order = 'YZX';
    this.body = new THREE.Group(); // 上下動・ピッチ
    this.root.add(this.body);
    this.shadow = M(g.shadow, shadowMat, 0, 0.04, 0);
    this.shadow.renderOrder = 1;
    this.root.add(this.shadow);
    const b = this.body;
    b.add(M(g.sph, coat, 0, 1.3, 0, 0.78, 0.36, 0.3));
    b.add(M(g.sph, coat, 0.5, 1.3, 0, 0.36, 0.4, 0.29));
    b.add(M(g.sph, coat, -0.48, 1.34, 0, 0.42, 0.4, 0.31));
    // 首・頭
    this.neck = new THREE.Group(); this.neck.position.set(0.66, 1.42, 0); b.add(this.neck);
    this.neck.add(M(g.neck, coat));
    this.neck.add(M(g.mane, mane, -0.15, 0.44, 0));
    this.head = new THREE.Group(); this.head.position.set(0, 0.82, 0); this.head.rotation.z = -1.3; this.neck.add(this.head);
    this.head.add(M(g.head, coat));
    const e1 = M(g.ear, coat, -0.06, 0.0, 0.07), e2 = M(g.ear, coat, -0.06, 0.0, -0.07);
    e1.rotation.z = 1.2; e2.rotation.z = 1.2; this.head.add(e1, e2);
    if (h.num % 3 === 0) this.head.add(M(g.sph, whiteMat, 0.05, 0.3, 0, 0.03, 0.2, 0.05)); // 流星
    // 尾
    this.tail = new THREE.Group(); this.tail.position.set(-0.86, 1.46, 0); this.tail.rotation.z = 1.95; b.add(this.tail);
    this.tail.add(M(g.tail, mane));
    // 脚
    this.legs = [];
    const mkLeg = (x, y, z, fore) => {
      const p = new THREE.Group(); p.position.set(x, y, z);
      p.add(M(fore ? g.foreU : g.hindU, coat));
      const k = new THREE.Group(); k.position.set(0, fore ? -0.5 : -0.55, 0); p.add(k);
      k.add(M(fore ? g.foreL : g.hindL, h.num % 4 === 1 && fore ? whiteMat : coat));
      k.add(M(g.hoof, hoofMat, 0, -0.52, 0));
      b.add(p);
      this.legs.push({ p, k, fore });
    };
    mkLeg(0.5, 1.1, -0.15, true); mkLeg(0.5, 1.1, 0.15, true);
    mkLeg(-0.56, 1.15, -0.17, false); mkLeg(-0.56, 1.15, 0.17, false);
    // ゼッケン
    b.add(M(g.cloth, whiteMat, -0.02, 1.645, 0));
    const pm = new THREE.MeshLambertMaterial({ map: numTex(h.num, h.waku) });
    const p1 = M(g.panel, pm, -0.02, 1.48, 0.325), p2 = M(g.panel, pm, -0.02, 1.48, -0.325);
    p1.rotation.x = -0.12; p2.rotation.y = Math.PI; p2.rotation.x = 0.12;
    b.add(p1, p2);
    // 騎手
    const j = (this.jockey = new THREE.Group()); j.position.set(-0.05, 1.68, 0); b.add(j);
    for (const s of [-1, 1]) {
      const th = M(g.thigh, whiteMat, 0.1, 0.02, s * 0.25); th.rotation.z = 0.25; j.add(th);
      j.add(M(g.boot, darkMat, 0.02, -0.16, s * 0.3));
    }
    this.torso = new THREE.Group(); this.torso.position.set(-0.08, 0.1, 0); this.torso.rotation.z = -1.02; j.add(this.torso);
    this.torso.add(M(g.torso, silk1));
    if (h.pattern === 1) this.torso.add(M(g.sph, silk2, 0, 0.22, 0, 0.158, 0.07, 0.158));
    if (h.pattern === 2) this.torso.add(M(g.sph, silk2, 0, 0.3, 0, 0.156, 0.16, 0.156));
    this.torso.add(M(g.sph, skinMat, 0.02, 0.6, 0, 0.1, 0.11, 0.1));
    this.torso.add(M(g.sph, cap, 0.0, 0.64, 0, 0.125, 0.115, 0.125));
    this.arms = [];
    for (const s of [-1, 1]) {
      const a = new THREE.Group(); a.position.set(0.02, 0.44, s * 0.17); a.rotation.z = -0.9;
      a.add(M(g.arm, h.pattern === 0 ? silk2 : silk1));
      this.torso.add(a); this.arms.push(a);
    }
    this.whip = M(g.whip, darkMat, 0, -0.42, 0); this.whip.rotation.z = 1.3; this.arms[1].add(this.whip);
    this.capColor = WAKU_COLORS[h.waku - 1]; this.capText = WAKU_TEXT[h.waku - 1];
    this.lean = 0; this.yaw = 0;
  }

  // r: Runner, geo: track.at の結果
  update(r, geo, dt) {
    const root = this.root;
    root.position.set(geo.x, geo.y, geo.z);
    const lv = r.v > 3 ? clamp(r.lat / r.v, -0.2, 0.2) : 0;
    const yaw = Math.atan2(-(geo.hz + geo.nz * lv), geo.hx + geo.nx * lv);
    root.rotation.y = yaw;
    root.rotation.z = Math.atan(geo.slope);
    // コーナーでは内に傾く
    const targetLean = clamp(r.v * r.v * geo.k * 0.06, 0, 0.22) * geo.tsign + clamp(r.lat * 0.05, -0.1, 0.1) * geo.tsign;
    this.lean += (targetLean - this.lean) * Math.min(1, dt * 5);
    root.rotation.x = this.lean;

    const amp = clamp(r.v / 9, 0, 1);
    const th = r.phase * Math.PI * 2;
    const b = this.body;
    b.position.y = amp * 0.07 * Math.sin(th + 1.0);
    b.rotation.z = amp * 0.05 * Math.sin(th + 2.3);
    const offs = [0.5, 0.6, 0.0, 0.12];
    for (let i = 0; i < 4; i++) {
      const L = this.legs[i], a = th - offs[i] * Math.PI * 2;
      const s = Math.sin(a), c = Math.cos(a + 0.35);
      if (L.fore) {
        L.p.rotation.z = amp * (0.85 * s - 0.05);
        L.k.rotation.z = -amp * 1.55 * Math.max(0, c);
      } else {
        L.p.rotation.z = -0.22 + amp * (0.72 * s + 0.12);
        L.k.rotation.z = 0.4 + amp * (0.95 * Math.max(0, c) - 0.25);
      }
    }
    const push = r.pushing ? 1 : 0;
    this.neck.rotation.z = -0.45 - amp * 0.45 - amp * 0.09 * Math.sin(th + 0.4) - push * 0.06;
    this.head.rotation.z = -1.3 + amp * 0.1 * Math.sin(th + 0.9);
    this.tail.rotation.z = 1.95 - amp * 0.45 + amp * 0.12 * Math.sin(th * 1 + 2);
    this.tail.rotation.x = 0.15 * Math.sin(th * 0.5);
    // 騎手: 追う動作・ムチ
    this.torso.rotation.z = -1.02 - push * 0.14 - amp * 0.03 * Math.sin(th + 0.4);
    const pump = push * 0.35 * Math.sin(th + 0.4);
    this.arms[0].rotation.z = -0.9 - pump;
    const w = r.whipAnim > 0 ? Math.sin((r.whipAnim / 0.5) * Math.PI) : 0;
    this.arms[1].rotation.z = -0.9 - pump + w * 2.6;
    this.whip.visible = w > 0.02;
    this.shadow.position.y = 0.04 - b.position.y * 0;
  }
}
