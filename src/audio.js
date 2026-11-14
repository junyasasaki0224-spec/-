// サウンドはすべて WebAudio で合成する(音声ファイルなし)。
// 2ストロークエンジン、水切り音、しぶき、衝突、観客、ファンファーレなど。
import { VMAX } from './sim/physics.js';

const clamp = (v, a, b) => (v < a ? a : v > b ? b : v);

export class GameAudio {
  constructor() { this.ctx = null; this.ready = false; this.muted = false; this.vol = 0.8; this.engines = []; this.cheer = 0; }

  // iPhone は、消音スイッチ(マナーモード)が入っているとスピーカーから WebAudio の音が出ない(イヤホンなら出る)。
  // 音の種類を「再生」にして、消音スイッチの影響を受けないようにする。
  // 新しい Safari は navigator.audioSession で指定でき、古いものは無音の <audio> を流しておくと同じ扱いになる
  _unlockSession() {
    try { if (navigator.audioSession && navigator.audioSession.type !== 'playback') navigator.audioSession.type = 'playback'; } catch (e) { /* 非対応 */ }
    if (!this.keepAlive) {
      // 0.5秒の無音 WAV(8kHz・8bit)をその場で作る
      const n = 4000, buf = new Uint8Array(44 + n), v = new DataView(buf.buffer);
      const str = (o, t) => { for (let i = 0; i < t.length; i++) buf[o + i] = t.charCodeAt(i); };
      str(0, 'RIFF'); v.setUint32(4, 36 + n, true); str(8, 'WAVEfmt '); v.setUint32(16, 16, true); v.setUint16(20, 1, true); v.setUint16(22, 1, true);
      v.setUint32(24, 8000, true); v.setUint32(28, 8000, true); v.setUint16(32, 1, true); v.setUint16(34, 8, true); str(36, 'data'); v.setUint32(40, n, true);
      buf.fill(128, 44);
      let bin = ''; for (let i = 0; i < buf.length; i++) bin += String.fromCharCode(buf[i]);
      const el = this.keepAlive = document.createElement('audio');
      el.src = 'data:audio/wav;base64,' + btoa(bin); el.loop = true; el.preload = 'auto';
      el.setAttribute('playsinline', ''); el.setAttribute('x-webkit-airplay', 'deny');
    }
    if (this.keepAlive.paused && !document.hidden) { try { const p = this.keepAlive.play(); if (p && p.catch) p.catch(() => {}); } catch (e) { /* 再生不可 */ } }
  }
  // 画面を離れたら止め、戻ったら次の操作で再開する
  suspend() { try { if (this.keepAlive) this.keepAlive.pause(); if (this.ctx && this.ctx.state === 'running') this.ctx.suspend(); } catch (e) { /* noop */ } }

