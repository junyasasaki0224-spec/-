// 競艇ボートとレーサー。モデルは Blender で生成した GLB (assets/blender/build_boat.py)。
// ローカル座標: +x 前, +y 上, +z 右。
import * as THREE from 'three';
import { GLTFLoader } from 'three/examples/jsm/loaders/GLTFLoader.js';
import { mergeGeometries } from 'three/examples/jsm/utils/BufferGeometryUtils.js';
import boatGlb from '../../assets/models/boat.glb';
import { BOAT_COLORS, BOAT_CSS, BOAT_TEXT_CSS, canvasTex, JP_FONT } from './common.js';
import { VMAX } from '../sim/physics.js';
import { clamp } from '../sim/course.js';

// レーサーごとのヘルメットの配色 [地色, ストライプ]
const HELMETS = [[0xf4f4f2, 0x1e4fd0], [0x16171b, 0xf2c200], [0xb81d2a, 0xffffff], [0x1740b0, 0xff8a1e], [0xe9e2c8, 0x0f7a55], [0x6a2fa8, 0xffffff], [0xff7a1a, 0x101010]];
const SUIT_COLORS = [0xf1f1ee, 0x1a1b20, 0xd91e2e, 0x1b50d4, 0xf3d21b, 0x18a24c];

export function loadGLB(bytes) {
  const buf = bytes.buffer.slice(bytes.byteOffset, bytes.byteOffset + bytes.byteLength);
  return new Promise((res, rej) => new GLTFLoader().parse(buf, '', (g) => res(g.scene), rej));
}

function numberTex(num) {
  const t = canvasTex(128, 128, (c, w, h) => {
    c.fillStyle = BOAT_CSS[num - 1]; c.fillRect(0, 0, w, h);
    c.strokeStyle = BOAT_TEXT_CSS[num - 1]; c.lineWidth = 5; c.strokeRect(5, 5, w - 10, h - 10);
    c.fillStyle = BOAT_TEXT_CSS[num - 1];
    c.font = `900 100px ${JP_FONT}`; c.textAlign = 'center'; c.textBaseline = 'middle';
    c.fillText(String(num), w / 2, h / 2 + 6);
  });
  t.flipY = false;       // glTF の UV に合わせる
  return t;
}

// 量子化された(整数の)頂点位置を Float32 に展開する
function floatPositions(geo) {
  const p = geo.attributes.position, a = new Float32Array(p.count * 3);
  for (let i = 0; i < p.count; i++) { a[i * 3] = p.getX(i); a[i * 3 + 1] = p.getY(i); a[i * 3 + 2] = p.getZ(i); }
  return new THREE.BufferAttribute(a, 3);
}

// 水面に落とす影用に、位置だけのジオメトリへまとめる
function mergedPositions(root, filter) {
  const list = [];
  root.updateMatrixWorld(true);
  const inv = new THREE.Matrix4().copy(root.matrixWorld).invert();
  root.traverse((o) => {
    if (!o.isMesh || !filter(o)) return;
    const g = new THREE.BufferGeometry();
    g.setAttribute('position', floatPositions(o.geometry));
    if (o.geometry.index) g.setIndex(Array.from(o.geometry.index.array));
    g.applyMatrix4(new THREE.Matrix4().multiplyMatrices(inv, o.matrixWorld));
    list.push(g.index ? g.toNonIndexed() : g);
  });
  return mergeGeometries(list, false);
}
const under = (o, name) => { for (let p = o; p; p = p.parent) if (p.name === name) return true; return false; };

let proto = null, shadowBodyGeo = null, shadowUpperGeo = null;
export async function loadBoatModel() {
  proto = await loadGLB(boatGlb);
  proto.traverse((o) => { if (o.isMesh) { o.castShadow = true; o.receiveShadow = true; } });
  shadowBodyGeo = mergedPositions(proto, (o) => !under(o, 'RacerUpper') && !under(o, 'Glass') && !under(o, 'Flag') && !under(o, 'Plates'));
  const up = proto.getObjectByName('RacerUpper');
  shadowUpperGeo = mergedPositions(up, () => true);
}

