// 競艇ボート(ハイドロプレーン)とレーサーのモデル。ローカル座標: +x 前, +y 上, +z 右。
import * as THREE from 'three';
import { BOAT_COLORS, BOAT_CSS, BOAT_TEXT_CSS, canvasTex, JP_FONT } from './common.js';
import { VMAX } from '../sim/physics.js';
import { clamp } from '../sim/course.js';

function hullShape(scale = 1) {
  // 上から見た艇の輪郭(x: 前後, y: 左右)
  const s = new THREE.Shape();
  const L = 1.45 * scale, W = 0.68 * scale;
  s.moveTo(-L, -W * 0.94);
  s.lineTo(-0.2 * scale, -W);
  s.bezierCurveTo(0.6 * scale, -W, 1.1 * scale, -W * 0.8, L * 0.97, -W * 0.36);
  s.quadraticCurveTo(L * 1.03, 0, L * 0.97, W * 0.36);
  s.bezierCurveTo(1.1 * scale, W * 0.8, 0.6 * scale, W, -0.2 * scale, W);
  s.lineTo(-L, W * 0.94);
  s.closePath();
  return s;
}

function numberTex(num) {
  return canvasTex(128, 128, (c, w, h) => {
    c.fillStyle = BOAT_CSS[num - 1]; c.fillRect(0, 0, w, h);
    c.fillStyle = BOAT_TEXT_CSS[num - 1];
    c.font = `900 104px ${JP_FONT}`; c.textAlign = 'center'; c.textBaseline = 'middle';
    c.fillText(String(num), w / 2, h / 2 + 6);
  });
}

function deckTex(num) {
  return canvasTex(256, 128, (c, w, h) => {
    c.fillStyle = '#f4f1e8'; c.fillRect(0, 0, w, h);
    c.fillStyle = BOAT_CSS[num - 1];
    c.fillRect(0, 0, w, 16); c.fillRect(0, h - 16, w, 16);
    c.fillRect(0, h / 2 - 5, w * 0.55, 10);
    c.strokeStyle = 'rgba(0,0,0,0.25)'; c.lineWidth = 2;
    for (let x = 30; x < w; x += 44) { c.beginPath(); c.moveTo(x, 18); c.lineTo(x, h - 18); c.stroke(); }
    c.strokeRect(1, 1, w - 2, h - 2);
  });
}

