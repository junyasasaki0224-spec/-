// ============================================================
//  競馬場の3D描画 (Three.js)
//  コース・ラチ・ハロン棒・ゴール板・スタンド・観客・ターフビジョン・発馬機・
//  樹木・遠景(富士山/六甲/淀の池 など)・天候 をすべて手続き生成する
// ============================================================
import * as THREE from '../vendor/three.module.min.js';
import { mulberry32, clamp, lerp, WAKU_COLORS, WAKU_TEXT, GOING, WEATHER } from './data.js';
import { Horse3D } from './horse3d.js';

const SEASON = {
  spring: { turfA: '#4f9a3c', turfB: '#5dab48', grass: 0x5a9a45, trees: [0xf4b6cc, 0xf7c6d8, 0xf1a7c2, 0xf9d3e0], green: [0x5c9a48, 0x4d8a3e], hill: 0x7ea088, crowd: [0xe8e8e8, 0xf2c0d0, 0x8fb8e8, 0xf0e0a0, 0x444444, 0xd05050] },
  early_summer: { turfA: '#3d8c2e', turfB: '#4b9c3a', grass: 0x4c8f3a, trees: [0x2f7a2e, 0x3b8a35, 0x2a6c2c, 0x4a9440], green: [0x2f7a2e, 0x3b8a35], hill: 0x5f8f72, crowd: [0xffffff, 0xf0f0f0, 0x70a8e0, 0xe86060, 0xf0d060, 0x333333] },
  rainy: { turfA: '#3a8431', turfB: '#46923b', grass: 0x47873a, trees: [0x2c702c, 0x357d33, 0x2a682c, 0x3f8a3c], green: [0x2c702c, 0x357d33], hill: 0x5c8770, crowd: [0xe8e8f0, 0x6080c0, 0xc04040, 0x40a070, 0xf0e070, 0x303038] },
  autumn: { turfA: '#4c8f38', turfB: '#5a9d43', grass: 0x6f9646, trees: [0xd9822b, 0xc8452a, 0xe2b93b, 0xb5632a], green: [0x4f7f3a, 0x5a8a40], hill: 0x8f8a62, crowd: [0x8a5a3a, 0x444450, 0xc8b890, 0x703030, 0x2f4a6a, 0xe0e0e0] },
  winter: { turfA: '#8a8f4c', turfB: '#989b58', grass: 0x9a9562, trees: [0x6b5a45, 0x7a6850, 0x5d4c3a, 0x66584a], green: [0x3d5a35, 0x34502f], hill: 0x76786f, crowd: [0x22222a, 0x3a3a48, 0x5a4a3a, 0x6a2a2a, 0x2a3a5a, 0x88888a] },
};
const SKY = [
  { top: 0x2c7bd4, hor: 0xc4e2f6, sun: 0xfff6e0, sunI: 3.0, hemi: 1.5, fog: 6500 },
  { top: 0x8b98a5, hor: 0xcdd3d8, sun: 0xe8e8ee, sunI: 1.2, hemi: 2.0, fog: 4200 },
  { top: 0x76808a, hor: 0xb0b7bd, sun: 0xd8dce2, sunI: 0.8, hemi: 1.9, fog: 2600 },
  { top: 0x59626b, hor: 0x8f979d, sun: 0xc0c6cc, sunI: 0.5, hemi: 1.7, fog: 1500 },
];

function ctex(w, h, draw, repeat) {
  const c = document.createElement('canvas'); c.width = w; c.height = h;
  draw(c.getContext('2d'), w, h);
  const t = new THREE.CanvasTexture(c); t.colorSpace = THREE.SRGBColorSpace; t.anisotropy = 4;
  if (repeat) { t.wrapS = t.wrapT = THREE.RepeatWrapping; t.repeat.set(repeat[0], repeat[1]); }
  return t;
}
const hex = (n) => '#' + n.toString(16).padStart(6, '0');

// コースに沿った帯状メッシュ。sec: 断面 [[d, yOffset], ...]
function ribbon(track, sec, o = {}) {
  const u0 = o.u0 ?? 0, u1 = o.u1 ?? track.lap, step = o.step ?? 5, uvLen = o.uvLen ?? 40;
  const n = Math.max(2, Math.round((u1 - u0) / step)), m = sec.length;
  const pos = new Float32Array((n + 1) * m * 3), uv = new Float32Array((n + 1) * m * 2);
  const p = {};
  for (let i = 0; i <= n; i++) {
    const u = u0 + ((u1 - u0) * i) / n;
    for (let j = 0; j < m; j++) {
      track.point(u, sec[j][0], p);
      const k = (i * m + j) * 3;
      pos[k] = p.x; pos[k + 1] = o.yFn ? o.yFn(sec[j][0], p.y, j) : p.y + sec[j][1]; pos[k + 2] = p.z;
      const q = (i * m + j) * 2; uv[q] = u / uvLen; uv[q + 1] = sec[j][2] ?? j / (m - 1);
    }
  }
  const idx = [];
  for (let i = 0; i < n; i++) for (let j = 0; j < m - 1; j++) {
    const a = i * m + j, b = a + 1, c = a + m, d = c + 1;
    if (track.t > 0) idx.push(a, c, b, b, c, d); else idx.push(a, b, c, b, d, c);
  }
  const g = new THREE.BufferGeometry();
  g.setAttribute('position', new THREE.BufferAttribute(pos, 3));
  g.setAttribute('uv', new THREE.BufferAttribute(uv, 2));
  g.setIndex(idx); g.computeVertexNormals();
  return g;
}
function quadGeo(a, b, c, d) { // a,b: 手前の左右 / c,d: 奥の左右
  const g = new THREE.BufferGeometry();
  g.setAttribute('position', new THREE.BufferAttribute(new Float32Array([...a, ...b, ...c, ...d]), 3));
  g.setAttribute('uv', new THREE.BufferAttribute(new Float32Array([0, 0, 1, 0, 0, 1, 1, 1]), 2));
  g.setIndex([0, 1, 2, 1, 3, 2]); g.computeVertexNormals();
  return g;
}

export class Venue {
  constructor(canvas) {
    this.canvas = canvas;
    this.renderer = new THREE.WebGLRenderer({ canvas, antialias: true, powerPreference: 'high-performance' });
    this.renderer.setPixelRatio(Math.min(window.devicePixelRatio || 1, 2));
    this.camera = new THREE.PerspectiveCamera(56, 1, 0.3, 16000);
    this.scene = new THREE.Scene();
    this.camPos = new THREE.Vector3(); this.camLook = new THREE.Vector3();
    this.camMode = 0; this.horses = []; this.time = 0;
    this._g = {}; this._v = new THREE.Vector3(); this._v2 = new THREE.Vector3();
    this.resize();
  }
  resize() {
    const w = this.canvas.clientWidth || window.innerWidth, h = this.canvas.clientHeight || window.innerHeight;
    this.renderer.setSize(w, h, false);
    this.camera.aspect = w / h;
    this.camera.fov = w < h ? 68 : 56;
    this.camera.updateProjectionMatrix();
  }
  dispose() {
    this.scene.traverse((o) => {
      if (o.geometry && !o.geometry.userData.shared) o.geometry.dispose();
      if (o.material) for (const m of Array.isArray(o.material) ? o.material : [o.material]) { if (m.map) m.map.dispose(); m.dispose(); }
    });
    this.scene = new THREE.Scene(); this.horses = [];
  }

