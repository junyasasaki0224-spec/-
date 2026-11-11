// ============================================================
//  競走馬 + 騎手: Blenderで生成したスキンメッシュ(assets/horse.glb)を読み込み、
//  骨格を直接動かして襲歩(ギャロップ)を再現する
//  モデル座標: +x 前方, +y 上, +z 右
// ============================================================
import * as THREE from '../vendor/three.module.min.js';
import { GLTFLoader } from '../vendor/GLTFLoader.js';
import * as SkeletonUtils from '../vendor/SkeletonUtils.js';
import { WAKU_COLORS, WAKU_TEXT, clamp, mulberry32 } from './data.js';
import { GALLOP_BEATS } from './hoof.js';

// assets/<name>.glb を読む。.glb を配信できないホスティングでは base64 テキスト版 (<name>.b64.txt) にフォールバック
export async function loadGLB(name) {
  const base = new URL('../assets/' + name, import.meta.url).href;
  let buf = null;
  try { const r = await fetch(base + '.glb'); if (r.ok) buf = await r.arrayBuffer(); } catch (e) { /* フォールバックへ */ }
  if (!buf || new Uint8Array(buf, 0, 4).join() !== '103,108,84,70') { // 先頭が "glTF" でなければ別形式を試す
    const r = await fetch(base + '.b64.txt'); if (!r.ok) throw new Error(name + ' を読み込めません');
    const bin = atob((await r.text()).trim()), u8 = new Uint8Array(bin.length);
    for (let i = 0; i < bin.length; i++) u8[i] = bin.charCodeAt(i);
    buf = u8.buffer;
  }
  return new Promise((res, rej) => new GLTFLoader().parse(buf, '', res, rej));
}
let TEMPLATE = null;
export async function loadHorseModel() {
  if (TEMPLATE) return;
  const gltf = await loadGLB('horse');
  TEMPLATE = gltf.scene;
  TEMPLATE.updateMatrixWorld(true);
}

const DEG = Math.PI / 180;
// 周期キーフレーム [位相, 角度(度)] をなめらかに補間
function kf(tab, p) {
  p -= Math.floor(p);
  for (let i = 0; i < tab.length - 1; i++) {
    if (p <= tab[i + 1][0]) {
      const a = tab[i], b = tab[i + 1];
      let t = (p - a[0]) / (b[0] - a[0]); t = t * t * (3 - 2 * t);
      return a[1] + (b[1] - a[1]) * t;
    }
  }
  return tab[tab.length - 1][1];
}
// 脚の位相0 = 着地。襲歩の接地期はおよそ0〜0.22
const F_SWING = [[0, 30], [0.11, 2], [0.22, -30], [0.36, -34], [0.55, 0], [0.75, 42], [0.9, 40], [1, 30]];
const F_KNEE = [[0, 0], [0.22, 2], [0.38, 70], [0.55, 108], [0.72, 60], [0.88, 8], [1, 0]];
const F_FET = [[0, 5], [0.1, 38], [0.2, 15], [0.3, -45], [0.55, -50], [0.85, -10], [1, 5]];
const H_HIP = [[0, 32], [0.11, 5], [0.22, -30], [0.36, -28], [0.55, 5], [0.78, 40], [0.92, 38], [1, 32]];
const H_FOLD = [[0, 12], [0.1, 22], [0.22, 2], [0.4, 62], [0.58, 88], [0.8, 48], [0.94, 15], [1, 12]];
const H_FET = [[0, 5], [0.1, 35], [0.2, 12], [0.32, -45], [0.6, -45], [0.88, -8], [1, 5]];
// 着地順 (右手前): 左後 → 右後 → 左前 → 右前 → 空中期
const OFF = { HL: GALLOP_BEATS[0], HR: GALLOP_BEATS[1], FL: GALLOP_BEATS[2], FR: GALLOP_BEATS[3] }; // 蹄音と同じ位相

const numTexCache = {};
function numTex(num, waku) {
  const key = num + '_' + waku;
  if (numTexCache[key]) return numTexCache[key];
  const c = document.createElement('canvas'); c.width = 128; c.height = 96;
  const x = c.getContext('2d');
  x.fillStyle = '#f4f4ee'; x.fillRect(0, 0, 128, 96);
  x.fillStyle = WAKU_COLORS[waku - 1]; x.fillRect(0, 0, 128, 12);
  x.fillStyle = '#111'; x.font = 'bold 74px sans-serif'; x.textAlign = 'center'; x.textBaseline = 'middle';
  x.fillText(String(num), 64, 58);
  const t = new THREE.CanvasTexture(c); t.colorSpace = THREE.SRGBColorSpace; t.anisotropy = 4;
  return (numTexCache[key] = t);
}
// 毛色ごとの「黒い長靴」(四肢・鼻先の黒み)の強さ
const POINTS = { 鹿毛: 0.88, 黒鹿毛: 0.7, 栗毛: 0.06, 青鹿毛: 0.4, 芦毛: 0.45, 栃栗毛: 0.1 };
const panelGeo = new THREE.PlaneGeometry(0.4, 0.3);
const whipGeo = (() => { const g = new THREE.CylinderGeometry(0.006, 0.011, 0.62, 5); g.translate(0, 0.31, 0); return g; })();

