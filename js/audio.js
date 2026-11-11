// ============================================================
//  サウンドエンジン: すべて Web Audio でその場合成 (音源ファイル不要・楽曲はオリジナル)
//   ・BGM: タイトル / 出馬表 / ファンファーレ / レース(展開で3段階に厚くなる) / 勝利
//   ・場内: 歓声(うねり・手拍子・指笛)、ゲート、蹄音(自馬+周囲の馬を左右に定位)、
//           馬の息づかい、ムチ、風、雨、接触
//   ・実況: ブラウザの音声合成
//  ホールの残響(畳み込みリバーブ)とリミッターを通して出力する
// ============================================================
import { synthHoof, synthBreath, synthTack, GALLOP_BEATS, GALLOP_ACCENT, GALLOP_RATE } from './hoof.js';
import { synthCrowd, CROWD_SR } from './crowd.js';
const mtof = (m) => 440 * Math.pow(2, (m - 69) / 12);

export class Sound {
  constructor() {
    this.ctx = null; this.musicOn = true; this.sfxOn = true; this.voiceOn = false; this.raceBgm = true; // 実況の読み上げは廃止 (歓声で展開を表現する)
    this.vol = { master: 0.9, music: 0.8, sfx: 1.0 };
    this.song = null; this.step = 0; this.timer = null; this.intensity = 0;
    this.lastPh = 0; this.nearPh = {}; this.swell = 0; this.nextCrowdFx = 0; this.clapUntil = 0;
  }

  // ---- 起動: ユーザー操作のたびに呼ぶ (ブラウザは操作なしに音を出せない) ----
  unlock() {
    const AC = window.AudioContext || window.webkitAudioContext;
    if (!AC) return false;
    if (!this.ctx) { this.ctx = new AC(); this.build(); }
    if (this.ctx.state !== 'running') { const p = this.ctx.resume(); if (p && p.catch) p.catch(() => {}); }
    // iPhone/iPad: 消音スイッチがオンでも鳴るよう、再生カテゴリに切り替える
    try { if (navigator.audioSession) navigator.audioSession.type = 'playback'; } catch (e) { /* 未対応 */ }
    if (!this.silentEl) {
      try {
        const n = 4000, b = new Uint8Array(44 + n), dv = new DataView(b.buffer), w = (o, s) => { for (let i = 0; i < s.length; i++) b[o + i] = s.charCodeAt(i); };
        w(0, 'RIFF'); dv.setUint32(4, 36 + n, true); w(8, 'WAVEfmt '); dv.setUint32(16, 16, true); dv.setUint16(20, 1, true); dv.setUint16(22, 1, true);
        dv.setUint32(24, 8000, true); dv.setUint32(28, 8000, true); dv.setUint16(32, 1, true); dv.setUint16(34, 8, true); w(36, 'data'); dv.setUint32(40, n, true);
        b.fill(128, 44);
        let s = ''; for (let i = 0; i < b.length; i++) s += String.fromCharCode(b[i]);
        const a = new Audio('data:audio/wav;base64,' + btoa(s)); a.loop = true; a.setAttribute('playsinline', '');
        const p = a.play(); if (p && p.catch) p.catch(() => {});
        this.silentEl = a;
      } catch (e) { /* 使えない環境では無視 */ }
    }
    return this.ctx.state === 'running';
  }
  init() { return this.unlock(); }
  get running() { return !!this.ctx && this.ctx.state === 'running'; }

