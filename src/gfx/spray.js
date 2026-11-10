// 水しぶき(インスタンス化したビルボード)と航跡(リボン)。
// しぶきは「水滴の群れ」と「霧」の2種類のスプライトを使い、水滴は進行方向に引き伸ばして筋状に見せる。
import * as THREE from 'three';
import { canvasTex } from './common.js';
import { TRAIL_MAX } from '../sim/race.js';
import { VMAX } from '../sim/physics.js';

function sprayAtlas() {
  const t = canvasTex(512, 256, (c, w, h) => {
    c.clearRect(0, 0, w, h);
    let s = 99;
    const R = () => { s = (s * 1664525 + 1013904223) | 0; return ((s >>> 8) & 0xffff) / 65536; };
    const dot = (x, y, r, a) => {
      const g = c.createRadialGradient(x, y, 0, x, y, r);
      g.addColorStop(0, `rgba(255,255,255,${a})`); g.addColorStop(0.55, `rgba(255,255,255,${a * 0.55})`); g.addColorStop(1, 'rgba(255,255,255,0)');
      c.fillStyle = g; c.beginPath(); c.arc(x, y, r, 0, 7); c.fill();
    };
    // 左: 水滴の群れ
    dot(128, 128, 104, 0.22);
    for (let i = 0; i < 170; i++) {
      const a = R() * 6.283, d = Math.pow(R(), 0.8) * 102;
      const r = 1.6 + R() * R() * 6, x = 128 + Math.cos(a) * d, y = 128 + Math.sin(a) * d;
      c.fillStyle = `rgba(255,255,255,${0.7 + 0.3 * R()})`;
      c.beginPath(); c.arc(x, y, r * 0.6, 0, 7); c.fill();
      dot(x, y, r * 1.6, 0.3);
    }
    // 右: 霧
    for (let i = 0; i < 46; i++) {
      const a = R() * 6.283, d = R() * 62;
      dot(384 + Math.cos(a) * d, 128 + Math.sin(a) * d, 26 + R() * 40, 0.05 + 0.06 * R());
    }
  });
  t.colorSpace = THREE.NoColorSpace;
  return t;
}

export class Spray {
  constructor(scene, max = 12000) {
    const M = this.max = max;
    this.pos = new Float32Array(M * 3); this.vel = new Float32Array(M * 3);
    this.life = new Float32Array(M); this.maxLife = new Float32Array(M);
    this.size0 = new Float32Array(M); this.grow = new Float32Array(M);
    this.alpha0 = new Float32Array(M); this.drag = new Float32Array(M);
    this.kind = new Float32Array(M); this.seed = new Float32Array(M);
    this.next = 0; this.density = 1;
    this.gPos = new Float32Array(M * 3); this.gVel = new Float32Array(M * 3); this.gPar = new Float32Array(M * 4);
    const g = new THREE.InstancedBufferGeometry();
    g.setAttribute('position', new THREE.Float32BufferAttribute([-0.5, -0.5, 0, 0.5, -0.5, 0, 0.5, 0.5, 0, -0.5, 0.5, 0], 3));
    g.setIndex([0, 1, 2, 0, 2, 3]);
    g.setAttribute('iPos', new THREE.InstancedBufferAttribute(this.gPos, 3).setUsage(THREE.DynamicDrawUsage));
    g.setAttribute('iVel', new THREE.InstancedBufferAttribute(this.gVel, 3).setUsage(THREE.DynamicDrawUsage));
    g.setAttribute('iPar', new THREE.InstancedBufferAttribute(this.gPar, 4).setUsage(THREE.DynamicDrawUsage));
    g.instanceCount = 0;
    this.uniforms = { tMap: { value: sprayAtlas() }, uColor: { value: new THREE.Color(0xffffff) }, uShade: { value: new THREE.Color(0xb8c8d0) } };
    const mat = new THREE.ShaderMaterial({
      uniforms: this.uniforms, transparent: true, depthWrite: false, side: THREE.DoubleSide,
      vertexShader: /* glsl */`
        attribute vec3 iPos, iVel; attribute vec4 iPar;
        varying vec2 vUv; varying float vA, vKind;
        void main(){
          vec4 mv = viewMatrix * vec4(iPos, 1.0);
          vec2 q = position.xy;
          float size = iPar.x, kind = iPar.z;
          vec2 off;
          if (kind < 0.5) {
            // 水滴: 画面上の速度方向へ引き伸ばす
            vec3 vv = (viewMatrix * vec4(iVel, 0.0)).xyz;
            float sp = length(vv.xy);
            vec2 dir = sp > 0.01 ? vv.xy / sp : vec2(0.0, 1.0);
            float len = size + min(sp * 0.035, size * 1.6);
            off = dir * q.y * len + vec2(dir.y, -dir.x) * q.x * size;
          } else {
            float a = iPar.w * 6.283; float cs = cos(a), sn = sin(a);
            off = vec2(q.x * cs - q.y * sn, q.x * sn + q.y * cs) * size;
          }
          mv.xy += off;
          gl_Position = projectionMatrix * mv;
          vUv = vec2((q.x + 0.5) * 0.5 + kind * 0.5, q.y + 0.5);
          vA = iPar.y; vKind = kind;
        }`,
      fragmentShader: /* glsl */`
        uniform sampler2D tMap; uniform vec3 uColor, uShade;
        varying vec2 vUv; varying float vA, vKind;
        void main(){
          float a = texture2D(tMap, vUv).a * vA * (vKind < 0.5 ? 1.25 : 1.0);
          if (a < 0.006) discard;
          vec3 col = mix(uShade, uColor, clamp(0.35 + vUv.y * 0.5 + a * 0.6, 0.0, 1.0));
          gl_FragColor = vec4(col, a);
          #include <tonemapping_fragment>
          #include <colorspace_fragment>
        }`,
    });
    this.mesh = new THREE.Mesh(g, mat);
    this.mesh.frustumCulled = false;
    this.mesh.renderOrder = 20;
    this.mesh.userData.noReflect = true;
    scene.add(this.mesh);
    this.geo = g;
  }