const shadowMat = new THREE.MeshBasicMaterial({
  color: 0x000a10, transparent: true, opacity: 0.42, depthWrite: false, fog: false,
  stencilWrite: true, stencilFunc: THREE.EqualStencilFunc, stencilRef: 0, stencilZPass: THREE.IncrementStencilOp,
  polygonOffset: true, polygonOffsetFactor: -1, polygonOffsetUnits: -1,
});
const _P = new THREE.Matrix4();
// 平行光源の向き L (水面→光源) で y=h の平面へ潰す行列
export function setShadowProjection(L, h = 0.03) {
  const ly = Math.max(L.y, 0.12), ax = L.x / ly, az = L.z / ly;
  _P.set(1, -ax, 0, h * ax, 0, 0, 0, h, 0, -az, 1, h * az, 0, 0, 0, 1);
  shadowMat.opacity = 0.2 + 0.24 * clamp(L.y * 1.6, 0, 1);
}

export class BoatView {
  constructor(scene, num) {
    this.num = num;
    const i = num - 1;
    const root = new THREE.Group(), tilt = new THREE.Group();
    root.add(tilt);
    this.root = root; this.tilt = tilt;
    const model = proto.clone(true);
    tilt.add(model);
    this.model = model;

    // 艇ごとのマテリアル差し替え
    const numTex = numberTex(num), cache = new Map();
    const swap = (m) => {
      if (cache.has(m)) return cache.get(m);
      let n = m;
      const base = m.name.replace(/\.\d+$/, '');
      if (base === 'BoatColor') { n = m.clone(); n.color.set(BOAT_COLORS[i]); }
      else if (base === 'Suit') { n = m.clone(); n.color.set(SUIT_COLORS[i]); }
      else if (base === 'Helmet') { n = m.clone(); n.color.set(HELMETS[i][0]); this.mHelmet = n; }
      else if (base === 'HelmetStripe') { n = m.clone(); n.color.set(HELMETS[i][1]); this.mStripe = n; }
      else if (base === 'NumberPlate') { n = m.clone(); n.color.set(0xffffff); n.map = numTex; }
      else if (base === 'Flag') { n = m.clone(); n.color.set(0xffffff); n.map = numTex; n.side = THREE.DoubleSide; }
      else if (base === 'Glass') { n = m.clone(); n.transparent = true; n.opacity = 0.4; n.depthWrite = false; n.side = THREE.DoubleSide; }
      cache.set(m, n);
      return n;
    };
    model.traverse((o) => { if (o.isMesh) { o.material = swap(o.material); if (o.material.transparent) o.castShadow = false; } });

    this.wheel = model.getObjectByName('Wheel');
    this.wheelQ = this.wheel.quaternion.clone();
    this.motor = model.getObjectByName('Motor');
    this.upper = model.getObjectByName('RacerUpper');
    this.upperP = this.upper.position.clone();
    this.upperQ = this.upper.quaternion.clone();
    // オンボード視点のときに隠す頭部
    this.head = [];
    this.upper.traverse((o) => { if (o.isMesh && /^(Helmet|HelmetStripe|Visor|Rubber)/.test(o.material.name)) this.head.push(o); });
    this.fp = false;
    // 艇旗: 頂点を揺らすので専用のジオメトリにする
    this.flag = null;
    const fl = model.getObjectByName('Flag');
    fl.traverse((o) => { if (o.isMesh && !this.flag) this.flag = o; });
    const fg = new THREE.BufferGeometry();
    fg.setAttribute('position', floatPositions(this.flag.geometry));
    fg.setAttribute('uv', this.flag.geometry.attributes.uv);
    fg.setIndex(this.flag.geometry.index);
    fg.computeVertexNormals();
    this.flag.geometry = fg;
    this.flagBase = fg.attributes.position.array.slice();

    // 水面の影
    this.shBody = new THREE.Mesh(shadowBodyGeo, shadowMat);
    this.shUpper = new THREE.Mesh(shadowUpperGeo, shadowMat);
    for (const s of [this.shBody, this.shUpper]) { s.matrixAutoUpdate = false; s.frustumCulled = false; s.renderOrder = 3; s.userData.noReflect = true; scene.add(s); }

    scene.add(root);
    this.slapped = 0;
    this.yawX = 0;
    this.roll = 0; this.pitch = 0; this.lean = 0; this.stand = 0;
    this.poundT = Math.random(); this.poundV = 0; this.poundY = 0;
    this._q = new THREE.Quaternion(); this._e = new THREE.Euler();
  }