  // ------------------------------------------------------------
  build(def, race, cond) {
    this.dispose();
    const sc = this.scene, tr = race.track, t = tr.t, W = tr.W, L = tr.L, R = tr.R;
    this.track = tr; this.race = race; this.def = def; this.cond = cond;
    const S = SEASON[def.season], sky = SKY[cond.weather];
    const dusk = def.time === 'dusk' && cond.weather <= 1;
    const rng = mulberry32(def.id.length * 7717 + def.dist);
    const A = (m) => { sc.add(m); return m; };
    const lam = (color, extra) => new THREE.MeshLambertMaterial({ color, ...extra });
    let minE = 1e9, sumE = 0;
    for (let i = 0; i < tr.ys.length; i++) { minE = Math.min(minE, tr.ys[i]); sumE += tr.ys[i]; }
    const groundY = minE - 0.6, infieldY = sumE / tr.ys.length - 0.3;
    this.center = new THREE.Vector3(L / 2, 0, t * R);
    const wet = cond.going >= 2 ? 0.8 : cond.going === 1 ? 0.92 : 1;

    // ---- 空・光 ----
    const top = new THREE.Color(dusk ? 0x3a5c9c : sky.top), hor = new THREE.Color(dusk ? 0xf6b983 : sky.hor);
    const sunDir = dusk ? new THREE.Vector3(0.85, 0.16, -t * 0.5).normalize() : new THREE.Vector3(0.35, 0.8, -t * 0.45).normalize();
    this.sunDir = sunDir;
    const skyMat = new THREE.ShaderMaterial({
      side: THREE.BackSide, depthWrite: false, fog: false,
      uniforms: { top: { value: top }, hor: { value: hor }, sunDir: { value: sunDir }, sunCol: { value: new THREE.Color(dusk ? 0xffb060 : sky.sun) }, sunK: { value: cond.weather === 0 ? 1 : cond.weather === 1 ? 0.25 : 0 } },
      vertexShader: 'varying vec3 vD; void main(){ vD = position; vec4 p = modelViewMatrix * vec4(position,1.0); gl_Position = projectionMatrix * p; }',
      fragmentShader: 'uniform vec3 top; uniform vec3 hor; uniform vec3 sunDir; uniform vec3 sunCol; uniform float sunK; varying vec3 vD; void main(){ vec3 d = normalize(vD); float h = max(d.y, 0.0); vec3 c = mix(hor, top, pow(h, 0.45)); float s = max(dot(d, sunDir), 0.0); c += sunCol * sunK * (pow(s, 600.0) * 3.0 + pow(s, 12.0) * 0.28); gl_FragColor = vec4(c, 1.0); }',
    });
    const dome = A(new THREE.Mesh(new THREE.SphereGeometry(13000, 24, 12), skyMat)); dome.position.copy(this.center);
    sc.fog = new THREE.Fog(hor.clone().lerp(top, 0.08), 200, dusk ? 5200 : sky.fog);
    A(new THREE.HemisphereLight(dusk ? 0xffd6b0 : 0xffffff, new THREE.Color(S.grass).multiplyScalar(0.6), dusk ? 1.5 : sky.hemi));
    const sun = A(new THREE.DirectionalLight(dusk ? 0xffa860 : sky.sun, dusk ? 2.6 : sky.sunI)); sun.position.copy(sunDir).multiplyScalar(100);

    // 雲
    const cloudTex = ctex(128, 64, (x, w, h) => {
      for (let i = 0; i < 26; i++) {
        const cx = 20 + rng() * 88, cy = 22 + rng() * 22, r = 10 + rng() * 16;
        const g = x.createRadialGradient(cx, cy, 0, cx, cy, r);
        g.addColorStop(0, 'rgba(255,255,255,0.55)'); g.addColorStop(1, 'rgba(255,255,255,0)');
        x.fillStyle = g; x.fillRect(0, 0, w, h);
      }
    });
    const nCloud = [14, 46, 60, 70][cond.weather];
    const cloudCol = dusk ? 0xffc9a0 : [0xffffff, 0xdfe3e8, 0xb9bfc6, 0x8d949b][cond.weather];
    this.clouds = [];
    for (let i = 0; i < nCloud; i++) {
      const sp = new THREE.Sprite(new THREE.SpriteMaterial({ map: cloudTex, color: cloudCol, fog: false, depthWrite: false, transparent: true, opacity: cond.weather === 0 ? 0.9 : 0.75 }));
      const a = rng() * Math.PI * 2, r = 2500 + rng() * 6500, s = 900 + rng() * 1800;
      sp.position.set(this.center.x + Math.cos(a) * r, 500 + rng() * 1400 + r * 0.08, this.center.z + Math.sin(a) * r);
      sp.scale.set(s, s * 0.42, 1); A(sp); this.clouds.push(sp);
    }

    // ---- 地面・コース ----
    const gnd = A(new THREE.Mesh(new THREE.CircleGeometry(12000, 48), lam(new THREE.Color(S.grass).multiplyScalar(0.8 * wet))));
    gnd.rotation.x = -Math.PI / 2; gnd.position.set(this.center.x, groundY - 0.05, this.center.z);

    const rough = cond.rough;
    const turfTex = ctex(256, 256, (x, w, h) => {
      for (let i = 0; i < 2; i++) { x.fillStyle = i ? S.turfB : S.turfA; x.fillRect((i * w) / 2, 0, w / 2, h); }
      // 芝目のノイズ
      for (let i = 0; i < 5000; i++) { x.fillStyle = `rgba(${rng() < 0.5 ? '0,30,0' : '200,230,140'},${0.04 + rng() * 0.06})`; x.fillRect(rng() * w, rng() * h, 1 + rng() * 2, 1 + rng() * 3); }
      // 内側の荒れ (開催後半ほど傷む)。v=0が内ラチ
      if (rough > 0.05) {
        const band = (7 / W) * h;
        const g = x.createLinearGradient(0, h, 0, h - band);
        g.addColorStop(0, `rgba(120,96,52,${Math.min(0.75, rough * 0.6)})`); g.addColorStop(1, 'rgba(120,96,52,0)');
        x.fillStyle = g; x.fillRect(0, h - band, w, band);
        for (let i = 0; i < 900 * rough; i++) { const yy = h - rng() * rng() * band; x.fillStyle = `rgba(90,70,40,${0.25 + rng() * 0.3})`; x.fillRect(rng() * w, yy, 2 + rng() * 5, 1 + rng() * 2); }
      }
      if (wet < 1) { x.fillStyle = `rgba(10,20,30,${(1 - wet) * 0.9})`; x.fillRect(0, 0, w, h); }
    }, [1, 1]);
    turfTex.wrapT = THREE.ClampToEdgeWrapping;
    const turfSec = []; for (let j = 0; j <= 6; j++) turfSec.push([-0.5 + ((W + 1) * j) / 6, 0, j / 6]);
    A(new THREE.Mesh(ribbon(tr, turfSec, { step: 4, uvLen: 44 }), lam(0xffffff, { map: turfTex })));
    const grassM = lam(new THREE.Color(S.grass).multiplyScalar(wet));
    const DI = 9, DO = 33; // 内側ダートコース
    A(new THREE.Mesh(ribbon(tr, [[-DI, 0], [-0.5, 0]], { step: 6 }), grassM));
    const dirtTex = ctex(128, 128, (x, w, h) => {
      x.fillStyle = cond.going >= 2 ? '#8f7654' : '#c8a978'; x.fillRect(0, 0, w, h);
      for (let i = 0; i < 1800; i++) { x.fillStyle = `rgba(${rng() < 0.5 ? '90,60,30' : '240,220,180'},${0.05 + rng() * 0.1})`; x.fillRect(rng() * w, rng() * h, 2, 2); }
    }, [1, 1]);
    A(new THREE.Mesh(ribbon(tr, [[-DO, 0], [-DI, 0]], { step: 6, uvLen: 12 }), lam(0xffffff, { map: dirtTex })));
    A(new THREE.Mesh(ribbon(tr, [[-R, 0], [-R * 0.6, 0], [-DO, 0]], { step: 8, yFn: (d, y, j) => (j === 2 ? y : infieldY) }), grassM));
    A(new THREE.Mesh(ribbon(tr, [[W + 0.5, 0], [W + 17, 0], [W + 48, 0]], { step: 8, yFn: (d, y, j) => (j === 2 ? groundY : y) }), grassM));
    // ポケット(引き込み線)
    if (tr.chute > 0) {
      const p0 = tr.point(tr.joinU, 0, {}), len = tr.chute + 22;
      const mk = (d0, d1, y, mat) => {
        const a = [p0.x + p0.nx * d0, p0.y + y, p0.z + p0.nz * d0], b = [p0.x + p0.nx * d1, p0.y + y, p0.z + p0.nz * d1];
        const c = [a[0] - p0.hx * len, a[1], a[2] - p0.hz * len], d = [b[0] - p0.hx * len, b[1], b[2] - p0.hz * len];
        const g = quadGeo(a, b, c, d); const m = A(new THREE.Mesh(g, mat)); m.material.side = THREE.DoubleSide; return m;
      };
      const ct = turfTex.clone(); ct.repeat.set(len / 44, 1); ct.rotation = Math.PI / 2; ct.needsUpdate = true;
      mk(-0.5, W + 0.5, 0.02, lam(new THREE.Color(S.turfA).multiplyScalar(wet)));
      mk(-14, -0.5, -0.02, grassM.clone()); mk(W + 0.5, W + 14, -0.02, grassM.clone());
      const railM = lam(0xf4f4f4);
      mk(-0.42, -0.28, 1.06, railM); mk(W + 0.28, W + 0.42, 1.06, railM.clone());
    }

    // ---- ラチ(柵) ----
    const white = lam(0xf6f6f4, { side: THREE.DoubleSide });
    const railSec = (d) => [[d - 0.07, 0.94], [d - 0.07, 1.08], [d + 0.07, 1.08], [d + 0.07, 0.94]];
    A(new THREE.Mesh(ribbon(tr, railSec(-0.35), { step: 3 }), white));
    A(new THREE.Mesh(ribbon(tr, railSec(W + 0.35), { step: 3 }), white));
    A(new THREE.Mesh(ribbon(tr, railSec(-DI), { step: 5 }), white));
    A(new THREE.Mesh(ribbon(tr, railSec(-DO), { step: 5 }), white));
    const postG = new THREE.CylinderGeometry(0.035, 0.035, 1.0, 5); postG.translate(0, 0.5, 0);
    const nPost = Math.floor(tr.lap / 3.2);
    const posts = A(new THREE.InstancedMesh(postG, lam(0xeeeeee), nPost * 2));
    const mt = new THREE.Matrix4(), p = {};
    for (let i = 0; i < nPost; i++) {
      for (let k = 0; k < 2; k++) { tr.point(i * 3.2, k ? W + 0.42 : -0.42, p); mt.makeTranslation(p.x, p.y, p.z); posts.setMatrixAt(i * 2 + k, mt); }
    }
    // 向正面〜コーナーの外ラチ沿いの生垣
    const hedgeM = lam(new THREE.Color(S.green[0]).multiplyScalar(0.8));
    A(new THREE.Mesh(ribbon(tr, [[W + 1.6, 0], [W + 1.6, 1.3], [W + 3.2, 1.3], [W + 3.2, 0]], { u0: L + 20, u1: tr.lap - 20, step: 6 }), hedgeM));

    // ---- ハロン棒・ゴール板 ----
    const poleG = new THREE.CylinderGeometry(0.06, 0.06, 2.6, 6); poleG.translate(0, 1.3, 0);
    for (let k = 1; k * 200 < tr.lap - 50; k++) {
      tr.point(tr.straight - k * 200, -1.2, p);
      const pole = A(new THREE.Mesh(poleG, lam(k % 2 ? 0xd82828 : 0xf2f2f2))); pole.position.set(p.x, p.y, p.z);
      const sp = new THREE.Sprite(new THREE.SpriteMaterial({ map: ctex(64, 64, (x) => { x.fillStyle = k % 2 ? '#fff' : '#d82828'; x.fillRect(0, 0, 64, 64); x.fillStyle = k % 2 ? '#d82828' : '#fff'; x.font = 'bold 44px sans-serif'; x.textAlign = 'center'; x.textBaseline = 'middle'; x.fillText(String(k * 2), 32, 34); }) }));
      sp.position.set(p.x, p.y + 3.0, p.z); sp.scale.set(1.0, 1.0, 1); A(sp);
    }
    {
      // ゴール板
      const gp = tr.point(tr.straight, -1.8, {});
      const board = A(new THREE.Mesh(new THREE.BoxGeometry(0.35, 4.2, 1.3), lam(0xf8f8f8))); board.position.set(gp.x, gp.y + 2.1, gp.z);
      const dsk = A(new THREE.Mesh(new THREE.CylinderGeometry(0.75, 0.75, 0.12, 20), lam(0xd42020))); dsk.rotation.z = Math.PI / 2; dsk.position.set(gp.x - 0.24, gp.y + 3.3, gp.z);
      const mir = A(new THREE.Mesh(new THREE.BoxGeometry(0.1, 1.6, 0.9), lam(0xbfd8ea))); mir.position.set(gp.x - 0.24, gp.y + 1.5, gp.z);
      const sign = new THREE.Sprite(new THREE.SpriteMaterial({ map: ctex(128, 48, (x) => { x.fillStyle = '#c81e1e'; x.fillRect(0, 0, 128, 48); x.fillStyle = '#fff'; x.font = 'bold 30px sans-serif'; x.textAlign = 'center'; x.textBaseline = 'middle'; x.fillText('GOAL', 64, 26); }) }));
      sign.position.set(gp.x, gp.y + 5.0, gp.z); sign.scale.set(2.6, 1.0, 1); A(sign);
      const go = tr.point(tr.straight, W + 1.2, {});
      const op = A(new THREE.Mesh(new THREE.CylinderGeometry(0.08, 0.08, 4, 6), lam(0xf8f8f8))); op.position.set(go.x, go.y + 2, go.z);
      // 決勝線 (実際は無いが目印として薄く)
      const a = tr.point(tr.straight, -0.3, {}), b = tr.point(tr.straight, W + 0.3, {});
      const ln = A(new THREE.Mesh(quadGeo([a.x - 0.12, a.y + 0.05, a.z], [a.x + 0.12, a.y + 0.05, a.z], [b.x - 0.12, b.y + 0.05, b.z], [b.x + 0.12, b.y + 0.05, b.z]), new THREE.MeshBasicMaterial({ color: 0xffffff, transparent: true, opacity: 0.55, side: THREE.DoubleSide })));
      ln.renderOrder = 2;
    }

    // ---- スタンド ----
    this.buildStand(def, tr, S, rng, dusk, groundY);

    // ---- ターフビジョン ----
    {
      const big = def.course === 'tokyo';
      const vw = big ? 52 : 34, vh = big ? 14 : 10.5;
      this.visCanvas = document.createElement('canvas'); this.visCanvas.width = 640; this.visCanvas.height = Math.round((640 * vh) / vw);
      this.visTex = new THREE.CanvasTexture(this.visCanvas); this.visTex.colorSpace = THREE.SRGBColorSpace;
      const vp = tr.point(tr.straight - 70, -(DO + 26), {});
      const grp = new THREE.Group(); grp.position.set(vp.x, infieldY, vp.z); if (t < 0) grp.rotation.y = 0; else grp.rotation.y = Math.PI;
      // 画面はスタンド(外)向き: ローカル+zを外向きにする
      const frame = new THREE.Mesh(new THREE.BoxGeometry(vw + 2.4, vh + 2.4, 3), lam(0x23262b)); frame.position.set(0, 5 + vh / 2 + 1.2, 0); grp.add(frame);
      const scr = new THREE.Mesh(new THREE.PlaneGeometry(vw, vh), new THREE.MeshBasicMaterial({ map: this.visTex, fog: false })); scr.position.set(0, 5 + vh / 2 + 1.2, 1.56); grp.add(scr);
      for (const s of [-1, 1]) { const leg = new THREE.Mesh(new THREE.BoxGeometry(2, 6, 2), lam(0x50555c)); leg.position.set(s * vw * 0.36, 3, 0); grp.add(leg); }
      A(grp); this.visT = 0;
    }

    // ---- 樹木・遠景 ----
    this.buildScenery(def, tr, S, rng, groundY, infieldY, dusk, sky, hor, cond);

    // ---- 発馬機 ----
    this.buildGate(race);

    // ---- 出走馬 ----
    for (const r of race.runners) { const h = new Horse3D(r.h); this.horses.push(h); sc.add(h.root); }

    // ---- 雨 ----
    this.rain = null;
    if (cond.weather >= 2) {
      const n = cond.weather === 3 ? 2600 : 1100;
      const pos = new Float32Array(n * 6); this.rainSeed = new Float32Array(n * 3);
      for (let i = 0; i < n * 3; i++) this.rainSeed[i] = rng();
      const g = new THREE.BufferGeometry(); g.setAttribute('position', new THREE.BufferAttribute(pos, 3));
      this.rain = A(new THREE.LineSegments(g, new THREE.LineBasicMaterial({ color: 0xdfe8f0, transparent: true, opacity: 0.38, fog: false })));
      this.rain.frustumCulled = false;
    }
    // ---- 蹴り上げる芝・泥 ----
    {
      const n = 220; this.pN = n; this.pPos = new Float32Array(n * 3); this.pVel = new Float32Array(n * 3); this.pLife = new Float32Array(n); this.pI = 0;
      for (let i = 0; i < n; i++) this.pPos[i * 3 + 1] = -100;
      const g = new THREE.BufferGeometry(); g.setAttribute('position', new THREE.BufferAttribute(this.pPos, 3));
      const col = cond.going >= 2 ? 0x5a4a32 : new THREE.Color(S.turfA).multiplyScalar(0.55);
      this.parts = A(new THREE.Points(g, new THREE.PointsMaterial({ color: col, size: 0.13, sizeAttenuation: true })));
      this.parts.frustumCulled = false;
    }
    this.introT = 0;
    this.drawVision(true);
  }

