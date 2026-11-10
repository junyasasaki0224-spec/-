// レース場と周辺の景観。実在の競艇場に共通する設備(大時計・ターンマーク・消波装置・
// 対岸の大型映像装置・ピット・スタンド・ナイター照明など)を架空の「みなと競艇場」として構成する。
import * as THREE from 'three';
import { Batch, canvasTex, JP_FONT, BOAT_COLORS, BOAT_CSS, BOAT_TEXT_CSS, RACERS } from './common.js';
import { M1, M2, BOUNDS, POLE } from '../sim/course.js';

const QUAY = 1.6;          // 岸壁の高さ
const L = (color, o = {}) => new THREE.MeshLambertMaterial({ color, ...o });
const rnd = (() => { let s = 12345; return () => { s = (s * 1664525 + 1013904223) | 0; return ((s >>> 8) & 0xffff) / 65536; }; })();

export function createVenue(scene) {
  const group = new THREE.Group();
  scene.add(group);
  const B = new Batch();
  const glow = [];            // 夜に光らせるマテリアル [mat, 強さ]
  const lightPos = [];        // 水面に映り込む照明の位置
  const dummy = new THREE.Object3D();

  const mConc = L(0xb8b6ad), mConcD = L(0x8e8d86), mAsph = L(0x5c6064), mGrass = L(0x5c8a4c);
  const mSteel = L(0x8d949c), mWhite = L(0xf1f1ee), mDark = L(0x2a2d33), mRed = L(0xd3262d), mBlue = L(0x2e62c9);
  const mYellow = L(0xf0c419), mRoof = L(0xdfe3e6), mOrange = L(0xf07a1a);

  // ================= 陸地 =================
  const W = BOUNDS;
  B.box(880, 4.6, 14, mConc, 0, QUAY - 2.3, W.maxZ + 0.8 + 7);                 // スタンド前の護岸
  B.box(880, 4.6, 260, mAsph, 0, QUAY - 2.35, W.maxZ + 14.8 + 130);            // スタンド側の敷地
  B.box(600, 4.6, 18, mConc, 0, QUAY - 2.3, W.minZ - 0.8 - 9);                 // 対岸の堤
  B.box(590, 0.3, 8, mGrass, 0, QUAY + 0.05, W.minZ - 13);
  B.box(150, 4.6, 156, mConc, -366, QUAY - 2.3, -19);                          // ピット側
  B.box(24, 4.6, 156, mConc, W.maxX + 0.8 + 12, QUAY - 2.3, -19);              // 1マーク奥の堤
  B.box(10, 0.3, 150, mGrass, W.maxX + 16, QUAY + 0.05, -19);
  B.box(150, 0.25, 110, mGrass, -366, QUAY + 0.03, -45);

  // ================= 消波装置 =================
  {
    const pts = [];
    for (let x = W.minX + 3; x < W.maxX; x += 6.4) { pts.push([x, W.maxZ + 0.1, 0]); pts.push([x, W.minZ - 0.1, 0]); }
    for (let z = W.minZ + 3; z < W.maxZ; z += 6.4) { pts.push([W.minX - 0.1, z, 1]); pts.push([W.maxX + 0.1, z, 1]); }
    const im = new THREE.InstancedMesh(new THREE.BoxGeometry(6, 0.85, 1.1), L(0xffffff), pts.length);
    const c = new THREE.Color();
    pts.forEach((p, i) => {
      dummy.position.set(p[0], 0.2, p[1]); dummy.rotation.set(0, p[2] ? Math.PI / 2 : 0, 0); dummy.scale.set(1, 1, 1); dummy.updateMatrix();
      im.setMatrixAt(i, dummy.matrix);
      im.setColorAt(i, c.set(i % 7 === 3 ? 0xe9c531 : i % 2 ? 0xb7c4cc : 0x9aa9b3));
    });
    group.add(im);
  }

  // ================= スタンド =================
  const SX = 20, SL = 340;      // 中心 x と長さ
  for (let i = 0; i < 12; i++) {
    const h = 0.62 * (i + 1);
    B.box(SL, h, 1.5, mConc, SX, QUAY + h / 2, 72 + 1.5 * i + 0.75);
    B.box(SL - 4, 0.1, 0.8, i % 4 < 2 ? mBlue : mOrange, SX, QUAY + h + 0.05, 72 + 1.5 * i + 1.0);
  }
  for (let x = SX - SL / 2; x <= SX + SL / 2; x += 34) B.box(1.4, 8, 18, mConcD, x, QUAY + 4, 81);   // 通路の仕切り
  B.box(SL, 8, 26, mConcD, SX, QUAY + 4, 103);                                   // コンコース階
  B.box(SL, 18.5, 32, mConc, SX, QUAY + 8 + 9.25, 100.2);                        // 上層階
  B.box(SL + 6, 1.1, 46, mRoof, SX, QUAY + 27.2, 96);                            // 大屋根
  B.box(SL + 6, 2.2, 0.6, mBlue, SX, QUAY + 26.6, 73.2);
  for (let x = SX - SL / 2 + 10; x < SX + SL / 2; x += 20) B.box(0.5, 1.6, 44, mSteel, x, QUAY + 28.4, 96);
  // ガラス張りの観覧席
  const winTex = canvasTex(256, 256, (c, w, h) => {
    c.fillStyle = '#5d7f9c'; c.fillRect(0, 0, w, h);
    const g = c.createLinearGradient(0, 0, 0, h); g.addColorStop(0, 'rgba(210,235,255,0.55)'); g.addColorStop(1, 'rgba(40,70,100,0.35)');
    c.fillStyle = g; c.fillRect(0, 0, w, h);
    c.fillStyle = '#d9dde0';
    for (let i = 0; i <= 4; i++) c.fillRect(i * 64 - 3, 0, 6, h);
    c.fillRect(0, 0, w, 14); c.fillRect(0, h - 26, w, 26);
  }, { repeat: true });
  const litTex = canvasTex(256, 256, (c, w, h) => {
    c.fillStyle = '#000'; c.fillRect(0, 0, w, h);
    for (let i = 0; i < 4; i++) { c.fillStyle = `rgba(255,${215 + (i * 13) % 30},${150 + (i * 37) % 60},${0.75 + 0.25 * ((i * 7) % 3) / 2})`; c.fillRect(i * 64 + 4, 16, 56, h - 44); }
  }, { repeat: true });
  winTex.repeat.set(21, 4); litTex.repeat.set(21, 4);
  const mGlass = L(0xffffff, { map: winTex, emissive: 0xffffff, emissiveMap: litTex, emissiveIntensity: 0 });
  glow.push([mGlass, 1.0]);
  const facade = new THREE.Mesh(new THREE.PlaneGeometry(SL - 2, 17.5), mGlass);
  facade.position.set(SX, QUAY + 8 + 9.25, 84.15); facade.rotation.y = Math.PI; group.add(facade);
  // 屋上の看板
  const signTex = canvasTex(1024, 96, (c, w, h) => {
    c.fillStyle = '#103a8c'; c.fillRect(0, 0, w, h);
    c.fillStyle = '#fff'; c.font = `900 60px ${JP_FONT}`; c.textBaseline = 'middle'; c.textAlign = 'center';
    c.fillText('MINATO BOAT STADIUM　みなと競艇場', w / 2, h / 2 + 3);
  });
  const mSign = new THREE.MeshBasicMaterial({ map: signTex });
  const sign = new THREE.Mesh(new THREE.PlaneGeometry(96, 9), mSign);
  sign.position.set(SX, QUAY + 33, 76); sign.rotation.y = Math.PI; group.add(sign);
  B.box(97, 9.6, 0.5, mDark, SX, QUAY + 33, 76.4);
  for (let x = SX - 44; x <= SX + 44; x += 22) B.box(0.5, 6, 0.5, mSteel, x, QUAY + 30, 77);
  // 屋根先端の照明
  const mLamp = L(0xe8e8e0, { emissive: 0xfff4d8, emissiveIntensity: 0 });
  glow.push([mLamp, 2.2]);
  for (let x = SX - SL / 2 + 8; x < SX + SL / 2; x += 8) B.box(3, 0.7, 0.8, mLamp, x, QUAY + 26.2, 73.6, 0, 0.5);
  for (const x of [-100, 0, 100, 180]) lightPos.push(new THREE.Vector3(x, QUAY + 26, 74));

  // ---- 観客 ----
  {
    const spots = [];
    for (let i = 0; i < 12; i++) for (let x = SX - SL / 2 + 3; x < SX + SL / 2 - 3; x += 0.8) {
      if ((x - (SX - SL / 2)) % 34 < 2.4) continue;
      if (rnd() < 0.5) spots.push([x + rnd() * 0.2, QUAY + 0.62 * (i + 1) + 0.42, 72 + 1.5 * i + 0.75, 0.85]);
    }
    for (let x = -240; x < 240; x += 1.1) if (rnd() < (Math.abs(x) < 120 ? 0.75 : 0.3)) spots.push([x, QUAY + 0.75, 61.2 + rnd() * 2.2, 1.6]);
    const mBody = L(0xffffff), mHead = L(0xe2b594);
    const cu = { uT: { value: 0 }, uCheer: { value: 0 } };
    const patch = (m) => {
      m.onBeforeCompile = (sh) => {
        sh.uniforms.uT = cu.uT; sh.uniforms.uCheer = cu.uCheer;
        sh.vertexShader = 'uniform float uT; uniform float uCheer;\n' + sh.vertexShader.replace('#include <begin_vertex>',
          '#include <begin_vertex>\n float ph = instanceMatrix[3].x * 3.1 + instanceMatrix[3].z * 1.7; transformed.y += uCheer * max(0.0, sin(uT * 9.0 + ph)) * 0.45;');
      };
    };
    patch(mBody); patch(mHead);
    const bodies = new THREE.InstancedMesh(new THREE.BoxGeometry(0.44, 0.75, 0.3), mBody, spots.length);
    const heads = new THREE.InstancedMesh(new THREE.SphereGeometry(0.15, 6, 5), mHead, spots.length);
    const c = new THREE.Color();
    const pal = [0xe8e8e8, 0x2b3a67, 0xc0392b, 0x1e824c, 0xf2c94c, 0x555b66, 0x8e6bbf, 0x3d8fd1, 0xe98b39, 0x222222, 0xf4f0e6, 0x7d8a96];
    spots.forEach((p, i) => {
      dummy.rotation.set(0, 0, 0); dummy.scale.set(1, p[3], 1);
      dummy.position.set(p[0], p[1] + (p[3] - 0.85) * 0.2, p[2]); dummy.updateMatrix(); bodies.setMatrixAt(i, dummy.matrix);
      dummy.scale.set(1, 1, 1); dummy.position.set(p[0], p[1] + 0.52 * p[3] + (p[3] - 0.85) * 0.2, p[2]); dummy.updateMatrix(); heads.setMatrixAt(i, dummy.matrix);
      bodies.setColorAt(i, c.set(pal[(rnd() * pal.length) | 0]));
    });
    group.add(bodies, heads);
    group.userData.crowd = cu;
  }

  // ---- 水際の柵とのぼり旗 ----
  B.box(514, 0.08, 0.08, mWhite, -5, QUAY + 1.1, 59.6).box(514, 0.08, 0.08, mWhite, -5, QUAY + 0.6, 59.6);
  for (let x = -262; x <= 252; x += 4) B.box(0.1, 1.1, 0.1, mWhite, x, QUAY + 0.55, 59.6);
  {
    const xs = []; for (let x = -246; x <= 240; x += 9) if (Math.abs(x) > 14) xs.push(x);
    const im = new THREE.InstancedMesh(new THREE.PlaneGeometry(0.7, 2.6), L(0xffffff, { side: THREE.DoubleSide }), xs.length);
    const c = new THREE.Color();
    xs.forEach((x, i) => {
      B.cyl(0.035, 0.035, 4, mSteel, x, QUAY + 2, 66, 5);
      dummy.position.set(x + 0.4, QUAY + 2.6, 66); dummy.rotation.set(0, 0, 0); dummy.scale.set(1, 1, 1); dummy.updateMatrix();
      im.setMatrixAt(i, dummy.matrix); im.setColorAt(i, c.set(BOAT_COLORS[i % 6] === 0x16161a ? 0x7a2fb0 : BOAT_COLORS[i % 6]));
    });
    group.add(im);
  }

  // ================= 審判塔・大時計・スタートライン =================
  B.box(5, 13, 5, mConc, 10, QUAY + 6.5, 66);
  B.box(9, 0.5, 9, mRoof, 10, QUAY + 13.2, 66).box(9.5, 0.5, 9.5, mRoof, 10, QUAY + 17.6, 66);
  const cabTex = canvasTex(128, 64, (c, w, h) => { c.fillStyle = '#35556e'; c.fillRect(0, 0, w, h); c.fillStyle = '#dfe3e6'; for (let i = 0; i <= 4; i++) c.fillRect(i * 32 - 2, 0, 4, h); c.fillRect(0, 0, w, 5); c.fillRect(0, h - 8, w, 8); });
  const mCab = L(0xffffff, { map: cabTex, emissive: 0xffe9b8, emissiveIntensity: 0 }); glow.push([mCab, 0.5]);
  B.box(8, 4, 8, mCab, 10, QUAY + 15.5, 66);
  B.cyl(0.08, 0.08, 6, mSteel, 10, QUAY + 20.8, 66, 5);

  // 大時計
  const clock = new THREE.Group();
  clock.position.set(0, QUAY + 7.4, 61.2);
  clock.rotation.y = Math.atan2(-0.72, -0.69);
  const faceTex = canvasTex(512, 512, (c, w) => {
    const r = w / 2;
    c.fillStyle = '#fbfbf6'; c.beginPath(); c.arc(r, r, r - 4, 0, 7); c.fill();
    // 0〜1秒のスタート有効ゾーン
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
  B.box(0.9, 6, 0.9, mSteel, 0.6, QUAY + 2.2, 62.2);
  // センターポールと空中線
  B.cyl(1.0, 1.0, 0.5, mWhite, POLE.x, 0.2, POLE.z, 14);
  B.cyl(0.14, 0.2, 13, mWhite, POLE.x, 6.8, POLE.z, 8);
  for (let i = 0; i < 3; i++) B.cyl(0.24, 0.24, 0.8, i % 2 ? mYellow : mRed, POLE.x, 2.2 + i * 1.6, POLE.z, 8);
  B.cyl(0.35, 0.35, 0.35, mRed, POLE.x, 13.5, POLE.z, 8);
  B.box(0.06, 0.06, 57, mDark, 0, 12.6, 32.5);
  {
    const n = 26, im = new THREE.InstancedMesh(new THREE.PlaneGeometry(0.5, 0.7), L(0xffffff, { side: THREE.DoubleSide }), n);
    const c = new THREE.Color();
    for (let i = 0; i < n; i++) { dummy.position.set(0, 12.2, 7 + i * 2); dummy.rotation.set(0, Math.PI / 2, 0); dummy.scale.set(1, 1, 1); dummy.updateMatrix(); im.setMatrixAt(i, dummy.matrix); im.setColorAt(i, c.set([0xd3262d, 0xffffff, 0x2e62c9, 0xf0c419][i % 4])); }
    group.add(im);
  }
  // 水面のスタートライン(ゲーム用の目印)
  const line = new THREE.Mesh(new THREE.PlaneGeometry(0.5, 53).rotateX(-Math.PI / 2), new THREE.MeshBasicMaterial({ color: 0xffffff, transparent: true, opacity: 0.4, depthWrite: false }));
  line.position.set(0, 0.03, 31.5); line.renderOrder = 4; group.add(line);
  // 距離標識
  for (const d of [50, 100, 150, 200]) {
    const t = canvasTex(128, 64, (c, w, h) => { c.fillStyle = d === 100 ? '#d3262d' : '#fff'; c.fillRect(0, 0, w, h); c.fillStyle = d === 100 ? '#fff' : '#111'; c.font = '900 50px sans-serif'; c.textAlign = 'center'; c.textBaseline = 'middle'; c.fillText(String(d), w / 2, h / 2 + 3); });
    const m = new THREE.Mesh(new THREE.PlaneGeometry(3.2, 1.6), new THREE.MeshBasicMaterial({ map: t }));
    m.position.set(-d, QUAY + 2.6, 59.2); m.rotation.y = Math.PI * 1.2; group.add(m);
    B.box(0.15, 2, 0.15, mSteel, -d, QUAY + 1, 59.4);
  }

  // ================= ターンマーク =================
  const buoyTex = canvasTex(64, 128, (c, w, h) => { for (let i = 0; i < 6; i++) { c.fillStyle = i % 2 ? '#f6f6f2' : '#dc2530'; c.fillRect(0, i * h / 6, w, h / 6 + 1); } });
  const buoys = {};
  for (const [id, m] of [[1, M1], [2, M2]]) {
    const g = new THREE.Group();
    const cone = new THREE.Mesh(new THREE.CylinderGeometry(0.16, 0.78, 1.7, 16), L(0xffffff, { map: buoyTex }));
    cone.position.y = 1.05; g.add(cone);
    const base = new THREE.Mesh(new THREE.CylinderGeometry(0.86, 0.86, 0.34, 18), L(0xf2f2ee)); base.position.y = 0.1; g.add(base);
    const cap = new THREE.Mesh(new THREE.SphereGeometry(0.2, 10, 8), L(0xdc2530)); cap.position.y = 1.95; g.add(cap);
    g.position.set(m.x, 0, m.z); group.add(g);
    buoys[id] = { g, tx: 0, tz: 0, vx: 0, vz: 0 };
  }

  // ================= 対岸: 大型映像装置・広告看板 =================
  const scr = document.createElement('canvas'); scr.width = 768; scr.height = 288;
  const scrTex = new THREE.CanvasTexture(scr); scrTex.colorSpace = THREE.SRGBColorSpace;
  const screen = new THREE.Mesh(new THREE.PlaneGeometry(42, 15.75), new THREE.MeshBasicMaterial({ map: scrTex }));
  screen.position.set(38, QUAY + 13, W.minZ - 9.4); group.add(screen);
  B.box(44, 17.5, 1.6, mDark, 38, QUAY + 13, W.minZ - 10.3);
  B.box(1.2, 6, 1.2, mSteel, 24, QUAY + 2.6, W.minZ - 10.3).box(1.2, 6, 1.2, mSteel, 52, QUAY + 2.6, W.minZ - 10.3);
  const ads = [
    ['海鮮 みなと丸', '#0c3c78', '#fff'], ['MINATO BREWING', '#e3b21a', '#111'], ['湾岸モータース', '#c9202b', '#fff'],
    ['しおかぜ信用金庫', '#fff', '#0b7a43'], ['SHIOKAZE MARINE', '#0f1720', '#59d0ff'], ['みなと観光ホテル', '#f3efe2', '#7a2d18'],
    ['港町やきとり 鶏八', '#2a2a2a', '#ffd23c'], ['NAMI ENERGY DRINK', '#14a36b', '#fff'],
  ].map(([txt, bg, fg]) => new THREE.MeshBasicMaterial({ map: canvasTex(512, 96, (c, w, h) => { c.fillStyle = bg; c.fillRect(0, 0, w, h); c.fillStyle = fg; c.font = `900 52px ${JP_FONT}`; c.textAlign = 'center'; c.textBaseline = 'middle'; c.fillText(txt, w / 2, h / 2 + 3, w - 30); }) }));
  let ai = 0;
  for (let x = W.minX + 8; x < W.maxX - 4; x += 13) {
    const m = new THREE.Mesh(new THREE.PlaneGeometry(12, 2.25), ads[ai++ % ads.length]);
    m.position.set(x, QUAY + 1.3, W.minZ - 1.5); group.add(m);
    B.box(12.2, 2.4, 0.2, mDark, x, QUAY + 1.3, W.minZ - 1.65);
  }
  for (let z = W.minZ + 10; z < W.maxZ - 6; z += 13) {
    const m = new THREE.Mesh(new THREE.PlaneGeometry(12, 2.25), ads[ai++ % ads.length]);
    m.position.set(W.maxX + 1.6, QUAY + 1.3, z); m.rotation.y = -Math.PI / 2; group.add(m);
    B.box(0.2, 2.4, 12.2, mDark, W.maxX + 1.75, QUAY + 1.3, z);
  }

  // ================= ナイター照明塔 =================
  const lampTex = canvasTex(128, 64, (c, w, h) => { c.fillStyle = '#3a3f46'; c.fillRect(0, 0, w, h); for (let j = 0; j < 4; j++) for (let i = 0; i < 8; i++) { c.fillStyle = '#e9ecef'; c.beginPath(); c.arc(8 + i * 16, 8 + j * 16, 6, 0, 7); c.fill(); } });
  const mPanel = L(0xffffff, { map: lampTex, emissive: 0xfff6e0, emissiveMap: lampTex, emissiveIntensity: 0 }); glow.push([mPanel, 3]);
  const glowTex = canvasTex(128, 128, (c, w) => { const g = c.createRadialGradient(w / 2, w / 2, 0, w / 2, w / 2, w / 2); g.addColorStop(0, 'rgba(255,250,235,1)'); g.addColorStop(0.2, 'rgba(255,244,214,0.55)'); g.addColorStop(1, 'rgba(255,240,200,0)'); c.fillStyle = g; c.fillRect(0, 0, w, w); });
  const mFlare = new THREE.SpriteMaterial({ map: glowTex, blending: THREE.AdditiveBlending, depthWrite: false, transparent: true, opacity: 0, fog: false });
  const flares = [];
  const tower = (x, z, ry) => {
    B.cyl(0.45, 0.7, 36, mSteel, x, QUAY + 18, z, 8);
    B.box(10, 5.5, 0.7, mPanel, x, QUAY + 37.5, z, ry, 0.35);
    B.box(10.6, 6.1, 0.4, mDark, x - Math.sin(ry) * 0.4, QUAY + 37.6, z - Math.cos(ry) * 0.4, ry, 0.35);
    const s = new THREE.Sprite(mFlare); s.position.set(x + Math.sin(ry) * 1, QUAY + 37.5, z + Math.cos(ry) * 1); s.scale.set(34, 34, 1); group.add(s); flares.push(s);
    lightPos.push(new THREE.Vector3(x, QUAY + 37, z));
  };
  for (const x of [-215, -75, 95, 215]) tower(x, W.minZ - 14, 0);
  tower(W.maxX + 18, -40, -Math.PI / 2); tower(W.maxX + 18, 25, -Math.PI / 2); tower(-300, -55, Math.PI / 2);
  for (const x of [-100, 0, 100, 180]) { const s = new THREE.Sprite(mFlare); s.position.set(x, QUAY + 26.5, 73); s.scale.set(22, 22, 1); group.add(s); flares.push(s); }

  // ================= ピット =================
  B.box(27, 0.8, 66, mConcD, -277.5, 0.15, 12);                       // 浮き桟橋
  B.box(26, 0.35, 60, mRoof, -279, 5.6, 13);                          // 屋根
  for (let i = 0; i <= 6; i++) { B.box(0.3, 5.2, 0.3, mSteel, -267, 3, -17 + i * 10).box(0.3, 5.2, 0.3, mSteel, -290, 3, -17 + i * 10); }
  for (let i = 0; i < 6; i++) {
    const t = canvasTex(64, 64, (c, w, h) => { c.fillStyle = BOAT_CSS[i]; c.fillRect(0, 0, w, h); c.fillStyle = BOAT_TEXT_CSS[i]; c.font = '900 52px sans-serif'; c.textAlign = 'center'; c.textBaseline = 'middle'; c.fillText(String(i + 1), w / 2, h / 2 + 3); });
    const m = new THREE.Mesh(new THREE.PlaneGeometry(2.2, 2.2), new THREE.MeshBasicMaterial({ map: t }));
    m.position.set(-265.9, 4.2, -12 + i * 10); m.rotation.y = Math.PI / 2; group.add(m);
    B.box(0.25, 0.5, 9, mWhite, -272, 0.7, -17 + i * 10);             // 係留の仕切り
  }
  B.box(40, 10, 84, mConc, -316, QUAY + 5, 10);                       // 競技棟
  const pitWin = canvasTex(256, 128, (c, w, h) => { c.fillStyle = '#c9c7bd'; c.fillRect(0, 0, w, h); c.fillStyle = '#3e5a72'; for (let j = 0; j < 2; j++) for (let i = 0; i < 6; i++) c.fillRect(8 + i * 42, 14 + j * 60, 32, 30); }, { repeat: true });
  pitWin.repeat.set(6, 1);
  const pw = new THREE.Mesh(new THREE.PlaneGeometry(84, 10), L(0xffffff, { map: pitWin })); pw.position.set(-295.9, QUAY + 5, 10); pw.rotation.y = Math.PI / 2; group.add(pw);
  B.box(41, 0.6, 85, mRoof, -316, QUAY + 10.3, 10);
  // 救助艇
  for (const [x, z, ry] of [[205, -66, 0.2], [-236, -68, 2.9]]) {
    B.box(5.2, 0.9, 2.1, mOrange, x, 0.35, z, ry).box(1.8, 1.1, 1.6, mWhite, x - Math.cos(ry) * 0.6, 1.3, z + Math.sin(ry) * 0.6, ry).cyl(0.04, 0.04, 1.6, mSteel, x, 2.4, z, 5);
  }

  // ================= 植栽 =================
  {
    const pts = [];
    for (let x = -290; x < 290; x += 7 + rnd() * 5) if (x < 14 || x > 62) pts.push([x, W.minZ - 15 - rnd() * 2, 0.8 + rnd() * 0.6]);
    for (let z = -90; z < 56; z += 8 + rnd() * 5) pts.push([W.maxX + 19 + rnd() * 2, z, 0.8 + rnd() * 0.5]);
    for (let i = 0; i < 70; i++) pts.push([-430 + rnd() * 860, 122 + rnd() * 18, 0.9 + rnd() * 0.7]);
    for (let i = 0; i < 40; i++) pts.push([-430 + rnd() * 130, -90 + rnd() * 90, 0.8 + rnd() * 0.8]);
    const fol = new THREE.InstancedMesh(new THREE.IcosahedronGeometry(2.4, 1), L(0x3f7a3a), pts.length);
    const trunk = new THREE.InstancedMesh(new THREE.CylinderGeometry(0.22, 0.3, 3, 6), L(0x6b4a2e), pts.length);
    const c = new THREE.Color();
    pts.forEach((p, i) => {
      dummy.rotation.set(0, rnd() * 6, 0);
      dummy.position.set(p[0], QUAY + 3.6 * p[2], p[1]); dummy.scale.set(p[2], p[2] * 1.15, p[2]); dummy.updateMatrix(); fol.setMatrixAt(i, dummy.matrix);
      fol.setColorAt(i, c.setHSL(0.3 + rnd() * 0.05, 0.4, 0.26 + rnd() * 0.1));
      dummy.position.set(p[0], QUAY + 1.5 * p[2], p[1]); dummy.scale.set(p[2], p[2], p[2]); dummy.updateMatrix(); trunk.setMatrixAt(i, dummy.matrix);
    });
    group.add(fol, trunk);
  }

  // ================= 駐車場と街並み =================
  {
    const n = 180, cars = new THREE.InstancedMesh(new THREE.BoxGeometry(4.2, 1.4, 1.8), L(0xffffff), n);
    const c = new THREE.Color(), pal = [0xf2f2f2, 0x22252b, 0xb8bcc2, 0x9a1f24, 0x1f3f8a, 0x6d7278, 0xdad6c8];
    for (let i = 0; i < n; i++) {
      const row = i % 6, col = (i / 6) | 0;
      dummy.position.set(-200 + col * 6.2 + (row % 2) * 0.4, QUAY + 0.7, 150 + row * 8); dummy.rotation.set(0, Math.PI / 2, 0); dummy.scale.set(1, 1, 1); dummy.updateMatrix();
      cars.setMatrixAt(i, dummy.matrix); cars.setColorAt(i, c.set(rnd() < 0.2 ? 0x55585c : pal[(rnd() * pal.length) | 0]));
    }
    group.add(cars);
  }
  const bldTex = canvasTex(128, 256, (c, w, h) => {
    c.fillStyle = '#9da3a8'; c.fillRect(0, 0, w, h);
    for (let y = 6; y < h - 8; y += 16) for (let x = 6; x < w - 8; x += 15) { c.fillStyle = rnd() < 0.5 ? '#4b5f73' : '#5f7387'; c.fillRect(x, y, 10, 10); }
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
    group.add(im);
    B.box(2400, 3, 320, mConcD, 0, 0, -910);       // 対岸の埋立地
    B.box(560, 3, 700, mConcD, 780, 0, 100);
  }

  // ================= 湾岸の大橋・港湾クレーン・煙突 =================
  const mBridge = L(0xe6e9ec), mCable = new THREE.LineBasicMaterial({ color: 0xd8dde2 });
  B.box(1900, 3, 16, mBridge, 0, 46, -520);
  for (let x = -900; x <= 900; x += 120) if (Math.abs(Math.abs(x) - 240) > 30) B.box(6, 46, 10, mConc, x, 23, -520);
  const cablePts = [];
  for (const tx of [-240, 240]) {
    for (const dz of [-9, 9]) B.box(6, 150, 5, mBridge, tx, 75, -520 + dz);
    B.box(7, 5, 22, mBridge, tx, 120, -520).box(7, 5, 22, mBridge, tx, 62, -520);
    for (let k = 1; k <= 9; k++) for (const s of [-1, 1]) for (const dz of [-8, 8]) {
      cablePts.push(tx, 148 - k * 3, -520 + dz, tx + s * k * 24, 48, -520 + dz);
    }
  }
  const cg = new THREE.BufferGeometry(); cg.setAttribute('position', new THREE.Float32BufferAttribute(cablePts, 3));
  group.add(new THREE.LineSegments(cg, mCable));
  const mBeacon = new THREE.MeshBasicMaterial({ color: 0xff3b30 });
  for (const tx of [-240, 240]) { const b = new THREE.Mesh(new THREE.SphereGeometry(2, 6, 5), mBeacon); b.position.set(tx, 152, -520); group.add(b); }
  const mBridgeLamp = L(0xd0d0d0, { emissive: 0xffd9a0, emissiveIntensity: 0 }); glow.push([mBridgeLamp, 3]);
  B.box(1900, 0.6, 0.6, mBridgeLamp, 0, 48.6, -511.5);
  // ガントリークレーン
  for (let i = 0; i < 4; i++) {
    const x = 560 + i * 70, z = -250;
    for (const dx of [-12, 12]) for (const dz of [-9, 9]) B.box(2.2, 62, 2.2, mRed, x + dx, 32, z + dz);
    B.box(28, 3, 22, mRed, x, 62, z).box(4, 3, 96, mWhite, x, 66, z - 30).box(3, 26, 3, mRed, x, 80, z + 4);
  }
  // 工場の煙突とタンク
  const chimTex = canvasTex(32, 128, (c, w, h) => { for (let i = 0; i < 8; i++) { c.fillStyle = i % 2 ? '#f1f1ee' : '#d3262d'; c.fillRect(0, i * 16, w, 16); } });
  const mChim = L(0xffffff, { map: chimTex });
  for (const [x, z, h] of [[-640, -700, 150], [-560, -730, 120], [-720, -760, 135]]) B.cyl(4, 6, h, mChim, x, h / 2, z, 12);
  for (let i = 0; i < 6; i++) B.cyl(16, 16, 20, mWhite, -520 + i * 40, 11, -780, 16);

  // ================= 遠景の山並み =================
  {
    const n = 34, im = new THREE.InstancedMesh(new THREE.ConeGeometry(1, 1, 7, 1).translate(0, 0.5, 0), L(0x566f84), n);
    for (let i = 0; i < n; i++) {
      const a = i / n * Math.PI * 2 + rnd() * 0.1, r = 1750 + rnd() * 250;
      if (Math.sin(a) > 0.92) { dummy.scale.set(0, 0, 0); }      // 湾の奥は海が開ける
      else dummy.scale.set(420 + rnd() * 380, 150 + rnd() * 260, 420 + rnd() * 380);
      dummy.position.set(Math.cos(a) * r, -5, -Math.sin(a) * r - 200); dummy.rotation.set(0, rnd() * 6, 0); dummy.updateMatrix(); im.setMatrixAt(i, dummy.matrix);
    }
    group.add(im);
  }

  B.build(group);

  // ================= カモメ =================
  const birds = [];
  {
    const wingG = new THREE.BufferGeometry();
    wingG.setAttribute('position', new THREE.Float32BufferAttribute([0, 0, 0, 0.5, 0, 1.3, -0.4, 0, 0.2], 3));
    wingG.computeVertexNormals();
    const mBird = new THREE.MeshBasicMaterial({ color: 0xf4f4f4, side: THREE.DoubleSide });
    for (let i = 0; i < 9; i++) {
      const g = new THREE.Group(), l = new THREE.Mesh(wingG, mBird), r = new THREE.Mesh(wingG, mBird);
      r.scale.z = -1; g.add(l, r); group.add(g);
      birds.push({ g, l, r, cx: -200 + rnd() * 400, cz: -60 + rnd() * 100, rad: 25 + rnd() * 50, h: 14 + rnd() * 22, sp: (0.12 + rnd() * 0.15) * (rnd() < 0.5 ? 1 : -1), ph: rnd() * 6 });
    }
  }

  // ---- 大型映像装置の描画 ----
  const sc = scr.getContext('2d');
  function drawScreen(race, title) {
    const w = scr.width, h = scr.height;
    sc.fillStyle = '#06101f'; sc.fillRect(0, 0, w, h);
    sc.fillStyle = '#0d2a55'; sc.fillRect(0, 0, w, 54);
    sc.fillStyle = '#fff'; sc.font = `900 32px ${JP_FONT}`; sc.textBaseline = 'middle'; sc.textAlign = 'left';
    sc.fillText(title, 16, 28);
    sc.textAlign = 'right'; sc.fillStyle = '#ffd23c';
    const lead = race.order[0];
    const lapTxt = race.state === 'pre' ? 'スタート展示' : race.state === 'done' ? '確定' : `${Math.min(3, lead.lap + 1)}周目 / 3`;
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
      sc.fillText(RACERS[b.i], x + 106, y + 33, 180);
      if (b.st !== null) { sc.font = `700 22px ${JP_FONT}`; sc.fillStyle = b.flying ? '#ff5a4d' : '#9fd0ff'; sc.textAlign = 'right'; sc.fillText(b.flying ? 'F' : b.st.toFixed(2), x + 352, y + 35); }
    }
    scrTex.needsUpdate = true;
  }

  let screenT = 0;
  return {
    group, buoys, lightPos, drawScreen,
    setEnv(env) {
      for (const [m, k] of glow) m.emissiveIntensity = env.glow * k;
      mFlare.opacity = env.glow * 0.9;
      line.material.opacity = env.night > 0.5 ? 0.3 : 0.4;
    },
    hitBuoy(id, nx, nz, power) { const b = buoys[id]; if (b) { b.vx -= nx * power * 0.5; b.vz -= nz * power * 0.5; } },
    update(dt, time, race, title, cheer) {
      // 大時計: 黄色い針は12秒で1周し、0秒で真上を指す
      const t = race.clock;
      hand12.rotation.z = -(t / 12) * Math.PI * 2;
      hand60.rotation.z = -(t / 60) * Math.PI * 2;
      hand12.visible = t < 1.5;
      // ブイの揺れ
      for (const id in buoys) {
        const b = buoys[id];
        b.vx += (-b.tx * 30 - b.vx * 2.2) * dt; b.vz += (-b.tz * 30 - b.vz * 2.2) * dt;
        b.tx += b.vx * dt; b.tz += b.vz * dt;
        b.g.rotation.set(b.tz * 0.5 + Math.sin(time * 1.3 + +id) * 0.04, 0, -b.tx * 0.5 + Math.cos(time * 1.1 + +id) * 0.04);
        b.g.position.y = Math.sin(time * 1.6 + +id * 2) * 0.05;
      }
      group.userData.crowd.uT.value = time;
      group.userData.crowd.uCheer.value += (cheer - group.userData.crowd.uCheer.value) * Math.min(1, dt * 2);
      for (const b of birds) {
        const a = time * b.sp + b.ph;
        b.g.position.set(b.cx + Math.cos(a) * b.rad, b.h + Math.sin(time * 0.5 + b.ph) * 2, b.cz + Math.sin(a) * b.rad);
        b.g.rotation.y = -a - (b.sp > 0 ? Math.PI / 2 : -Math.PI / 2) + Math.PI / 2;
        const f = Math.sin(time * 6 + b.ph) * 0.55;
        b.l.rotation.x = f; b.r.rotation.x = -f;
      }
      screenT -= dt;
      if (screenT <= 0) { screenT = 0.4; drawScreen(race, title); }
    },
  };
}
