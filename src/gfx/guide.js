// 走行ガイド: AI が組み立てた理想ラインを水面に矢印で描く(レバーを落とす区間は赤)。
import * as THREE from 'three';

const N = 26;
export class Guide {
  constructor(scene) {
    this.pos = new Float32Array((N + 1) * 2 * 3);
    this.uv = new Float32Array((N + 1) * 2 * 2);
    this.col = new Float32Array((N + 1) * 2 * 4);
    const idx = [];
    for (let i = 0; i < N; i++) { const o = i * 2; idx.push(o, o + 1, o + 2, o + 1, o + 3, o + 2); }
    const g = new THREE.BufferGeometry();
    g.setAttribute('position', new THREE.BufferAttribute(this.pos, 3).setUsage(THREE.DynamicDrawUsage));
    g.setAttribute('uv', new THREE.BufferAttribute(this.uv, 2).setUsage(THREE.DynamicDrawUsage));
    g.setAttribute('aCol', new THREE.BufferAttribute(this.col, 4).setUsage(THREE.DynamicDrawUsage));
    g.setIndex(idx);
    this.uniforms = { uTime: { value: 0 } };
    const mat = new THREE.ShaderMaterial({
      uniforms: this.uniforms, transparent: true, depthWrite: false, side: THREE.DoubleSide, fog: false,
      polygonOffset: true, polygonOffsetFactor: -3, polygonOffsetUnits: -3,
      vertexShader: 'attribute vec4 aCol; varying vec4 vC; varying vec2 vUv; void main(){ vC = aCol; vUv = uv; gl_Position = projectionMatrix * viewMatrix * vec4(position, 1.0); }',
      fragmentShader: /* glsl */`
        uniform float uTime; varying vec4 vC; varying vec2 vUv;
        void main(){
          float u = fract(vUv.x - uTime * 1.4 - abs(vUv.y) * 0.5);       // 進行方向へ流れる山形
          float chev = smoothstep(0.0, 0.08, u) * smoothstep(0.55, 0.4, u);
          float a = vC.a * (0.25 + 0.75 * chev) * smoothstep(1.0, 0.75, abs(vUv.y));
          if (a < 0.01) discard;
          gl_FragColor = vec4(vC.rgb, a);
          #include <tonemapping_fragment>
          #include <colorspace_fragment>
        }`,
    });
    this.mesh = new THREE.Mesh(g, mat);
    this.mesh.frustumCulled = false; this.mesh.renderOrder = 6; this.mesh.visible = false;
    this.mesh.userData.noReflect = true;
    scene.add(this.mesh);
    this.geo = g;
  }

  update(b, time, on) {
    const ai = b && b.ai, P = ai && ai.plan;
    if (!on || !P || !b.started || b.finished || b.flying) { this.mesh.visible = false; return; }
    this.mesh.visible = true;
    this.uniforms.uTime.value = time;
    const { pos, uv, col } = this, xs = P.xs, zs = P.zs, M = xs.length;
    let dist = 0, px = b.x, pz = b.z;
    const lift = b.advice.lift;
    for (let i = 0; i <= N; i++) {
      const k = Math.min(M - 1, ai.k + 1 + i);
      const x = xs[k], z = zs[k];
      const k2 = Math.min(M - 1, k + 1);
      let dx = xs[k2] - x, dz = zs[k2] - z, l = Math.hypot(dx, dz);
      if (l < 1e-3) { dx = x - px; dz = z - pz; l = Math.hypot(dx, dz) || 1; }
      dx /= l; dz /= l;
      dist += Math.hypot(x - px, z - pz); px = x; pz = z;
      const o = i * 2, w = 0.55;
      pos[o * 3] = x - dz * w; pos[o * 3 + 1] = 0.06; pos[o * 3 + 2] = z + dx * w;
      pos[o * 3 + 3] = x + dz * w; pos[o * 3 + 4] = 0.06; pos[o * 3 + 5] = z - dx * w;
      uv[o * 2] = dist / 3.2; uv[o * 2 + 1] = -1; uv[o * 2 + 2] = dist / 3.2; uv[o * 2 + 3] = 1;
      // 旋回円の区間は黄、いまレバーを落とすべき時は手前を赤く
      const inArc = k >= P.kT && k <= P.kT + 14;
      const red = lift && dist < 45;
      const r = red ? 1.0 : inArc ? 1.0 : 0.3, g = red ? 0.25 : inArc ? 0.8 : 0.9, bl = red ? 0.2 : inArc ? 0.2 : 1.0;
      const a = Math.min(1, dist / 6) * Math.max(0, 1 - dist / 95) * (k >= M - 1 ? 0 : 0.8);
      for (let s = 0; s < 2; s++) { const c = (o + s) * 4; col[c] = r; col[c + 1] = g; col[c + 2] = bl; col[c + 3] = a; }
    }
    this.geo.attributes.position.needsUpdate = true; this.geo.attributes.uv.needsUpdate = true; this.geo.attributes.aCol.needsUpdate = true;
  }
}
