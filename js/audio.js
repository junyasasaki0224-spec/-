// ============================================================
//  サウンド: すべてWeb Audioでその場合成 (音源ファイル不要・楽曲はオリジナル)
//  BGM(メニュー/レース/ファンファーレ/結果) + 環境音(歓声・蹄音・風・雨) + 実況(音声合成)
// ============================================================
const mtof = (m) => 440 * Math.pow(2, (m - 69) / 12);

export class Sound {
  constructor() {
    this.ctx = null; this.musicOn = true; this.sfxOn = true; this.voiceOn = true; this.raceBgm = true;
    this.song = null; this.step = 0; this.timer = null; this.intensity = 0; this.lastHoof = 0;
  }
  init() {
    if (this.ctx) { if (this.ctx.state === 'suspended') this.ctx.resume(); return; }
    const AC = window.AudioContext || window.webkitAudioContext;
    if (!AC) return;
    const c = (this.ctx = new AC());
    this.master = c.createGain(); this.master.gain.value = 0.9;
    const comp = c.createDynamicsCompressor(); comp.threshold.value = -14; comp.ratio.value = 5;
    this.master.connect(comp); comp.connect(c.destination);
    this.music = c.createGain(); this.music.gain.value = 0.5; this.music.connect(this.master);
    this.sfx = c.createGain(); this.sfx.gain.value = 0.9; this.sfx.connect(this.master);
    // 簡易リバーブ(ディレイ)
    const dl = c.createDelay(0.5); dl.delayTime.value = 0.19; const fb = c.createGain(); fb.gain.value = 0.28; const wet = c.createGain(); wet.gain.value = 0.22;
    this.music.connect(dl); dl.connect(fb); fb.connect(dl); dl.connect(wet); wet.connect(this.master);
    // ノイズ
    const len = c.sampleRate * 2, buf = c.createBuffer(1, len, c.sampleRate), d = buf.getChannelData(0);
    for (let i = 0; i < len; i++) d[i] = Math.random() * 2 - 1;
    this.noise = buf;
    // 環境音レイヤー
    const layer = (type, freq, q) => {
      const s = c.createBufferSource(); s.buffer = buf; s.loop = true; s.playbackRate.value = 0.8 + Math.random() * 0.4;
      const f = c.createBiquadFilter(); f.type = type; f.frequency.value = freq; f.Q.value = q;
      const g = c.createGain(); g.gain.value = 0; s.connect(f); f.connect(g); g.connect(this.sfx); s.start();
      return { g, f };
    };
    this.amb = { crowd: layer('bandpass', 850, 0.5), roar: layer('bandpass', 2100, 0.7), wind: layer('bandpass', 420, 0.8), rain: layer('highpass', 3800, 0.3), rumble: layer('lowpass', 110, 0.7) };
    this.timer = setInterval(() => this.tick(), 60);
  }
  setMusic(on) { this.musicOn = on; if (this.music) this.music.gain.setTargetAtTime(on ? 0.5 : 0, this.ctx.currentTime, 0.1); }

