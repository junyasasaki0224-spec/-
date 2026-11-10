// サウンドはすべて WebAudio で合成する(音声ファイルなし)。
// 2ストロークエンジン、水切り音、しぶき、衝突、観客、ファンファーレなど。
import { VMAX } from './sim/physics.js';

const clamp = (v, a, b) => (v < a ? a : v > b ? b : v);

export class GameAudio {
  constructor() { this.ctx = null; this.ready = false; this.muted = false; this.vol = 0.8; this.engines = []; this.cheer = 0; }

  init() {
    if (this.ctx) { if (this.ctx.state === 'suspended') this.ctx.resume(); return; }
    const AC = window.AudioContext || window.webkitAudioContext;
    if (!AC) return;
    const ctx = this.ctx = new AC();
    const comp = ctx.createDynamicsCompressor();
    comp.threshold.value = -16; comp.knee.value = 18; comp.ratio.value = 5; comp.attack.value = 0.004; comp.release.value = 0.2;
    this.master = ctx.createGain(); this.master.gain.value = this.muted ? 0 : this.vol;
    this.master.connect(comp); comp.connect(ctx.destination);
    this.sfx = ctx.createGain(); this.sfx.connect(this.master);

    // ノイズ素材
    const len = ctx.sampleRate * 2;
    this.noiseBuf = ctx.createBuffer(1, len, ctx.sampleRate);
    const d = this.noiseBuf.getChannelData(0);
    for (let i = 0; i < len; i++) d[i] = Math.random() * 2 - 1;
    this.pinkBuf = ctx.createBuffer(1, len, ctx.sampleRate);
    const p = this.pinkBuf.getChannelData(0);
    let b0 = 0, b1 = 0, b2 = 0;
    for (let i = 0; i < len; i++) { const w = Math.random() * 2 - 1; b0 = 0.997 * b0 + w * 0.03; b1 = 0.985 * b1 + w * 0.05; b2 = 0.95 * b2 + w * 0.08; p[i] = (b0 + b1 + b2) * 1.6; }

    // 歪み(エンジンの荒々しさ)
    const curve = new Float32Array(1024);
    for (let i = 0; i < 1024; i++) { const x = i / 512 - 1; curve[i] = Math.tanh(x * 3.2); }
    this.curve = curve;

    for (let i = 0; i < 6; i++) this.engines.push(this._makeEngine(i));

    // 水切り音(速度で大きく・高く)
    this.rush = this._noiseLoop(this.noiseBuf, 'bandpass', 900, 0.7);
    // 旋回時のしぶき
    this.hiss = this._noiseLoop(this.noiseBuf, 'highpass', 2600, 0.5);
    // 観客のざわめき
    this.crowd = this._noiseLoop(this.pinkBuf, 'bandpass', 750, 0.6);
    this.crowdLfo = ctx.createOscillator(); this.crowdLfo.frequency.value = 0.23;
    const lg = ctx.createGain(); lg.gain.value = 180; this.crowdLfo.connect(lg); lg.connect(this.crowd.filter.frequency); this.crowdLfo.start();
    // 風
    this.wind = this._noiseLoop(this.pinkBuf, 'lowpass', 420, 0.3);
    this.ready = true;
  }

  _noiseLoop(buf, type, freq, q) {
    const ctx = this.ctx, src = ctx.createBufferSource();
    src.buffer = buf; src.loop = true; src.playbackRate.value = 0.9 + Math.random() * 0.2;
    const filter = ctx.createBiquadFilter(); filter.type = type; filter.frequency.value = freq; filter.Q.value = q;
    const gain = ctx.createGain(); gain.gain.value = 0;
    src.connect(filter); filter.connect(gain); gain.connect(this.master); src.start();
    return { src, filter, gain };
  }