  build() {
    const c = this.ctx;
    this.master = c.createGain(); this.master.gain.value = this.vol.master;
    const lim = c.createDynamicsCompressor(); lim.threshold.value = -9; lim.knee.value = 8; lim.ratio.value = 14; lim.attack.value = 0.003; lim.release.value = 0.18;
    this.master.connect(lim); lim.connect(c.destination);
    // 残響
    const len = Math.floor(c.sampleRate * 2.3), ir = c.createBuffer(2, len, c.sampleRate);
    for (let ch = 0; ch < 2; ch++) {
      const d = ir.getChannelData(ch); let lp = 0;
      for (let i = 0; i < len; i++) { const t = i / c.sampleRate, n = Math.random() * 2 - 1; lp += (n - lp) * 0.45; d[i] = lp * Math.exp(-t * 2.7) * (t < 0.012 ? t / 0.012 : 1); }
    }
    this.rev = c.createConvolver(); this.rev.buffer = ir;
    const revOut = c.createGain(); revOut.gain.value = 0.9; this.rev.connect(revOut); revOut.connect(this.master);
    const bus = (g, send) => { const b = c.createGain(); b.gain.value = g; b.connect(this.master); if (send) { const s = c.createGain(); s.gain.value = send; b.connect(s); s.connect(this.rev); } return b; };
    this.music = bus(this.vol.music, 0.3);
    // 効果音(蹄音など)は瞬間的なピークが大きいので専用のコンプレッサーで整えてから混ぜる
    const sc = c.createDynamicsCompressor(); sc.threshold.value = -16; sc.knee.value = 6; sc.ratio.value = 6; sc.attack.value = 0.001; sc.release.value = 0.07;
    const scOut = c.createGain(); scOut.gain.value = 1.25; sc.connect(scOut); scOut.connect(this.master);
    this.sfx = c.createGain(); this.sfx.gain.value = this.vol.sfx; this.sfx.connect(sc);
    { const sd = c.createGain(); sd.gain.value = 0.05; this.sfx.connect(sd); sd.connect(this.rev); } this.crowdBus = bus(this.vol.sfx, 0.22); this.ui = bus(0.8, 0.05);
    // ノイズ素材
    const nl = c.sampleRate * 3, nb = c.createBuffer(1, nl, c.sampleRate), nd = nb.getChannelData(0);
    for (let i = 0; i < nl; i++) nd[i] = Math.random() * 2 - 1;
    this.noise = nb;
    const layer = (type, freq, q, out) => {
      const s = c.createBufferSource(); s.buffer = nb; s.loop = true; s.playbackRate.value = 0.7 + Math.random() * 0.5;
      const f = c.createBiquadFilter(); f.type = type; f.frequency.value = freq; f.Q.value = q;
      const g = c.createGain(); g.gain.value = 0; s.connect(f); f.connect(g); g.connect(out); s.start();
      return { g, f };
    };
    // 歓声は帯域の違う層を重ね、ゆっくり揺らす
    this.amb = {
      murmur: layer('bandpass', 520, 0.45, this.crowdBus), crowd: layer('bandpass', 1100, 0.5, this.crowdBus), roar: layer('bandpass', 2300, 0.6, this.crowdBus),
      wind: layer('bandpass', 420, 0.8, this.sfx), rain: layer('highpass', 3600, 0.3, this.sfx), rumble: layer('lowpass', 150, 0.7, this.sfx),
    };
    for (const k of ['murmur', 'crowd', 'roar']) { const l = c.createOscillator(), lg = c.createGain(); l.frequency.value = 0.13 + Math.random() * 0.2; lg.gain.value = this.amb[k].f.frequency.value * 0.18; l.connect(lg); lg.connect(this.amb[k].f.frequency); l.start(); }
    // 蹄音専用のバス: 粒を揃えるコンプレッサー + スタンドからの反響 (スタンド前で強くなる)
    const hc = c.createDynamicsCompressor(); hc.threshold.value = -20; hc.knee.value = 10; hc.ratio.value = 4; hc.attack.value = 0.004; hc.release.value = 0.12;
    this.hoofBus = c.createGain(); this.hoofBus.gain.value = this.vol.sfx; this.hoofBus.connect(hc);
    const hm = c.createGain(); hm.gain.value = 1.35; hc.connect(hm); hm.connect(this.master);
    const dl = c.createDelay(0.3); dl.delayTime.value = 0.105; const dlf = c.createBiquadFilter(); dlf.type = 'lowpass'; dlf.frequency.value = 2000;
    this.echoG = c.createGain(); this.echoG.gain.value = 0; hm.connect(dl); dl.connect(dlf); dlf.connect(this.echoG); this.echoG.connect(this.master);
    { const rs = c.createGain(); rs.gain.value = 0.05; hm.connect(rs); rs.connect(this.rev); }
    // 蹄音・呼吸・馬具の音を合成して貯めておく (画面が固まらないよう少しずつ)
    const sr = c.sampleRate, toBuf = (arr) => { const b = c.createBuffer(1, arr.length, sr); b.getChannelData(0).set(arr); return b; };
    this.bank = { dry: [], wet: [], breath: [], inhale: [], tack: [] };
    this.bankJobs = [];
    for (let k = 0; k < 6; k++) this.bankJobs.push(['dry', () => synthHoof(sr, 101 + k, false)]);
    for (let k = 0; k < 3; k++) this.bankJobs.push(['breath', () => synthBreath(sr, 301 + k)]);
    for (let k = 0; k < 2; k++) this.bankJobs.push(['inhale', () => synthBreath(sr, 401 + k, true)]);
    for (let k = 0; k < 3; k++) this.bankJobs.push(['tack', () => synthTack(sr, 501 + k)]);
    for (let k = 0; k < 6; k++) this.bankJobs.push(['wet', () => synthHoof(sr, 201 + k, true)]);
    this.toBuf = toBuf;
    this.buildCrowd();
    this.newFan();
    this.timer = setInterval(() => this.tick(), 50);
  }
  // ---- 観客の声 ----
  buildCrowd() {
    const c = this.ctx;
    this.crowdPan = c.createStereoPanner ? c.createStereoPanner() : c.createGain(); this.crowdPan.connect(this.crowdBus);
    this.crowdLoops = {};
    for (const k of ['murmur', 'roar']) { const g = c.createGain(); g.gain.value = 0; g.connect(this.crowdPan); this.crowdLoops[k] = { g, src: null }; }
    this.voice = { swell: [], gasp: [] };
    const jobs = [['murmur', [11, 23], 8], ['roar', [31, 43], 8], ['swell', [51, 63], 6], ['gasp', [91, 97], 2.5], ['swell', [71, 83], 6]];
    const done = (kind, chans) => {
      const b = c.createBuffer(chans.length, chans[0].length, CROWD_SR);
      chans.forEach((ch, i) => b.getChannelData(i).set(ch));
      if (kind === 'murmur' || kind === 'roar') {
        const src = c.createBufferSource(); src.buffer = b; src.loop = true; src.connect(this.crowdLoops[kind].g); src.start(); this.crowdLoops[kind].src = src;
      } else if (kind === 'gasp') { for (const ch of chans) { const m = c.createBuffer(1, ch.length, CROWD_SR); m.getChannelData(0).set(ch); this.voice.gasp.push(m); } }
      else this.voice.swell.push(b);
    };
    let worker = null;
    try { worker = new Worker(new URL('./sfx-worker.js', import.meta.url), { type: 'module' }); } catch (e) { worker = null; }
    const fallback = () => { // 裏のスレッドが使えない環境: 少しずつメインで作る
      for (const [kind, seeds, dur] of jobs) if (!this.crowdDone[kind + seeds[0]]) this.bankJobs.push([null, () => { done(kind, seeds.map((sd) => synthCrowd(CROWD_SR, sd, kind, dur))); this.crowdDone[kind + seeds[0]] = 1; return null; }]);
    };
    this.crowdDone = {};
    if (worker) {
      worker.onmessage = (e) => { const [kind, seeds] = jobs[e.data.id]; done(kind, e.data.chans); this.crowdDone[kind + seeds[0]] = 1; };
      worker.onerror = () => { worker.terminate(); fallback(); };
      jobs.forEach(([kind, seeds, dur], id) => worker.postMessage({ id, sr: CROWD_SR, kind, seeds, dur }));
    } else fallback();
  }
  // ファンファーレ専用の経路 (スキップ時にまとめて止められるように)
  newFan() { const c = this.ctx; this.fan = c.createGain(); this.fan.gain.value = 0.72; this.fan.connect(this.music); this.fanCrowd = c.createGain(); this.fanCrowd.gain.value = 1; this.fanCrowd.connect(this.crowdBus); }
  cutFanfare() {
    if (!this.ctx || !this.fan) return; const t = this.ctx.currentTime, a = this.fan, b = this.fanCrowd;
    for (const g of [a, b]) { g.gain.cancelScheduledValues(t); g.gain.setTargetAtTime(0, t, 0.06); }
    setTimeout(() => { try { a.disconnect(); b.disconnect(); } catch (e) { /* noop */ } }, 600);
    this.newFan();
  }
  setVolume(kind, v) {
    this.vol[kind] = v; if (!this.ctx) return;
    const t = this.ctx.currentTime;
    if (kind === 'master') this.master.gain.setTargetAtTime(v, t, 0.05);
    if (kind === 'music') this.music.gain.setTargetAtTime(this.musicOn ? v * (this.musicScale || 1) : 0, t, 0.05);
    if (kind === 'sfx') { this.sfx.gain.setTargetAtTime(v, t, 0.05); this.crowdBus.gain.setTargetAtTime(v, t, 0.05); this.hoofBus.gain.setTargetAtTime(v, t, 0.05); }
  }
  setMusic(on) { this.musicOn = on; if (this.ctx) this.music.gain.setTargetAtTime(on ? this.vol.music * (this.musicScale || 1) : 0, this.ctx.currentTime, 0.1); }

