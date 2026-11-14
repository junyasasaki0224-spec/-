// 空と水面。
// 水面: タイル化した波の法線テクスチャ(起動時に生成)を多重に流し、フレネル反射で
// 平面リフレクション(艇・会場・空の映り込み)と水色を混ぜる。
import * as THREE from 'three';
import { HULL_MASK } from './common.js';
import { GLSL_NOISE } from './common.js';

// ---------------- 波テクスチャ ----------------
// 整数波数の正弦波を重ねるので継ぎ目なく繰り返せる。RG = 傾き, B = 高さ
export function makeWaveTexture(N = 256) {
  const h = new Float32Array(N * N);
  let s = 20240611;
  const rnd = () => { s = (s * 1664525 + 1013904223) | 0; return ((s >>> 8) & 0xffffff) / 0x1000000; };
  const table = new Float32Array(N);
  for (let i = 0; i < N; i++) table[i] = Math.cos(2 * Math.PI * i / N);
  for (let w = 0; w < 64; w++) {
    const k = 1 + Math.floor(Math.pow(rnd(), 1.6) * 30);
    const a = rnd() * Math.PI * 2;
    const m = Math.round(Math.cos(a) * k), n = Math.round(Math.sin(a) * k);
    if (!m && !n) continue;
    const amp = 1 / Math.pow(Math.hypot(m, n), 1.15), off = Math.floor(rnd() * N);
    for (let y = 0; y < N; y++) {
      const row = y * N, ny = n * y + off;
      for (let x = 0; x < N; x++) h[row + x] += amp * table[((m * x + ny) % N + N) % N];
    }
  }
  let mx = 0;
  for (let i = 0; i < h.length; i++) mx = Math.max(mx, Math.abs(h[i]));
  const data = new Uint8Array(N * N * 4), S = 9 / mx;
  for (let y = 0; y < N; y++) for (let x = 0; x < N; x++) {
    const i = y * N + x;
    const sx = (h[y * N + (x + 1) % N] - h[y * N + (x + N - 1) % N]) * 0.5 * S;
    const sy = (h[((y + 1) % N) * N + x] - h[((y + N - 1) % N) * N + x]) * 0.5 * S;
    data[i * 4] = Math.max(0, Math.min(255, 127.5 + 127.5 * sx));
    data[i * 4 + 1] = Math.max(0, Math.min(255, 127.5 + 127.5 * sy));
    data[i * 4 + 2] = Math.max(0, Math.min(255, 127.5 + 127.5 * h[i] / mx));
    data[i * 4 + 3] = 255;
  }
  const t = new THREE.DataTexture(data, N, N, THREE.RGBAFormat);
  t.wrapS = t.wrapT = THREE.RepeatWrapping;
  t.magFilter = THREE.LinearFilter; t.minFilter = THREE.LinearMipmapLinearFilter;
  t.generateMipmaps = true; t.anisotropy = 8; t.needsUpdate = true;
  return t;
}