  emit(x, y, z, vx, vy, vz, life, size, alpha, grow = 1.5, drag = 1.2, kind = 0) {
    const i = this.next; this.next = (i + 1) % this.max;
    const k = i * 3;
    this.pos[k] = x; this.pos[k + 1] = y; this.pos[k + 2] = z;
    this.vel[k] = vx; this.vel[k + 1] = vy; this.vel[k + 2] = vz;
    this.life[i] = life; this.maxLife[i] = life; this.size0[i] = size;
    this.alpha0[i] = alpha; this.grow[i] = grow; this.drag[i] = drag;
    this.kind[i] = kind; this.seed[i] = Math.random();
  }

  clear() { this.life.fill(0); this.geo.instanceCount = 0; }

  update(dt) {
    const { pos, vel, life, maxLife, size0, grow, alpha0, drag, kind, seed, gPos, gVel, gPar, max } = this;
    let n = 0;
    for (let i = 0; i < max; i++) {
      if (life[i] <= 0) continue;
      life[i] -= dt;
      const k = i * 3, mist = kind[i] > 0.5, dr = Math.exp(-drag[i] * dt);
      vel[k] *= dr; vel[k + 2] *= dr;
      vel[k + 1] -= (mist ? 1.2 : 9.8) * dt;
      if (mist) vel[k + 1] *= dr;
      pos[k] += vel[k] * dt; pos[k + 1] += vel[k + 1] * dt; pos[k + 2] += vel[k + 2] * dt;
      if (pos[k + 1] < 0.03) { pos[k + 1] = 0.03; vel[k + 1] = 0; vel[k] *= 0.85; vel[k + 2] *= 0.85; life[i] -= dt * 3; }
      if (life[i] <= 0) continue;
      const t = 1 - life[i] / maxLife[i];
      const o = n * 3, p = n * 4;
      gPos[o] = pos[k]; gPos[o + 1] = pos[k + 1]; gPos[o + 2] = pos[k + 2];
      gVel[o] = vel[k]; gVel[o + 1] = vel[k + 1]; gVel[o + 2] = vel[k + 2];
      gPar[p] = size0[i] * (1 + grow[i] * t);
      gPar[p + 1] = alpha0[i] * (1 - t) * Math.min(1, t * (mist ? 5 : 14));
      gPar[p + 2] = kind[i]; gPar[p + 3] = seed[i];
      n++;
    }
    const g = this.geo;
    g.instanceCount = n;
    for (const name of ['iPos', 'iVel', 'iPar']) {
      const a = g.attributes[name];
      a.clearUpdateRanges(); a.addUpdateRange(0, n * a.itemSize); a.needsUpdate = true;
    }
  }