  // ---- 楽器 ----
  adsr(g, t, a, d, s, r, dur, vol) {
    const p = g.gain; p.setValueAtTime(0.0001, t); p.linearRampToValueAtTime(vol, t + a);
    p.linearRampToValueAtTime(vol * s, t + a + d); p.setValueAtTime(vol * s, Math.max(t + a + d + 0.001, t + dur));
    p.exponentialRampToValueAtTime(0.0001, Math.max(t + a + d + 0.002, t + dur) + r);
  }
  osc(type, f, t, end, dest, det = 0, vib = 0) {
    const o = this.ctx.createOscillator(); o.type = type; o.frequency.value = f; o.detune.value = det;
    if (vib && end - t > 0.4) { // 伸ばす音にはビブラート
      const l = this.ctx.createOscillator(), lg = this.ctx.createGain(); l.frequency.value = 5.4; lg.gain.setValueAtTime(0, t + 0.16); lg.gain.linearRampToValueAtTime(vib, t + 0.4);
      l.connect(lg); lg.connect(o.detune); l.start(t); l.stop(end);
    }
    o.connect(dest); o.start(t); o.stop(end); return o;
  }
  brass(m, t, dur, vol = 0.2, out = this.music) {
    const c = this.ctx, f = c.createBiquadFilter(), g = c.createGain(), fr = mtof(m), end = t + dur + 0.25; f.type = 'lowpass'; f.Q.value = 1.8;
    f.frequency.setValueAtTime(fr * 1.4, t); f.frequency.linearRampToValueAtTime(Math.min(9000, fr * 6.5), t + 0.05); f.frequency.linearRampToValueAtTime(Math.min(7000, fr * 3.4), t + Math.max(0.12, dur));
    this.adsr(g, t, 0.03, 0.09, 0.82, 0.13, dur, vol); f.connect(g); g.connect(out);
    for (const d of [-8, 0, 7]) this.osc('sawtooth', fr, t, end, f, d, 8);
  }
  horn(m, t, dur, vol = 0.16, out = this.music) {
    const c = this.ctx, f = c.createBiquadFilter(), g = c.createGain(), fr = mtof(m), end = t + dur + 0.35; f.type = 'lowpass'; f.frequency.value = Math.min(4200, fr * 3.2); f.Q.value = 0.7;
    this.adsr(g, t, 0.07, 0.12, 0.85, 0.28, dur, vol); f.connect(g); g.connect(out);
    this.osc('sawtooth', fr, t, end, f, -5, 6); this.osc('triangle', fr, t, end, f, 5, 6); this.osc('sine', fr * 2, t, end, f, 0);
  }
  strings(m, t, dur, vol = 0.07, out = this.music) {
    const c = this.ctx, f = c.createBiquadFilter(), g = c.createGain(), fr = mtof(m), end = t + dur + 0.4; f.type = 'lowpass'; f.frequency.value = 2800; f.Q.value = 0.4;
    this.adsr(g, t, Math.min(0.14, dur * 0.4), 0.06, 0.92, 0.26, dur, vol); f.connect(g); g.connect(out);
    for (const d of [-11, 3, 10]) this.osc('sawtooth', fr, t, end, f, d, 5);
  }
  piano(m, t, dur, vol = 0.16, out = this.music) {
    const c = this.ctx, f = c.createBiquadFilter(), g = c.createGain(), fr = mtof(m), end = t + dur + 1.3; f.type = 'lowpass';
    f.frequency.setValueAtTime(Math.min(8000, fr * 7), t); f.frequency.exponentialRampToValueAtTime(Math.max(400, fr * 1.6), t + 0.9);
    g.gain.setValueAtTime(0.0001, t); g.gain.linearRampToValueAtTime(vol, t + 0.006); g.gain.exponentialRampToValueAtTime(vol * 0.32, t + 0.35); g.gain.exponentialRampToValueAtTime(0.0001, end);
    f.connect(g); g.connect(out);
    this.osc('triangle', fr, t, end, f, -3); this.osc('triangle', fr, t, end, f, 4); const h = c.createGain(); h.gain.value = 0.25; h.connect(f); this.osc('sine', fr * 2, t, end, h);
  }
  harp(m, t, vol = 0.1, out = this.music) {
    const g = this.ctx.createGain(), fr = mtof(m); g.gain.setValueAtTime(vol, t); g.gain.exponentialRampToValueAtTime(0.0001, t + 1.5); g.connect(out);
    this.osc('triangle', fr, t, t + 1.55, g); const h = this.ctx.createGain(); h.gain.value = 0.35; h.connect(g); this.osc('sine', fr * 3, t, t + 0.5, h);
  }
  bass(m, t, dur, vol = 0.24, out = this.music) {
    const c = this.ctx, f = c.createBiquadFilter(), g = c.createGain(), fr = mtof(m); f.type = 'lowpass'; f.frequency.setValueAtTime(700, t); f.frequency.exponentialRampToValueAtTime(260, t + 0.2);
    this.adsr(g, t, 0.012, 0.07, 0.75, 0.08, dur, vol); f.connect(g); g.connect(out);
    this.osc('sawtooth', fr, t, t + dur + 0.15, f); this.osc('sine', fr, t, t + dur + 0.15, g);
  }
  nz(t, dur, type, freq, vol, out = this.music, q = 0.8) {
    const c = this.ctx, s = c.createBufferSource(); s.buffer = this.noise; s.loop = true;
    const f = c.createBiquadFilter(); f.type = type; f.frequency.value = freq; f.Q.value = q;
    const g = c.createGain(); g.gain.setValueAtTime(vol, t); g.gain.exponentialRampToValueAtTime(0.0001, t + dur);
    s.connect(f); f.connect(g); g.connect(out); s.start(t, Math.random() * 2); s.stop(t + dur + 0.03);
    return g;
  }
  tone(type, f0, f1, t, dur, vol, out) {
    const o = this.ctx.createOscillator(), g = this.ctx.createGain(); o.type = type; o.frequency.setValueAtTime(f0, t); if (f1 !== f0) o.frequency.exponentialRampToValueAtTime(f1, t + dur);
    g.gain.setValueAtTime(vol, t); g.gain.exponentialRampToValueAtTime(0.0001, t + dur); o.connect(g); g.connect(out); o.start(t); o.stop(t + dur + 0.02);
  }
  kick(t, vol = 0.5, out = this.music) { this.tone('sine', 140, 44, t, 0.2, vol, out); this.nz(t, 0.02, 'lowpass', 900, vol * 0.4, out); }
  snare(t, vol = 0.25, out = this.music) { this.nz(t, 0.16, 'bandpass', 2100, vol, out, 0.5); this.nz(t, 0.09, 'highpass', 5000, vol * 0.5, out); this.tone('triangle', 196, 170, t, 0.09, vol * 0.6, out); }
  hat(t, vol = 0.07, out = this.music) { this.nz(t, 0.045, 'highpass', 7800, vol, out); }
  timp(m, t, vol = 0.5, out = this.music) { const fr = mtof(m); this.tone('sine', fr * 1.1, fr, t, 1.1, vol, out); this.tone('sine', fr * 1.5, fr * 1.5, t, 0.5, vol * 0.3, out); this.nz(t, 0.06, 'lowpass', 320, vol * 0.7, out); }
  cym(t, vol = 0.2, dur = 1.8, out = this.music) { this.nz(t, dur, 'highpass', 5200, vol, out); this.nz(t, dur * 0.6, 'bandpass', 3300, vol * 0.5, out, 2); }
  clap(t, vol = 0.2, out = this.crowdBus) { for (let i = 0; i < 3; i++) this.nz(t + i * 0.011 + Math.random() * 0.006, 0.07, 'bandpass', 1300 + Math.random() * 500, vol * (0.6 + Math.random() * 0.4), out, 1.2); }

