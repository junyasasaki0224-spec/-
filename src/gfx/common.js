import * as THREE from 'three';
import { mergeGeometries } from 'three/examples/jsm/utils/BufferGeometryUtils.js';

// 艇番の色: 1白 2黒 3赤 4青 5黄 6緑
export const BOAT_COLORS = [0xf2f2f0, 0x16161a, 0xd91e2e, 0x1b50d4, 0xf3d21b, 0x18a24c];
export const BOAT_CSS = ['#f2f2f0', '#16161a', '#d91e2e', '#1b50d4', '#f3d21b', '#18a24c'];
export const BOAT_TEXT_CSS = ['#111', '#fff', '#fff', '#fff', '#111', '#fff'];
export const RACERS = ['青波 隼人', '水城 拓海', '潮見 蓮', '汐崎 航', '風間 颯太', '帆足 大河'];

// 時間帯ごとの環境設定
export const ENVS = {
  day: {
    zenith: 0x2a6fd0, horizon: 0xb9d9f0, fog: 0xbcd6e8, fogD: 0.00075,
    sunDir: [-0.45, 0.62, -0.64], sunCol: 0xfff0d6, sunInt: 3.1,
    hemiSky: 0xd4e8ff, hemiGround: 0x7b8478, hemiInt: 1.55,
    deep: 0x0d4750, shallow: 0x2f8d88, cloud: 0xffffff, night: 0, spray: 0xffffff, glow: 0,
  },
  evening: {
    zenith: 0x35508f, horizon: 0xf6b27a, fog: 0xd9a888, fogD: 0.0009,
    sunDir: [-0.82, 0.16, -0.55], sunCol: 0xffb060, sunInt: 2.6,
    hemiSky: 0xc9b6c8, hemiGround: 0x6b5f58, hemiInt: 1.15,
    deep: 0x12303f, shallow: 0x6c6f78, cloud: 0xffd2b0, night: 0.25, spray: 0xffe6d2, glow: 0.5,
  },
  night: {
    zenith: 0x03060f, horizon: 0x18203c, fog: 0x0d1426, fogD: 0.001,
    sunDir: [0.05, 0.92, 0.38], sunCol: 0xe4ecff, sunInt: 1.9,
    hemiSky: 0x8fa4d8, hemiGround: 0x2a3040, hemiInt: 0.75,
    deep: 0x030f16, shallow: 0x12323c, cloud: 0x2a3350, night: 1, spray: 0xdfe8ff, glow: 1,
  },
};

export const GLSL_NOISE = /* glsl */`
float hash21(vec2 p){ p = fract(p * vec2(123.34, 456.21)); p += dot(p, p + 45.32); return fract(p.x * p.y); }
float vnoise(vec2 p){
  vec2 i = floor(p), f = fract(p); f = f * f * (3.0 - 2.0 * f);
  return mix(mix(hash21(i), hash21(i + vec2(1.0, 0.0)), f.x), mix(hash21(i + vec2(0.0, 1.0)), hash21(i + vec2(1.0, 1.0)), f.x), f.y);
}
float fbm(vec2 p){ float a = 0.5, s = 0.0; for (int i = 0; i < 4; i++) { s += a * vnoise(p); p = p * 2.03 + 17.1; a *= 0.5; } return s; }
`;

// 同じマテリアルのジオメトリをまとめて1メッシュにする
export class Batch {
  constructor() { this.map = new Map(); }
  add(geo, mat, x = 0, y = 0, z = 0, ry = 0, rx = 0, rz = 0) {
    const g = geo.index ? geo.toNonIndexed() : geo.clone();
    if (rx || ry || rz) g.applyMatrix4(new THREE.Matrix4().makeRotationFromEuler(new THREE.Euler(rx, ry, rz, 'YXZ')));
    g.translate(x, y, z);
    for (const k of Object.keys(g.attributes)) if (k !== 'position' && k !== 'normal' && k !== 'uv') g.deleteAttribute(k);
    if (!this.map.has(mat)) this.map.set(mat, []);
    this.map.get(mat).push(g);
    return this;
  }
  box(w, h, d, mat, x, y, z, ry = 0, rx = 0, rz = 0) { return this.add(new THREE.BoxGeometry(w, h, d), mat, x, y, z, ry, rx, rz); }
  cyl(rt, rb, h, mat, x, y, z, seg = 10, rx = 0, rz = 0) { return this.add(new THREE.CylinderGeometry(rt, rb, h, seg), mat, x, y, z, 0, rx, rz); }
  build(parent) {
    for (const [mat, list] of this.map) {
      const m = new THREE.Mesh(mergeGeometries(list, false), mat);
      m.matrixAutoUpdate = false;
      parent.add(m);
      list.forEach((g) => g.dispose());
    }
    this.map.clear();
  }
}

export function canvasTex(w, h, draw, { repeat = false, aniso = 4 } = {}) {
  const c = document.createElement('canvas');
  c.width = w; c.height = h;
  const ctx = c.getContext('2d');
  draw(ctx, w, h);
  const t = new THREE.CanvasTexture(c);
  t.colorSpace = THREE.SRGBColorSpace;
  t.anisotropy = aniso;
  if (repeat) t.wrapS = t.wrapT = THREE.RepeatWrapping;
  return t;
}

export const JP_FONT = '"Hiragino Sans","Hiragino Kaku Gothic ProN","Noto Sans JP","Yu Gothic","Meiryo",sans-serif';