export class Horse3D {
  constructor(h) {
    const root = (this.root = new THREE.Group());
    root.rotation.order = 'YZX';
    const model = SkeletonUtils.clone(TEMPLATE);
    root.add(model);
    const rng = mulberry32(h.num * 977 + h.name.length * 31 + h.weight);
    const coat = new THREE.Color(h.coat.body), dark = new THREE.Color(h.coat.mane).lerp(new THREE.Color(0x0a0807), 0.5);
    const std = (color, rough, metal = 0) => new THREE.MeshStandardMaterial({ color, roughness: rough, metalness: metal, envMapIntensity: 0.55 });
    const silkB = h.pattern === 0 ? h.silk2 : h.silk1;
    const mats = {
      coat: new THREE.MeshStandardMaterial({ color: 0xffffff, roughness: h.coat.name === '芦毛' ? 0.6 : 0.42, vertexColors: true, envMapIntensity: 0.6 }),
      hoof: std(0x1b1815, 0.5), mane: std(h.coat.mane, 0.7), eye: std(0x050505, 0.08),
      silk: std(h.silk1, 0.4), sleeve: std(silkB, 0.4), breeches: std(0xeeeeea, 0.75), boot: std(0x0d0d0f, 0.28),
      skin: std(0xd9a888, 0.65), helmet: std(new THREE.Color(WAKU_COLORS[h.waku - 1]), 0.45), goggles: std(0x101014, 0.12),
      glove: std(0xe8e8e8, 0.7), saddle: std(0x24160d, 0.5), cloth: std(0xf0f0ea, 0.85), tack: std(0x1a0f08, 0.45),
    };
    // 白徴 (流星・白い脚) は馬ごとに決める
    const blaze = rng() < 0.42, sock = [0, 1, 2, 3].map(() => (rng() < 0.24 ? 0.35 + rng() * 0.6 : 0));
    const pStr = POINTS[h.coat.name] ?? 0.5;
    this.bones = {};
    model.traverse((o) => {
      if (o.isBone) this.bones[o.name] = o;
      if (!o.isSkinnedMesh) return;
      o.frustumCulled = false; o.castShadow = true; o.receiveShadow = false;
      const name = o.material.name;
      if (name === 'coat') {
        const src = o.geometry, g = new THREE.BufferGeometry();
        for (const k in src.attributes) g.setAttribute(k, src.attributes[k]);
        g.setIndex(src.index); g.boundingSphere = src.boundingSphere; g.boundingBox = src.boundingBox;
        const uv = src.attributes.uv, uv1 = src.attributes.uv1, n = uv.count, col = new Float32Array(n * 3), c = new THREE.Color();
        for (let i = 0; i < n; i++) {
          const pts = uv.getX(i), mark = 1 - uv.getY(i), ao = uv1 ? uv1.getX(i) : 1, sh = uv1 ? 1 - uv1.getY(i) : 1;
          c.copy(coat).lerp(dark, pts * pStr);
          let white = 0;
          if (blaze && Math.abs(mark - 0.2) < 0.05) white = 1;
          for (let k = 0; k < 4; k++) if (sock[k] && Math.abs(mark - (0.4 + k * 0.1)) < 0.04 && sh < sock[k]) white = 1;
          if (white) c.setRGB(0.86, 0.84, 0.8);
          col[i * 3] = c.r * ao; col[i * 3 + 1] = c.g * ao; col[i * 3 + 2] = c.b * ao;
        }
        g.setAttribute('color', new THREE.BufferAttribute(col, 3));
        o.geometry = g;
      } else o.geometry.userData.shared = true;
      o.material = mats[name] || std(0x888888, 0.6);
    });
    // 各骨の静止姿勢と「左右軸まわりの回転軸」(骨ローカル)
    this.rest = {}; this.axis = {};
    const q = new THREE.Quaternion();
    for (const k in this.bones) {
      const b = this.bones[k];
      this.rest[k] = b.quaternion.clone();
      b.getWorldQuaternion(q);
      this.axis[k] = new THREE.Vector3(0, 0, 1).applyQuaternion(q.invert()).normalize();
    }
    this.hipsY = this.bones.hips.position.clone();
    // ゼッケンの番号
    const pm = new THREE.MeshStandardMaterial({ map: numTex(h.num, h.waku), roughness: 0.85 });
    for (const s of [-1, 1]) {
      const p = new THREE.Mesh(panelGeo, pm);
      p.position.set(0.09, 1.415, s * 0.283); p.rotation.y = s > 0 ? 0 : Math.PI; p.rotation.x = s * -0.2;
      p.rotation.order = 'YXZ';
      root.add(p); root.updateMatrixWorld(true); this.bones.spine.attach(p);
    }
    // ムチ
    this.whip = new THREE.Mesh(whipGeo, mats.tack); this.whip.visible = false; this.whip.castShadow = true;
    this.whip.position.set(0.79, 1.80, 0.07); this.whip.rotation.z = 0.5;
    root.add(this.whip); root.updateMatrixWorld(true); this.bones.jarmLR.attach(this.whip);
    this.lean = 0; this._q = new THREE.Quaternion();
  }