  _makeEngine(i) {
    const ctx = this.ctx;
    const o1 = ctx.createOscillator(), o2 = ctx.createOscillator(), o3 = ctx.createOscillator();
    o1.type = 'sawtooth'; o2.type = 'square'; o3.type = 'sawtooth';
    const g1 = ctx.createGain(), g2 = ctx.createGain(), g3 = ctx.createGain();
    g1.gain.value = 0.5; g2.gain.value = 0.32; g3.gain.value = 0.16;
    const pre = ctx.createGain(); pre.gain.value = 0.6;
    const shaper = ctx.createWaveShaper(); shaper.curve = this.curve;
    const lp = ctx.createBiquadFilter(); lp.type = 'lowpass'; lp.frequency.value = 900; lp.Q.value = 1.2;
    const trem = ctx.createGain(); trem.gain.value = 1;
    const lfo = ctx.createOscillator(); lfo.type = 'square'; lfo.frequency.value = 14;
    const lfoG = ctx.createGain(); lfoG.gain.value = 0.2; lfo.connect(lfoG); lfoG.connect(trem.gain);
    const out = ctx.createGain(); out.gain.value = 0;
    const pan = ctx.createStereoPanner ? ctx.createStereoPanner() : null;
    // 排気管の共鳴(回転数によらず一定の帯域が強調される)
    const formant = ctx.createBiquadFilter(); formant.type = 'peaking'; formant.frequency.value = 760 + i * 25; formant.Q.value = 1.4; formant.gain.value = 7;
    o1.connect(g1); o2.connect(g2); o3.connect(g3);
    g1.connect(pre); g2.connect(pre); g3.connect(pre);
    pre.connect(shaper); shaper.connect(lp); lp.connect(formant); formant.connect(trem); trem.connect(out);
    // 2ストローク特有のざらついた排気音: ノイズを爆発の周期で刻む
    const rasp = ctx.createBufferSource(); rasp.buffer = this.noiseBuf; rasp.loop = true; rasp.playbackRate.value = 0.8 + i * 0.07;
    const raspBp = ctx.createBiquadFilter(); raspBp.type = 'bandpass'; raspBp.frequency.value = 1500; raspBp.Q.value = 0.9;
    const raspG = ctx.createGain(); raspG.gain.value = 0;
    const raspAm = ctx.createGain(); raspAm.gain.value = 0.5;
    o1.connect(raspAm); raspAm.connect(raspG.gain);
    rasp.connect(raspBp); raspBp.connect(raspG); raspG.connect(out); rasp.start(i * 0.13);
    if (pan) { out.connect(pan); pan.connect(this.master); } else out.connect(this.master);
    o1.start(); o2.start(); o3.start(); lfo.start();
    return { o1, o2, o3, lp, lfo, lfoG, out, pan, raspG, raspBp, rpm: 1500, jit: 0, detune: 1 + (i - 2.5) * 0.012 };
  }

  setMuted(m) { this.muted = m; if (this.master) this.master.gain.setTargetAtTime(m ? 0 : this.vol, this.ctx.currentTime, 0.05); }
  setVolume(v) { this.vol = v; if (this.master && !this.muted) this.master.gain.setTargetAtTime(v, this.ctx.currentTime, 0.05); }