  // ------------------------------------------------------------
  buildStand(def, tr, S, rng, dusk, groundY) {
    const sc = this.scene, t = tr.t, W = tr.W, st = def.courseObj.stand;
    const len = st.len, H = st.h;
    const lam = (color, extra) => new THREE.MeshLambertMaterial({ color, ...extra });
    const g = new THREE.Group();
    const xC = tr.straight - len / 2 + 95;
    let baseY = 1e9; for (let x = xC - len / 2; x <= xC + len / 2; x += 10) baseY = Math.min(baseY, tr.elevAt(x - tr.straight));
    g.position.set(xC, baseY - 0.2, -t * (W + 17)); if (t > 0) g.rotation.y = Math.PI;
    this.standX0 = xC - len / 2; this.standX1 = xC + len / 2;
    // 観客席テクスチャ
    const crowdTex = (dens) => ctex(256, 128, (x, w, h) => {
      x.fillStyle = '#3a3d44'; x.fillRect(0, 0, w, h);
      for (let r = 0; r < 16; r++) for (let c = 0; c < 64; c++) {
        if (rng() > dens) { x.fillStyle = '#5b6d86'; x.fillRect(c * 4, r * 8 + 2, 3, 4); continue; }
        x.fillStyle = hex(S.crowd[(rng() * S.crowd.length) | 0]); x.fillRect(c * 4, r * 8 + 2, 3, 5);
        x.fillStyle = '#e8c8a8'; x.fillRect(c * 4 + 1, r * 8, 2, 2);
      }
    }, [len / 16, 1]);
    const glassTex = ctex(128, 128, (x, w, h) => {
      const gr = x.createLinearGradient(0, 0, 0, h); gr.addColorStop(0, dusk ? '#f3c08a' : '#a9cde8'); gr.addColorStop(1, dusk ? '#7a6f7c' : '#5d86a8');
      x.fillStyle = gr; x.fillRect(0, 0, w, h);
      x.strokeStyle = '#e9edf0'; x.lineWidth = 3;
      for (let i = 0; i <= 4; i++) { x.beginPath(); x.moveTo(i * 32, 0); x.lineTo(i * 32, h); x.stroke(); x.beginPath(); x.moveTo(0, i * 32); x.lineTo(w, i * 32); x.stroke(); }
      if (dusk) for (let i = 0; i < 16; i++) if (rng() < 0.5) { x.fillStyle = 'rgba(255,230,160,0.8)'; x.fillRect((i % 4) * 32 + 4, ((i / 4) | 0) * 32 + 4, 24, 24); }
    }, [len / 14, H / 26]);
    const conc = lam(0xd8d6cf), dark = lam(0x4a4e55), roofM = lam(0xeceef0), steel = lam(0x9aa3ad);
    const hl = len / 2;
    // 1階スタンド(立ち見の傾斜)
    g.add(new THREE.Mesh(quadGeo([-hl, 0.4, 0], [hl, 0.4, 0], [-hl, 7.5, 18], [hl, 7.5, 18]), lam(0xffffff, { map: crowdTex(0.92), side: THREE.DoubleSide })));
    const frontWall = new THREE.Mesh(new THREE.BoxGeometry(len, 1.2, 0.4), conc); frontWall.position.set(0, 0.6, -0.1); g.add(frontWall);
    // 本体
    const body = new THREE.Mesh(new THREE.BoxGeometry(len, H * 0.62, 34), conc); body.position.set(0, H * 0.31, 35); g.add(body);
    const glass = new THREE.Mesh(new THREE.PlaneGeometry(len - 4, H * 0.62 - 9), lam(0xffffff, { map: glassTex, emissive: dusk ? 0x403020 : 0x000000 })); glass.rotation.y = Math.PI; glass.position.set(0, 8 + (H * 0.62 - 9) / 2, 17.9); g.add(glass);
    // 上層スタンド
    const y0 = H * 0.5, y1 = H * 0.84;
    g.add(new THREE.Mesh(quadGeo([-hl, y0, 10], [hl, y0, 10], [-hl, y1, 31], [hl, y1, 31]), lam(0xffffff, { map: crowdTex(0.8), side: THREE.DoubleSide })));
    const lip = new THREE.Mesh(new THREE.BoxGeometry(len, 2.2, 1.2), conc); lip.position.set(0, y0 - 0.6, 9.6); g.add(lip);
    const back = new THREE.Mesh(new THREE.BoxGeometry(len, H * 0.42, 12), conc); back.position.set(0, H * 0.62 + H * 0.19, 38); g.add(back);
    const box = new THREE.Mesh(new THREE.PlaneGeometry(len - 6, 3.2), lam(0x9fc4dd, { emissive: dusk ? 0x554020 : 0x000000 })); box.rotation.y = Math.PI; box.position.set(0, y1 + 2.6, 31.9); g.add(box);
    // 大屋根
    const roof = new THREE.Mesh(new THREE.BoxGeometry(len + 18, 1.6, 56), roofM); roof.position.set(0, H + 3.5, 17); roof.rotation.x = 0.07; g.add(roof);
    const under = new THREE.Mesh(new THREE.BoxGeometry(len + 14, 0.5, 52), dark); under.position.set(0, H + 2.4, 17); under.rotation.x = 0.07; g.add(under);
    // 看板
    const sign = new THREE.Mesh(new THREE.PlaneGeometry(64, 5), new THREE.MeshBasicMaterial({ map: ctex(512, 40, (x, w, h) => { x.fillStyle = '#17324f'; x.fillRect(0, 0, w, h); x.fillStyle = '#f4f1e6'; x.font = 'bold 26px sans-serif'; x.textAlign = 'center'; x.textBaseline = 'middle'; x.fillText(st.name + ' STAND  ' + def.courseObj.short.toUpperCase(), w / 2, h / 2 + 1); }) }));
    sign.rotation.y = Math.PI; sign.position.set(0, H + 5.8, -10.6); g.add(sign);
    // 支柱・マスト
    const tall = def.course === 'tokyo';
    for (let i = 0; i <= 8; i++) {
      const x = -hl + (len * i) / 8;
      const col = new THREE.Mesh(new THREE.BoxGeometry(2.2, tall ? H + 26 : H + 6, 2.2), steel); col.position.set(x, (tall ? H + 26 : H + 6) / 2, 45); g.add(col);
      if (tall) {
        const cab = new THREE.Mesh(new THREE.CylinderGeometry(0.22, 0.22, 60, 4), steel);
        cab.position.set(x, H + 15.5, 19); cab.rotation.x = -1.13; g.add(cab);
      }
    }
    for (const s of [-1, 1]) { const ew = new THREE.Mesh(new THREE.BoxGeometry(3, H * 0.9, 44), conc); ew.position.set(s * (hl + 1.5), H * 0.45, 24); g.add(ew); }
    // 照明塔
    for (const s of [-1, 1]) {
      const tw = new THREE.Mesh(new THREE.CylinderGeometry(0.7, 1.0, H + 22, 6), steel); tw.position.set(s * (hl + 26), (H + 22) / 2, 20); g.add(tw);
      const lp = new THREE.Mesh(new THREE.BoxGeometry(9, 5, 1), lam(0xe8e8e0, { emissive: dusk ? 0xfff0c0 : 0x222222 })); lp.position.set(s * (hl + 26), H + 23, 19.4); g.add(lp);
    }
    sc.add(g);

    // エプロン(コンクリート)と立ち見の観客
    const a0 = this.standX0 - 60, a1 = this.standX1 + 40;
    sc.add(new THREE.Mesh(ribbon(tr, [[W + 1.4, 0.03], [W + 17.2, 0.03]], { u0: a0, u1: a1, step: 10 }), lam(0xb9b6ae)));
    const n = 2600, per = n / 3;
    const pg = new THREE.BoxGeometry(0.46, 1.62, 0.3); pg.translate(0, 0.81, 0);
    this.crowd = [];
    const col = new THREE.Color(), m4 = new THREE.Matrix4(), p = {};
    for (let k = 0; k < 3; k++) {
      const im = new THREE.InstancedMesh(pg, lam(0xffffff), per);
      for (let i = 0; i < per; i++) {
        // ゴール前ほど密
        const fx = rng(), x = fx < 0.55 ? tr.straight + (rng() - 0.62) * 170 : a0 + rng() * (a1 - a0);
        const d = W + 1.9 + 14.6 * Math.pow(rng(), 1.7);
        tr.point(clamp(x, a0, a1), d, p);
        m4.makeTranslation(p.x, p.y + 0.03, p.z); im.setMatrixAt(i, m4);
        col.setHex(S.crowd[(rng() * S.crowd.length) | 0]).multiplyScalar(0.75 + rng() * 0.35); im.setColorAt(i, col);
      }
      im.instanceColor.needsUpdate = true; sc.add(im); this.crowd.push(im);
    }
    this.cheer = 0;
  }