  // ---- シーケンサ ----
  play(name) {
    if (!this.ctx) { this.pending = name; return; }
    if (this.song && this.song.name === name) return;
    this.song = SONGS[name] ? { ...SONGS[name], name } : null;
    this.step = 0; this.t0 = this.ctx.currentTime + 0.1;
    // レース中は蹄音と歓声を主役にするためBGMを一段下げる
    this.musicScale = name === 'race' ? 0.7 : 1; this.music.gain.setTargetAtTime(this.musicOn ? this.vol.music * this.musicScale : 0, this.ctx.currentTime, 0.3);
  }
  stop() { this.song = null; this.pending = null; if (this.ctx) { this.musicScale = 1; this.music.gain.setTargetAtTime(this.musicOn ? this.vol.music : 0, this.ctx.currentTime, 0.3); } }
  tick() {
    const c = this.ctx; if (!c) return;
    if (this.bankJobs.length) { const [k, fn] = this.bankJobs.shift(); const r = fn(); if (k) this.bank[k].push(this.toBuf(r)); }
    if (this.pending && c.state === 'running') { const p = this.pending; this.pending = null; this.play(p); }
    if (!this.song) return;
    const s = this.song, sd = 60 / s.bpm / 4;
    while (this.t0 + this.step * sd < c.currentTime + 0.25) {
      const i = this.step % s.len;
      if (this.t0 + this.step * sd >= c.currentTime - 0.04) s.fn(this, i, this.t0 + this.step * sd, sd, Math.floor(this.step / s.len));
      this.step++;
      if (!s.loop && this.step >= s.len) { this.song = null; break; }
    }
  }

  // ---- ファンファーレ (オリジナル): 小太鼓のロール → 金管の主題 → 上行して全奏、観客の手拍子と歓声 ----
  fanfare() {
    if (!this.ctx) return 14.5;
    this.stop();
    this.cutFanfare();
    const t0 = this.ctx.currentTime + 0.2, b = 60 / 126, M = this.fan, C = this.fanCrowd;
    const SC = [70, 72, 74, 75, 77, 79, 81]; // 変ロ長調
    const third = (m) => { const pc = ((m - 70) % 12 + 12) % 12, oc = Math.floor((m - 70) / 12), i = [0, 2, 4, 5, 7, 9, 11].indexOf(pc); if (i < 0) return m - 4; const j = i - 2; return 70 + oc * 12 + (j < 0 ? [0, 2, 4, 5, 7, 9, 11][j + 7] - 12 : [0, 2, 4, 5, 7, 9, 11][j]); };
    void SC;
    for (let i = 0; i < 16; i++) this.snare(t0 + i * b * 0.125, 0.05 + i * 0.012, M);   // ロール(2拍)
    this.timp(46, t0, 0.35, M);
    const T = t0 + 2 * b, tr = 1 / 3;
    const mel = [[0, 77, 0.7], [0.75, 77, 0.25], [1, 77, 0.9], [2, 82, 1.4], [3.5, 77, 0.5], [4, 79, 0.9], [5, 75, 0.9], [6, 77, 1.9],
      [8, 74, 0.7], [8.75, 74, 0.25], [9, 74, 0.9], [10, 79, 1.4], [11.5, 74, 0.5], [12, 75, 0.9], [13, 72, 0.9], [14, 74, 0.9], [15, 77, 0.9],
      [16, 82, 0.45], [16.5, 81, 0.45], [17, 82, 0.9], [18, 86, 1.9], [20, 84, 0.45], [20.5, 82, 0.45], [21, 84, 0.9], [22, 87, 0.9], [23, 86, 0.9],
      [24, 84, 1.4], [25.5, 81, 0.5], [26, 82, tr * 0.95], [26 + tr, 84, tr * 0.95], [26 + 2 * tr, 86, tr * 0.95], [27, 84, 0.9], [28, 82, 5.6]];
    for (const [bt, m, d] of mel) {
      const tt = T + bt * b, dd = d * b, last = bt >= 28;
      this.brass(m, tt, dd, 0.2, M); this.brass(third(m), tt, dd, 0.14, M);
      if (last) { for (const x of [86, 77, 74, 70, 65, 58]) this.brass(x, tt, dd, 0.1, M); }
      else this.horn(m - 12, tt, dd, 0.09, M);
    }
    // 伴奏: トロンボーンの和音、チューバ、小太鼓、ティンパニ
    const ch = [[58, 62, 65], [58, 62, 65], [63, 67, 70], [58, 62, 65], [55, 58, 62], [55, 58, 62], [60, 63, 67], [65, 69, 72], [58, 62, 65], [58, 62, 65], [63, 67, 70], [63, 67, 70], [65, 69, 72], [65, 69, 72]];
    const root = [46, 46, 51, 46, 43, 43, 48, 41, 46, 46, 51, 51, 41, 41];
    for (let h = 0; h < 14; h++) {
      const tt = T + h * 2 * b;
      for (let k = 0; k < 2; k++) for (const x of ch[h]) this.brass(x - 12, tt + k * b, b * 0.55, 0.075, M);
      this.bass(root[h] - 12, tt, b * 1.7, 0.3, M); this.timp(root[h], tt, 0.32, M);
      for (let k = 0; k < 4; k++) { this.snare(tt + k * b * 0.5, k % 2 ? 0.09 : 0.16, M); if (k === 3) this.snare(tt + (k + 0.5) * b * 0.5, 0.08, M); }
    }
    for (const bt of [0, 8, 16, 24]) this.cym(T + bt * b, 0.16, 1.6, M);
    const E = T + 28 * b;
    for (let i = 0; i < 44; i++) this.snare(E + i * b * 0.125, 0.07 + Math.min(0.1, i * 0.004), M);
    this.cym(E, 0.3, 4.5, M); this.timp(46, E, 0.6, M); this.bass(34, E, 5.4 * b, 0.34, M);
    for (let i = 0; i < 10; i++) this.timp(46, E + 0.25 + i * b * 0.5, 0.16 + i * 0.02, M);
    this.cym(E + 5.6 * b, 0.25, 2.5, M); this.timp(46, E + 5.6 * b, 0.6, M);
    // 観客: 拍に合わせた手拍子が次第に大きくなり、最後に大歓声
    for (let bt = 0; bt < 28; bt++) { const v = 0.05 + bt * 0.006; for (let k = 0; k < 5; k++) this.clap(T + bt * b + (Math.random() - 0.5) * 0.05, v * (0.5 + Math.random() * 0.6), C); }
    const dur = (E - this.ctx.currentTime) + 5.9 * b;
    this.cheerAt(E + 4.2 * b, 1.0, 5.5, C);
    return dur + 0.3;
  }
  jingle(win) {
    if (!this.ctx) return;
    const t = this.ctx.currentTime + 0.06, M = this.music;
    if (win) {
      [[0, 74], [0.16, 78], [0.32, 81], [0.48, 86]].forEach(([d, m]) => { this.brass(m, t + d, 0.15, 0.2, M); this.brass(m - 12, t + d, 0.15, 0.12, M); });
      for (const m of [62, 69, 74, 78, 81, 86, 90]) this.brass(m, t + 0.68, 2.0, 0.085, M);
      this.cym(t + 0.68, 0.28, 3); this.timp(50, t + 0.68, 0.6, M); this.bass(38, t + 0.68, 2.0, 0.3, M);
      for (let i = 0; i < 12; i++) this.snare(t + 0.68 + i * 0.06, 0.06, M);
    } else { [[0, 69], [0.34, 65], [0.68, 62]].forEach(([d, m]) => this.horn(m, t + d, 0.5, 0.14, M)); for (const m of [50, 57, 62, 65]) this.strings(m, t + 1.05, 2.0, 0.06, M); }
  }