  // ---- 楽器 ----
  env(g, t, a, d, s, r, dur, vol) {
    g.gain.setValueAtTime(0.0001, t); g.gain.linearRampToValueAtTime(vol, t + a);
    g.gain.linearRampToValueAtTime(vol * s, t + a + d); g.gain.setValueAtTime(vol * s, Math.max(t + a + d, t + dur));
    g.gain.exponentialRampToValueAtTime(0.0001, t + dur + r);
  }
  osc(type, f, t, end, dest, det = 0) { const o = this.ctx.createOscillator(); o.type = type; o.frequency.value = f; o.detune.value = det; o.connect(dest); o.start(t); o.stop(end); return o; }
  brass(m, t, dur, vol = 0.2, out = this.music) {
    const c = this.ctx, f = c.createBiquadFilter(), g = c.createGain(); f.type = 'lowpass'; f.Q.value = 1.2;
    const fr = mtof(m);
    f.frequency.setValueAtTime(fr * 1.2, t); f.frequency.linearRampToValueAtTime(fr * 5, t + 0.06); f.frequency.linearRampToValueAtTime(fr * 2.6, t + dur);
    this.env(g, t, 0.03, 0.08, 0.8, 0.12, dur, vol); f.connect(g); g.connect(out);
    this.osc('sawtooth', fr, t, t + dur + 0.2, f, -7); this.osc('sawtooth', fr, t, t + dur + 0.2, f, 7);
  }
  strings(m, t, dur, vol = 0.08, out = this.music) {
    const c = this.ctx, f = c.createBiquadFilter(), g = c.createGain(); f.type = 'lowpass'; f.frequency.value = 2200;
    this.env(g, t, Math.min(0.09, dur * 0.4), 0.05, 0.9, 0.18, dur, vol); f.connect(g); g.connect(out);
    const fr = mtof(m); this.osc('sawtooth', fr, t, t + dur + 0.3, f, -9); this.osc('sawtooth', fr, t, t + dur + 0.3, f, 9);
  }
  keys(m, t, dur, vol = 0.14, out = this.music) {
    const g = this.ctx.createGain(); g.gain.setValueAtTime(vol, t); g.gain.exponentialRampToValueAtTime(0.0001, t + dur + 0.5); g.connect(out);
    const fr = mtof(m); this.osc('sine', fr, t, t + dur + 0.6, g); const g2 = this.ctx.createGain(); g2.gain.value = 0.3; g2.connect(g); this.osc('triangle', fr * 2, t, t + dur + 0.6, g2);
  }
  bass(m, t, dur, vol = 0.22, out = this.music) {
    const c = this.ctx, f = c.createBiquadFilter(), g = c.createGain(); f.type = 'lowpass'; f.frequency.value = 500;
    this.env(g, t, 0.01, 0.06, 0.7, 0.06, dur, vol); f.connect(g); g.connect(out);
    const fr = mtof(m); this.osc('triangle', fr, t, t + dur + 0.1, f); this.osc('sawtooth', fr, t, t + dur + 0.1, f, 4).connect(f);
  }
  nz(t, dur, type, freq, vol, out = this.music, q = 0.8) {
    const c = this.ctx, s = c.createBufferSource(); s.buffer = this.noise; s.loop = true;
    const f = c.createBiquadFilter(); f.type = type; f.frequency.value = freq; f.Q.value = q;
    const g = c.createGain(); g.gain.setValueAtTime(vol, t); g.gain.exponentialRampToValueAtTime(0.0001, t + dur);
    s.connect(f); f.connect(g); g.connect(out); s.start(t, Math.random()); s.stop(t + dur + 0.02);
  }
  kick(t, vol = 0.5, out = this.music) {
    const o = this.ctx.createOscillator(), g = this.ctx.createGain(); o.frequency.setValueAtTime(130, t); o.frequency.exponentialRampToValueAtTime(42, t + 0.14);
    g.gain.setValueAtTime(vol, t); g.gain.exponentialRampToValueAtTime(0.0001, t + 0.2); o.connect(g); g.connect(out); o.start(t); o.stop(t + 0.22);
  }
  snare(t, vol = 0.25, out = this.music) { this.nz(t, 0.14, 'bandpass', 1900, vol, out, 0.6); const g = this.ctx.createGain(); g.gain.setValueAtTime(vol * 0.5, t); g.gain.exponentialRampToValueAtTime(0.0001, t + 0.08); g.connect(out); this.osc('triangle', 190, t, t + 0.1, g); }
  hat(t, vol = 0.07, out = this.music) { this.nz(t, 0.04, 'highpass', 7500, vol, out); }
  timp(m, t, vol = 0.5, out = this.music) {
    const o = this.ctx.createOscillator(), g = this.ctx.createGain(), fr = mtof(m); o.frequency.setValueAtTime(fr * 1.12, t); o.frequency.exponentialRampToValueAtTime(fr, t + 0.08);
    g.gain.setValueAtTime(vol, t); g.gain.exponentialRampToValueAtTime(0.0001, t + 0.9); o.connect(g); g.connect(out); o.start(t); o.stop(t + 1); this.nz(t, 0.05, 'lowpass', 300, vol * 0.6, out);
  }
  cym(t, vol = 0.2, dur = 1.6, out = this.music) { this.nz(t, dur, 'highpass', 5200, vol, out); }