  // ------------------------------------------------------------
  buildScenery(def, tr, S, rng, groundY, infieldY, dusk, sky, hor, cond) {
    const sc = this.scene, t = tr.t, W = tr.W, L = tr.L, R = tr.R, id = def.course;
    const lam = (color, extra) => new THREE.MeshLambertMaterial({ color, ...extra });
    const cz = t * R;
    const dOf = (x, z) => { const cx = clamp(x, 0, L); return Math.hypot(x - cx, z - cz) - R; }; // 内ラチからの距離相当
    const inStandZone = (x, z) => (-t * z > 0) && x > this.standX0 - 110 && x < this.standX1 + 90;

    // 樹木
    const trunkG = new THREE.CylinderGeometry(0.22, 0.32, 1, 5); trunkG.translate(0, 0.5, 0);
    const leafG = new THREE.IcosahedronGeometry(1, 1), coneG = new THREE.ConeGeometry(1, 2.4, 7); coneG.translate(0, 1.2, 0);
    const list = [];
    const addTree = (x, z, y, s, kind) => list.push({ x, z, y, s, kind });
    const winter = def.season === 'winter', spring = def.season === 'spring';
    // 内馬場
    for (let i = 0; i < 150; i++) {
      const x = -R * 0.5 + rng() * (L + R), z = cz + (rng() - 0.5) * 2 * R * 0.8;
      const d = dOf(x, z);
      if (d > -52 || (Math.abs(x - (tr.straight - 70)) < 60 && -t * (z - cz) > 0)) continue;
      if (id === 'kyoto' && Math.hypot((x - L * 0.5) / 190, (z - cz) / 62) < 1.12) continue;
      addTree(x, z, infieldY, 3.5 + rng() * 3, rng() < 0.2 ? 'conifer' : 'round');
    }
    // 外周
    for (let i = 0; i < 520; i++) {
      const x = -R - 220 + rng() * (L + 2 * R + 440), z = cz + (rng() - 0.5) * (2 * R + 440);
      const d = dOf(x, z);
      if (d < W + 52 || d > W + 190 || inStandZone(x, z)) continue;
      addTree(x, z, groundY, 4 + rng() * 5, rng() < 0.25 ? 'conifer' : 'round');
    }
    // 東京: 3〜4コーナー内側の大ケヤキ
    if (id === 'tokyo') {
      const p = tr.point(tr.half + L + Math.PI * R * 0.42, -(R * 0.45), {});
      for (let i = 0; i < 9; i++) addTree(p.x + (rng() - 0.5) * 34, p.z + (rng() - 0.5) * 30, infieldY, 11 + rng() * 6, 'keyaki');
    }
    // 阪神(春): 桜並木
    if (spring) {
      for (let u = L + 30; u < tr.lap - 30; u += 13) { const p = tr.point(u, W + 20 + rng() * 8, {}); addTree(p.x, p.z, p.y - 0.5, 4.5 + rng() * 2, 'cherry'); }
      for (let i = 0; i < 40; i++) { const p = tr.point(rng() * tr.lap, -(48 + rng() * 14), {}); addTree(p.x, p.z, infieldY, 4 + rng() * 2, 'cherry'); }
    }
    const nT = list.length;
    const trunks = new THREE.InstancedMesh(trunkG, lam(0x5a4634), nT);
    const leaves = new THREE.InstancedMesh(leafG, lam(0xffffff), nT);
    const cones = new THREE.InstancedMesh(coneG, lam(0xffffff), nT);
    const m4 = new THREE.Matrix4(), q = new THREE.Quaternion(), v = new THREE.Vector3(), sv = new THREE.Vector3(), col = new THREE.Color();
    let nl = 0, nc = 0;
    list.forEach((tr0, i) => {
      const s = tr0.s, th = s * (tr0.kind === 'conifer' ? 0.35 : 0.55);
      m4.compose(v.set(tr0.x, tr0.y, tr0.z), q, sv.set(s * 0.22, th, s * 0.22)); trunks.setMatrixAt(i, m4);
      if (tr0.kind === 'conifer') {
        m4.compose(v.set(tr0.x, tr0.y + th * 0.6, tr0.z), q, sv.set(s * 0.36, s * 0.42, s * 0.36)); cones.setMatrixAt(nc, m4);
        cones.setColorAt(nc++, col.setHex(S.green[(rng() * 2) | 0]).multiplyScalar(0.65 + rng() * 0.2));
      } else {
        const bare = winter && tr0.kind !== 'keyaki' ? 0.6 : 1;
        m4.compose(v.set(tr0.x, tr0.y + th + s * 0.28, tr0.z), q, sv.set(s * 0.5 * bare, s * 0.42 * bare, s * 0.5 * bare)); leaves.setMatrixAt(nl, m4);
        let c;
        if (tr0.kind === 'cherry') c = S.trees[(rng() * 4) | 0];
        else if (tr0.kind === 'keyaki') c = winter ? 0x7a6850 : S.green[0];
        else c = spring ? (rng() < 0.4 ? S.trees[(rng() * 4) | 0] : S.green[(rng() * 2) | 0]) : S.trees[(rng() * S.trees.length) | 0];
        leaves.setColorAt(nl++, col.setHex(c).multiplyScalar(0.8 + rng() * 0.3));
      }
    });
    leaves.count = nl; cones.count = nc;
    if (leaves.instanceColor) leaves.instanceColor.needsUpdate = true;
    if (cones.instanceColor) cones.instanceColor.needsUpdate = true;
    sc.add(trunks, leaves, cones);

    // 周辺の街並み
    const urban = { tokyo: 230, nakayama: 300, kyoto: 120, hanshin: 260 }[id];
    const winTex = ctex(64, 64, (x) => {
      x.fillStyle = '#c9c6bd'; x.fillRect(0, 0, 64, 64);
      for (let r = 0; r < 8; r++) for (let c = 0; c < 4; c++) { x.fillStyle = dusk && rng() < 0.45 ? '#ffe9a8' : '#6f8194'; x.fillRect(c * 16 + 3, r * 8 + 2, 10, 4); }
    }, [1, 1]);
    const bG = new THREE.BoxGeometry(1, 1, 1); bG.translate(0, 0.5, 0);
    const blds = new THREE.InstancedMesh(bG, lam(0xffffff, { map: winTex }), urban);
    let nb = 0;
    for (let i = 0; i < urban * 4 && nb < urban; i++) {
      const x = -R - 1300 + rng() * (L + 2 * R + 2600), z = cz + (rng() - 0.5) * (2 * R + 2600);
      const d = dOf(x, z);
      if (d < W + 190 || (inStandZone(x, z) && d < W + 260)) continue;
      const far = clamp((d - 200) / 900, 0, 1);
      const h = 8 + rng() * rng() * (id === 'kyoto' ? 22 : 55) * (0.5 + far), w = 14 + rng() * 26, dp = 12 + rng() * 22;
      q.setFromAxisAngle(v.set(0, 1, 0), rng() * 0.5);
      m4.compose(v.set(x, groundY, z), q, sv.set(w, h, dp)); blds.setMatrixAt(nb, m4);
      blds.setColorAt(nb++, col.setHSL(0.08 + rng() * 0.08, 0.06 + rng() * 0.1, 0.62 + rng() * 0.25));
    }
    blds.count = nb; if (blds.instanceColor) blds.instanceColor.needsUpdate = true; sc.add(blds);

    // 遠景の山並み (霞ませた色・フォグ無効)
    const haze = (c, k) => new THREE.Color(c).lerp(hor, k);
    const ridge = (r, base, amp, seed, color, a0 = 0, a1 = Math.PI * 2, k = 0.55) => {
      const rr = mulberry32(seed), n = 140, pos = [], idx = [];
      const f = [0, 1, 2, 3, 4].map(() => rr() * 6.28), w = [3, 7, 13, 23, 41];
      for (let i = 0; i <= n; i++) {
        const a = a0 + ((a1 - a0) * i) / n;
        let h = 0; for (let j = 0; j < 5; j++) h += Math.sin(a * w[j] + f[j]) / (j + 1.5);
        const edge = a1 - a0 < 6 ? Math.sin((Math.PI * i) / n) : 1;
        h = base + amp * (0.55 + 0.45 * h) * Math.sqrt(edge);
        const x = this.center.x + Math.cos(a) * r, z = this.center.z + Math.sin(a) * r;
        pos.push(x, groundY - 5, z, x, Math.max(groundY, h), z);
        if (i < n) { const b = i * 2; idx.push(b, b + 1, b + 2, b + 1, b + 3, b + 2); }
      }
      const g = new THREE.BufferGeometry(); g.setAttribute('position', new THREE.Float32BufferAttribute(pos, 3)); g.setIndex(idx);
      sc.add(new THREE.Mesh(g, new THREE.MeshBasicMaterial({ color: haze(color, k), fog: false, side: THREE.DoubleSide })));
    };
    const vis = cond.weather >= 2 ? 0.82 : cond.weather === 1 ? 0.7 : 0.5;
    if (id === 'tokyo') {
      ridge(7000, 60, 260, 11, S.hill, 0, Math.PI * 2, vis + 0.12);
      ridge(5200, 30, 150, 12, S.hill, 0, Math.PI * 2, vis);
      // 富士山 (直線の先・やや内馬場寄りの方角)
      if (cond.weather <= 1) {
        const pts = []; for (let i = 0; i <= 14; i++) { const f = i / 14; pts.push(new THREE.Vector2(1500 * Math.pow(1 - f, 1.7) + 95, f * 600)); }
        const fg = new THREE.LatheGeometry(pts, 28);
        const cols = []; const pa = fg.attributes.position; const c0 = haze(0x5d7fa8, vis - 0.1), c1 = haze(0xffffff, 0.12), cc = new THREE.Color();
        for (let i = 0; i < pa.count; i++) { const y = pa.getY(i), s = clamp((y - 370 + 28 * Math.sin(pa.getX(i) * 0.05 + pa.getZ(i) * 0.07)) / 40, 0, 1); cc.copy(c0).lerp(c1, s); cols.push(cc.r, cc.g, cc.b); }
        fg.setAttribute('color', new THREE.Float32BufferAttribute(cols, 3));
        const fuji = new THREE.Mesh(fg, new THREE.MeshBasicMaterial({ vertexColors: true, fog: false })); fuji.position.set(this.center.x + 8400, groundY - 20, this.center.z + t * 2600); sc.add(fuji);
      }
    } else if (id === 'hanshin') {
      // 六甲山系: 向正面の奥に大きく連なる
      const a = t > 0 ? 0.15 : Math.PI + 0.15;
      ridge(6000, 80, 620, 21, S.hill, a, a + Math.PI * 0.95, vis);
      ridge(4300, 40, 330, 22, new THREE.Color(S.hill).multiplyScalar(0.85).getHex(), a - 0.2, a + Math.PI * 0.8, vis - 0.12);
      ridge(8000, 30, 120, 23, S.hill, 0, Math.PI * 2, vis + 0.15);
    } else if (id === 'kyoto') {
      ridge(6500, 60, 380, 31, S.hill, 0, Math.PI * 2, vis + 0.05);
      ridge(4600, 30, 240, 32, new THREE.Color(S.hill).multiplyScalar(0.9).getHex(), 2.2, 5.6, vis - 0.1);
      // 内馬場の池と白鳥
      const pond = new THREE.Mesh(new THREE.CircleGeometry(1, 40), new THREE.MeshLambertMaterial({ color: new THREE.Color(sky.top).lerp(new THREE.Color(0x3d6f8f), 0.5), emissive: 0x0a1820 }));
      pond.rotation.x = -Math.PI / 2; pond.scale.set(180, 56, 1); pond.position.set(L * 0.5, infieldY + 0.06, cz); sc.add(pond);
      const isl = new THREE.Mesh(new THREE.CylinderGeometry(10, 12, 1.2, 12), lam(S.grass)); isl.position.set(L * 0.5 + 30, infieldY + 0.4, cz + 6); sc.add(isl);
      this.swans = [];
      const sg = new THREE.SphereGeometry(1, 8, 6);
      for (let i = 0; i < 9; i++) {
        const s = new THREE.Group();
        const b = new THREE.Mesh(sg, lam(0xffffff)); b.scale.set(0.7, 0.35, 0.4); b.position.y = 0.3; s.add(b);
        const nk = new THREE.Mesh(new THREE.CylinderGeometry(0.07, 0.09, 0.8, 5), lam(0xffffff)); nk.position.set(0.55, 0.75, 0); nk.rotation.z = -0.25; s.add(nk);
        s.userData = { a: rng() * 6.28, r: 0.25 + rng() * 0.6, sp: (rng() - 0.5) * 0.06 };
        sc.add(s); this.swans.push(s);
      }
      this.pondC = new THREE.Vector3(L * 0.5, infieldY + 0.06, cz);
    } else {
      ridge(7500, 30, 130, 41, S.hill, 0, Math.PI * 2, vis + 0.15);
    }
    // パトロールタワー
    for (const u of [L + 30, tr.half - 30, tr.half + L + 30, tr.lap - 30]) {
      const p = tr.point(u, W + 7, {});
      const leg = new THREE.Mesh(new THREE.CylinderGeometry(0.25, 0.25, 9, 5), lam(0xdddddd)); leg.position.set(p.x, p.y + 4.5, p.z); sc.add(leg);
      const cab = new THREE.Mesh(new THREE.BoxGeometry(2.6, 2.2, 2.6), lam(0xf4f4f4)); cab.position.set(p.x, p.y + 10, p.z); sc.add(cab);
    }
  }