  // 1艇ぶんのしぶきを出す。near = カメラに近いほど細かく出す(0..1)
  emitBoat(b, dt, near) {
    const sp = b.speed;
    if (sp < 1.2) return;
    const R = Math.random;
    const ch = Math.cos(b.h), sh = Math.sin(b.h);
    const rx = -sh, rz = ch;                       // 右方向
    const f = sp / VMAX, q = (0.3 + 0.7 * near) * this.density;
    const cnt = (rate) => { const n = rate * q * dt; return Math.floor(n) + (R() < n % 1 ? 1 : 0); };
    // 1) プロペラ後方のルースターテール
    let n = cnt((22 + 70 * b.throttle) * f);
    for (let i = 0; i < n; i++) {
      const s = R() - 0.5, up = (1.8 + 3.6 * R()) * (0.45 + 0.55 * b.throttle) * (0.5 + f);
      this.emit(b.x - ch * 1.8 + rx * s * 0.4, 0.12, b.z - sh * 1.8 + rz * s * 0.4,
        b.vx * 0.32 - ch * (1 + 3 * R()) + rx * s * 1.8, up, b.vz * 0.32 - sh * (1 + 3 * R()) + rz * s * 1.8,
        0.45 + 0.5 * R(), 0.22 + 0.32 * R(), 0.55 + 0.35 * R(), 1.5, 1.4);
    }
    // 2) 艇の両舷から薄く広がるしぶき
    n = cnt(70 * f * f);
    for (let i = 0; i < n; i++) {
      const side = R() < 0.5 ? -1 : 1, along = -1.1 + R() * 1.5;
      this.emit(b.x + ch * along + rx * side * 0.66, 0.08, b.z + sh * along + rz * side * 0.66,
        b.vx * 0.6 + rx * side * (1.2 + 2.6 * R()), 0.8 + 1.8 * R(), b.vz * 0.6 + rz * side * (1.2 + 2.6 * R()),
        0.28 + 0.3 * R(), 0.16 + 0.24 * R(), 0.5 + 0.3 * R(), 1.4, 2.0);
    }
    // 3) 旋回時: 流れる側へ立ち上がる水の壁
    const ti = b.turnInt;
    if (ti > 0.1) {
      const side = b.vl > 0 ? 1 : -1;
      n = cnt(300 * ti * (0.4 + 0.6 * f));
      for (let i = 0; i < n; i++) {
        const along = -1.6 + R() * 2.7, pw = (0.45 + 0.55 * R()) * ti;
        this.emit(b.x + ch * along + rx * side * 0.7, 0.1, b.z + sh * along + rz * side * 0.7,
          b.vx * 0.45 + rx * side * (2.5 + 7.5 * R()) * pw, (2.2 + 6.8 * R()) * pw, b.vz * 0.45 + rz * side * (2.5 + 7.5 * R()) * pw,
          0.5 + 0.7 * R(), 0.24 + 0.5 * R(), 0.42 + 0.38 * R(), 1.6, 1.1);
      }
      n = cnt(9 * ti);
      for (let i = 0; i < n; i++) {
        this.emit(b.x + rx * side * (0.8 + R()), 0.4 + R() * 0.8, b.z + rz * side * (0.8 + R()),
          b.vx * 0.3 + rx * side * (1.5 + 2 * R()), 0.9 + 1.2 * R(), b.vz * 0.3 + rz * side * (1.5 + 2 * R()),
          1.0 + 0.9 * R(), 1.0 + 1.0 * R(), 0.16 + 0.1 * R(), 1.2, 0.9, 1);
      }
    }
    // 4) 後方に薄く残る霧
    if (f > 0.45 && R() < 4 * f * q * dt) {
      this.emit(b.x - ch * 2.4, 0.5, b.z - sh * 2.4, b.vx * 0.2, 0.7 + R(), b.vz * 0.2, 1.0 + R(), 0.9 + 0.8 * R(), 0.09 + 0.06 * R(), 1.4, 0.8, 1);
    }
    // 5) 艇底が水面を叩いた時に前方へ飛ぶしぶき
    if (f > 0.55 && R() < 8 * f * q * dt) {
      for (let i = 0; i < 5; i++) {
        const side = R() - 0.5;
        this.emit(b.x + ch * 0.7 + rx * side * 1.2, 0.1, b.z + sh * 0.7 + rz * side * 1.2,
          b.vx * 0.75 + rx * side * 5.5, 1.2 + 2.4 * R(), b.vz * 0.75 + rz * side * 5.5, 0.3 + 0.3 * R(), 0.22 + 0.3 * R(), 0.6, 1.6, 2.2);
      }
    }
  }

