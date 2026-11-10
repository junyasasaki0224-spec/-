// 水しぶき(パーティクル)と航跡(リボン)。
import * as THREE from 'three';
import { GLSL_NOISE } from './common.js';
import { TRAIL_MAX } from '../sim/race.js';
import { VMAX } from '../sim/physics.js';

const MAXP = 14000;

export class Spray {
  constructor(scene) {
    this.pos = new Float32Array(MAXP * 3);
    this.vel = new Float32Array(MAXP * 3);
    this.life = new Float32Array(MAXP);     // 残り寿命
    this.maxLife = new Float32Array(MAXP);
    this.size0 = new Float32Array(MAXP);
    this.grow = new Float32Array(MAXP);
    this.alpha0 = new Float32Array(MAXP);
    this.drag = new Float32Array(MAXP);
    this.aSize = new Float32Array(MAXP);
    this.aAlpha = new Float32Array(MAXP);
    this.next = 0;
    const g = new THREE.BufferGeometry();
    g.setAttribute('position', new THREE.BufferAttribute(this.pos, 3).setUsage(THREE.DynamicDrawUsage));
    g.setAttribute('aSize', new THREE.BufferAttribute(this.aSize, 1).setUsage(THREE.DynamicDrawUsage));
    g.setAttribute('aAlpha', new THREE.BufferAttribute(this.aAlpha, 1).setUsage(THREE.DynamicDrawUsage));
    this.uniforms = { uPx: { value: 600 }, uColor: { value: new THREE.Color(0xffffff) } };
    const mat = new THREE.ShaderMaterial({
      uniforms: this.uniforms, transparent: true, depthWrite: false,
      vertexShader: /* glsl */`
        attribute float aSize, aAlpha; uniform float uPx; varying float vA;
        void main(){
          vec4 mv = modelViewMatrix * vec4(position, 1.0);
          gl_Position = projectionMatrix * mv;
          gl_PointSize = aAlpha > 0.0 ? clamp(aSize * uPx / max(-mv.z, 0.1), 1.5, 90.0) : 0.0;
          vA = aAlpha;
        }`,
      fragmentShader: /* glsl */`
        uniform vec3 uColor; varying float vA;
        void main(){
          vec2 q = gl_PointCoord - 0.5;
          float d = length(q) * 2.0;
          float a = smoothstep(1.0, 0.5, d) * vA;
          if (a < 0.004) discard;
          gl_FragColor = vec4(uColor * (0.86 + 0.14 * (0.5 - q.y)), a);
          #include <tonemapping_fragment>
          #include <colorspace_fragment>
        }`,
    });
    this.points = new THREE.Points(g, mat);
    this.points.frustumCulled = false;
    this.points.renderOrder = 20;
    scene.add(this.points);
    this.geo = g;
  }

  emit(x, y, z, vx, vy, vz, life, size, alpha, grow = 1.5, drag = 1.2) {
    const i = this.next; this.next = (i + 1) % MAXP;
    const k = i * 3;
    this.pos[k] = x; this.pos[k + 1] = y; this.pos[k + 2] = z;
    this.vel[k] = vx; this.vel[k + 1] = vy; this.vel[k + 2] = vz;
    this.life[i] = life; this.maxLife[i] = life; this.size0[i] = size;
    this.alpha0[i] = alpha; this.grow[i] = grow; this.drag[i] = drag;
  }

  update(dt) {
    const { pos, vel, life, maxLife, size0, grow, alpha0, drag, aSize, aAlpha } = this;
    for (let i = 0; i < MAXP; i++) {
      if (life[i] <= 0) { if (aAlpha[i] !== 0) aAlpha[i] = 0; continue; }
      life[i] -= dt;
      const k = i * 3, dr = Math.exp(-drag[i] * dt);
      vel[k] *= dr; vel[k + 2] *= dr;
      vel[k + 1] -= 9.8 * dt;
      pos[k] += vel[k] * dt; pos[k + 1] += vel[k + 1] * dt; pos[k + 2] += vel[k + 2] * dt;
      if (pos[k + 1] < 0.02) { pos[k + 1] = 0.02; vel[k + 1] = 0; vel[k] *= 0.9; vel[k + 2] *= 0.9; life[i] -= dt * 2.5; }
      const t = 1 - Math.max(life[i], 0) / maxLife[i];
      aSize[i] = size0[i] * (1 + grow[i] * t);
      aAlpha[i] = life[i] > 0 ? alpha0[i] * (1 - t) * Math.min(1, t * 12) : 0;
    }
    this.geo.attributes.position.needsUpdate = true;
    this.geo.attributes.aSize.needsUpdate = true;
    this.geo.attributes.aAlpha.needsUpdate = true;
  }