// ---------------- 空 ----------------
export function createSky(scene) {
  const uniforms = {
    uZenith: { value: new THREE.Color() }, uHorizon: { value: new THREE.Color() },
    uSunDir: { value: new THREE.Vector3() }, uSunCol: { value: new THREE.Color() },
    uCloud: { value: new THREE.Color() }, uNight: { value: 0 }, uTime: { value: 0 }, uCover: { value: 0.5 },
  };
  const mat = new THREE.ShaderMaterial({
    uniforms, side: THREE.BackSide, depthWrite: false, fog: false,
    vertexShader: /* glsl */`
      varying vec3 vDir;
      void main(){ vDir = position; vec4 p = projectionMatrix * viewMatrix * vec4(position + cameraPosition, 1.0); gl_Position = p.xyww; }`,
    fragmentShader: /* glsl */`
      uniform vec3 uZenith, uHorizon, uSunDir, uSunCol, uCloud; uniform float uNight, uTime, uCover;
      varying vec3 vDir;
      ${GLSL_NOISE}
      float fbm5(vec2 p){ float a = 0.5, s = 0.0; for (int i = 0; i < 5; i++) { s += a * vnoise(p); p = p * 2.07 + vec2(13.1, 7.7); a *= 0.5; } return s; }
      void main(){
        vec3 d = normalize(vDir);
        float h = max(d.y, 0.0);
        vec3 col = mix(uHorizon, uZenith, pow(h, 0.42));
        float sd = max(dot(d, uSunDir), 0.0);
        float sunAmt = 1.0 - smoothstep(0.6, 1.0, uNight);
        // 地平線近くのもや
        col = mix(col, uHorizon * 1.06, exp(-h * 9.0) * 0.6);
        col += uSunCol * (pow(sd, 2200.0) * 14.0 + pow(sd, 90.0) * 0.5 + pow(sd, 8.0) * 0.16) * sunAmt;
        if (uNight > 0.5) {
          vec2 sp = d.xz / (abs(d.y) + 0.25) * 90.0;
          float st = hash21(floor(sp));
          vec2 f = fract(sp) - 0.5;
          col += vec3(0.9, 0.95, 1.0) * step(0.985, st) * smoothstep(0.25, 0.0, length(f)) * smoothstep(0.03, 0.3, d.y) * (0.5 + 0.5 * sin(uTime * 2.0 + st * 60.0));
          vec3 md = normalize(vec3(0.55, 0.42, -0.72));
          float m = max(dot(d, md), 0.0);
          col += vec3(1.0, 0.97, 0.88) * (smoothstep(0.9993, 0.9996, m) * 1.6 + pow(m, 300.0) * 0.25);
        }
        // 雲: 2層のノイズを歪ませて重ね、太陽側を明るくする
        vec2 uv = d.xz / (d.y + 0.16) * 1.05 + vec2(uTime * 0.005, uTime * 0.002);
        vec2 warp = vec2(fbm(uv * 0.7 + 3.1), fbm(uv * 0.7 - 5.7)) - 0.5;
        float c = fbm5(uv + warp * 0.9);
        float dens = smoothstep(1.0 - uCover, 1.0 - uCover + 0.34, c) * smoothstep(0.01, 0.2, d.y);
        float lit = smoothstep(0.25, 0.9, c - fbm5(uv + warp * 0.9 + uSunDir.xz * 0.12) + 0.55);
        vec3 cc = mix(uCloud * 0.55, uCloud * 1.08, lit) + uSunCol * pow(sd, 6.0) * 0.25 * sunAmt;
        col = mix(col, cc, dens * 0.9);
        if (d.y < 0.0) col = mix(uHorizon, uHorizon * 0.8, clamp(-d.y * 4.0, 0.0, 1.0));
        gl_FragColor = vec4(col, 1.0);
        #include <tonemapping_fragment>
        #include <colorspace_fragment>
      }`,
  });
  const mesh = new THREE.Mesh(new THREE.SphereGeometry(100, 32, 16), mat);
  mesh.frustumCulled = false;
  mesh.renderOrder = -10;
  scene.add(mesh);
  return { mesh, uniforms, material: mat };
}