  // ------------------------------------------------------------
  buildGate(race) {
    const tr = race.track, n = race.runners.length, t = tr.t;
    const lam = (color) => new THREE.MeshLambertMaterial({ color });
    const p = tr.at(0, 0, {});
    const g = new THREE.Group();
    g.position.set(p.x, p.y, p.z); g.rotation.y = Math.atan2(-p.hz, p.hx);
    const zOf = (d) => -t * d;
    const green = lam(0x1f7a4a), wht = lam(0xf2f2f2), blue = lam(0x2f55a0);
    const d0 = 1.3 - 0.59, d1 = 1.3 + (n - 1) * 1.18 + 0.59, span = d1 - d0, zc = zOf((d0 + d1) / 2);
    for (let i = 0; i <= n; i++) {
      const dv = new THREE.Mesh(new THREE.BoxGeometry(3.3, 2.3, 0.14), i % 2 ? green : wht); dv.position.set(-1.75, 1.25, zOf(d0 + i * 1.18)); g.add(dv);
    }
    const topB = new THREE.Mesh(new THREE.BoxGeometry(0.5, 0.55, span + 0.6), blue); topB.position.set(0.05, 2.75, zc); g.add(topB);
    const rear = new THREE.Mesh(new THREE.BoxGeometry(0.3, 0.3, span + 0.6), blue); rear.position.set(-3.3, 2.6, zc); g.add(rear);
    for (const s of [d0 - 0.5, d1 + 0.5]) { const w = new THREE.Mesh(new THREE.CylinderGeometry(0.55, 0.55, 0.3, 12), lam(0x222222)); w.rotation.x = Math.PI / 2; w.position.set(-1.7, 0.55, zOf(s)); g.add(w); }
    this.gateDoors = [];
    for (let i = 0; i < n; i++) {
      for (const s of [-1, 1]) {
        const hinge = new THREE.Group(); hinge.position.set(0.0, 1.2, zOf(d0 + i * 1.18 + (s < 0 ? 0.08 : 1.1)));
        const door = new THREE.Mesh(new THREE.BoxGeometry(0.06, 1.5, 0.5), wht); door.position.set(0, 0, zOf(s < 0 ? 0.25 : -0.25) ); hinge.add(door);
        hinge.userData.s = s * -t; g.add(hinge); this.gateDoors.push(hinge);
      }
      const h = race.runners[i].h;
      const sp = new THREE.Sprite(new THREE.SpriteMaterial({ map: ctex(48, 48, (x) => { x.fillStyle = WAKU_COLORS[h.waku - 1]; x.fillRect(0, 0, 48, 48); x.fillStyle = WAKU_TEXT[h.waku - 1]; x.font = 'bold 32px sans-serif'; x.textAlign = 'center'; x.textBaseline = 'middle'; x.fillText(String(h.num), 24, 26); }) }));
      sp.position.set(0.05, 3.45, zOf(1.3 + i * 1.18)); sp.scale.set(0.8, 0.8, 1); g.add(sp);
    }
    this.gate = g; this.gateOpen = 0; this.scene.add(g);
  }