  // 1艇ぶんのしぶきを出す。near = カメラに近いほど細かく出す(0..1)
  emitBoat(b, dt, near) {
    const sp = b.speed;
    if (sp < 1.2) return;
    const R = Math.random;
    const ch = Math.cos(b.h), sh = Math.sin(b.h);
    const rx = -sh, rz = ch;                       // 右方向
    const f = sp / VMAX, q = 0.35 + 0.65 * near;
    // 1) プロペラ後方のルースターテール
    let n = (30 + 90 * b.throttle) * f * q * dt;
    n = Math.floor(n) + (R() < n % 1 ? 1 : 0);
    for (let i = 0; i < n; i++) {
      const s = R() - 0.5;
      this.emit(b.x - ch * 1.75 + rx * s * 0.5, 0.1, b.z - sh * 1.75 + rz * s * 0.5,
        b.vx * 0.3 - ch * (1.5 + 3 * R()) + rx * s * 2.0, (1.6 + 3.4 * R()) * (0.5 + 0.5 * b.throttle) * (0.5 + f), b.vz * 0.3 - sh * (1.5 + 3 * R()) + rz * s * 2.0,
        0.4 + 0.45 * R(), 0.05 + 0.13 * R(), 0.45 + 0.3 * R(), 1.4, 1.4);
    }
    // 2) 艇の両舷から出る細かいしぶき
    n = 120 * f * f * q * dt; n = Math.floor(n) + (R() < n % 1 ? 1 : 0);
    for (let i = 0; i < n; i++) {
      const side = R() < 0.5 ? -1 : 1, along = -0.9 + R() * 1.3;
      this.emit(b.x + ch * along + rx * side * 0.66, 0.08, b.z + sh * along + rz * side * 0.66,
        b.vx * 0.55 + rx * side * (1.5 + 2.5 * R()), 1.0 + 2.0 * R(), b.vz * 0.55 + rz * side * (1.5 + 2.5 * R()),
        0.3 + 0.35 * R(), 0.04 + 0.1 * R(), 0.5 + 0.3 * R(), 1.4, 2.0);
    }
    // 3) 旋回時: 流れる側へ大きな水の壁
    const ti = b.turnInt;
    if (ti > 0.12) {
      const side = b.vl > 0 ? 1 : -1;
      n = 1500 * ti * (0.4 + 0.6 * f) * q * dt; n = Math.floor(n) + (R() < n % 1 ? 1 : 0);
      for (let i = 0; i < n; i++) {
        const along = -1.5 + R() * 2.6, pw = (0.5 + 0.5 * R()) * ti;
        this.emit(b.x + ch * along + rx * side * 0.7, 0.1, b.z + sh * along + rz * side * 0.7,
          b.vx * 0.45 + rx * side * (3 + 7 * R()) * pw, (2.5 + 6.5 * R()) * pw, b.vz * 0.45 + rz * side * (3 + 7 * R()) * pw,
          0.5 + 0.7 * R(), 0.045 + 0.2 * R() * R(), 0.45 + 0.35 * R(), 1.5, 1.1);
      }
      // 霧状に残るミスト
      if (R() < 14 * ti * q * dt) {
        this.emit(b.x + rx * side * 1.2, 0.5 + R(), b.z + rz * side * 1.2,
          b.vx * 0.3 + rx * side * 2, 1.2 + R(), b.vz * 0.3 + rz * side * 2, 1.4 + R(), 1.4 + 1.2 * R(), 0.06, 1.6, 0.8);
      }
    }
    // 4) 艇底が水面を叩く時の前方のしぶき
    if (f > 0.55 && R() < 9 * f * q * dt) {
      for (let i = 0; i < 6; i++) {
        const side = R() - 0.5;
        this.emit(b.x + ch * 0.9 + rx * side * 1.1, 0.1, b.z + sh * 0.9 + rz * side * 1.1,
          b.vx * 0.7 + rx * side * 5, 1.5 + 2.5 * R(), b.vz * 0.7 + rz * side * 5, 0.3 + 0.3 * R(), 0.05 + 0.1 * R(), 0.5, 1.5, 2.2);
      }
    }
  }

  // 衝突・着水の飛沫
  burst(x, z, power, vx = 0, vz = 0) {
    const R = Math.random, n = Math.min(260, Math.floor(50 + power * 45));
    for (let i = 0; i < n; i++) {
      const a = R() * Math.PI * 2, s = (1 + 4.5 * R()) * Math.min(1.6, 0.5 + power * 0.25);
      this.emit(x + Math.cos(a) * 0.4, 0.15, z + Math.sin(a) * 0.4,
        vx * 0.5 + Math.cos(a) * s, (2 + 6 * R()) * Math.min(1.5, 0.5 + power * 0.2), vz * 0.5 + Math.sin(a) * s,
        0.5 + 0.7 * R(), 0.05 + 0.2 * R() * R(), 0.6, 1.5, 1.2);
    }
  }
}