export class BoatView {
  constructor(scene, num) {
    this.num = num;
    const col = BOAT_COLORS[num - 1];
    const root = new THREE.Group(), tilt = new THREE.Group();
    root.add(tilt);
    this.root = root; this.tilt = tilt;

    const mWhite = new THREE.MeshStandardMaterial({ color: 0xf3f1ea, roughness: 0.35, metalness: 0.05 });
    const mCol = new THREE.MeshStandardMaterial({ color: col, roughness: 0.4, metalness: 0.05 });
    const mDark = new THREE.MeshStandardMaterial({ color: 0x1b1d22, roughness: 0.6 });
    const mMetal = new THREE.MeshStandardMaterial({ color: 0x9aa0a8, roughness: 0.35, metalness: 0.8 });
    const mNum = new THREE.MeshStandardMaterial({ map: numberTex(num), roughness: 0.5 });
    const mDeck = new THREE.MeshStandardMaterial({ map: deckTex(num), roughness: 0.5 });

    // ---- 艇体 ----
    const hullG = new THREE.ExtrudeGeometry(hullShape(), { depth: 0.2, bevelEnabled: true, bevelThickness: 0.07, bevelSize: 0.06, bevelSegments: 2, curveSegments: 10 });
    hullG.rotateX(Math.PI / 2);          // 押し出し方向を下向きに
    hullG.translate(0, 0.3, 0);
    const hull = new THREE.Mesh(hullG, mWhite);
    tilt.add(hull);
    // 艇底の色帯(吃水線)
    const keelG = new THREE.ExtrudeGeometry(hullShape(0.93), { depth: 0.08, bevelEnabled: false, curveSegments: 8 });
    keelG.rotateX(Math.PI / 2); keelG.translate(-0.03, 0.06, 0);
    tilt.add(new THREE.Mesh(keelG, mDark));
    // デッキ
    const deckG = new THREE.ShapeGeometry(hullShape(0.95), 10);
    deckG.rotateX(-Math.PI / 2);
    const dp = deckG.attributes.position, duv = deckG.attributes.uv;
    for (let i = 0; i < dp.count; i++) duv.setXY(i, (dp.getX(i) + 1.45) / 2.9, (dp.getZ(i) + 0.68) / 1.36);
    deckG.translate(0, 0.375, 0);
    tilt.add(new THREE.Mesh(deckG, mDeck));
    // コックピット(くぼみ)
    const pit = new THREE.Mesh(new THREE.BoxGeometry(1.25, 0.03, 0.78), mDark);
    pit.position.set(-0.62, 0.385, 0); tilt.add(pit);
    // カウリング(艇番色)
    const cowlG = new THREE.BoxGeometry(0.95, 0.3, 0.86, 4, 1, 1);
    const cp = cowlG.attributes.position;
    for (let i = 0; i < cp.count; i++) {
      const x = cp.getX(i), y = cp.getY(i), t = (x + 0.475) / 0.95;   // 0=後端, 1=前端
      if (y > 0) cp.setY(i, y * (1 - t * 0.9));
      cp.setZ(i, cp.getZ(i) * (1 - t * 0.35));
    }
    cowlG.computeVertexNormals();
    const cowl = new THREE.Mesh(cowlG, mCol);
    cowl.position.set(0.5, 0.52, 0); tilt.add(cowl);
    // 艇番プレート(左右と上面)
    for (const s of [-1, 1]) {
      const pl = new THREE.Mesh(new THREE.PlaneGeometry(0.34, 0.24), mNum);
      pl.position.set(0.22, 0.54, s * 0.436); pl.rotation.y = s > 0 ? 0 : Math.PI;
      tilt.add(pl);
    }
    const top = new THREE.Mesh(new THREE.PlaneGeometry(0.4, 0.4), mNum);
    top.rotation.set(-Math.PI / 2, 0, -Math.PI / 2); top.position.set(1.05, 0.378, 0); tilt.add(top);
    // 風防とハンドル
    const ws = new THREE.Mesh(new THREE.BoxGeometry(0.03, 0.2, 0.7), new THREE.MeshStandardMaterial({ color: 0x9fc4dd, transparent: true, opacity: 0.45, roughness: 0.1 }));
    ws.position.set(0.02, 0.74, 0); ws.rotation.z = 0.5; tilt.add(ws);
    const wheel = new THREE.Mesh(new THREE.TorusGeometry(0.13, 0.022, 6, 14), mDark);
    wheel.position.set(-0.1, 0.62, 0.05); wheel.rotation.set(0, Math.PI / 2, 0.5); tilt.add(wheel);
    this.wheel = wheel;
    // 艇旗
    const pole = new THREE.Mesh(new THREE.CylinderGeometry(0.012, 0.012, 0.5, 5), mMetal);
    pole.position.set(1.22, 0.62, 0); tilt.add(pole);
    const flag = new THREE.Mesh(new THREE.PlaneGeometry(0.3, 0.2), new THREE.MeshStandardMaterial({ map: mNum.map, side: THREE.DoubleSide, roughness: 0.7 }));
    flag.position.set(1.06, 0.76, 0); tilt.add(flag);
    this.flag = flag;

    // ---- モーター(船外機) ----
    const motor = new THREE.Group();
    motor.position.set(-1.5, 0.35, 0);
    const head = new THREE.Mesh(new THREE.BoxGeometry(0.34, 0.36, 0.3), mDark);
    head.position.set(-0.08, 0.36, 0); motor.add(head);
    const band = new THREE.Mesh(new THREE.BoxGeometry(0.35, 0.09, 0.31), mCol);
    band.position.set(-0.08, 0.4, 0); motor.add(band);
    const fly = new THREE.Mesh(new THREE.CylinderGeometry(0.13, 0.13, 0.05, 12), mMetal);
    fly.position.set(-0.08, 0.57, 0); motor.add(fly);
    const tank = new THREE.Mesh(new THREE.CylinderGeometry(0.09, 0.09, 0.3, 8), new THREE.MeshStandardMaterial({ color: 0xc8312a, roughness: 0.4 }));
    tank.rotation.x = Math.PI / 2; tank.position.set(0.16, 0.22, 0); motor.add(tank);
    const shaft = new THREE.Mesh(new THREE.BoxGeometry(0.09, 0.75, 0.06), mMetal);
    shaft.position.set(-0.08, -0.1, 0); motor.add(shaft);
    const gear = new THREE.Mesh(new THREE.CapsuleGeometry(0.05, 0.22, 3, 8), mMetal);
    gear.rotation.z = Math.PI / 2; gear.position.set(-0.1, -0.46, 0); motor.add(gear);
    tilt.add(motor);
    this.motor = motor;

    // ---- レーサー ----
    const racer = new THREE.Group();
    racer.position.set(-0.72, 0.4, 0);
    const mSuit = new THREE.MeshStandardMaterial({ color: col, roughness: 0.75 });
    const mPants = new THREE.MeshStandardMaterial({ color: num === 2 ? 0x3a3d46 : 0x23262d, roughness: 0.8 });
    const mHelm = new THREE.MeshStandardMaterial({ color: num === 1 ? 0xe8e8e8 : col, roughness: 0.25, metalness: 0.1 });
    const mVisor = new THREE.MeshStandardMaterial({ color: 0x101418, roughness: 0.1, metalness: 0.6 });
    // ひざ立ちの脚
    const shin = new THREE.Mesh(new THREE.BoxGeometry(0.5, 0.13, 0.42), mPants);
    shin.position.set(-0.22, 0.07, 0); racer.add(shin);
    const body = new THREE.Group();       // 腰から上
    body.position.set(0, 0.12, 0);
    const thigh = new THREE.Mesh(new THREE.CapsuleGeometry(0.11, 0.3, 3, 8), mPants);
    thigh.scale.z = 1.7; thigh.position.set(0.0, 0.17, 0); thigh.rotation.z = -0.25; body.add(thigh);
    const torso = new THREE.Mesh(new THREE.CapsuleGeometry(0.17, 0.36, 4, 10), mSuit);
    torso.scale.set(1, 1, 1.25); torso.position.set(0.22, 0.52, 0); torso.rotation.z = -0.85; body.add(torso);
    const vest = new THREE.Mesh(new THREE.BoxGeometry(0.2, 0.3, 0.3), mNum);
    vest.position.set(0.14, 0.62, 0); vest.rotation.z = -0.85; body.add(vest);
    const helm = new THREE.Mesh(new THREE.SphereGeometry(0.155, 14, 10), mHelm);
    helm.position.set(0.52, 0.8, 0); body.add(helm);
    const visor = new THREE.Mesh(new THREE.SphereGeometry(0.158, 12, 8, 0, Math.PI * 2, 1.0, 0.75), mVisor);
    visor.position.copy(helm.position); visor.rotation.z = -Math.PI / 2 + 0.25; body.add(visor);
    for (const s of [-1, 1]) {
      const arm = new THREE.Mesh(new THREE.CapsuleGeometry(0.055, 0.42, 3, 6), mSuit);
      arm.position.set(0.46, 0.5, s * 0.2); arm.rotation.z = -1.25; arm.rotation.y = s * 0.15; body.add(arm);
    }
    racer.add(body);
    tilt.add(racer);
    this.racer = racer; this.body = body;

    // 水面に落ちる影
    const sh = new THREE.Mesh(new THREE.CircleGeometry(1, 20).rotateX(-Math.PI / 2), new THREE.MeshBasicMaterial({ color: 0x00141c, transparent: true, opacity: 0.32, depthWrite: false }));
    sh.scale.set(1.75, 1, 0.85); sh.position.y = 0.025; sh.renderOrder = 3; root.add(sh);

    scene.add(root);
    this.slapped = 0;
    this.roll = 0; this.pitch = 0; this.heave = 0; this.lean = 0; this.stand = 0;
    this.poundT = Math.random(); this.poundV = 0; this.poundY = 0;
  }