  // ---- 効果音 ----
  pan(v) { const c = this.ctx; if (!c.createStereoPanner) return this.sfx; const p = c.createStereoPanner(); p.pan.value = Math.max(-1, Math.min(1, v)); p.connect(this.sfx); return p; }
  gate() { // 発馬機: 金属の開閉音 + 直後に歓声
    if (!this.ctx) return; const t = this.ctx.currentTime, o = this.sfx;
    this.nz(t, 0.05, 'highpass', 2500, 0.9, o); this.nz(t, 0.3, 'bandpass', 2700, 0.55, o, 2.2); this.nz(t, 0.16, 'lowpass', 380, 0.9, o); this.tone('sine', 95, 50, t, 0.18, 0.8, o);
    for (const [f, v, d] of [[523, 0.1, 0.7], [811, 0.09, 0.55], [1174, 0.08, 0.5], [1733, 0.06, 0.4], [2390, 0.04, 0.3]]) this.tone('square', f, f * 0.995, t, d, v, o);
    this.nz(t + 0.09, 0.12, 'bandpass', 1800, 0.35, o, 1.5);
    this.cheerAt(t + 0.15, 0.8, 3.5);
  }
  whip(good) { if (!this.ctx) return; const t = this.ctx.currentTime, o = this.sfx; this.nz(t, 0.035, 'highpass', good ? 4200 : 2600, good ? 0.9 : 0.6, o); this.nz(t + 0.004, 0.1, 'bandpass', good ? 1500 : 900, 0.45, o, 1.2); this.tone('sine', good ? 320 : 220, 90, t, 0.05, 0.35, o); }
  click() { if (!this.ctx) return; const t = this.ctx.currentTime; this.tone('triangle', 1900, 1500, t, 0.05, 0.22, this.ui); }
  select() { if (!this.ctx) return; const t = this.ctx.currentTime; this.tone('triangle', 880, 880, t, 0.09, 0.2, this.ui); this.tone('triangle', 1320, 1320, t + 0.07, 0.14, 0.2, this.ui); }
  confirm() { if (!this.ctx) return; const t = this.ctx.currentTime; [784, 988, 1175, 1568].forEach((f, i) => this.tone('triangle', f, f, t + i * 0.06, 0.22, 0.18, this.ui)); }
  chime(m = 88) { if (!this.ctx) return; const t = this.ctx.currentTime, f = mtof(m); this.tone('sine', f, f, t, 0.5, 0.2, this.ui); this.tone('sine', f * 1.5, f * 1.5, t + 0.07, 0.6, 0.15, this.ui); this.tone('sine', f * 2.76, f * 2.76, t, 0.2, 0.06, this.ui); }
  buzz() { if (!this.ctx) return; const t = this.ctx.currentTime; this.tone('sawtooth', 120, 100, t, 0.28, 0.22, this.ui); this.tone('sawtooth', 127, 106, t, 0.28, 0.22, this.ui); }
  bump() { if (!this.ctx) return; const t = this.ctx.currentTime; this.nz(t, 0.14, 'lowpass', 300, 1.0, this.sfx); this.tone('sine', 110, 55, t, 0.16, 0.7, this.sfx); this.snort(t + 0.05, 0.3); }
  whoosh() { if (!this.ctx) return; const t = this.ctx.currentTime, g = this.nz(t, 0.4, 'bandpass', 900, 0.001, this.sfx, 1.2); g.gain.cancelScheduledValues(t); g.gain.setValueAtTime(0.001, t); g.gain.exponentialRampToValueAtTime(0.4, t + 0.14); g.gain.exponentialRampToValueAtTime(0.0001, t + 0.4); }
  // 貯めておいた音を鳴らす (再生速度で音程の個体差、距離に応じて高域を落とし、左右に定位)
  playBuf(list, t, vol, pan = 0, rate = 1, lpHz = 0, out = this.hoofBus) {
    if (!list || !list.length || vol <= 0.002) return;
    const c = this.ctx, src = c.createBufferSource(); src.buffer = list[(Math.random() * list.length) | 0];
    src.playbackRate.value = rate * (0.95 + Math.random() * 0.1);
    let node = src;
    if (lpHz) { const f = c.createBiquadFilter(); f.type = 'lowpass'; f.frequency.value = lpHz; node.connect(f); node = f; }
    const g = c.createGain(); g.gain.value = vol; node.connect(g); node = g;
    if (pan && c.createStereoPanner) { const p = c.createStereoPanner(); p.pan.value = Math.max(-1, Math.min(1, pan)); node.connect(p); node = p; }
    node.connect(out); src.start(Math.max(c.currentTime, t));
  }
  snort(t, vol) { this.playBuf(this.bank && this.bank.breath, t, vol, 0, 0.85); }
  hoof(vol, pan, wet) { this.playBuf(this.bank && (wet && this.bank.wet.length ? this.bank.wet : this.bank.dry), this.ctx.currentTime, vol, pan); }
  // どよめき: 低めの声のうねり
  gasp(amount = 1) {
    if (!this.ctx) return; const t = this.ctx.currentTime + 0.02;
    if (this.voice && this.voice.gasp.length) { this.playVoice(this.voice.gasp, t, 1.25 * amount, 2.5); return; }
    for (const [fq, k] of [[430, 0.5], [760, 0.32]]) {
      const g = this.ctx.createGain(); g.gain.setValueAtTime(0.0001, t); g.gain.exponentialRampToValueAtTime(k * amount, t + 0.3); g.gain.exponentialRampToValueAtTime(0.0001, t + 1.7);
      const sr = this.ctx.createBufferSource(); sr.buffer = this.noise; sr.loop = true; const fl = this.ctx.createBiquadFilter(); fl.type = 'bandpass'; fl.frequency.setValueAtTime(fq * 1.25, t); fl.frequency.exponentialRampToValueAtTime(fq * 0.8, t + 1.5); fl.Q.value = 0.8;
      sr.connect(fl); fl.connect(g); g.connect(this.crowdBus); sr.start(t); sr.stop(t + 1.8);
    }
  }
  // 声の素材を鳴らす。dur が素材より短いときは途中で引かせる
  playVoice(list, t, vol, dur, out = this.crowdPan) {
    const c = this.ctx, src = c.createBufferSource(), g = c.createGain();
    src.buffer = list[(Math.random() * list.length) | 0]; src.playbackRate.value = 0.96 + Math.random() * 0.08;
    const len = src.buffer.duration / src.playbackRate.value;
    g.gain.setValueAtTime(vol, t);
    if (dur < len) { g.gain.setValueAtTime(vol, t + dur * 0.6); g.gain.linearRampToValueAtTime(0.0001, t + dur); }
    src.connect(g); g.connect(out || this.crowdBus); src.start(t); src.stop(t + Math.min(len, dur) + 0.05);
  }
  // 拍手: 入線後に場内から湧く
  applause(dur = 6, amount = 1) {
    if (!this.ctx) return; const t = this.ctx.currentTime + 0.05, n = Math.floor(dur * 34 * amount);
    for (let i = 0; i < n; i++) { const x = Math.random(), tt = t + x * dur; this.clap(tt, (0.05 + Math.random() * 0.07) * amount * (1 - x * 0.7)); }
  }
  // 歓声の盛り上がりを時刻指定で起こす
  cheerAt(t, amount, dur, out) {
    if (!this.ctx || amount <= 0) return;
    if (this.voice && this.voice.swell.length) { // 観客の声で沸く + 手拍子と指笛
      this.playVoice(this.voice.swell, t, 1.5 * amount, dur, out);
      for (let i = 0; i < 10 * amount; i++) this.clap(t + 0.3 + Math.random() * dur * 0.7, 0.05 + Math.random() * 0.06, out || this.crowdBus);
      for (let i = 0; i < 3 * amount; i++) { const f0 = 1700 + Math.random() * 600; this.tone('sine', f0, f0 * 1.45, t + 0.4 + Math.random() * dur * 0.6, 0.35, 0.04, out || this.crowdBus); }
      return;
    }
    out = out || this.crowdBus;
    const add = (n, k) => { const g = this.ctx.createGain(); g.gain.setValueAtTime(0.0001, t); g.gain.exponentialRampToValueAtTime(k * amount, t + 0.5); g.gain.setValueAtTime(k * amount, t + dur * 0.45); g.gain.exponentialRampToValueAtTime(0.0001, t + dur);
      const s = this.ctx.createBufferSource(); s.buffer = this.noise; s.loop = true; s.playbackRate.value = 0.8 + Math.random() * 0.4; const f = this.ctx.createBiquadFilter(); f.type = 'bandpass'; f.frequency.value = n; f.Q.value = 0.55;
      s.connect(f); f.connect(g); g.connect(out); s.start(t); s.stop(t + dur + 0.1); };
    add(900, 0.5); add(1900, 0.42); add(3100, 0.2);
    for (let i = 0; i < 14 * amount; i++) this.clap(t + 0.3 + Math.random() * dur * 0.8, 0.07 + Math.random() * 0.08, out);
    for (let i = 0; i < 3 * amount; i++) { const f0 = 1700 + Math.random() * 600; this.tone('sine', f0, f0 * 1.45, t + 0.4 + Math.random() * dur * 0.6, 0.35, 0.035, out); }   // 指笛
  }
  cheer(amount = 1, dur = 4) { if (this.ctx) this.cheerAt(this.ctx.currentTime + 0.02, amount, dur); }