// ---------------- 平面リフレクション ----------------
export class Reflection {
  constructor(renderer) {
    this.renderer = renderer;
    this.enabled = true;
    this.scale = 0.5;
    this.rt = new THREE.WebGLRenderTarget(4, 4, { type: THREE.HalfFloatType, depthBuffer: true, stencilBuffer: false, generateMipmaps: true, minFilter: THREE.LinearMipmapLinearFilter });
    this.cam = new THREE.PerspectiveCamera();
    this.matrix = new THREE.Matrix4();
    this._v = new THREE.Vector3(); this._look = new THREE.Vector3(); this._rot = new THREE.Matrix4();
    this._plane = new THREE.Plane(); this._clip = new THREE.Vector4(); this._q = new THREE.Vector4();
    this._n = new THREE.Vector3(0, 1, 0); this._hidden = [];
  }
  setSize(w, h) { this.rt.setSize(Math.max(4, Math.floor(w * this.scale)), Math.max(4, Math.floor(h * this.scale))); }
  render(scene, camera) {
    if (!this.enabled) return;
    const cam = this.cam, n = this._n, r = this.renderer;
    camera.updateMatrixWorld();
    const cp = this._v.setFromMatrixPosition(camera.matrixWorld);
    if (cp.y <= 0.05) return;
    this._rot.extractRotation(camera.matrixWorld);
    const look = this._look.set(0, 0, -1).applyMatrix4(this._rot).add(cp);
    cam.position.set(cp.x, -cp.y, cp.z);
    cam.up.set(0, 1, 0).applyMatrix4(this._rot).reflect(n);
    cam.lookAt(look.x, -look.y, look.z);
    cam.near = camera.near; cam.far = camera.far;
    cam.updateMatrixWorld();
    cam.projectionMatrix.copy(camera.projectionMatrix);
    this.matrix.set(0.5, 0, 0, 0.5, 0, 0.5, 0, 0.5, 0, 0, 0.5, 0.5, 0, 0, 0, 1);
    this.matrix.multiply(cam.projectionMatrix).multiply(cam.matrixWorldInverse);
    // 水面より下を切り落とす(斜めニアクリップ)
    this._plane.set(n, 0.02).applyMatrix4(cam.matrixWorldInverse);
    const c = this._clip.set(this._plane.normal.x, this._plane.normal.y, this._plane.normal.z, this._plane.constant);
    const pm = cam.projectionMatrix.elements, q = this._q;
    q.x = (Math.sign(c.x) + pm[8]) / pm[0]; q.y = (Math.sign(c.y) + pm[9]) / pm[5]; q.z = -1; q.w = (1 + pm[10]) / pm[14];
    c.multiplyScalar(2 / c.dot(q));
    pm[2] = c.x; pm[6] = c.y; pm[10] = c.z + 1 - 0.003; pm[14] = c.w;

    const hidden = this._hidden; hidden.length = 0;
    for (const o of scene.children) if (o.visible && o.userData.noReflect) { o.visible = false; hidden.push(o); }
    const prevRT = r.getRenderTarget(), prevShadow = r.shadowMap.autoUpdate, prevXr = r.xr.enabled;
    r.shadowMap.autoUpdate = false; r.xr.enabled = false;
    r.setRenderTarget(this.rt);
    r.state.buffers.depth.setMask(true);
    if (r.autoClear === false) r.clear();
    r.render(scene, cam);
    r.setRenderTarget(prevRT);
    r.shadowMap.autoUpdate = prevShadow; r.xr.enabled = prevXr;
    for (const o of hidden) o.visible = true;
  }
}