// 航跡(引き波)。艇ごとに帯状メッシュを毎フレーム更新する
export class Wakes {
  constructor(scene, nBoats = 6) {
    const N = TRAIL_MAX + 2;
    this.N = N; this.nBoats = nBoats;
    const verts = nBoats * N * 2;
    this.pos = new Float32Array(verts * 3);
    this.uv = new Float32Array(verts * 2);
    this.al = new Float32Array(verts);
    const idx = [];
    for (let b = 0; b < nBoats; b++) for (let i = 0; i < N - 1; i++) {
      const o = (b * N + i) * 2;
      idx.push(o, o + 1, o + 2, o + 1, o + 3, o + 2);
    }
    const g = new THREE.BufferGeometry();
    g.setAttribute('position', new THREE.BufferAttribute(this.pos, 3).setUsage(THREE.DynamicDrawUsage));
    g.setAttribute('uv', new THREE.BufferAttribute(this.uv, 2).setUsage(THREE.DynamicDrawUsage));
    g.setAttribute('aAlpha', new THREE.BufferAttribute(this.al, 1).setUsage(THREE.DynamicDrawUsage));
    g.setIndex(idx);
    this.uniforms = { uTime: { value: 0 }, uColor: { value: new THREE.Color(0xffffff) } };
    const mat = new THREE.ShaderMaterial({
      uniforms: this.uniforms, transparent: true, depthWrite: false, side: THREE.DoubleSide,
      polygonOffset: true, polygonOffsetFactor: -2, polygonOffsetUnits: -2,
      vertexShader: /* glsl */`
        attribute float aAlpha; varying float vA; varying vec2 vUv; varying vec3 vW;
        void main(){ vA = aAlpha; vUv = uv; vW = position; gl_Position = projectionMatrix * viewMatrix * vec4(position, 1.0); }`,
      fragmentShader: /* glsl */`
        uniform float uTime; uniform vec3 uColor; varying float vA; varying vec2 vUv; varying vec3 vW;
        ${GLSL_NOISE}
        void main(){
          float v = abs(vUv.y);
          float n = fbm(vW.xz * 1.4 + vec2(uTime * 0.3, 0.0));
          float n2 = vnoise(vW.xz * 4.5 - vec2(0.0, uTime * 0.6));
          float core = smoothstep(0.55, 0.0, v);                       // 中央の泡立ち
          float edge = smoothstep(0.62, 0.86, v) * smoothstep(1.0, 0.9, v);  // 両縁の波
          float foam = core * smoothstep(0.42, 0.75, n * 0.7 + n2 * 0.5 + vA * 0.3) + edge * (0.2 + 0.5 * n2) * smoothstep(0.35, 0.7, n2 + n * 0.4);
          float a = clamp(foam, 0.0, 1.0) * vA;
          if (a < 0.01) discard;
          gl_FragColor = vec4(uColor, a * 0.75);
          #include <tonemapping_fragment>
          #include <colorspace_fragment>
        }`,
    });
    this.mesh = new THREE.Mesh(g, mat);
    this.mesh.frustumCulled = false;
    this.mesh.renderOrder = 5;
    scene.add(this.mesh);
    this.geo = g;
  }

  update(boats, clock, time) {
    this.uniforms.uTime.value = time;
    const { pos, uv, al, N } = this;
    for (let bi = 0; bi < boats.length; bi++) {
      const b = boats[bi], tr = b.trail, n = tr.length;
      const base = bi * N * 2;
      const ch = Math.cos(b.h), sh = Math.sin(b.h);
      const hx = b.x - ch * 1.5, hz = b.z - sh * 1.5;
      let dist = 0, px = 0, pz = 0;
      for (let i = 0; i < N; i++) {
        // i=0 が艇尾(最新)、後ろほど古い
        const o = base + i * 2;
        let x, z, age, s;
        if (i === 0) { x = hx; z = hz; age = 0; s = n ? tr[n - 1].s : 0; }
        else if (i <= n) { const p = tr[n - i]; x = p.x; z = p.z; age = clock - p.t; s = p.s; }
        else { x = px; z = pz; age = 99; s = 0; }
        let dx, dz;
        if (i === 0) { dx = ch; dz = sh; }
        else { dx = px - x; dz = pz - z; const l = Math.hypot(dx, dz); if (l > 1e-4) { dx /= l; dz /= l; dist += l; } else { dx = ch; dz = sh; } }
        const life = Math.max(0, 1 - age / 4.6);
        const w = (0.6 + age * 1.5) * (0.6 + 0.4 * Math.min(s, 1.2));
        const a = i > n || b.speed < 2 && i === 0 ? 0 : Math.pow(life, 1.4) * Math.min(1, s) * Math.min(1, 0.35 + age * 2.5);
        const nx = -dz * w, nz = dx * w;
        pos[o * 3] = x + nx; pos[o * 3 + 1] = 0.035; pos[o * 3 + 2] = z + nz;
        pos[o * 3 + 3] = x - nx; pos[o * 3 + 4] = 0.035; pos[o * 3 + 5] = z - nz;
        uv[o * 2] = dist * 0.25; uv[o * 2 + 1] = 1; uv[o * 2 + 2] = dist * 0.25; uv[o * 2 + 3] = -1;
        al[o] = a; al[o + 1] = a;
        px = x; pz = z;
      }
    }
    this.geo.attributes.position.needsUpdate = true;
    this.geo.attributes.uv.needsUpdate = true;
    this.geo.attributes.aAlpha.needsUpdate = true;
  }
}