  // 毎フレーム: 艇とカメラの状態から各音を更新
  update(dt, boats, listenerBoat, cam, camRight, active, cheer) {
    if (!this.ready) return;
    const ctx = this.ctx, t = ctx.currentTime;
    let nearSpeed = 0, nearTurn = 0;
    for (let i = 0; i < 6; i++) {
      const b = boats[i], e = this.engines[i];
      if (!active) { e.out.gain.setTargetAtTime(0, t, 0.1); continue; }
      const f = clamp(b.speed / VMAX, 0, 1);
      // 回転数: アイドル1500 → 全開6600。旋回や引き波ではプロペラが空転気味に吹け上がる
      const slip = b.turnInt * 0.12 + b.inWake * 0.05;
      const target = 1500 + 5100 * clamp(0.62 * f + 0.38 * b.throttle + slip * b.throttle, 0, 1.08);
      e.rpm += (target - e.rpm) * Math.min(1, dt * 6);
      e.jit += (Math.random() - 0.5 - e.jit * 0.2) * 0.25;                    // 回転のわずかなばらつき
      const dx = b.x - cam.x, dz = b.z - cam.z, dist = Math.hypot(dx, dz, cam.y);
      // ドップラー効果
      const vr = dist > 1 ? (b.vx * dx + b.vz * dz) / dist - (listenerBoat ? (listenerBoat.vx * dx + listenerBoat.vz * dz) / dist : 0) : 0;
      const dop = clamp(340 / (340 + vr), 0.8, 1.25);
      const hz = e.rpm / 60 * 2 * e.detune * dop * (1 + e.jit * 0.012);      // 2気筒2ストローク
      e.o1.frequency.setTargetAtTime(hz, t, 0.03);
      e.o2.frequency.setTargetAtTime(hz * 0.5, t, 0.03);
      e.o3.frequency.setTargetAtTime(hz * 2.01, t, 0.03);
      e.lp.frequency.setTargetAtTime(500 + 2600 * b.throttle + 900 * f, t, 0.05);
      e.lfo.frequency.setTargetAtTime(hz / 8, t, 0.05);
      e.lfoG.gain.setTargetAtTime(0.28 * (1 - f), t, 0.1);
      e.raspG.gain.setTargetAtTime(0.25 + 0.5 * b.throttle, t, 0.05);
      e.raspBp.frequency.setTargetAtTime(1100 + 1500 * b.throttle + 600 * f, t, 0.05);
      const own = b === listenerBoat;
      const att = own ? 1 : 1 / (1 + (dist / 9) ** 2);
      const vol = (own ? 0.2 : 0.28) * (0.35 + 0.65 * b.throttle) * att;
      e.out.gain.setTargetAtTime(vol, t, 0.05);
      if (e.pan) e.pan.pan.setTargetAtTime(own ? 0 : clamp((dx * camRight.x + dz * camRight.z) / Math.max(dist, 4), -1, 1) * 0.85, t, 0.05);
      const w = own ? 1 : att;
      nearSpeed = Math.max(nearSpeed, f * w); nearTurn = Math.max(nearTurn, b.turnInt * w);
    }
    if (!active) { nearSpeed = 0; nearTurn = 0; }
    this.rush.gain.gain.setTargetAtTime(0.22 * nearSpeed * nearSpeed, t, 0.08);
    this.rush.filter.frequency.setTargetAtTime(500 + 1900 * nearSpeed, t, 0.08);
    this.hiss.gain.gain.setTargetAtTime(0.16 * nearTurn, t, 0.06);
    this.wind.gain.gain.setTargetAtTime(0.05 + 0.1 * nearSpeed, t, 0.2);
    // 観客: スタンドに近いほど、盛り上がるほど大きい
    this.cheer += (cheer - this.cheer) * Math.min(1, dt * 1.5);
    const standD = Math.hypot(cam.x - 20, cam.z - 80, cam.y);
    this.crowd.gain.gain.setTargetAtTime((0.05 + 0.2 * this.cheer) / (1 + (standD / 90) ** 2) + 0.012, t, 0.2);
    this.crowd.filter.frequency.setTargetAtTime(700 + 500 * this.cheer, t, 0.3);
  }

  _burst(buf, type, freq, q, vol, dur, when = 0) {
    const ctx = this.ctx, t = ctx.currentTime + when, src = ctx.createBufferSource();
    src.buffer = buf; src.playbackRate.value = 0.8 + Math.random() * 0.5;
    const f = ctx.createBiquadFilter(); f.type = type; f.frequency.value = freq; f.Q.value = q;
    const g = ctx.createGain(); g.gain.setValueAtTime(0, t); g.gain.linearRampToValueAtTime(vol, t + 0.008); g.gain.exponentialRampToValueAtTime(0.0008, t + dur);
    src.connect(f); f.connect(g); g.connect(this.sfx); src.start(t, Math.random()); src.stop(t + dur + 0.05);
  }

  _tone(type, f0, f1, vol, dur, when = 0, attack = 0.005) {
    const ctx = this.ctx, t = ctx.currentTime + when, o = ctx.createOscillator(), g = ctx.createGain();
    o.type = type; o.frequency.setValueAtTime(f0, t); if (f1 !== f0) o.frequency.exponentialRampToValueAtTime(f1, t + dur);
    g.gain.setValueAtTime(0.0001, t); g.gain.linearRampToValueAtTime(vol, t + attack); g.gain.exponentialRampToValueAtTime(0.0008, t + dur);
    o.connect(g); g.connect(this.sfx); o.start(t); o.stop(t + dur + 0.05);
  }

