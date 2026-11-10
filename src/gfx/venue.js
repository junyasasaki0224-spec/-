// レース場と周辺の景観(架空の「みなと競艇場」)。
// 固定構造物は Blender 製の GLB (assets/blender/build_venue.py、AO を頂点カラーに焼き込み)。
// 動くもの・文字のあるもの・大量に並ぶもの(観客、木、旗、看板、大時計、映像装置など)はここで作る。
import * as THREE from 'three';
import { mergeGeometries } from 'three/examples/jsm/utils/BufferGeometryUtils.js';
import venueGlb from '../../assets/models/venue.glb';
import { loadGLB } from './boat.js';
import { canvasTex, JP_FONT, BOAT_COLORS, BOAT_CSS, BOAT_TEXT_CSS } from './common.js';
import { M1, M2, BOUNDS } from '../sim/course.js';

const QUAY = 1.6;
const L = (color, o = {}) => new THREE.MeshLambertMaterial({ color, ...o });
const rnd = (() => { let s = 12345; return () => { s = (s * 1664525 + 1013904223) | 0; return ((s >>> 8) & 0xffff) / 65536; }; })();

// ---------- 会場全体に落とす太陽の影(環境を切り替えた時に1回だけ描く) ----------
class StaticShadow {
  constructor() {
    this.u = { tStat: { value: null }, uStatM: { value: new THREE.Matrix4() }, uStatOn: { value: 0 }, uStatTexel: { value: 1 / 2048 } };
    this.cam = new THREE.OrthographicCamera(-1, 1, 1, -1, 1, 1000);
    this.rt = null; this.size = 0;
    this.depthMat = new THREE.MeshBasicMaterial({ colorWrite: false, side: THREE.DoubleSide });
    this.tmp = new THREE.Scene(); this.tmp.overrideMaterial = this.depthMat;
  }
  patch(m, extra) {
    const u = this.u;
    m.onBeforeCompile = (sh) => {
      Object.assign(sh.uniforms, u);
      sh.vertexShader = 'uniform mat4 uStatM;\nvarying vec3 vStatPos;\n' + sh.vertexShader.replace('#include <project_vertex>', `#include <project_vertex>
        { vec4 swp = vec4(transformed, 1.0); vec3 swn = objectNormal;
          #ifdef USE_INSTANCING
            swp = instanceMatrix * swp; swn = mat3(instanceMatrix) * swn;
          #endif
          swp = modelMatrix * swp; swn = normalize(mat3(modelMatrix) * swn);
          swp.xyz += swn * 0.3;
          vStatPos = (uStatM * swp).xyz; }`);
      sh.fragmentShader = `uniform sampler2D tStat; uniform float uStatOn, uStatTexel; varying vec3 vStatPos;
        float statShadow(){
          if (uStatOn < 0.5) return 1.0;
          vec3 p = vStatPos;
          if (p.x < 0.0 || p.x > 1.0 || p.y < 0.0 || p.y > 1.0 || p.z > 1.0) return 1.0;
          float s = 0.0, b = p.z - 0.0006;
          s += step(b, texture2D(tStat, p.xy + vec2(-0.5, -0.5) * uStatTexel).r);
          s += step(b, texture2D(tStat, p.xy + vec2(0.5, -0.5) * uStatTexel).r);
          s += step(b, texture2D(tStat, p.xy + vec2(-0.5, 0.5) * uStatTexel).r);
          s += step(b, texture2D(tStat, p.xy + vec2(0.5, 0.5) * uStatTexel).r);
          return s * 0.25;
        }\n` + sh.fragmentShader.replace('#include <lights_fragment_end>', `#include <lights_fragment_end>
        { float ss = statShadow(); reflectedLight.directDiffuse *= ss; reflectedLight.directSpecular *= ss; }`);
      if (extra) extra(sh);
    };
    m.customProgramCacheKey = () => 'stat' + (extra ? extra.key : '');
    return m;
  }
  render(renderer, group, sunDir, size) {
    if (!size) { this.u.uStatOn.value = 0; return; }
    if (size !== this.size) {
      if (this.rt) this.rt.dispose();
      this.rt = new THREE.WebGLRenderTarget(size, size, { depthBuffer: true });
      this.rt.depthTexture = new THREE.DepthTexture(size, size);
      this.rt.depthTexture.minFilter = this.rt.depthTexture.magFilter = THREE.NearestFilter;
      this.size = size;
    }
    const cam = this.cam, c = new THREE.Vector3(-20, 10, 5);
    cam.position.copy(sunDir).multiplyScalar(900).add(c);
    cam.up.set(0, 1, 0); cam.lookAt(c); cam.updateMatrixWorld();
    // 会場の範囲をライト空間に収める
    const inv = cam.matrixWorldInverse.copy(cam.matrixWorld).invert(), v = new THREE.Vector3();
    let x0 = 1e9, x1 = -1e9, y0 = 1e9, y1 = -1e9, z0 = 1e9, z1 = -1e9;
    for (const x of [-345, 305]) for (const y of [-1, 48]) for (const z of [-112, 128]) {
      v.set(x, y, z).applyMatrix4(inv);
      x0 = Math.min(x0, v.x); x1 = Math.max(x1, v.x); y0 = Math.min(y0, v.y); y1 = Math.max(y1, v.y); z0 = Math.min(z0, v.z); z1 = Math.max(z1, v.z);
    }
    cam.left = x0; cam.right = x1; cam.bottom = y0; cam.top = y1; cam.near = -z1 - 5; cam.far = -z0 + 5;
    cam.updateProjectionMatrix();
    this.u.uStatM.value.set(0.5, 0, 0, 0.5, 0, 0.5, 0, 0.5, 0, 0, 0.5, 0.5, 0, 0, 0, 1).multiply(cam.projectionMatrix).multiply(cam.matrixWorldInverse);
    const parent = group.parent, hidden = [];
    group.traverse((o) => { if (o.visible && (o.userData.noShadow || o.isSprite || o.isLine)) { o.visible = false; hidden.push(o); } });
    this.tmp.add(group);
    const prev = renderer.getRenderTarget(), prevSh = renderer.shadowMap.autoUpdate;
    renderer.shadowMap.autoUpdate = false;
    renderer.setRenderTarget(this.rt); renderer.clear();
    renderer.render(this.tmp, cam);
    renderer.setRenderTarget(prev); renderer.shadowMap.autoUpdate = prevSh;
    parent.add(group);
    for (const o of hidden) o.visible = true;
    this.u.tStat.value = this.rt.depthTexture; this.u.uStatTexel.value = 1 / size; this.u.uStatOn.value = 1;
  }
}