  update(b, dt, time) {
    const sp = b.speed, f = clamp(sp / VMAX, 0, 1);
    this.root.position.set(b.x, 0, b.z);
    this.root.rotation.y = -b.h;
    // ロール(旋回内側へ傾く) + 衝突の揺れ
    const rollT = clamp(b.w * b.vf * 0.024, -0.36, 0.36) + b.bump * b.bumpSide * 0.35 * Math.sin(time * 28);
    this.roll += (rollT - this.roll) * Math.min(1, dt * 7);
    // ピッチ: 滑走で艇首が上がる。加速でさらに上がる
    const plane = clamp((sp - 2) / 8, 0, 1);
    const pitchT = 0.015 + 0.075 * plane - 0.03 * f + clamp(b.af, -6, 6) * 0.006;
    this.pitch += (pitchT - this.pitch) * Math.min(1, dt * 5);
    // 艇底が波を叩く上下動
    this.poundT -= dt * (1.5 + 7 * f);
    if (this.poundT <= 0) { this.poundT = 0.5 + Math.random(); const imp = (0.25 + Math.random() * 0.5) * f * (1 + b.inWake * 1.6); this.poundV += imp; if (f > 0.4) this.slapped = imp; }
    this.poundV += (-this.poundY * 90 - this.poundV * 9) * dt;
    this.poundY += this.poundV * dt;
    const bob = Math.sin(time * 1.7 + this.num) * 0.025 * (1 - f);
    this.tilt.position.y = 0.02 + bob + Math.max(this.poundY, -0.05) + 0.05 * plane;
    this.tilt.rotation.set(this.roll, 0, this.pitch + this.poundY * 0.35);
    // レーサー: 旋回で立ち上がり内側へ体重移動(モンキーターン)
    const ti = clamp(Math.abs(b.w) * sp / 14, 0, 1);
    this.stand += (ti - this.stand) * Math.min(1, dt * 6);
    const leanT = clamp(b.w * 0.6, -0.7, 0.7);
    this.lean += (leanT - this.lean) * Math.min(1, dt * 6);
    this.body.rotation.x = this.lean * 0.9;
    this.body.rotation.z = this.stand * 0.38;
    this.body.position.y = 0.12 + this.stand * 0.1;
    this.racer.position.z = this.lean * 0.22;
    this.racer.position.x = -0.72 - this.stand * 0.12;
    this.motor.rotation.y = -b.steer * 0.45;
    this.wheel.rotation.x = b.steer * 1.4;
    this.flag.rotation.y = Math.sin(time * 14 + this.num) * 0.25 * (0.3 + f);
  }
}