  // ------------------------------------------------------------
  drawVision(force) {
    const c = this.visCanvas, x = c.getContext('2d'), w = c.width, h = c.height, race = this.race, def = this.def;
    x.fillStyle = '#0b1622'; x.fillRect(0, 0, w, h);
    x.fillStyle = '#12304f'; x.fillRect(0, 0, w, 34);
    x.fillStyle = '#ffe9a0'; x.font = 'bold 22px sans-serif'; x.textBaseline = 'middle'; x.textAlign = 'left';
    x.fillText(`${def.grade} ${def.name}`, 10, 18);
    x.textAlign = 'right'; x.fillStyle = '#fff';
    x.fillText(`芝${def.dist}m ${WEATHER[this.cond.weather]}・${GOING[this.cond.going]}`, w - 10, 18);
    const fo = race.finishOrder, ord = race.order;
    const fin = fo.length > 0;
    x.textAlign = 'left'; x.font = 'bold 20px sans-serif';
    if (race.state === 'gate') {
      x.fillStyle = '#9fd0ff'; x.font = 'bold 40px sans-serif'; x.textAlign = 'center';
      x.fillText(def.courseObj.name, w / 2, h * 0.5); x.font = 'bold 22px sans-serif'; x.fillStyle = '#fff'; x.fillText('まもなく発走', w / 2, h * 0.78);
    } else {
      const rem = Math.max(0, race.D - ord[0].s);
      x.fillStyle = fin ? '#ff6b5b' : '#7fe08a'; x.font = 'bold 30px sans-serif';
      x.fillText(fin ? (race.state === 'done' ? '確定' : '入線') : `残り ${Math.ceil(rem / 10) * 10}m`, 12, 62);
      x.fillStyle = '#fff'; x.font = 'bold 24px sans-serif'; x.textAlign = 'right';
      const tt = fin ? fo[0].ft : race.t; x.fillText(`${Math.floor(tt / 60)}:${(tt % 60).toFixed(1).padStart(4, '0')}`, w - 12, 62);
      const list = fin ? fo.slice().sort((a, b) => a.ft - b.ft) : ord;
      const bw = (w - 24) / 5;
      for (let i = 0; i < 5 && i < list.length; i++) {
        const r = list[i], bx = 12 + i * bw, by = 84;
        x.fillStyle = '#1b2a3a'; x.fillRect(bx, by, bw - 8, h - by - 10);
        x.fillStyle = '#aab'; x.font = 'bold 15px sans-serif'; x.textAlign = 'left'; x.fillText(`${i + 1}着`.replace('着', fin ? '着' : '番手'), bx + 6, by + 14);
        x.fillStyle = WAKU_COLORS[r.h.waku - 1]; x.fillRect(bx + 8, by + 28, bw - 24, h - by - 48);
        x.fillStyle = WAKU_TEXT[r.h.waku - 1]; x.font = `bold ${Math.min(52, h - by - 56)}px sans-serif`; x.textAlign = 'center';
        x.fillText(String(r.h.num), bx + (bw - 8) / 2, by + 28 + (h - by - 48) / 2 + 2);
        if (r.isPlayer) { x.strokeStyle = '#ffe14a'; x.lineWidth = 5; x.strokeRect(bx + 2, by + 2, bw - 12, h - by - 14); }
      }
    }
    this.visTex.needsUpdate = true;
  }