  // ---- シーケンサ ----
  play(name) {
    if (!this.ctx) return;
    if (this.song && this.song.name === name) return;
    this.song = SONGS[name] ? { ...SONGS[name], name } : null;
    this.step = 0; this.t0 = this.ctx.currentTime + 0.08;
  }
  stop() { this.song = null; }
  tick() {
    const c = this.ctx; if (!c || !this.song) return;
    const s = this.song, sd = 60 / s.bpm / 4;
    while (this.t0 + this.step * sd < c.currentTime + 0.22) {
      const i = this.step % s.len;
      if (this.t0 + this.step * sd >= c.currentTime - 0.05) s.fn(this, i, this.t0 + this.step * sd, sd);
      this.step++;
      if (!s.loop && this.step >= s.len) { this.song = null; break; }
    }
  }

  // ---- ファンファーレ (オリジナル) ----
  fanfare() {
    if (!this.ctx) return 8.5;
    this.stop();
    const t0 = this.ctx.currentTime + 0.15, b = 60 / 132, T = 1 / 3;
    const mel = [[0, 70, T], [T, 70, T], [2 * T, 70, T], [1, 75, 1], [2, 79, 0.5], [2.5, 75, 0.5], [3, 79, 1],
      [4, 82, 1.5], [5.5, 80, 0.5], [6, 79, 1], [7, 77, 1],
      [8, 75, T], [8 + T, 75, T], [8 + 2 * T, 75, T], [9, 80, 1], [10, 84, 0.5], [10.5, 80, 0.5], [11, 84, 1],
      [12, 82, 1], [13, 79, 0.5], [13.5, 82, 0.5], [14, 87, 3.6]];
    for (const [bt, m, d] of mel) {
      this.brass(m, t0 + bt * b, d * b * 0.92, 0.2); this.brass(m - (bt >= 14 ? 5 : 4), t0 + bt * b, d * b * 0.92, 0.13); this.brass(m - (bt >= 14 ? 8 : 9), t0 + bt * b, d * b * 0.92, 0.11);
    }
    const bassL = [[0, 39, 2], [2, 39, 2], [4, 39, 2], [6, 46, 2], [8, 44, 2], [10, 44, 2], [12, 46, 2], [14, 39, 3.6]];
    for (const [bt, m, d] of bassL) { this.bass(m, t0 + bt * b, d * b * 0.9, 0.3); this.timp(m + 12, t0 + bt * b, 0.4); }
    for (let i = 0; i < 16; i++) { this.snare(t0 + i * b, 0.16); if (i % 4 === 3) { this.snare(t0 + (i + 0.5) * b, 0.12); this.snare(t0 + (i + 0.75) * b, 0.12); } }
    for (let i = 0; i < 14; i++) this.snare(t0 + (14 + i * 0.125) * b, 0.06 + i * 0.012);
    this.cym(t0 + 14 * b, 0.25, 3); this.cym(t0 + 16 * b, 0.2, 2.5); this.timp(51, t0 + 16 * b, 0.5);
    return 17.8 * b + 0.4;
  }
  jingle(win) {
    if (!this.ctx) return;
    const t = this.ctx.currentTime + 0.05;
    if (win) { [[0, 72], [0.14, 76], [0.28, 79], [0.42, 84]].forEach(([d, m]) => this.brass(m, t + d, 0.14, 0.2)); for (const m of [72, 76, 79, 84, 88]) this.brass(m, t + 0.6, 1.5, 0.1); this.cym(t + 0.6, 0.2, 2); this.timp(48, t + 0.6, 0.5); }
    else { [[0, 67], [0.3, 64], [0.6, 60]].forEach(([d, m]) => this.strings(m, t + d, 0.5, 0.1)); for (const m of [48, 55, 60, 63]) this.strings(m, t + 0.9, 1.6, 0.06); }
  }

