// 描画の土台: レンダラー、ライティング(影・環境マップ)、水面の映り込み、ポストエフェクト、画質設定。
import * as THREE from 'three';
import { EffectComposer } from 'three/examples/jsm/postprocessing/EffectComposer.js';
import { RenderPass } from 'three/examples/jsm/postprocessing/RenderPass.js';
import { UnrealBloomPass } from 'three/examples/jsm/postprocessing/UnrealBloomPass.js';
import { OutputPass } from 'three/examples/jsm/postprocessing/OutputPass.js';
import { ENVS } from './common.js';
import { createSky, createWater, makeWaveTexture, Reflection } from './water.js';
import { Spray, Wakes } from './spray.js';
import { BoatView, loadBoatModel, setShadowProjection } from './boat.js';
import { createVenue } from './venue.js';
import { clamp } from '../sim/course.js';

export const QUALITY = {
  high: { dpr: 2, shadow: 2048, refl: 0.5, bloom: true, msaa: 4, spray: 1, crowd: 1 },
  medium: { dpr: 1.5, shadow: 1024, refl: 0.34, bloom: true, msaa: 2, spray: 0.7, crowd: 1 },
  low: { dpr: 1, shadow: 0, refl: 0, bloom: false, msaa: 0, spray: 0.45, crowd: 0.5 },
};
const ORDER = ['low', 'medium', 'high'];

export class Stage {
  constructor(canvas) {
    this.canvas = canvas;
    const r = this.renderer = new THREE.WebGLRenderer({ canvas, antialias: true, stencil: true, powerPreference: 'high-performance' });
    r.outputColorSpace = THREE.SRGBColorSpace;
    r.toneMapping = THREE.ACESFilmicToneMapping;
    r.shadowMap.type = THREE.PCFSoftShadowMap;
    this.scene = new THREE.Scene();
    this.camera = new THREE.PerspectiveCamera(62, 1, 0.25, 7000);
    this.hemi = new THREE.HemisphereLight(0xffffff, 0x888888, 1);
    this.sun = new THREE.DirectionalLight(0xffffff, 3);
    this.sun.shadow.bias = -0.0006; this.sun.shadow.normalBias = 0.025;
    const sc = this.sun.shadow.camera; sc.left = -13; sc.right = 13; sc.top = 13; sc.bottom = -13; sc.near = 5; sc.far = 130;
    this.scene.add(this.hemi, this.sun, this.sun.target);
    this.sunDir = new THREE.Vector3(0, 1, 0);
    this.envName = 'day'; this.quality = 'high'; this.q = QUALITY.high;
    this.composer = null; this.bloom = null;
    this.views = [];
    this.wind = { x: 1, z: 0, speed: 2 };
    this._ema = 0.016; this._qT = 0; this.autoQuality = true;
    this._size = new THREE.Vector2();
  }

  async init() {
    await loadBoatModel();
    const scene = this.scene;
    this.waveTex = makeWaveTexture(256);
    this.sky = createSky(scene);
    this.water = createWater(scene, this.waveTex);
    this.reflection = new Reflection(this.renderer);
    this.water.uniforms.tRefl.value = this.reflection.rt.texture;
    this.venue = await createVenue(scene);
    this.wakes = new Wakes(scene, this.waveTex);
    this.spray = new Spray(scene);
    for (let i = 0; i < 6; i++) this.views.push(new BoatView(scene, i + 1));
    // 環境マップ(艇体の映り込みと間接光)用に空だけのシーンを持つ
    this.pmrem = new THREE.PMREMGenerator(this.renderer);
    this.envScene = new THREE.Scene();
    const skyCopy = new THREE.Mesh(this.sky.mesh.geometry, this.sky.material);
    skyCopy.frustumCulled = false;
    this.envScene.add(skyCopy);
    this.envRT = null;
  }

  setQuality(name) {
    this.quality = name; const q = this.q = QUALITY[name];
    const r = this.renderer;
    r.setPixelRatio(Math.min(window.devicePixelRatio || 1, q.dpr));
    r.shadowMap.enabled = q.shadow > 0;
    this.sun.castShadow = q.shadow > 0;
    if (q.shadow) {
      this.sun.shadow.mapSize.set(q.shadow, q.shadow);
      if (this.sun.shadow.map) { this.sun.shadow.map.dispose(); this.sun.shadow.map = null; }
    }
    this.reflection.enabled = q.refl > 0; this.reflection.scale = q.refl || 0.25;
    this.water.uniforms.uRefl.value = q.refl > 0 ? 1 : 0;
    this.spray.density = q.spray;
    if (this.venue.setCrowd) this.venue.setCrowd(q.crowd);
    if (this.composer) { this.composer.dispose(); this.composer = null; this.bloom = null; }
    this.scene.traverse((o) => { if (o.material) { const ms = Array.isArray(o.material) ? o.material : [o.material]; for (const m of ms) m.needsUpdate = true; } });
    this.resize();
    this._applyEnvPost();
    if (this.envRT) this.venue.bakeShadow(r, this.sunDir, q.shadow ? q.shadow * 2 : 0);
  }