  // ------------------------------------------------------------
  // 発走前の場内紹介カメラ
  introCam(tau, dur) {
    const tr = this.track, t = tr.t, W = tr.W, cam = this.camera, c = this.center, g = this._g;
    const f = tau / dur;
    if (f < 0.4) {
      const k = f / 0.4, a = (t > 0 ? -1 : 1) * (0.9 + k * 0.9) + Math.PI / 2 * -t;
      const r = tr.L * 0.75 + tr.R;
      cam.position.set(c.x + Math.cos(a) * r, 130 - k * 50, c.z + Math.sin(a) * r * 0.9 * 1);
      cam.lookAt(tr.straight - 60, 10, -t * W * 0.5);
    } else if (f < 0.72) {
      const k = (f - 0.4) / 0.32;
      tr.point(tr.straight - 230 + k * 120, W * 0.45, g);
      cam.position.set(g.x, g.y + 2.2 + k * 1.5, g.z);
      tr.point(tr.straight + 30, W + 30, g);
      cam.lookAt(g.x, g.y + 16, g.z);
    } else {
      const k = (f - 0.72) / 0.28, n = this.race.runners.length;
      const mid = 1.3 + (n - 1) * 0.59;
      tr.at(16 - k * 5, mid + (1 - k) * 6 - 3, g);
      cam.position.set(g.x, g.y + 1.7 + k * 1.2, g.z);
      tr.at(-2, mid, g);
      cam.lookAt(g.x, g.y + 1.5, g.z);
    }
    this.camPos.copy(cam.position); this.snap = true;
  }