// ---------------- 水面 ----------------
export function createWater(scene, waveTex) {
  const lights = [];
  for (let i = 0; i < 8; i++) lights.push(new THREE.Vector3(0, -1000, 0));
  const uniforms = {
    uTime: { value: 0 }, tWave: { value: waveTex }, tRefl: { value: null }, uTexM: { value: new THREE.Matrix4() }, uRefl: { value: 0 },
    uSunDir: { value: new THREE.Vector3() }, uSunCol: { value: new THREE.Color() },
    uDeep: { value: new THREE.Color() }, uShallow: { value: new THREE.Color() },
    uHorizon: { value: new THREE.Color() }, uZenith: { value: new THREE.Color() },
    uFog: { value: new THREE.Color() }, uFogD: { value: 0.001 }, uNight: { value: 0 },
    uLights: { value: lights }, uChop: { value: 1 }, uWind: { value: new THREE.Vector2(1, 0) },
  };
  const mat = new THREE.ShaderMaterial({
    // 艇の上面の目印(boat.js の hullMask)がある所には水面を描かない。旋回で傾いても操縦席に水が見えないように
    stencilWrite: true, stencilFunc: THREE.NotEqualStencilFunc, stencilRef: HULL_MASK, stencilFuncMask: HULL_MASK, stencilWriteMask: 0,
    uniforms, fog: false,
    vertexShader: /* glsl */`
      varying vec3 vW;
      void main(){ vec4 w = modelMatrix * vec4(position, 1.0); vW = w.xyz; gl_Position = projectionMatrix * viewMatrix * w; }`,
    fragmentShader: /* glsl */`
      uniform float uTime, uFogD, uNight, uRefl, uChop;
      uniform sampler2D tWave, tRefl; uniform mat4 uTexM; uniform vec2 uWind;
      uniform vec3 uSunDir, uSunCol, uDeep, uShallow, uHorizon, uZenith, uFog;
      uniform vec3 uLights[8];
      varying vec3 vW;
      void main(){
        vec3 toCam = cameraPosition - vW;
        float dist = length(toCam);
        vec3 V = toCam / dist;
        vec2 p = vW.xz; float t = uTime;
        vec2 wd = uWind, wp = vec2(-uWind.y, uWind.x);
        // 4つのスケールで波を重ねる(うねり / 風波 / さざ波 / 細かいきらめき)
        vec3 a = texture2D(tWave, p / 53.0 + wd * t * 0.011).xyz - 0.5;
        vec3 b = texture2D(tWave, p / 17.3 + (wd * 0.9 + wp * 0.35) * t * 0.034).xyz - 0.5;
        vec3 c = texture2D(tWave, p.yx / 5.9 + (wd * 0.7 - wp * 0.5) * t * 0.085).xyz - 0.5;
        vec3 d = texture2D(tWave, p / 1.7 - wp * t * 0.16 + 0.37).xyz - 0.5;
        float fine = 1.0 / (1.0 + dist * 0.035);
        vec2 slope = (a.xy * 0.55 + b.xy * 0.8 + c.yx * 0.75 + d.xy * 0.5 * fine) * uChop;
        float hgt = a.z * 0.5 + b.z * 0.3 + c.z * 0.2;
        vec3 N = normalize(vec3(-slope.x, 1.0, -slope.y));
        // 遠景は法線をならして、ぎらつきを抑える
        vec3 Nf = normalize(mix(N, vec3(0.0, 1.0, 0.0), smoothstep(40.0, 600.0, dist) * 0.75));
        vec3 R = reflect(-V, Nf); R.y = abs(R.y);
        float ndv = max(dot(Nf, V), 0.0);
        float fres = 0.02 + 0.98 * pow(1.0 - ndv, 5.0);

        // 映り込み
        vec3 sky = mix(uHorizon, uZenith, pow(R.y, 0.42));
        vec3 refl = sky;
        if (uRefl > 0.5) {
          vec4 mc = uTexM * vec4(vW.x, 0.0, vW.z, 1.0);
          vec2 uv = mc.xy / mc.w + vec2(Nf.x * 0.05, -abs(Nf.z) * 0.11 - abs(Nf.x) * 0.03) * (0.35 + 0.65 * clamp(dist / 30.0, 0.0, 1.0));
          refl = min(texture2D(tRefl, clamp(uv, 0.001, 0.999), 1.2).rgb, vec3(1.6));
        }
        // 水の色: 濁った緑がかった水。波の峰と太陽側を明るく
        float sunUp = clamp(uSunDir.y * 2.0 + 0.3, 0.0, 1.0);
        vec3 body = mix(uDeep, uShallow, clamp(0.25 + hgt * 0.9 + pow(1.0 - ndv, 3.0) * 0.4, 0.0, 1.0));
        body *= 0.55 + 0.45 * sunUp * clamp(dot(N, uSunDir) * 0.6 + 0.6, 0.0, 1.0);
        vec3 col = mix(body, refl, fres);

        // 太陽のきらめき
        float sunAmt = 1.0 - smoothstep(0.6, 1.0, uNight);
        vec3 Rs = reflect(-V, N); Rs.y = abs(Rs.y);
        float sd = max(dot(Rs, uSunDir), 0.0);
        col += uSunCol * (pow(sd, 520.0) * 9.0 + pow(sd, 60.0) * 0.35) * sunAmt * (0.4 + 0.6 * fres);
        // ナイター照明の照り返し(映り込みを描かない設定のとき)
        if (uNight > 0.2 && uRefl < 0.5) {
          for (int i = 0; i < 8; i++) {
            vec3 L = uLights[i] - vW; float dl = length(L); L /= dl;
            float s = pow(max(dot(Rs, L), 0.0), 70.0) * 1.4 + pow(max(dot(Rs, L), 0.0), 12.0) * 0.06;
            col += vec3(1.0, 0.96, 0.86) * s * uNight / (1.0 + dl * 0.006);
          }
        }
        float f = 1.0 - exp(-pow(dist * uFogD, 2.0));
        col = mix(col, uFog, f);
        gl_FragColor = vec4(col, 1.0);
        #include <tonemapping_fragment>
        #include <colorspace_fragment>
      }`,
  });
  const mesh = new THREE.Mesh(new THREE.PlaneGeometry(9000, 9000).rotateX(-Math.PI / 2), mat);
  mesh.renderOrder = -5;
  mesh.userData.noReflect = true;
  scene.add(mesh);
  return { mesh, uniforms };
}