  // 毎フレーム: 環境音・蹄音・息づかい
  // o: {crowd, roar, wind, rain, rumble, speed, phase, wet, effort, near:[{id, phase, dist, side, v}]}
  update(o) {
    if (!this.ctx || this.ctx.state !== 'running') return;
    const t = this.ctx.currentTime, a = this.amb, on = this.sfxOn ? 1 : 0, set = (n, v) => n.g.gain.setTargetAtTime(v * on, t, 0.3);
    const rr = Math.min(1.5, o.roar);
    const voiced = this.crowdLoops && this.crowdLoops.roar.src ? 1 : 0, nk = voiced ? 0.3 : 1;
    set(a.murmur, (o.crowd * 0.5 + rr * 0.1) * nk); set(a.crowd, (o.crowd * 0.32 + rr * 0.34) * nk); set(a.roar, rr * 0.46 * nk);
    if (this.crowdLoops) {
      this.crowdLoops.murmur.g.gain.setTargetAtTime(on * Math.min(1.3, o.crowd * 1.4) * (1 - Math.min(0.6, rr * 0.5)), t, 0.4);
      this.crowdLoops.roar.g.gain.setTargetAtTime(on * Math.min(2.2, rr * 1.8 + Math.max(0, o.crowd - 0.45) * 0.7), t, 0.35);
      this.hoofBus.gain.setTargetAtTime(this.vol.sfx * (1 - 0.18 * Math.min(1, rr)), t, 0.4); // 大歓声の中では蹄音を少し引く
      if (this.crowdPan.pan) this.crowdPan.pan.setTargetAtTime(o.standPan || 0, t, 0.6);
    }
    set(a.wind, o.wind * 0.2); set(a.rain, o.rain * 0.16);
    a.wind.f.frequency.setTargetAtTime(280 + o.wind * 560, t, 0.3);
    if (!on) { this.lastPh = o.phase; this.lastUpdT = t; set(a.rumble, 0); this.echoG.gain.setTargetAtTime(0, t, 0.2); return; }
    // 直線の大歓声: 手拍子や指笛が散発的に混じる
    if (o.roar > 0.45 && t > this.nextCrowdFx) {
      this.nextCrowdFx = t + 0.25 + Math.random() * 0.5;
      this.clap(t + Math.random() * 0.2, 0.05 + o.roar * 0.07);
      if (Math.random() < 0.12) { const f0 = 1600 + Math.random() * 700; this.tone('sine', f0, f0 * 1.4, t, 0.3, 0.03 * o.roar, this.crowdBus); }
    }
    // ---- 馬の音: フレームの間に来た着地を、正確な時刻に並べ直して鳴らす ----
    const dtA = Math.min(0.25, Math.max(0, t - (this.lastUpdT ?? t))); this.lastUpdT = t;
    const LAT = 0.035, bank = this.bank;
    const hits = (lp, ph, beats, cb) => {
      if (!(ph > lp) || ph - lp > 1.5) return;               // 巻き戻り・長い中断のあとは鳴らさず同期し直す
      const span = ph - lp;
      for (let k = Math.floor(lp); k <= Math.floor(ph); k++) for (let i = 0; i < beats.length; i++) {
        const x = k + beats[i];
        if (x > lp && x <= ph) cb(i, Math.max(t + 0.004, t + LAT - (1 - (x - lp) / span) * dtA));
      }
    };
    const hoofs = o.wet && bank.wet.length ? bank.wet : bank.dry;
    this.echoG.gain.setTargetAtTime((o.echo || 0) * 0.34 * on, t, 0.4);
    // 自分の馬
    if (o.speed > 2) {
      const sp = Math.min(1, o.speed / 16), v = 0.42 + 0.58 * sp;
      hits(this.lastPh, o.phase, GALLOP_BEATS, (i, tt) => this.playBuf(hoofs, tt, v * GALLOP_ACCENT[i], i % 2 ? 0.1 : -0.1, GALLOP_RATE[i]));
      if (o.speed > 8) {
        const ef = Math.min(1, o.effort || 0);
        hits(this.lastPh, o.phase, [0.42], (i, tt) => this.playBuf(bank.breath, tt, 0.16 + ef * 0.36, 0, 0.92));          // 呼気 (完歩ごと)
        hits(this.lastPh, o.phase, [0.76], (i, tt) => this.playBuf(bank.inhale, tt, 0.07 + ef * 0.14, 0));               // 吸気
        hits(this.lastPh, o.phase, [0.3], (i, tt) => { if (Math.random() < 0.45) this.playBuf(bank.tack, tt, 0.06 + Math.random() * 0.05, (Math.random() - 0.5) * 0.4); });
      }
    }
    this.lastPh = o.phase;
    // 周囲の馬: 距離で減衰・高域が落ち、左右の位置に定位する。全体のうなりも足音の量から決める
    let energy = 0;
    if (o.near) for (const h of o.near) {
      const lp = this.nearPh[h.id] ?? h.phase; this.nearPh[h.id] = h.phase;
      if (h.v < 2) continue;
      const v = (0.6 / Math.pow(1 + h.dist * 0.25, 1.5)) * (0.4 + 0.6 * Math.min(1, h.v / 16)), lpHz = 7000 / (1 + h.dist * 0.12);
      energy += v * v * 9.4;
      hits(lp, h.phase, GALLOP_BEATS, (i, tt) => this.playBuf(hoofs, tt + Math.random() * 0.004, v * GALLOP_ACCENT[i], h.side, GALLOP_RATE[i], lpHz));
      if (h.dist < 4 && h.v > 8) hits(lp, h.phase, [0.42], (i, tt) => this.playBuf(bank.breath, tt, 0.09, h.side, 0.9 + (h.id % 5) * 0.04));
    }
    set(a.rumble, Math.min(0.75, Math.sqrt(energy) * 0.55));
    // ゲートの中: 落ち着かない馬が扉を蹴る・足踏みする・鼻を鳴らす
    if (o.gate && dtA > 0) {
      if (Math.random() < dtA * 1.6) this.playBuf(bank.dry, t + 0.01, 0.12 + Math.random() * 0.12, (Math.random() - 0.5) * 1.6, 1.1, 2500);
      if (Math.random() < dtA * 0.35) this.playBuf(bank.tack, t + 0.01, 0.12 + Math.random() * 0.1, (Math.random() - 0.5) * 1.6, 0.32 + Math.random() * 0.1);
      if (Math.random() < dtA * 0.5) this.playBuf(bank.breath, t + 0.01, 0.1 + Math.random() * 0.08, (Math.random() - 0.5) * 1.6, 0.8);
    }
  }
  silence() { this.update({ crowd: 0, roar: 0, wind: 0, rain: 0, rumble: 0, speed: 0, phase: this.lastPh, effort: 0, echo: 0 }); }