  rot(name, deg) {
    const b = this.bones[name];
    b.quaternion.copy(this.rest[name]).multiply(this._q.setFromAxisAngle(this.axis[name], deg * DEG));
  }

  // r: Runner, geo: track.at の結果 (+ tsign)
  update(r, geo, dt) {
    const root = this.root;
    root.position.set(geo.x, geo.y, geo.z);
    const lv = r.v > 3 ? clamp(r.lat / r.v, -0.2, 0.2) : 0;
    root.rotation.y = Math.atan2(-(geo.hz + geo.nz * lv), geo.hx + geo.nx * lv);
    const targetLean = (clamp(r.v * r.v * geo.k * 0.055, 0, 0.2) + clamp(r.lat * 0.04, -0.08, 0.08)) * geo.tsign;
    this.lean += (targetLean - this.lean) * Math.min(1, dt * 5);
    root.rotation.x = this.lean;

    const amp = clamp(r.v / 8, 0, 1), ph = r.phase, s2 = Math.PI * 2;
    const reach = 0.72 + 0.28 * clamp((r.v - 8) / 9, 0, 1); // 速いほど完歩が伸びる
    // 回りと手前: 左回りのコーナーは左手前、直線で手前を替える
    const leftLead = (geo.tsign < 0) !== !!r.leadDone;
    const sideA = leftLead ? 'R' : 'L', sideB = leftLead ? 'L' : 'R'; // A=先に着く側
    const legs = [['H', sideA, OFF.HL], ['H', sideB, OFF.HR], ['F', sideA, OFF.FL], ['F', sideB, OFF.FR]];
    for (const [kind, side, off] of legs) {
      const p = ph - off;
      if (kind === 'F') {
        const A = kf(F_SWING, p) * amp * reach, K = kf(F_KNEE, p) * amp, Ft = kf(F_FET, p) * amp;
        this.rot('scapula' + side, A * 0.22);
        this.rot('humerus' + side, A * 0.18 - K * 0.22);
        this.rot('radius' + side, A * 0.6 + K * 0.30);
        this.rot('cannonF' + side, -K * 1.05);
        this.rot('pasternF' + side, Ft);
      } else {
        const H = kf(H_HIP, p) * amp * reach, Q = kf(H_FOLD, p) * amp, Ft = kf(H_FET, p) * amp;
        this.rot('femur' + side, H + Q * 0.25);
        this.rot('tibia' + side, -Q * 0.95);
        this.rot('cannonH' + side, Q * 0.85);
        this.rot('pasternH' + side, Ft);
      }
    }
    // 体幹: 空中期に背を丸め、後肢の蹴りで伸びる
    const pitch = amp * 3.2 * Math.sin(s2 * (ph - 0.2)) + geo.slope * 57.3;
    this.rot('hips', pitch);
    this.rot('spine', amp * 3.5 * Math.sin(s2 * (ph - 0.52)));
    this.rot('chest', amp * 2.0 * Math.sin(s2 * (ph - 0.52)));
    this.bones.hips.position.y = this.hipsY.y + amp * 0.055 * Math.sin(s2 * (ph - 0.52));
    // 頸は前へ伸ばし、完歩に合わせて上下する
    const push = r.pushing ? 1 : 0, nod = Math.sin(s2 * (ph - 0.32));
    this.rot('neck1', -amp * 17 - amp * 5 * nod - push * 3);
    this.rot('neck2', -amp * 7 - amp * 3 * nod);
    this.rot('head', amp * 9 + amp * 3 * nod);
    this.rot('tail1', -amp * 36 + 4 * Math.sin(s2 * ph + 1));
    this.rot('tail2', -amp * 20 + amp * 8 * Math.sin(s2 * ph + 2.2));
    this.rot('tail3', amp * 6 + amp * 14 * Math.sin(s2 * ph + 3.3));
    // 騎手: 追う動作とムチ
    const pump = push * Math.sin(s2 * (ph - 0.32));
    this.rot('jtorso', -push * 5 - amp * 1.5 * nod);
    this.rot('jhead', push * 4);
    const w = r.whipAnim > 0 ? Math.sin((r.whipAnim / 0.5) * Math.PI) : 0;
    this.rot('jarmUL', pump * 14); this.rot('jarmLL', -pump * 16 - amp * 5 * nod);
    this.rot('jarmUR', pump * 14 - w * 95); this.rot('jarmLR', -pump * 16 - amp * 5 * nod - w * 35);
    this.rot('jthighL', pump * 3); this.rot('jthighR', pump * 3);
    this.whip.visible = w > 0.02;
  }
}