function treeGeometry() {
  const parts = [], col = new THREE.Color();
  const paint = (g, fn) => {
    g = g.index ? g.toNonIndexed() : g;
    const p = g.attributes.position, c = new Float32Array(p.count * 3);
    for (let i = 0; i < p.count; i++) { fn(col, p.getY(i)); c[i * 3] = col.r; c[i * 3 + 1] = col.g; c[i * 3 + 2] = col.b; }
    g.setAttribute('color', new THREE.BufferAttribute(c, 3)); g.deleteAttribute('uv');
    return g;
  };
  parts.push(paint(new THREE.CylinderGeometry(0.2, 0.32, 3.2, 6).translate(0, 1.6, 0), (c) => c.setRGB(0.2, 0.14, 0.09)));
  for (const [x, y, z, r] of [[0, 4.6, 0, 2.3], [1.3, 3.8, 0.5, 1.6], [-1.2, 3.9, -0.6, 1.7], [0.2, 3.7, -1.3, 1.5], [-0.3, 5.9, 0.3, 1.5]]) {
    const g = new THREE.IcosahedronGeometry(r, 1);
    const p = g.attributes.position;
    for (let i = 0; i < p.count; i++) {   // でこぼこさせる
      const k = 1 + 0.16 * Math.sin(p.getX(i) * 3.1 + p.getY(i) * 2.3) * Math.cos(p.getZ(i) * 2.7);
      p.setXYZ(i, p.getX(i) * k, p.getY(i) * k * 0.85, p.getZ(i) * k);
    }
    g.translate(x, y, z);
    parts.push(paint(g, (c, yy) => { const t = THREE.MathUtils.clamp((yy - 2.2) / 4.5, 0, 1); c.setRGB(0.04 + 0.08 * t, 0.1 + 0.17 * t, 0.035 + 0.05 * t); }));
  }
  const g = mergeGeometries(parts, false); g.computeVertexNormals();
  return g;
}