  // 衝突・着水の飛沫
  burst(x, z, power, vx = 0, vz = 0) {
    const R = Math.random, n = Math.min(110, Math.floor((18 + power * 18) * this.density));
    for (let i = 0; i < n; i++) {
      const a = R() * Math.PI * 2, s = (1 + 4.5 * R()) * Math.min(1.6, 0.5 + power * 0.25);
      this.emit(x + Math.cos(a) * 0.4, 0.15, z + Math.sin(a) * 0.4,
        vx * 0.5 + Math.cos(a) * s, (2 + 6 * R()) * Math.min(1.5, 0.5 + power * 0.2), vz * 0.5 + Math.sin(a) * s,
        0.5 + 0.7 * R(), 0.25 + 0.5 * R(), 0.75, 1.6, 1.2);
    }
    this.emit(x, 0.6, z, vx * 0.3, 1 + R(), vz * 0.3, 1.0 + R(), 1.3 + R(), 0.16, 1.3, 0.9, 1);
  }
}

// 航跡(引き波)。艇ごとに帯状メッシュを毎フレーム更新する
export class Wakes {
  constructor(scene, waveTex, nBoats = 6) {
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
    this.uniforms = { uTime: { value: 0 }, uColor: { value: new THREE.Color(0xffffff) }, tWave: { value: waveTex } };
    const mat = new THREE.ShaderMaterial({
      uniforms: this.uniforms, transparent: true, depthWrite: false, side: THREE.DoubleSide,
      polygonOffset: true, polygonOffsetFactor: -2, polygonOffsetUnits: -2,
      vertexShader: /* glsl */`
        attribute float aAlpha; varying float vA; varying vec2 vUv; varying vec3 vW;
        void main(){ vA = aAlpha; vUv = uv; vW = position; gl_Position = projectionMatrix * viewMatrix * vec4(position, 1.0); }`,
      fragmentShader: /* glsl */`
        uniform float uTime; uniform vec3 uColor; uniform sampler2D tWave; varying float vA; varying vec2 vUv; varying vec3 vW;
        void main(){
          float v = abs(vUv.y);
          float n = texture2D(tWave, vW.xz / 2.9 + vec2(uTime * 0.02, 0.0)).b;
          float n2 = texture2D(tWave, vW.zx / 0.83 - vec2(0.0, uTime * 0.05)).b;
          float n3 = texture2D(tWave, vW.xz / 0.27).b;
          float tex = n * 0.4 + n2 * 0.35 + n3 * 0.25;
          float core = smoothstep(0.75, 0.0, v);                              // 中央の泡立ち
          float edge = smoothstep(0.62, 0.86, v) * smoothstep(1.0, 0.9, v);   // 両縁の波
          // 新しい航跡ほど泡が濃く、時間とともに細かくちぎれて消える
          float th = mix(0.56, 0.34, vA);
          float foam = core * smoothstep(th - 0.04, th + 0.16, tex) + edge * smoothstep(0.5, 0.62, tex) * 0.3 * vA;
          float a = clamp(foam, 0.0, 1.0) * (0.3 + 0.55 * vA) * (1.0 - v * v * 0.6);
          if (a < 0.01) discard;
          gl_FragColor = vec4(uColor, a * 0.9);
          #include <tonemapping_fragment>
          #include <colorspace_fragment>
        }`,
    });
    this.mesh = new THREE.Mesh(g, mat);
    this.mesh.frustumCulled = false;
    this.mesh.renderOrder = 5;
    this.mesh.userData.noReflect = true;
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
        const life = Math.max(0, 1 - age / 4.2);
        const w = (0.55 + age * 0.62) * (0.6 + 0.4 * Math.min(s, 1.2));
        const a = i > n || (b.speed < 2 && i === 0) ? 0 : Math.pow(life, 1.9) * Math.min(1, s) * Math.min(1, 0.35 + age * 2.5);
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