  _buildComposer(w, h) {
    const q = this.q, r = this.renderer;
    if (this.composer) this.composer.dispose();
    if (!q.bloom) { this.composer = null; this.bloom = null; return; }
    const pr = r.getPixelRatio();
    const rt = new THREE.WebGLRenderTarget(w * pr, h * pr, { type: THREE.HalfFloatType, samples: q.msaa, stencilBuffer: true });
    const c = this.composer = new EffectComposer(r, rt);
    c.setPixelRatio(pr); c.setSize(w, h);
    c.addPass(new RenderPass(this.scene, this.camera));
    this.bloom = new UnrealBloomPass(new THREE.Vector2(w / 2, h / 2), 0.3, 0.5, 0.95);
    c.addPass(this.bloom);
    c.addPass(new OutputPass());
  }

  resize() {
    const w = window.innerWidth, h = window.innerHeight, r = this.renderer;
    r.setSize(w, h, false);
    this.camera.aspect = w / h; this.camera.updateProjectionMatrix();
    r.getDrawingBufferSize(this._size);
    this.reflection.setSize(this._size.x, this._size.y);
    this._buildComposer(w, h);
    this._applyEnvPost();
  }

  _applyEnvPost() {
    const e = ENVS[this.envName];
    this.renderer.toneMappingExposure = e.exposure;
    if (this.bloom) { this.bloom.strength = e.bloom; this.bloom.threshold = e.bloomTh; this.bloom.radius = 0.55; }
  }

  // weather: { windDir(rad), wind(m/s), cover(0..1) }
  setEnv(name, weather) {
    this.envName = name;
    const e = ENVS[name];
    const sd = this.sunDir.set(...e.sunDir).normalize();
    const su = this.sky.uniforms;
    su.uZenith.value.set(e.zenith); su.uHorizon.value.set(e.horizon);
    su.uSunDir.value.copy(sd); su.uSunCol.value.set(e.sunCol);
    su.uCloud.value.set(e.cloud); su.uNight.value = e.night;
    su.uCover.value = weather ? weather.cover : 0.45;
    const wu = this.water.uniforms;
    wu.uSunDir.value.copy(sd); wu.uSunCol.value.set(e.sunCol); wu.uDeep.value.set(e.deep); wu.uShallow.value.set(e.shallow);
    wu.uHorizon.value.set(e.horizon); wu.uZenith.value.set(e.zenith); wu.uFog.value.set(e.fog); wu.uFogD.value = e.fogD; wu.uNight.value = e.night;
    this.venue.lightPos.slice(0, 8).forEach((p, i) => wu.uLights.value[i].copy(p));
    if (weather) {
      this.wind = { x: Math.cos(weather.windDir), z: Math.sin(weather.windDir), speed: weather.wind };
      wu.uWind.value.set(this.wind.x, this.wind.z);
      wu.uChop.value = 0.55 + weather.wind * 0.13;
    }
    this.scene.fog = new THREE.FogExp2(e.fog, e.fogD);
    this.hemi.color.set(e.hemiSky); this.hemi.groundColor.set(e.hemiGround); this.hemi.intensity = e.hemiInt;
    this.sun.color.set(e.sunCol); this.sun.intensity = e.sunInt;
    this.spray.uniforms.uColor.value.set(e.spray); this.spray.uniforms.uShade.value.set(e.sprayShade);
    this.wakes.uniforms.uColor.value.set(e.wake);
    this.venue.setEnv(e, this.wind);
    this.venue.bakeShadow(this.renderer, sd, this.q.shadow ? this.q.shadow * 2 : 0);
    setShadowProjection(sd);
    // 環境マップを作り直す
    if (this.envRT) this.envRT.dispose();
    this.envRT = this.pmrem.fromScene(this.envScene, 0, 0.1, 1000);
    this.scene.environment = this.envRT.texture;
    this.scene.environmentIntensity = e.envInt;
    this._applyEnvPost();
  }

  // レース状態を見た目へ反映する
  update(dt, time, race, opts = {}) {
    const cam = this.camera;
    for (let i = 0; i < 6; i++) {
      const b = race.boats[i], v = this.views[i];
      v.update(b, dt, time);
      const d = Math.hypot(b.x - cam.position.x, b.z - cam.position.z);
      this.spray.emitBoat(b, dt, clamp(1.15 - d / 110, 0.12, 1));
    }
    this.spray.update(dt);
    this.wakes.update(race.boats, race.clock, time);
    this.venue.update(dt, time, race, opts.title || '', opts.cheer || 0, opts.names);
    this.sky.uniforms.uTime.value = time; this.water.uniforms.uTime.value = time;
  }

  render(focus) {
    // 影はカメラが見ている艇のまわりだけ高解像度で落とす
    if (focus && this.q.shadow) {
      this.sun.target.position.set(focus.x, 0, focus.z);
      this.sun.position.copy(this.sunDir).multiplyScalar(60).add(this.sun.target.position);
      this.sun.target.updateMatrixWorld();
    }
    if (this.reflection.enabled) {
      this.reflection.render(this.scene, this.camera);
      this.water.uniforms.uTexM.value.copy(this.reflection.matrix);
    }
    if (this.composer) this.composer.render();
    else this.renderer.render(this.scene, this.camera);
  }

  // 重い端末では画質を自動で下げる
  adapt(rawDt) {
    if (!this.autoQuality) return null;
    if (rawDt < 0.5) this._ema += (rawDt - this._ema) * 0.05;
    this._qT += rawDt;
    if (this._qT < 3) return null;
    this._qT = 0;
    const i = ORDER.indexOf(this.quality);
    if (this._ema > 0.034 && i > 0) { this.setQuality(ORDER[i - 1]); this._ema = 0.02; return this.quality; }
    return null;
  }
}