export async function createVenue(scene) {
  const group = new THREE.Group();
  scene.add(group);
  const glow = [];            // 夜に光らせるマテリアル [mat, 強さ]
  const lightPos = [];        // 水面に映り込む照明の位置(映り込みを描かない画質用)
  const dummy = new THREE.Object3D();
  const stat = new StaticShadow();
  const W = BOUNDS;

  // ================= Blender 製の固定構造物 =================
  const winTex = canvasTex(256, 128, (c, w, h) => {
    c.fillStyle = '#6b8ca6'; c.fillRect(0, 0, w, h);
    const g = c.createLinearGradient(0, 0, 0, h); g.addColorStop(0, 'rgba(225,240,255,0.5)'); g.addColorStop(1, 'rgba(30,60,90,0.45)');
    c.fillStyle = g; c.fillRect(0, 0, w, h);
  }, { repeat: true });
  const litTex = canvasTex(256, 64, (c, w, h) => {
    c.fillStyle = '#000'; c.fillRect(0, 0, w, h);
    for (let i = 0; i < 16; i++) { c.fillStyle = `rgba(255,${214 + (i * 13) % 30},${150 + (i * 37) % 70},${[1, 0.75, 0.95, 0.55][i % 4]})`; c.fillRect(i * 16, 0, 16, h); }
  }, { repeat: true });
  litTex.repeat.set(0.25, 1);
  const lampTex = canvasTex(128, 64, (c, w, h) => { c.fillStyle = '#30353c'; c.fillRect(0, 0, w, h); for (let j = 0; j < 4; j++) for (let i = 0; i < 8; i++) { c.fillStyle = '#eef0f2'; c.beginPath(); c.arc(8 + i * 16, 8 + j * 16, 6, 0, 7); c.fill(); } });
  lampTex.flipY = false; winTex.flipY = false; litTex.flipY = false;
  const mGlass = stat.patch(new THREE.MeshStandardMaterial({ color: 0xffffff, map: winTex, metalness: 0.85, roughness: 0.08, envMapIntensity: 1.25, emissive: 0xffffff, emissiveMap: litTex, emissiveIntensity: 0, vertexColors: true }));
  const mLampPanel = new THREE.MeshStandardMaterial({ color: 0xffffff, map: lampTex, roughness: 0.5, emissive: 0xfff3da, emissiveMap: lampTex, emissiveIntensity: 0 });
  glow.push([mGlass, 0.9], [mLampPanel, 3.4]);
  const model = await loadGLB(venueGlb);
  const seen = new Map();
  model.traverse((o) => {
    if (!o.isMesh) return;
    const name = o.material.name.replace(/\.\d+$/, '');
    if (name === 'Glass') o.material = mGlass;
    else if (name === 'Lamp') o.material = mLampPanel;
    else {
      if (!seen.has(o.material)) { o.material.envMapIntensity = 0.3; o.material.color.multiplyScalar(0.82); seen.set(o.material, stat.patch(o.material)); }
      o.material = seen.get(o.material);
    }
    o.matrixAutoUpdate = false; o.updateMatrix();
  });
  group.add(model);

  const P = (m, extra) => stat.patch(m, extra);
  const mSteel = P(L(0x8d949c)), mDark = L(0x2a2d33);

  // ================= 観客 =================
  const SX0 = -150, SX1 = 190, BAY = 8.5;
  const cu = { uT: { value: 0 }, uCheer: { value: 0 } };
  let crowdMeshes = [], crowdTotal = 0;
  {
    const spots = [];
    for (let i = 0; i < 12; i++) for (let x = SX0 + 0.5; x < SX1 - 0.4; x += 0.62) {
      const inBay = (x - SX0) % BAY, bay = Math.floor((x - SX0) / BAY);
      if (inBay < 0.3 || inBay > BAY - 0.3 || (bay % 4 === 0 && inBay < 1.7)) continue;
      const dens = 0.62 - 0.02 * i - Math.min(0.3, Math.abs(x - 20) / 600);
      if (rnd() < dens) spots.push([x + rnd() * 0.15, QUAY + 0.62 * (i + 1) + 0.42, 72 + 1.5 * i + 1.0, 0]);
    }
    for (let x = -240; x < 240; x += 0.9) if (rnd() < (Math.abs(x) < 120 ? 0.7 : 0.3)) spots.push([x, QUAY, 62.6 + rnd() * 2.4, 1]);
    for (let i = spots.length - 1; i > 0; i--) { const j = (rnd() * (i + 1)) | 0; [spots[i], spots[j]] = [spots[j], spots[i]]; }
    const cheer = (sh) => {
      sh.uniforms.uT = cu.uT; sh.uniforms.uCheer = cu.uCheer;
      sh.vertexShader = 'uniform float uT; uniform float uCheer;\n' + sh.vertexShader.replace('#include <begin_vertex>',
        '#include <begin_vertex>\n float ph = instanceMatrix[3].x * 3.1 + instanceMatrix[3].z * 1.7; transformed.y += uCheer * max(0.0, sin(uT * 9.0 + ph)) * 0.35;');
    };
    cheer.key = 'cheer';
    const bodyG = new THREE.CapsuleGeometry(0.19, 0.34, 2, 6); bodyG.scale(1, 1, 0.72);
    const bodies = new THREE.InstancedMesh(bodyG, P(L(0xffffff), cheer), spots.length);
    const heads = new THREE.InstancedMesh(new THREE.SphereGeometry(0.115, 6, 5), P(L(0xffffff), cheer), spots.length);
    const c = new THREE.Color();
    const pal = [0xe8e8e8, 0x2b3a67, 0xc0392b, 0x1e824c, 0xf2c94c, 0x555b66, 0x8e6bbf, 0x3d8fd1, 0xe98b39, 0x222222, 0xf4f0e6, 0x7d8a96, 0xd7d2c4, 0x394a3f];
    const skin = [0xe2b594, 0xd9a981, 0xeec3a4, 0x2a2622, 0xf0f0f0, 0x1b3a8a];   // 肌 / 黒髪 / 帽子
    spots.forEach((p, i) => {
      const stand = p[3], h = stand ? 1.25 + rnd() * 0.25 : 0.8;
      dummy.rotation.set(0, (rnd() - 0.5) * 0.6, 0); dummy.scale.set(1, stand ? 1.7 : 1, 1);
      dummy.position.set(p[0], p[1] + (stand ? 0.62 : 0.1), p[2]); dummy.updateMatrix(); bodies.setMatrixAt(i, dummy.matrix);
      dummy.scale.set(1, 1, 1); dummy.position.set(p[0], p[1] + (stand ? h + 0.12 : 0.52), p[2] - 0.03); dummy.updateMatrix(); heads.setMatrixAt(i, dummy.matrix);
      bodies.setColorAt(i, c.set(pal[(rnd() * pal.length) | 0]));
      heads.setColorAt(i, c.set(skin[rnd() < 0.72 ? (rnd() * 3) | 0 : 3 + ((rnd() * 3) | 0)]));
    });
    group.add(bodies, heads);
    crowdMeshes = [bodies, heads]; crowdTotal = spots.length;
  }

  // ================= のぼり旗・万国旗 =================
  let noboriMat;
  {
    const xs = []; for (let x = -246; x <= 240; x += 9) if (Math.abs(x) > 14) xs.push(x);
    const poleG = new THREE.CylinderGeometry(0.035, 0.035, 4, 5);
    const poles = new THREE.InstancedMesh(poleG, mSteel, xs.length);
    const fg = new THREE.PlaneGeometry(0.7, 2.6, 2, 8);
    const wu = { uT: { value: 0 }, uWindS: { value: 1 } };
    const wave = (sh) => {
      sh.uniforms.uT = wu.uT; sh.uniforms.uWindS = wu.uWindS;
      sh.vertexShader = 'uniform float uT, uWindS;\n' + sh.vertexShader.replace('#include <begin_vertex>',
        '#include <begin_vertex>\n float fx = position.x + 0.35; transformed.z += sin(uT * (3.0 + uWindS) + position.y * 3.0 + instanceMatrix[3].x) * 0.16 * fx * (0.4 + 0.3 * uWindS);');
    };
    wave.key = 'wave';
    noboriMat = P(L(0xffffff, { side: THREE.DoubleSide }), wave); noboriMat.userData.u = wu;
    const flags = new THREE.InstancedMesh(fg, noboriMat, xs.length);
    const c = new THREE.Color();
    xs.forEach((x, i) => {
      dummy.rotation.set(0, 0, 0); dummy.scale.set(1, 1, 1);
      dummy.position.set(x, QUAY + 2, 66.5); dummy.updateMatrix(); poles.setMatrixAt(i, dummy.matrix);
      dummy.position.set(x + 0.4, QUAY + 2.6, 66.5); dummy.updateMatrix(); flags.setMatrixAt(i, dummy.matrix);
      flags.setColorAt(i, c.set(BOAT_COLORS[i % 6] === 0x16161a ? 0x7a2fb0 : BOAT_COLORS[i % 6]));
    });
    group.add(poles, flags);
    const n = 27, bunting = new THREE.InstancedMesh(new THREE.PlaneGeometry(0.5, 0.7), L(0xffffff, { side: THREE.DoubleSide }), n);
    for (let i = 0; i < n; i++) { dummy.position.set(0, 12.2, 7 + i * 2); dummy.rotation.set(0, Math.PI / 2, 0); dummy.scale.set(1, 1, 1); dummy.updateMatrix(); bunting.setMatrixAt(i, dummy.matrix); bunting.setColorAt(i, c.set([0xd3262d, 0xffffff, 0x2e62c9, 0xf0c419][i % 4])); }
    group.add(bunting);
  }

  // ================= 看板・大時計・標識 =================
  const signTex = canvasTex(1024, 96, (c, w, h) => {
    c.fillStyle = '#103a8c'; c.fillRect(0, 0, w, h);
    c.fillStyle = '#fff'; c.font = `900 60px ${JP_FONT}`; c.textBaseline = 'middle'; c.textAlign = 'center';
    c.fillText('MINATO BOAT STADIUM　みなと競艇場', w / 2, h / 2 + 3);
  });
  const sign = new THREE.Mesh(new THREE.PlaneGeometry(96, 9), new THREE.MeshBasicMaterial({ map: signTex }));
  sign.position.set(20, 35.44, 79.7); sign.rotation.y = Math.PI; group.add(sign);

  const clock = new THREE.Group();
  clock.position.set(0, QUAY + 7.4, 61.2);
  clock.rotation.y = Math.atan2(-0.72, -0.69);
  const faceTex = canvasTex(512, 512, (c, w) => {
    const r = w / 2;
    c.fillStyle = '#fbfbf6'; c.beginPath(); c.arc(r, r, r - 4, 0, 7); c.fill();
    c.fillStyle = 'rgba(40,180,90,0.5)'; c.beginPath(); c.moveTo(r, r); c.arc(r, r, r - 30, -Math.PI / 2, -Math.PI / 2 + Math.PI / 6); c.closePath(); c.fill();
    c.strokeStyle = '#111'; c.lineWidth = 14; c.beginPath(); c.arc(r, r, r - 12, 0, 7); c.stroke();
    for (let i = 0; i < 60; i++) {
      const a = i / 60 * Math.PI * 2, big = i % 5 === 0;
      c.lineWidth = big ? 12 : 4; c.beginPath();
      c.moveTo(r + Math.sin(a) * (r - 28), r - Math.cos(a) * (r - 28));
      c.lineTo(r + Math.sin(a) * (r - (big ? 72 : 48)), r - Math.cos(a) * (r - (big ? 72 : 48))); c.stroke();
    }
    c.fillStyle = '#111'; c.font = '900 54px sans-serif'; c.textAlign = 'center'; c.textBaseline = 'middle';
    for (let i = 0; i < 12; i++) { const a = i / 12 * Math.PI * 2; c.fillText(String(i), r + Math.sin(a) * (r - 108), r - Math.cos(a) * (r - 108)); }
  });
  const face = new THREE.Mesh(new THREE.CircleGeometry(3.3, 48), new THREE.MeshLambertMaterial({ map: faceTex, emissive: 0xffffff, emissiveMap: faceTex, emissiveIntensity: 0 }));
  glow.push([face.material, 0.7]);
  clock.add(face);
  const rim = new THREE.Mesh(new THREE.CylinderGeometry(3.45, 3.45, 0.5, 40), mDark); rim.rotation.x = Math.PI / 2; rim.position.z = -0.27; clock.add(rim);
  const hand12 = new THREE.Mesh(new THREE.BoxGeometry(0.22, 3.2, 0.06).translate(0, 1.25, 0), new THREE.MeshBasicMaterial({ color: 0xf4a300 }));
  const hand60 = new THREE.Mesh(new THREE.BoxGeometry(0.14, 2.3, 0.05).translate(0, 0.95, 0), new THREE.MeshBasicMaterial({ color: 0x1a1a1a }));
  hand12.position.z = 0.1; hand60.position.z = 0.05;
  const hub = new THREE.Mesh(new THREE.CylinderGeometry(0.22, 0.22, 0.2, 12), mDark); hub.rotation.x = Math.PI / 2; hub.position.z = 0.1;
  clock.add(hand12, hand60, hub);
  group.add(clock);

  // 水面のスタートライン(ゲーム用の目印)
  const line = new THREE.Mesh(new THREE.PlaneGeometry(0.5, 53).rotateX(-Math.PI / 2), new THREE.MeshBasicMaterial({ color: 0xffffff, transparent: true, opacity: 0.4, depthWrite: false }));
  line.position.set(0, 0.03, 31.5); line.renderOrder = 4; line.userData.noShadow = true; group.add(line);
  for (const d of [50, 100, 150, 200]) {
    const t = canvasTex(128, 64, (c, w, h) => { c.fillStyle = d === 100 ? '#d3262d' : '#fff'; c.fillRect(0, 0, w, h); c.fillStyle = d === 100 ? '#fff' : '#111'; c.font = '900 50px sans-serif'; c.textAlign = 'center'; c.textBaseline = 'middle'; c.fillText(String(d), w / 2, h / 2 + 3); });
    const m = new THREE.Mesh(new THREE.PlaneGeometry(3.2, 1.6), new THREE.MeshBasicMaterial({ map: t }));
    m.position.set(-d, QUAY + 2.6, 59.2); m.rotation.y = Math.PI * 1.2; group.add(m);
  }

  // ================= ターンマーク =================
  const buoyTex = canvasTex(64, 128, (c, w, h) => { for (let i = 0; i < 6; i++) { c.fillStyle = i % 2 ? '#f6f6f2' : '#dc2530'; c.fillRect(0, i * h / 6, w, h / 6 + 1); } });
  const buoys = {};
  for (const [id, m] of [[1, M1], [2, M2]]) {
    const g = new THREE.Group();
    const mk = (geo, mat, y) => { const o = new THREE.Mesh(geo, mat); o.position.y = y; o.castShadow = true; g.add(o); return o; };
    mk(new THREE.CylinderGeometry(0.16, 0.78, 1.7, 20), new THREE.MeshStandardMaterial({ map: buoyTex, roughness: 0.45 }), 1.05);
    mk(new THREE.CylinderGeometry(0.86, 0.86, 0.34, 22), new THREE.MeshStandardMaterial({ color: 0xf2f2ee, roughness: 0.5 }), 0.1);
    mk(new THREE.SphereGeometry(0.2, 12, 8), new THREE.MeshStandardMaterial({ color: 0xdc2530, roughness: 0.4 }), 1.95);
    g.position.set(m.x, 0, m.z); group.add(g);
    buoys[id] = { g, tx: 0, tz: 0, vx: 0, vz: 0 };
  }

  // ================= 対岸: 大型映像装置・広告看板 =================
  const scr = document.createElement('canvas'); scr.width = 768; scr.height = 288;
  const scrTex = new THREE.CanvasTexture(scr); scrTex.colorSpace = THREE.SRGBColorSpace;
  const screenMat = new THREE.MeshBasicMaterial({ map: scrTex });
  const screen = new THREE.Mesh(new THREE.PlaneGeometry(42, 15.75), screenMat);
  screen.position.set(38, QUAY + 13, W.minZ - 9.38); group.add(screen);
  const ads = [
    ['海鮮 みなと丸', '#0c3c78', '#fff'], ['MINATO BREWING', '#e3b21a', '#111'], ['湾岸モータース', '#c9202b', '#fff'],
    ['しおかぜ信用金庫', '#fff', '#0b7a43'], ['SHIOKAZE MARINE', '#0f1720', '#59d0ff'], ['みなと観光ホテル', '#f3efe2', '#7a2d18'],
    ['港町やきとり 鶏八', '#2a2a2a', '#ffd23c'], ['NAMI ENERGY DRINK', '#14a36b', '#fff'],
  ].map(([txt, bg, fg]) => P(L(0xffffff, { map: canvasTex(512, 96, (c, w, h) => { c.fillStyle = bg; c.fillRect(0, 0, w, h); c.fillStyle = fg; c.font = `900 52px ${JP_FONT}`; c.textAlign = 'center'; c.textBaseline = 'middle'; c.fillText(txt, w / 2, h / 2 + 3, w - 30); }), emissive: 0xffffff, emissiveIntensity: 0 })));
  ads.forEach((m) => { m.emissiveMap = m.map; glow.push([m, 0.35]); });
  let ai = 0;
  for (let x = W.minX + 8; x < W.maxX - 4; x += 13) {
    const m = new THREE.Mesh(new THREE.PlaneGeometry(12, 2.25), ads[ai++ % ads.length]);
    m.position.set(x, QUAY + 1.3, W.minZ - 1.55); group.add(m);
  }
  for (let z = W.minZ + 10; z < W.maxZ - 6; z += 13) {
    const m = new THREE.Mesh(new THREE.PlaneGeometry(12, 2.25), ads[ai++ % ads.length]);
    m.position.set(W.maxX + 1.65, QUAY + 1.3, z); m.rotation.y = -Math.PI / 2; group.add(m);
  }

  // ================= 照明のフレア =================
  const glowTex = canvasTex(128, 128, (c, w) => { const g = c.createRadialGradient(w / 2, w / 2, 0, w / 2, w / 2, w / 2); g.addColorStop(0, 'rgba(255,250,235,1)'); g.addColorStop(0.15, 'rgba(255,244,214,0.45)'); g.addColorStop(0.5, 'rgba(255,240,200,0.08)'); g.addColorStop(1, 'rgba(255,240,200,0)'); c.fillStyle = g; c.fillRect(0, 0, w, w); });
  const mFlare = new THREE.SpriteMaterial({ map: glowTex, blending: THREE.AdditiveBlending, depthWrite: false, transparent: true, opacity: 0, fog: false });
  const towers = [[-215, W.minZ - 14, 0], [-75, W.minZ - 14, 0], [95, W.minZ - 14, 0], [215, W.minZ - 14, 0], [W.maxX + 18, -40, -Math.PI / 2], [W.maxX + 18, 25, -Math.PI / 2], [-300, -55, Math.PI / 2]];
  for (const [x, z, ry] of towers) {
    const s = new THREE.Sprite(mFlare); s.position.set(x + Math.sin(ry) * 1, QUAY + 38, z + Math.cos(ry) * 1); s.scale.set(26, 26, 1); group.add(s);
    lightPos.push(new THREE.Vector3(x, QUAY + 37, z));
  }
  for (const x of [-100, 0, 100, 180]) { const s = new THREE.Sprite(mFlare); s.position.set(x, 28.6, 71.5); s.scale.set(16, 16, 1); group.add(s); lightPos.push(new THREE.Vector3(x, 28, 72)); }

  // ================= ピットの艇番表示 =================
  for (let i = 0; i < 6; i++) {
    const t = canvasTex(64, 64, (c, w, h) => { c.fillStyle = BOAT_CSS[i]; c.fillRect(0, 0, w, h); c.fillStyle = BOAT_TEXT_CSS[i]; c.font = '900 52px sans-serif'; c.textAlign = 'center'; c.textBaseline = 'middle'; c.fillText(String(i + 1), w / 2, h / 2 + 3); });
    const m = new THREE.Mesh(new THREE.PlaneGeometry(2.2, 2.2), new THREE.MeshBasicMaterial({ map: t }));
    m.position.set(-265.88, 4.2, -12 + i * 10); m.rotation.y = Math.PI / 2; group.add(m);
  }

  // ================= 植栽 =================
  {
    const pts = [];
    for (let x = -290; x < 290; x += 7 + rnd() * 5) if (x < 12 || x > 64) pts.push([x, W.minZ - 15 - rnd() * 3, 0.8 + rnd() * 0.5]);
    for (let z = -90; z < 56; z += 8 + rnd() * 5) pts.push([W.maxX + 19 + rnd() * 3, z, 0.8 + rnd() * 0.5]);
    for (let i = 0; i < 60; i++) pts.push([-430 + rnd() * 860, 126 + rnd() * 16, 0.9 + rnd() * 0.6]);
    for (let i = 0; i < 40; i++) pts.push([-430 + rnd() * 120, -90 + rnd() * 90, 0.8 + rnd() * 0.7]);
    const trees = new THREE.InstancedMesh(treeGeometry(), P(L(0xffffff, { vertexColors: true })), pts.length);
    const c = new THREE.Color();
    pts.forEach((p, i) => {
      dummy.rotation.set(0, rnd() * 6.28, 0); dummy.position.set(p[0], QUAY, p[1]); dummy.scale.set(p[2], p[2] * (0.9 + rnd() * 0.3), p[2]); dummy.updateMatrix();
      trees.setMatrixAt(i, dummy.matrix); trees.setColorAt(i, c.setHSL(0.27 + rnd() * 0.08, 0.25, 0.75 + rnd() * 0.25));
    });
    group.add(trees);
  }

  // ================= 駐車場と街並み =================
  {
    const n = 180, cars = new THREE.InstancedMesh(new THREE.BoxGeometry(4.2, 1.4, 1.8), L(0xffffff), n);
    const c = new THREE.Color(), pal = [0xf2f2f2, 0x22252b, 0xb8bcc2, 0x9a1f24, 0x1f3f8a, 0x6d7278, 0xdad6c8];
    for (let i = 0; i < n; i++) {
      const row = i % 6, col = (i / 6) | 0;
      dummy.position.set(-200 + col * 6.2 + (row % 2) * 0.4, QUAY + 0.7, 150 + row * 8); dummy.rotation.set(0, Math.PI / 2, 0); dummy.scale.set(1, 1, 1); dummy.updateMatrix();
      cars.setMatrixAt(i, dummy.matrix); cars.setColorAt(i, c.set(pal[(rnd() * pal.length) | 0]));
    }
    cars.userData.noShadow = true; group.add(cars);
  }
  const bldTex = canvasTex(128, 256, (c, w, h) => {
    c.fillStyle = '#a4a9ad'; c.fillRect(0, 0, w, h);
    for (let y = 6; y < h - 8; y += 16) { c.fillStyle = '#8f9498'; c.fillRect(0, y + 11, w, 4); for (let x = 6; x < w - 8; x += 15) { c.fillStyle = rnd() < 0.5 ? '#44586b' : '#586c80'; c.fillRect(x, y, 10, 10); } }
  }, { repeat: true });
  const bldLit = canvasTex(128, 256, (c, w, h) => {
    c.fillStyle = '#000'; c.fillRect(0, 0, w, h);
    for (let y = 6; y < h - 8; y += 16) for (let x = 6; x < w - 8; x += 15) if (rnd() < 0.42) { c.fillStyle = rnd() < 0.7 ? '#ffe2a0' : '#cfe6ff'; c.fillRect(x, y, 10, 10); }
  }, { repeat: true });
  const mBld = L(0xffffff, { map: bldTex, emissive: 0xffffff, emissiveMap: bldLit, emissiveIntensity: 0 }); glow.push([mBld, 1.1]);
  {
    const list = [];
    for (let i = 0; i < 46; i++) list.push([-430 + rnd() * 860, 215 + rnd() * 100, 14 + rnd() * 20, 12 + rnd() * 50, 14 + rnd() * 16]);       // スタンド裏の街
    for (let i = 0; i < 90; i++) list.push([-1100 + rnd() * 2200, -780 - rnd() * 260, 26 + rnd() * 40, 30 + rnd() * rnd() * 190, 26 + rnd() * 30]); // 湾の対岸
    for (let i = 0; i < 30; i++) list.push([520 + rnd() * 500, -200 + rnd() * 600, 24 + rnd() * 30, 20 + rnd() * 70, 24 + rnd() * 30]);       // 東側
    const im = new THREE.InstancedMesh(new THREE.BoxGeometry(1, 1, 1).translate(0, 0.5, 0), mBld, list.length);
    const c = new THREE.Color();
    list.forEach((p, i) => { dummy.position.set(p[0], 1, p[1]); dummy.rotation.set(0, 0, 0); dummy.scale.set(p[2], p[3], p[4]); dummy.updateMatrix(); im.setMatrixAt(i, dummy.matrix); im.setColorAt(i, c.setHSL(0.58, 0.06, 0.62 + rnd() * 0.3)); });
    im.userData.noShadow = true; group.add(im);
  }

  // ================= 大橋のケーブルと灯り =================
  {
    const cablePts = [];
    for (const tx of [-240, 240]) for (let k = 1; k <= 10; k++) for (const s of [-1, 1]) for (const dz of [-7, 7]) cablePts.push(tx, 150 - k * 3.2, -520 + dz * 0.5, tx + s * k * 22, 48, -520 + dz);
    const cg = new THREE.BufferGeometry(); cg.setAttribute('position', new THREE.Float32BufferAttribute(cablePts, 3));
    group.add(new THREE.LineSegments(cg, new THREE.LineBasicMaterial({ color: 0xd8dde2 })));
    const mBeacon = new THREE.MeshBasicMaterial({ color: 0xff3b30 });
    for (const tx of [-240, 240]) { const b = new THREE.Mesh(new THREE.SphereGeometry(2, 6, 5), mBeacon); b.position.set(tx, 158, -520); b.userData.noShadow = true; group.add(b); }
    const mBridgeLamp = L(0x333333, { emissive: 0xffd9a0, emissiveIntensity: 0 }); glow.push([mBridgeLamp, 3]);
    const lamp = new THREE.Mesh(new THREE.BoxGeometry(1900, 0.5, 0.5), mBridgeLamp); lamp.position.set(0, 49.2, -511.4); lamp.userData.noShadow = true; group.add(lamp);
  }

  // ================= 遠景の山並み =================
  {
    const N = 160, pos = [], idx = [];
    const hgt = (a, k) => 90 + 150 * (0.5 + 0.5 * Math.sin(a * 3.0 + k)) * (0.6 + 0.4 * Math.sin(a * 7.3 + k * 2.1)) + 60 * Math.sin(a * 17.0 + k) + 25 * Math.sin(a * 41.0 + k * 3.0);
    for (const [r, k, s] of [[2150, 0.0, 1.25], [1750, 2.4, 0.8]]) {
      const base = pos.length / 3;
      for (let i = 0; i <= N; i++) {
        const a = i / N * Math.PI * 2, open = Math.sin(a) > 0.86 ? 0.15 : 1;       // 湾の奥は海が開ける
        const cx = Math.cos(a), cz = -Math.sin(a);
        pos.push(cx * r, -4, cz * r - 200, cx * (r + 260), Math.max(6, hgt(a, k) * s * open), cz * (r + 260) - 200);
      }
      for (let i = 0; i < N; i++) { const o = base + i * 2; idx.push(o, o + 1, o + 2, o + 1, o + 3, o + 2); }
    }
    const g = new THREE.BufferGeometry(); g.setAttribute('position', new THREE.Float32BufferAttribute(pos, 3)); g.setIndex(idx); g.computeVertexNormals();
    const m = new THREE.Mesh(g, L(0x4a6a58, { side: THREE.DoubleSide })); m.userData.noShadow = true; group.add(m);
  }

  // ================= カモメ =================
  const birds = [];
  {
    const wingG = new THREE.BufferGeometry();
    wingG.setAttribute('position', new THREE.Float32BufferAttribute([0, 0, 0, 0.5, 0, 1.3, -0.4, 0, 0.2], 3));
    wingG.computeVertexNormals();
    const mBird = new THREE.MeshBasicMaterial({ color: 0xf4f4f4, side: THREE.DoubleSide });
    for (let i = 0; i < 9; i++) {
      const g = new THREE.Group(), l = new THREE.Mesh(wingG, mBird), r = new THREE.Mesh(wingG, mBird);
      r.scale.z = -1; g.add(l, r); g.userData.noShadow = true; group.add(g);
      birds.push({ g, l, r, cx: -200 + rnd() * 400, cz: -60 + rnd() * 100, rad: 25 + rnd() * 50, h: 14 + rnd() * 22, sp: (0.12 + rnd() * 0.15) * (rnd() < 0.5 ? 1 : -1), ph: rnd() * 6 });
    }
  }

  // ---- 大型映像装置の描画 ----
  const sc = scr.getContext('2d');
  function drawScreen(race, title, names) {
    const w = scr.width, h = scr.height;
    sc.fillStyle = '#06101f'; sc.fillRect(0, 0, w, h);
    sc.fillStyle = '#0d2a55'; sc.fillRect(0, 0, w, 54);
    sc.fillStyle = '#fff'; sc.font = `900 32px ${JP_FONT}`; sc.textBaseline = 'middle'; sc.textAlign = 'left';
    sc.fillText(title, 16, 28);
    sc.textAlign = 'right'; sc.fillStyle = '#ffd23c';
    const lead = race.order[0];
    const lapTxt = race.state === 'pre' ? 'まもなく発走' : race.state === 'done' ? '確定' : `${Math.min(3, lead.lap + 1)}周目 / 3`;
    sc.fillText(lapTxt, w - 16, 28);
    for (let k = 0; k < 6; k++) {
      const b = race.order[k], col = k < 3 ? 0 : 1, row = k % 3;
      const x = 16 + col * 376, y = 68 + row * 72;
      sc.fillStyle = '#12213a'; sc.fillRect(x, y, 360, 62);
      sc.fillStyle = '#fff'; sc.font = `900 38px ${JP_FONT}`; sc.textAlign = 'left';
      sc.fillText(`${k + 1}`, x + 10, y + 33);
      sc.fillStyle = BOAT_CSS[b.i]; sc.fillRect(x + 44, y + 8, 50, 46);
      sc.strokeStyle = '#fff'; sc.lineWidth = 2; sc.strokeRect(x + 44, y + 8, 50, 46);
      sc.fillStyle = BOAT_TEXT_CSS[b.i]; sc.textAlign = 'center'; sc.fillText(String(b.num), x + 69, y + 33);
      sc.fillStyle = '#fff'; sc.textAlign = 'left'; sc.font = `700 30px ${JP_FONT}`;
      sc.fillText(names ? names[b.i] : '', x + 106, y + 33, 180);
      if (b.st !== null) { sc.font = `700 22px ${JP_FONT}`; sc.fillStyle = b.flying ? '#ff5a4d' : '#9fd0ff'; sc.textAlign = 'right'; sc.fillText(b.flying ? 'F' : b.st.toFixed(2), x + 352, y + 35); }
    }
    scrTex.needsUpdate = true;
  }

  let screenT = 0, env = null;
  return {
    group, buoys, lightPos, drawScreen,
    setCrowd(f) { for (const m of crowdMeshes) m.count = Math.floor(crowdTotal * f); },
    setEnv(e, wind) {
      env = e;
      for (const [m, k] of glow) m.emissiveIntensity = e.glow * k;
      mFlare.opacity = e.glow * 0.8;
      line.material.opacity = e.night > 0.5 ? 0.3 : 0.4;
      screenMat.color.setScalar(e.night > 0.5 ? 1.0 : e.night > 0.1 ? 0.9 : 0.8);
      if (wind) noboriMat.userData.u.uWindS.value = wind.speed;
    },
    // 会場の影を描き直す(環境や画質を変えた時)
    bakeShadow(renderer, sunDir, size) { stat.render(renderer, group, sunDir, size); },
    hitBuoy(id, nx, nz, power) { const b = buoys[id]; if (b) { b.vx -= nx * power * 0.5; b.vz -= nz * power * 0.5; } },
    update(dt, time, race, title, cheer, names) {
      // 大時計: 黄色い針は12秒で1周し、0秒で真上を指す
      const t = race.clock;
      hand12.rotation.z = -(t / 12) * Math.PI * 2;
      hand60.rotation.z = -(t / 60) * Math.PI * 2;
      hand12.visible = t < 1.5;
      for (const id in buoys) {
        const b = buoys[id];
        b.vx += (-b.tx * 30 - b.vx * 2.2) * dt; b.vz += (-b.tz * 30 - b.vz * 2.2) * dt;
        b.tx += b.vx * dt; b.tz += b.vz * dt;
        b.g.rotation.set(b.tz * 0.5 + Math.sin(time * 1.3 + +id) * 0.04, 0, -b.tx * 0.5 + Math.cos(time * 1.1 + +id) * 0.04);
        b.g.position.y = Math.sin(time * 1.6 + +id * 2) * 0.05;
      }
      cu.uT.value = time; noboriMat.userData.u.uT.value = time;
      cu.uCheer.value += (cheer - cu.uCheer.value) * Math.min(1, dt * 2);
      for (const b of birds) {
        const a = time * b.sp + b.ph;
        b.g.position.set(b.cx + Math.cos(a) * b.rad, b.h + Math.sin(time * 0.5 + b.ph) * 2, b.cz + Math.sin(a) * b.rad);
        b.g.rotation.y = -a - (b.sp > 0 ? Math.PI / 2 : -Math.PI / 2) + Math.PI / 2;
        const f = Math.sin(time * 6 + b.ph) * 0.55;
        b.l.rotation.x = f; b.r.rotation.x = -f;
      }
      screenT -= dt;
      if (screenT <= 0) { screenT = 0.4; drawScreen(race, title, names); }
    },
  };
}