  // ---- 効果音 ----
  gate() {
    if (!this.ctx) return; const t = this.ctx.currentTime, o = this.sfx;
    this.nz(t, 0.25, 'bandpass', 2600, 0.7, o, 1.5); this.nz(t, 0.12, 'lowpass', 400, 0.8, o);
    for (const f of [820, 1240, 1710]) { const g = this.ctx.createGain(); g.gain.setValueAtTime(0.12, t); g.gain.exponentialRampToValueAtTime(0.0001, t + 0.5); g.connect(o); this.osc('square', f, t, t + 0.5, g); }
  }
  whip(good) { if (!this.ctx) return; const t = this.ctx.currentTime; this.nz(t, 0.05, 'highpass', good ? 3500 : 2200, good ? 0.6 : 0.4, this.sfx); this.nz(t + 0.01, 0.09, 'bandpass', 900, 0.3, this.sfx); }
  click() { if (!this.ctx) return; const t = this.ctx.currentTime; this.keys(84, t, 0.05, 0.1, this.sfx); }
  chime(m = 88) { if (!this.ctx) return; const t = this.ctx.currentTime; this.keys(m, t, 0.2, 0.14, this.sfx); this.keys(m + 4, t + 0.08, 0.3, 0.1, this.sfx); }
  buzz() { if (!this.ctx) return; const t = this.ctx.currentTime; const g = this.ctx.createGain(); g.gain.setValueAtTime(0.1, t); g.gain.exponentialRampToValueAtTime(0.0001, t + 0.25); g.connect(this.sfx); this.osc('square', 110, t, t + 0.25, g); }
  bump() { if (!this.ctx) return; this.nz(this.ctx.currentTime, 0.12, 'lowpass', 260, 0.9, this.sfx); }
  thump(vol, pitch) {
    const c = this.ctx, t = c.currentTime, o = c.createOscillator(), g = c.createGain();
    o.frequency.setValueAtTime(pitch, t); o.frequency.exponentialRampToValueAtTime(pitch * 0.55, t + 0.06);
    g.gain.setValueAtTime(vol, t); g.gain.exponentialRampToValueAtTime(0.0001, t + 0.09); o.connect(g); g.connect(this.sfx); o.start(t); o.stop(t + 0.1);
    this.nz(t, 0.035, 'lowpass', 600, vol * 0.5, this.sfx);
  }
  // 毎フレーム: 蹄音と環境音の更新
  update(o) {
    if (!this.ctx) return;
    const t = this.ctx.currentTime, a = this.amb, set = (n, v) => n.g.gain.setTargetAtTime(this.sfxOn ? v : 0, t, 0.25);
    set(a.crowd, o.crowd * 0.35); set(a.roar, o.roar * 0.3); set(a.wind, o.wind * 0.16); set(a.rain, o.rain * 0.1); set(a.rumble, o.rumble * 0.5);
    a.wind.f.frequency.setTargetAtTime(300 + o.wind * 500, t, 0.3);
    if (this.sfxOn && o.speed > 3) {
      const beats = [0, 0.12, 0.5, 0.62], ph = o.phase % 1, lp = this.lastHoof % 1;
      for (const b of beats) if ((lp < b && ph >= b) || (lp > ph && (b > lp || b <= ph))) this.thump(0.16 + Math.random() * 0.06, o.wet ? 62 : 82 + Math.random() * 14);
    }
    this.lastHoof = o.phase;
  }
  silence() { this.update({ crowd: 0, roar: 0, wind: 0, rain: 0, rumble: 0, speed: 0, phase: 0 }); }

  // ---- 実況 (ブラウザの音声合成) ----
  say(text, urgent) {
    if (!this.voiceOn || !window.speechSynthesis) return;
    try {
      const ss = window.speechSynthesis;
      if (urgent || ss.pending) ss.cancel();
      const u = new SpeechSynthesisUtterance(text);
      u.lang = 'ja-JP'; u.rate = 1.3; u.pitch = 1.05; u.volume = 0.9;
      const v = ss.getVoices().find((x) => x.lang && x.lang.startsWith('ja'));
      if (v) u.voice = v;
      ss.speak(u);
    } catch (e) { /* 音声合成が使えない環境 */ }
  }
  hush() { try { window.speechSynthesis && window.speechSynthesis.cancel(); } catch (e) { /* noop */ } }
}