  setFirstPerson(on) { if (on === this.fp) return; this.fp = on; for (const o of this.head) o.visible = !on; }

  // レーサーごとのヘルメットに塗り替える
  setRacer(r) { const h = HELMETS[r.helmet % HELMETS.length]; this.mHelmet.color.set(h[0]); this.mStripe.color.set(h[1]); }

  update(b, dt, time) {
    const sp = b.speed, f = clamp(sp / VMAX, 0, 1);
    this.root.position.set(b.x, 0, b.z);
    // 旋回中は、艇首が進む向きより内側を向いて外へ滑りながら回る(見た目だけ角度を足す)
    const tiv = clamp(Math.abs(b.w) * sp / 12, 0, 1);
    this.yawX += ((b.w < 0 ? -1 : 1) * tiv * 0.2 - this.yawX) * Math.min(1, dt * 5);
    this.root.rotation.y = -(b.h + this.yawX);
    // ロール(旋回内側へ傾く) + 衝突の揺れ
    const rollT = clamp(b.w * b.vf * 0.034, -0.56, 0.56) + b.bump * b.bumpSide * 0.3 * Math.sin(time * 28);
    this.roll += (rollT - this.roll) * Math.min(1, dt * 7);
    // ピッチ: 滑走に入ると艇首が上がる。加速でさらに上がる
    const plane = clamp((sp - 2) / 8, 0, 1);
    const pitchT = 0.01 + 0.07 * plane - 0.028 * f + clamp(b.af, -6, 6) * 0.006 + 0.05 * tiv;   // 旋回中は艇首が上がる
    this.pitch += (pitchT - this.pitch) * Math.min(1, dt * 5);
    // 艇底が波を叩く上下動
    this.poundT -= dt * (1.5 + 7 * f);
    if (this.poundT <= 0) {
      this.poundT = 0.5 + Math.random();
      const imp = (0.25 + Math.random() * 0.5) * f * (1 + b.inWake * 1.6) * (b.chop || 1);
      this.poundV += imp; if (f > 0.4) this.slapped = imp;
    }
    this.poundV += (-this.poundY * 90 - this.poundV * 9) * dt;
    this.poundY += this.poundV * dt;
    const bob = Math.sin(time * 1.7 + this.num) * 0.02 * (1 - f);
    this.tilt.position.y = -0.065 + bob + Math.max(this.poundY, -0.05) + 0.085 * plane;
    this.tilt.rotation.set(this.roll, 0, this.pitch + this.poundY * 0.35);

    // レーサー: 旋回で腰を浮かせて内側へ体重を移す(モンキーターン)
    const ti = clamp(Math.abs(b.w) * sp / 14, 0, 1);
    this.stand += (ti - this.stand) * Math.min(1, dt * 6);
    const leanT = clamp(b.w * 0.75, -0.85, 0.85);
    this.lean += (leanT - this.lean) * Math.min(1, dt * 6);
    this._e.set(this.lean * 0.95, 0, this.stand * 0.28 - f * 0.05);
    this.upper.quaternion.copy(this.upperQ).multiply(this._q.setFromEuler(this._e));
    this.upper.position.set(this.upperP.x - this.stand * 0.04, this.upperP.y + this.stand * 0.16, this.upperP.z + this.lean * 0.2);
    this.motor.rotation.y = -b.steer * 0.42;
    this._e.set(0, b.steer * 1.5, 0);
    this.wheel.quaternion.copy(this.wheelQ).multiply(this._q.setFromEuler(this._e));

    // 艇旗のはためき
    const pa = this.flag.geometry.attributes.position, arr = pa.array, base = this.flagBase, amp = 0.012 + 0.03 * f;
    for (let k = 0; k < arr.length; k += 3) {
      const d = -base[k];                      // 竿からの距離
      arr[k + 2] = base[k + 2] + Math.sin(time * (9 + 14 * f) - d * 26 + this.num) * amp * (d / 0.27);
    }
    pa.needsUpdate = true;

    // 影
    this.root.updateMatrixWorld(true);
    this.shBody.matrix.multiplyMatrices(_P, this.model.matrixWorld);
    this.shUpper.matrix.multiplyMatrices(_P, this.upper.matrixWorld);
  }
}