  // ------------------------------------------------------------
  frame(dt, opt = {}) {
    const race = this.race, tr = this.track, g = this._g, cam = this.camera;
    this.time += dt;
    // 馬
    for (let i = 0; i < race.runners.length; i++) {
      const r = race.runners[i];
      tr.at(r.s - 1.5, r.d, g); g.tsign = tr.t;
      this.horses[i].update(r, g, dt);
    }
    // ゲート
    if (this.gate) {
      const target = race.state === 'gate' ? 0 : 1;
      this.gateOpen += (target - this.gateOpen) * Math.min(1, dt * 14);
      for (const h of this.gateDoors) h.rotation.y = h.userData.s * this.gateOpen * 1.45;
      if (race.state !== 'gate' && race.order[race.order.length - 1].s > 260) this.gate.visible = false;
    }
    // カメラ
    if (!opt.intro) {
      const pl = opt.focus || race.player || race.order[0];
      tr.at(pl.s - 1.5, pl.d, g);
      const P = this._v.set(g.x, g.y, g.z), look = this._v2;
      let pos = new THREE.Vector3(), k = 13;
      const mode = opt.cam ?? this.camMode;
      if (mode === 0) { // 後方追尾
        pos.set(P.x - g.hx * 6.6, P.y + 3.3, P.z - g.hz * 6.6);
        look.set(P.x + g.hx * 7, P.y + 1.5, P.z + g.hz * 7);
      } else if (mode === 1) { // 騎手目線
        pos.set(P.x - g.hx * 0.3, P.y + 2.55, P.z - g.hz * 0.3);
        look.set(P.x + g.hx * 12, P.y + 1.6, P.z + g.hz * 12); k = 14;
      } else if (mode === 2) { // 中継カメラ(外から)
        tr.at(pl.s + 2, tr.W + 12, g);
        pos.set(g.x - g.hx * 5, g.y + 7.5, g.z - g.hz * 5);
        look.set(P.x + g.hx * 3, P.y + 1.2, P.z + g.hz * 3); k = 5;
      } else if (mode === 3) { // 俯瞰
        pos.set(P.x - g.hx * 26, P.y + 24, P.z - g.hz * 26);
        look.set(P.x + g.hx * 10, P.y, P.z + g.hz * 10); k = 4;
      } else { // ゴール前固定
        tr.point(tr.straight + 6, tr.W + 14, g);
        pos.set(g.x, g.y + 3.2, g.z);
        tr.point(tr.straight - 2, tr.W * 0.35, g);
        look.set((g.x + P.x * 0.5) / 1.5, g.y + 1.2, (g.z + P.z * 0.5) / 1.5); k = 6;
      }
      const a = this.snap ? 1 : 1 - Math.exp(-dt * k);
      this.camPos.lerp(pos, a); this.camLook.lerp(look, this.snap ? 1 : 1 - Math.exp(-dt * (k + 3)));
      this.snap = false;
      cam.position.copy(this.camPos);
      // 走行の振動
      if (mode <= 1 && pl.v > 5) cam.position.y += Math.sin(pl.phase * Math.PI * 2) * (mode === 1 ? 0.07 : 0.025);
      cam.lookAt(this.camLook);
    }
    // 観客: 直線で盛り上がる
    if (this.crowd) {
      const lead = race.order[0];
      const hot = race.state === 'run' && lead.s > race.D - tr.straight - 150 && race.finishOrder.length < 3 ? 1 : 0;
      this.cheer += (hot - this.cheer) * Math.min(1, dt * 1.5);
      for (let k = 0; k < 3; k++) this.crowd[k].position.y = Math.abs(Math.sin(this.time * (6 + k * 0.7) + k * 2.1)) * (0.04 + this.cheer * 0.28);
    }
    if (this.swans) for (const s of this.swans) {
      const u = s.userData; u.a += u.sp * dt;
      s.position.set(this.pondC.x + Math.cos(u.a) * 170 * u.r, this.pondC.y, this.pondC.z + Math.sin(u.a) * 50 * u.r);
      s.rotation.y = -u.a - (u.sp > 0 ? Math.PI / 2 : -Math.PI / 2);
    }
    // ターフビジョン
    this.visT -= dt; if (this.visT <= 0) { this.visT = 0.5; this.drawVision(); }
    // 雨
    if (this.rain) {
      const pa = this.rain.geometry.attributes.position, arr = pa.array, n = arr.length / 6, sd = this.rainSeed;
      const cx = cam.position.x, cy = cam.position.y, cz = cam.position.z, tt = this.time;
      for (let i = 0; i < n; i++) {
        const x = cx + ((sd[i * 3] * 70 + tt * 3) % 70) - 35, z = cz + sd[i * 3 + 2] * 70 - 35;
        const y = cy + 22 - ((sd[i * 3 + 1] * 34 + tt * 30) % 34);
        const k = i * 6; arr[k] = x; arr[k + 1] = y; arr[k + 2] = z; arr[k + 3] = x + 0.12; arr[k + 4] = y - 1.1; arr[k + 5] = z;
      }
      pa.needsUpdate = true;
    }
    // 蹴り上げ
    if (this.parts) {
      const pp = this.pPos, pv = this.pVel, pl = this.pLife, n = this.pN;
      if (race.state !== 'gate') {
        for (const r of race.runners) {
          if (r.v < 9 || Math.random() > dt * 22) continue;
          const dx = r.geo.x - cam.position.x, dz = r.geo.z - cam.position.z;
          if (dx * dx + dz * dz > 3600) continue;
          const i = this.pI = (this.pI + 1) % n, k = i * 3;
          tr.at(r.s - 2.6, r.d + (Math.random() - 0.5) * 0.4, g);
          pp[k] = g.x; pp[k + 1] = g.y + 0.1; pp[k + 2] = g.z;
          pv[k] = -g.hx * (2 + Math.random() * 3) + (Math.random() - 0.5) * 2; pv[k + 1] = 2.5 + Math.random() * 3.5; pv[k + 2] = -g.hz * (2 + Math.random() * 3) + (Math.random() - 0.5) * 2;
          pl[i] = 1;
        }
      }
      for (let i = 0; i < n; i++) {
        if (pl[i] <= 0) continue;
        const k = i * 3; pl[i] -= dt * 1.1;
        pv[k + 1] -= 14 * dt; pp[k] += pv[k] * dt; pp[k + 1] += pv[k + 1] * dt; pp[k + 2] += pv[k + 2] * dt;
        if (pl[i] <= 0) pp[k + 1] = -100;
      }
      this.parts.geometry.attributes.position.needsUpdate = true;
    }
    this.renderer.render(this.scene, cam);
  }
}