  init() {
    this._unlockSession();
    if (this.ctx) { if (this.ctx.state !== 'running') this.ctx.resume().catch(() => {}); return; }
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
    this._scheduleOpening();
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

  // オープニング曲(このゲームのためのオリジナル)。ティンパニのロールとシンバルで幕を開け、
  // 金管の主題・弦の和音・行進のスネアを、ホールの残響つきで鳴らす。16小節・毎分120拍でループ
  startOpening() {
    this.stopOpening(0);
    if (!this.ready) return;
    const ctx = this.ctx;
    const gain = ctx.createGain(); gain.gain.value = 0.85; gain.connect(this.master);
    const bus = ctx.createGain(); bus.connect(gain);
    if (!this.hallBuf) {            // 残響(約2.6秒)の素材を1度だけ作る
      const n = Math.floor(ctx.sampleRate * 2.6); this.hallBuf = ctx.createBuffer(2, n, ctx.sampleRate);
      for (let c = 0; c < 2; c++) { const d = this.hallBuf.getChannelData(c); for (let q = 0; q < n; q++) d[q] = (Math.random() * 2 - 1) * Math.pow(1 - q / n, 2.6); }
    }
    const hall = ctx.createConvolver(); hall.buffer = this.hallBuf;
    const wet = ctx.createGain(); wet.gain.value = 0.32; bus.connect(hall); hall.connect(wet); wet.connect(gain);
    this.openingMusic = { gain, bus, next: ctx.currentTime + 0.05, bar: -1, nodes: new Set() };
    this._scheduleOpening();
  }
  stopOpening(fade = 0) {
    if (fade === 0 && this.fadingOpening) {
      for (const old of this.fadingOpening) {
        old.gain.gain.cancelScheduledValues(this.ctx.currentTime);
        old.gain.gain.setValueAtTime(0, this.ctx.currentTime);
        for (const node of old.nodes) node.stop(this.ctx.currentTime);
      }
      this.fadingOpening.clear();
    }
    const music = this.openingMusic;
    if (!music) return;
    this.openingMusic = null;
    this.fadingOpening ??= new Set();
    this.fadingOpening.add(music);
    const t = this.ctx.currentTime;
    music.gain.gain.cancelScheduledValues(t);
    music.gain.gain.setValueAtTime(music.gain.gain.value, t);
    music.gain.gain.linearRampToValueAtTime(0, t + fade);
    for (const node of music.nodes) node.stop(t + fade + 0.02);
    if (!music.nodes.size) music.gain.disconnect();
  }
  _scheduleOpening() {
    const music = this.openingMusic;
    if (!music || this.ctx.state !== 'running') return;
    const ctx = this.ctx, B = 60 / 120, hz = (m) => 440 * 2 ** ((m - 69) / 12);
    const track = (src, t0, t1) => {
      music.nodes.add(src);
      src.onended = () => { music.nodes.delete(src); if (this.openingMusic !== music && !music.nodes.size) { music.gain.disconnect(); this.fadingOpening?.delete(music); } };
      src.start(t0); src.stop(t1);
    };
    // 金管: 少しずらした2本のノコギリ波を、吹き始めに明るく開くフィルターに通す
    const brass = (m, t, d, v) => {
      const lp = ctx.createBiquadFilter(), g = ctx.createGain();
      lp.type = 'lowpass'; lp.Q.value = 0.8; lp.frequency.setValueAtTime(500, t); lp.frequency.linearRampToValueAtTime(3200, t + 0.07); lp.frequency.linearRampToValueAtTime(1500, t + d);
      g.gain.setValueAtTime(0.0001, t); g.gain.linearRampToValueAtTime(v, t + 0.035); g.gain.setValueAtTime(v * 0.82, t + d * 0.75); g.gain.exponentialRampToValueAtTime(0.0008, t + d + 0.12);
      lp.connect(g); g.connect(music.bus);
      for (const det of [-5, 6]) { const o = ctx.createOscillator(); o.type = 'sawtooth'; o.frequency.value = hz(m); o.detune.value = det; o.connect(lp); track(o, t, t + d + 0.15); }
    };
    // 弦: 3本のノコギリ波をゆっくり立ち上げる
    const strings = (m, t, d, v) => {
      const lp = ctx.createBiquadFilter(), g = ctx.createGain();
      lp.type = 'lowpass'; lp.frequency.value = 2100;
      g.gain.setValueAtTime(0.0001, t); g.gain.linearRampToValueAtTime(v, t + 0.22); g.gain.setValueAtTime(v, t + d - 0.1); g.gain.linearRampToValueAtTime(0.0001, t + d + 0.25);
      lp.connect(g); g.connect(music.bus);
      for (const det of [-9, 0, 8]) { const o = ctx.createOscillator(); o.type = 'sawtooth'; o.frequency.value = hz(m); o.detune.value = det; o.connect(lp); track(o, t, t + d + 0.3); }
    };
    const bass = (m, t, d, v) => {
      const o = ctx.createOscillator(), g = ctx.createGain(); o.type = 'triangle'; o.frequency.value = hz(m);
      g.gain.setValueAtTime(0.0001, t); g.gain.linearRampToValueAtTime(v, t + 0.02); g.gain.exponentialRampToValueAtTime(0.001, t + d);
      o.connect(g); g.connect(music.bus); track(o, t, t + d + 0.05);
    };
    const timp = (m, t, v) => {
      const o = ctx.createOscillator(), g = ctx.createGain(); o.type = 'sine';
      o.frequency.setValueAtTime(hz(m) * 1.35, t); o.frequency.exponentialRampToValueAtTime(hz(m), t + 0.06);
      g.gain.setValueAtTime(0.0001, t); g.gain.linearRampToValueAtTime(v, t + 0.006); g.gain.exponentialRampToValueAtTime(0.001, t + 0.7);
      o.connect(g); g.connect(music.bus); track(o, t, t + 0.75);
    };
    const noise = (t, d, v, type, f, q) => {
      const src = ctx.createBufferSource(), fl = ctx.createBiquadFilter(), g = ctx.createGain();
      src.buffer = this.noiseBuf; src.loop = true; fl.type = type; fl.frequency.value = f; fl.Q.value = q;
      g.gain.setValueAtTime(0.0001, t); g.gain.linearRampToValueAtTime(v, t + 0.004); g.gain.exponentialRampToValueAtTime(0.0006, t + d);
      src.connect(fl); fl.connect(g); g.connect(music.bus); track(src, t, t + d + 0.05);
    };
    const snare = (t, v) => { noise(t, 0.11, v, 'bandpass', 2400, 0.7); };
    const crash = (t, v) => { noise(t, 2.4, v, 'highpass', 5200, 0.5); };

    // 和音(根音と3つの音)と主題。主題は [拍, 長さ(拍), 音の高さ] の並び
    const CH = { C: [36, 60, 64, 67], F: [41, 60, 65, 69], G: [43, 59, 62, 67], Am: [45, 60, 64, 69], Dm: [38, 62, 65, 69], Ab: [44, 60, 63, 68], Bb: [46, 62, 65, 70] };
    const bars = [
      ['C', [[0, 1.5, 67], [1.5, 0.5, 72], [2, 2, 76]]], ['C', [[0, 3, 79], [3, 1, 76]]],
      ['F', [[0, 1.5, 77], [1.5, 0.5, 81], [2, 2, 84]]], ['G', [[0, 1, 83], [1, 1, 79], [2, 2, 74]]],
      ['Am', [[0, 1.5, 76], [1.5, 0.5, 81], [2, 2, 84]]], ['F', [[0, 1, 81], [1, 1, 77], [2, 2, 72]]],
      ['Dm', [[0, 1, 74], [1, 1, 77], [2, 1, 81], [3, 1, 86]]], ['G', [[0, 3, 83], [3, 0.5, 79], [3.5, 0.5, 79]]],
      ['Ab', [[0, 2, 84], [2, 1, 80], [3, 1, 75]]], ['Bb', [[0, 2, 86], [2, 1, 82], [3, 1, 77]]],
      ['C', [[0, 3, 88], [3, 1, 84]]], ['C', [[0, 1, 79], [1, 1, 84], [2, 1, 88], [3, 1, 91]]],
      ['F', [[0, 1.5, 81], [1.5, 0.5, 84], [2, 2, 89]]], ['G', [[0, 1, 86], [1, 1, 83], [2, 2, 79]]],
      ['Ab', [[0, 1, 80], [1, 1, 84], [2, 1, 82], [3, 1, 86]]], ['C', [[0, 4, 84]]],
    ];
    // 主題の下でハモる音: 主題より3半音以上低い、いちばん近い和音の音
    const under = (m, c) => { for (let x = m - 3; x > m - 12; x--) if (c.slice(1).some((n) => (x - n) % 12 === 0)) return x; return m - 12; };
    music.next = Math.max(music.next, ctx.currentTime);
    while (music.next < ctx.currentTime + 0.3) {
      const t = music.next;
      if (music.bar < 0) {
        // 幕開け: ティンパニのロールがふくらみ、金管が駆け上がる
        for (let q = 0; q < 16; q++) timp(q % 2 ? 43 : 36, t + q * B / 4, 0.05 + 0.2 * (q / 15) ** 2);
        [[2, 67], [2.5, 72], [3, 76], [3.5, 79]].forEach(([b, m]) => { brass(m, t + b * B, B * 0.45, 0.1); brass(m - 12, t + b * B, B * 0.45, 0.08); });
        for (let q = 0; q < 8; q++) snare(t + 2 * B + q * B / 4, 0.03 + 0.012 * q);
      } else {
        const [name, mel] = bars[music.bar % 16], c = CH[name], big = music.bar % 16 >= 8;
        if (music.bar % 8 === 0) crash(t, 0.16);
        for (const [b, d, m] of mel) { brass(m, t + b * B, d * B * 0.92, 0.1); brass(m - 12, t + b * B, d * B * 0.92, 0.075); if (big) brass(under(m, c), t + b * B, d * B * 0.92, 0.045); }
        for (const m of c.slice(1)) { strings(m, t, 4 * B, 0.034); strings(m + 12, t, 4 * B, 0.02); }
        strings(c[0] + 12, t, 4 * B, 0.05);
        for (const b of [0, 1, 2, 3]) bass(b % 2 ? c[0] + 7 : c[0], t + b * B, B * 0.9, 0.16);
        timp(c[0], t, 0.26); timp(c[0] + 7, t + 2 * B, 0.17); if (music.bar % 4 === 3) { timp(c[0] + 7, t + 3 * B, 0.15); timp(c[0] + 7, t + 3.5 * B, 0.2); }
        for (const [b, v] of [[0, 0.06], [1, 0.075], [1.5, 0.04], [2, 0.06], [3, 0.075], [3.5, 0.04], [3.75, 0.04]]) snare(t + b * B, v);
      }
      music.next += 4 * B; music.bar++;
    }
  }

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
