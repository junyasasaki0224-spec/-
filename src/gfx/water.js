// 空と水面。水面は手続き的な波の法線 + フレネル反射 + 太陽/照明の照り返し。
import * as THREE from 'three';
import { GLSL_NOISE } from './common.js';

export function createSky(scene) {
  const uniforms = {
    uZenith: { value: new THREE.Color() }, uHorizon: { value: new THREE.Color() },
    uSunDir: { value: new THREE.Vector3() }, uSunCol: { value: new THREE.Color() },
    uCloud: { value: new THREE.Color() }, uNight: { value: 0 }, uTime: { value: 0 },
  };
  const mat = new THREE.ShaderMaterial({
    uniforms, side: THREE.BackSide, depthWrite: false, fog: false,
    vertexShader: /* glsl */`
      varying vec3 vDir;
      void main(){ vDir = position; vec4 p = projectionMatrix * viewMatrix * vec4(position + cameraPosition, 1.0); gl_Position = p.xyww; }`,
    fragmentShader: /* glsl */`
      uniform vec3 uZenith, uHorizon, uSunDir, uSunCol, uCloud; uniform float uNight, uTime;
      varying vec3 vDir;
      ${GLSL_NOISE}
      void main(){
        vec3 d = normalize(vDir);
        float h = max(d.y, 0.0);
        vec3 col = mix(uHorizon, uZenith, pow(h, 0.5));
        float sd = max(dot(d, uSunDir), 0.0);
        float sunAmt = 1.0 - smoothstep(0.6, 1.0, uNight);
        col += uSunCol * (pow(sd, 1400.0) * 8.0 + pow(sd, 40.0) * 0.35 + pow(sd, 6.0) * 0.12) * sunAmt;
        // 星と月
        if (uNight > 0.5) {
          vec2 sp = d.xz / (abs(d.y) + 0.25) * 90.0;
          float st = hash21(floor(sp));
          vec2 f = fract(sp) - 0.5;
          col += vec3(0.9, 0.95, 1.0) * step(0.985, st) * smoothstep(0.25, 0.0, length(f)) * smoothstep(0.03, 0.3, d.y) * (0.5 + 0.5 * sin(uTime * 2.0 + st * 60.0));
          vec3 md = normalize(vec3(0.55, 0.42, -0.72));
          float m = max(dot(d, md), 0.0);
          col += vec3(1.0, 0.97, 0.88) * (smoothstep(0.9993, 0.9996, m) * 1.3 + pow(m, 300.0) * 0.25);
        }
        // 雲
        vec2 uv = d.xz / (d.y + 0.14) * 1.1 + vec2(uTime * 0.006, 0.0);
        float c = fbm(uv) * 0.7 + fbm(uv * 3.1 + 9.0) * 0.3;
        c = smoothstep(0.5, 0.8, c) * smoothstep(0.015, 0.22, d.y);
        vec3 cc = mix(uCloud * 0.72, uCloud, smoothstep(-0.2, 0.6, dot(d, uSunDir)));
        col = mix(col, cc, c * 0.82);
        if (d.y < 0.0) col = uHorizon;
        gl_FragColor = vec4(col, 1.0);
        #include <tonemapping_fragment>
        #include <colorspace_fragment>
      }`,
  });
  const mesh = new THREE.Mesh(new THREE.SphereGeometry(100, 32, 16), mat);
  mesh.frustumCulled = false;
  mesh.renderOrder = -10;
  scene.add(mesh);
  return { mesh, uniforms };
}

export function createWater(scene) {
  const lights = [];
  for (let i = 0; i < 8; i++) lights.push(new THREE.Vector3(0, -1000, 0));
  const uniforms = {
    uTime: { value: 0 },
    uSunDir: { value: new THREE.Vector3() }, uSunCol: { value: new THREE.Color() },
    uDeep: { value: new THREE.Color() }, uShallow: { value: new THREE.Color() },
    uHorizon: { value: new THREE.Color() }, uZenith: { value: new THREE.Color() },
    uFog: { value: new THREE.Color() }, uFogD: { value: 0.001 }, uNight: { value: 0 },
    uLights: { value: lights },
  };
  const mat = new THREE.ShaderMaterial({
    uniforms, fog: false,
    vertexShader: /* glsl */`
      varying vec3 vW;
      void main(){ vec4 w = modelMatrix * vec4(position, 1.0); vW = w.xyz; gl_Position = projectionMatrix * viewMatrix * w; }`,
    fragmentShader: /* glsl */`
      uniform float uTime, uFogD, uNight;
      uniform vec3 uSunDir, uSunCol, uDeep, uShallow, uHorizon, uZenith, uFog;
      uniform vec3 uLights[8];
      varying vec3 vW;
      ${GLSL_NOISE}
      float H(vec2 p, float detail){
        float t = uTime;
        float h = vnoise(p * 0.22 + vec2(t * 0.25, t * 0.1)) * 0.55;
        h += vnoise(p * 0.7 + vec2(-t * 0.45, t * 0.38)) * 0.3;
        h += vnoise(p * 1.9 + vec2(t * 0.8, -t * 0.62)) * 0.14 * detail;
        h += vnoise(p * 5.3 + vec2(-t * 1.5, t * 1.1)) * 0.05 * detail;
        return h;
      }
      void main(){
        vec3 toCam = cameraPosition - vW;
        float dist = length(toCam);
        vec3 V = toCam / dist;
        float detail = 1.0 / (1.0 + dist * 0.02);
        float e = 0.15 + dist * 0.004;
        vec2 p = vW.xz;
        float h0 = H(p, detail), hx = H(p + vec2(e, 0.0), detail), hz = H(p + vec2(0.0, e), detail);
        float str = 0.9 / (1.0 + dist * 0.006);
        vec3 N = normalize(vec3(-(hx - h0) / e * str, 1.0, -(hz - h0) / e * str));
        vec3 R = reflect(-V, N); R.y = abs(R.y);
        float ndv = max(dot(N, V), 0.0);
        float fres = 0.03 + 0.97 * pow(1.0 - ndv, 5.0);
        vec3 sky = mix(uHorizon, uZenith, pow(R.y, 0.5));
        vec3 body = mix(uDeep, uShallow, clamp(pow(1.0 - ndv, 2.0) * 0.6 + (h0 - 0.5) * 0.5, 0.0, 1.0));
        vec3 col = mix(body, sky, fres * 0.92);
        // 太陽のきらめき
        float sd = max(dot(R, uSunDir), 0.0);
        float sunAmt = 1.0 - smoothstep(0.6, 1.0, uNight);
        col += uSunCol * (pow(sd, 260.0) * 2.6 + pow(sd, 28.0) * 0.14) * sunAmt;
        // ナイター照明の映り込み
        if (uNight > 0.2) {
          for (int i = 0; i < 8; i++) {
            vec3 L = uLights[i] - vW; float d = length(L); L /= d;
            float s = pow(max(dot(R, L), 0.0), 70.0) * 1.4 + pow(max(dot(R, L), 0.0), 12.0) * 0.06;
            col += vec3(1.0, 0.96, 0.86) * s * uNight / (1.0 + d * 0.006);
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
  scene.add(mesh);
  return { mesh, uniforms };
}