// ---- 楽曲データ (すべて本作のための書き下ろし) ----
const MENU_CH = [[48, 55, 64, 67], [45, 57, 60, 64], [41, 57, 60, 65], [43, 55, 59, 62], [40, 55, 59, 64], [45, 57, 60, 64], [38, 57, 62, 65], [43, 55, 59, 65]];
const MENU_MEL = [
  [[0, 76, 4], [4, 79, 2], [6, 81, 2], [8, 79, 6], [14, 76, 2]], [[0, 72, 4], [4, 76, 4], [8, 74, 2], [10, 72, 2], [12, 69, 4]],
  [[0, 69, 2], [2, 72, 2], [4, 77, 4], [8, 76, 4], [12, 72, 4]], [[0, 74, 6], [6, 71, 2], [8, 74, 4], [12, 79, 4]],
  [[0, 79, 4], [4, 76, 2], [6, 79, 2], [8, 83, 6], [14, 79, 2]], [[0, 81, 4], [4, 79, 2], [6, 76, 2], [8, 72, 4], [12, 76, 4]],
  [[0, 77, 4], [4, 74, 4], [8, 69, 2], [10, 74, 2], [12, 77, 4]], [[0, 79, 8], [8, 74, 4], [12, 71, 4]],
];
const RACE_CH = [[38, 62, 65, 69], [38, 62, 65, 69], [34, 58, 62, 65], [36, 60, 64, 67], [38, 62, 65, 69], [41, 60, 65, 69], [43, 58, 62, 67], [45, 61, 64, 69]];
const RACE_MEL = [
  [[0, 74, 6], [6, 77, 2], [8, 81, 8]], [[0, 79, 4], [4, 77, 4], [8, 76, 4], [12, 74, 4]],
  [[0, 70, 6], [6, 74, 2], [8, 77, 8]], [[0, 76, 4], [4, 79, 4], [8, 84, 8]],
  [[0, 81, 6], [6, 79, 2], [8, 77, 4], [12, 74, 4]], [[0, 72, 4], [4, 77, 4], [8, 81, 6], [14, 84, 2]],
  [[0, 82, 4], [4, 81, 4], [8, 79, 4], [12, 82, 4]], [[0, 81, 8], [8, 73, 4], [12, 76, 4]],
];
const SONGS = {
  menu: {
    bpm: 92, len: 128, loop: true,
    fn(S, i, t, sd) {
      const bar = (i / 16) | 0, st = i % 16, ch = MENU_CH[bar];
      if (st === 0) for (let k = 1; k < 4; k++) S.strings(ch[k], t, sd * 15, 0.035);
      if (st % 2 === 0) S.keys(ch[1 + ((st / 2) % 3)] + 12, t, sd * 1.5, 0.05);
      if (st === 0 || st === 10) S.bass(ch[0], t, sd * (st ? 5 : 8), 0.2);
      if (st === 0 || st === 8) S.kick(t, 0.22);
      if (st === 4 || st === 12) S.nz(t, 0.05, 'bandpass', 1500, 0.07, S.music, 2);
      if (st % 2 === 0) S.hat(t, st % 4 === 2 ? 0.045 : 0.025);
      for (const [s0, m, l] of MENU_MEL[bar]) if (s0 === st) S.keys(m, t, sd * l * 0.9, 0.13);
    },
  },
  race: {
    bpm: 156, len: 128, loop: true,
    fn(S, i, t, sd) {
      const bar = (i / 16) | 0, st = i % 16, ch = RACE_CH[bar], I = S.intensity;
      const gal = st % 4 !== 1; // タタッタ タタッタ: 蹄のリズム
      if (gal) S.strings(ch[1 + (st % 8 < 4 ? 0 : 2)] - (st % 4 === 0 ? 12 : 0), t, sd * 0.8, 0.045 + I * 0.012);
      if (st % 2 === 0) S.bass(ch[0], t, sd * 1.6, 0.2);
      if (st === 0) for (let k = 1; k < 4; k++) S.strings(ch[k] + 12, t, sd * 15, 0.02 + I * 0.008);
      if (I >= 1) { if (st % 4 === 0) S.kick(t, 0.36); if (st === 4 || st === 12) S.snare(t, 0.16); if (st % 2 === 0) S.hat(t, 0.04); if (st === 14 || st === 15) S.snare(t, 0.07); }
      else if (st % 4 === 0) S.hat(t, 0.03);
      if (I >= 2) { for (const [s0, m, l] of RACE_MEL[bar]) if (s0 === st) { S.brass(m, t, sd * l * 0.92, 0.15); S.brass(m - 12, t, sd * l * 0.92, 0.08); } if (i === 0) S.cym(t, 0.18, 2); }
    },
  },
};