  // 艇どうし・壁との衝突
  hit(power, att = 1) {
    if (!this.ready) return;
    const v = clamp(power * 0.16, 0.08, 0.7) * att;
    this._tone('sine', 150, 48, v * 1.2, 0.22);
    this._burst(this.noiseBuf, 'bandpass', 520, 0.8, v, 0.16);
    this._burst(this.noiseBuf, 'highpass', 1800, 0.5, v * 0.7, 0.5, 0.02);   // 飛沫
  }
  buoy(power, att = 1) { if (this.ready) { this._tone('sine', 220, 90, 0.25 * att, 0.25); this._burst(this.noiseBuf, 'lowpass', 600, 0.7, 0.22 * att, 0.3); } }
  splash(vol = 0.3) { if (this.ready) this._burst(this.noiseBuf, 'highpass', 1500, 0.4, vol, 0.6); }
  slap(vol) { if (this.ready) { this._tone('sine', 95, 50, vol, 0.09); this._burst(this.noiseBuf, 'lowpass', 900, 0.6, vol * 0.5, 0.08); } }
  click() { if (this.ready) this._tone('triangle', 880, 660, 0.12, 0.07); }
  tick(final) { if (this.ready) this._tone('sine', final ? 1320 : 880, final ? 1320 : 880, final ? 0.28 : 0.14, final ? 0.5 : 0.09); }
  buzzer() { if (this.ready) { this._tone('square', 196, 196, 0.25, 0.9, 0, 0.02); this._tone('square', 207, 207, 0.2, 0.9, 0, 0.02); } }

  // 館内チャイム + オリジナルのファンファーレ
  fanfare() {
    if (!this.ready) return;
    const chime = [659.3, 523.3, 587.3, 392];
    chime.forEach((f, i) => this._tone('sine', f, f, 0.14, 0.9, i * 0.38, 0.01));
    const B = 0.17, t0 = 1.9;
    const seq = [[392, 1], [392, 0.5], [392, 0.5], [523.3, 1], [659.3, 1], [587.3, 0.5], [659.3, 0.5], [784, 2], [698.5, 0.5], [659.3, 0.5], [587.3, 1], [784, 3]];
    let t = t0;
    for (const [f, len] of seq) {
      const d = len * B * 1.9;
      this._brass(f, d, t, 0.13); this._brass(f * 0.75, d, t, 0.06); this._brass(f * 0.5, d, t, 0.07);
      t += len * B;
    }
  }
  _brass(f, dur, when, vol) {
    const ctx = this.ctx, t = ctx.currentTime + when, o = ctx.createOscillator(), o2 = ctx.createOscillator(), lp = ctx.createBiquadFilter(), g = ctx.createGain();
    o.type = 'sawtooth'; o2.type = 'sawtooth'; o.frequency.value = f; o2.frequency.value = f * 1.004;
    lp.type = 'lowpass'; lp.frequency.setValueAtTime(600, t); lp.frequency.linearRampToValueAtTime(2800, t + 0.06); lp.frequency.linearRampToValueAtTime(1500, t + dur);
    g.gain.setValueAtTime(0.0001, t); g.gain.linearRampToValueAtTime(vol, t + 0.03); g.gain.setValueAtTime(vol * 0.8, t + dur * 0.7); g.gain.exponentialRampToValueAtTime(0.0008, t + dur);
    o.connect(lp); o2.connect(lp); lp.connect(g); g.connect(this.sfx); o.start(t); o2.start(t); o.stop(t + dur + 0.05); o2.stop(t + dur + 0.05);
  }
  // ゴール時のジングル
  finishJingle(win) {
    if (!this.ready) return;
    const seq = win ? [523.3, 659.3, 784, 1046.5, 784, 1046.5] : [523.3, 659.3, 784];
    seq.forEach((f, i) => this._brass(f, i === seq.length - 1 ? 0.9 : 0.22, i * 0.15, 0.12));
  }
}