  // ---- 実況 (ブラウザの音声合成) ----
  say(text, urgent) {
    if (!this.voiceOn || !window.speechSynthesis) return;
    try {
      const ss = window.speechSynthesis;
      if (urgent || ss.pending) ss.cancel();
      const u = new SpeechSynthesisUtterance(text);
      u.lang = 'ja-JP'; u.rate = 1.3; u.pitch = 1.05; u.volume = 1;
      const v = ss.getVoices().find((x) => x.lang && x.lang.startsWith('ja'));
      if (v) u.voice = v;
      ss.speak(u);
    } catch (e) { /* 音声合成が使えない環境 */ }
  }
  hush() { try { window.speechSynthesis && window.speechSynthesis.cancel(); } catch (e) { /* noop */ } }
}

// ---- 楽曲データ (すべて本作のための書き下ろし) ----
// タイトル: ニ長調のゆったりした主題 (弦 + ハープ + ホルン)
const TITLE_CH = [[38, 62, 66, 69], [37, 61, 64, 69], [35, 59, 62, 66], [31, 59, 62, 67], [42, 62, 66, 69], [43, 62, 67, 71], [40, 59, 64, 67], [45, 61, 64, 69]];
const TITLE_MEL = [
  [[0, 66, 6], [6, 69, 2], [8, 74, 8]], [[0, 73, 6], [6, 71, 2], [8, 69, 8]], [[0, 71, 4], [4, 74, 4], [8, 78, 6], [14, 76, 2]], [[0, 74, 8], [8, 71, 4], [12, 67, 4]],
  [[0, 69, 6], [6, 74, 2], [8, 78, 8]], [[0, 79, 6], [6, 78, 2], [8, 76, 4], [12, 74, 4]], [[0, 76, 4], [4, 79, 4], [8, 71, 4], [12, 76, 4]], [[0, 76, 8], [8, 73, 8]],
];
// 出馬表: ハ長調の軽快な曲 (ピアノ + ベース + ブラシ)
const PAD_CH = [[48, 55, 64, 67], [45, 57, 60, 64], [41, 57, 60, 65], [43, 55, 59, 62], [40, 55, 59, 64], [45, 57, 60, 64], [38, 57, 62, 65], [43, 55, 59, 65]];
const PAD_MEL = [
  [[0, 76, 4], [4, 79, 2], [6, 81, 2], [8, 79, 6], [14, 76, 2]], [[0, 72, 4], [4, 76, 4], [8, 74, 2], [10, 72, 2], [12, 69, 4]],
  [[0, 69, 2], [2, 72, 2], [4, 77, 4], [8, 76, 4], [12, 72, 4]], [[0, 74, 6], [6, 71, 2], [8, 74, 4], [12, 79, 4]],
  [[0, 79, 4], [4, 76, 2], [6, 79, 2], [8, 83, 6], [14, 79, 2]], [[0, 81, 4], [4, 79, 2], [6, 76, 2], [8, 72, 4], [12, 76, 4]],
  [[0, 77, 4], [4, 74, 4], [8, 69, 2], [10, 74, 2], [12, 77, 4]], [[0, 79, 8], [8, 74, 4], [12, 71, 4]],
];
// レース: ニ短調。蹄のリズムの弦オスティナート → 打楽器 → 金管の主題
const RACE_CH = [[38, 62, 65, 69], [38, 62, 65, 69], [34, 58, 62, 65], [36, 60, 64, 67], [38, 62, 65, 69], [41, 60, 65, 69], [43, 58, 62, 67], [45, 61, 64, 69]];
const RACE_MEL = [
  [[0, 74, 6], [6, 77, 2], [8, 81, 8]], [[0, 79, 4], [4, 77, 4], [8, 76, 4], [12, 74, 4]], [[0, 70, 6], [6, 74, 2], [8, 77, 8]], [[0, 76, 4], [4, 79, 4], [8, 84, 8]],
  [[0, 81, 6], [6, 79, 2], [8, 77, 4], [12, 74, 4]], [[0, 72, 4], [4, 77, 4], [8, 81, 6], [14, 84, 2]], [[0, 82, 4], [4, 81, 4], [8, 79, 4], [12, 82, 4]], [[0, 81, 8], [8, 73, 4], [12, 76, 4]],
];
export const SONGS = {
  title: {
    bpm: 76, len: 128, loop: true,
    fn(S, i, t, sd) {
      const bar = (i / 16) | 0, st = i % 16, ch = TITLE_CH[bar];
      if (st === 0) { for (let k = 1; k < 4; k++) S.strings(ch[k], t, sd * 15.5, 0.05); S.strings(ch[1] + 12, t, sd * 15.5, 0.028); S.bass(ch[0], t, sd * 7, 0.26); if (bar % 4 === 0) S.timp(ch[0] + 12, t, 0.22); }
      if (st === 8) S.bass(ch[0], t, sd * 7, 0.2);
      if (st % 2 === 0) { const seq = [1, 2, 3, 2, 1, 2, 3, 2], oc = st >= 8 ? 12 : 0; S.harp(ch[seq[st / 2]] + 12 + oc, t, 0.075); }
      for (const [s0, m, l] of TITLE_MEL[bar]) if (s0 === st) S.horn(m, t, sd * l * 0.94, 0.17);
      if (bar === 7 && st === 8) S.cym(t, 0.05, sd * 8);
    },
  },
  paddock: {
    bpm: 96, len: 128, loop: true,
    fn(S, i, t, sd) {
      const bar = (i / 16) | 0, st = i % 16, ch = PAD_CH[bar], sw = st % 2 ? sd * 0.18 : 0; // 軽くスウィング
      if (st === 0) for (let k = 1; k < 4; k++) S.strings(ch[k], t, sd * 15, 0.03);
      if (st === 3 || st === 6 || st === 11 || st === 14) for (let k = 1; k < 4; k++) S.piano(ch[k], t + sw, sd * 1.2, 0.055);
      if (st % 4 === 0) S.bass(ch[0] + (st === 8 ? 7 : st === 12 ? 4 : 0), t, sd * 3.2, 0.24);
      if (st === 0 || st === 10) S.kick(t + sw, 0.22);
      if (st === 4 || st === 12) S.nz(t, 0.07, 'bandpass', 1700, 0.08, S.music, 1.6);
      if (st % 2 === 0) S.hat(t, st % 4 === 2 ? 0.05 : 0.028); else if (st % 4 === 3) S.hat(t + sw, 0.02);
      for (const [s0, m, l] of PAD_MEL[bar]) if (s0 === st) S.piano(m, t, sd * l * 0.9, 0.17);
    },
  },
  race: {
    bpm: 156, len: 128, loop: true,
    fn(S, i, t, sd, lap) {
      const bar = (i / 16) | 0, st = i % 16, ch = RACE_CH[bar], I = S.intensity;
      if (st % 4 !== 1) S.strings(ch[1 + (st % 8 < 4 ? 0 : 2)] - (st % 4 === 0 ? 12 : 0), t, sd * 0.8, 0.06 + I * 0.014);   // タタッタ: 蹄のリズム
      if (st % 2 === 0) S.bass(ch[0], t, sd * 1.6, 0.26);
      if (st === 0) { for (let k = 1; k < 4; k++) S.strings(ch[k] + 12, t, sd * 15, 0.028 + I * 0.01); if (I >= 1) S.timp(ch[0] + 12, t, 0.3); }
      if (I >= 1) { if (st % 4 === 0) S.kick(t, 0.42); if (st === 4 || st === 12) S.snare(t, 0.2); if (st % 2 === 0) S.hat(t, 0.05); if (st === 14 || st === 15) S.snare(t, 0.09); }
      else if (st % 4 === 0) S.hat(t, 0.035);
      if (I >= 2) {
        for (const [s0, m, l] of RACE_MEL[bar]) if (s0 === st) { S.brass(m, t, sd * l * 0.92, 0.17); S.brass(m - 12, t, sd * l * 0.92, 0.1); if (lap % 2) S.horn(m - 5, t, sd * l * 0.92, 0.07); }
        if (i === 0) S.cym(t, 0.2, 2.2); if (st % 4 === 2) S.snare(t, 0.07);
      }
    },
  },
};
SONGS.menu = SONGS.title;
