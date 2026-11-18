// ガチャの演出の曲(このゲームのためのオリジナル)を合成して録音し、WAV にする。
// 使い方は record-opening.js と同じ:
//   1. python -I roblox/tools/receive_wav.py 録音.wav
//   2. ブラウザ版(index.html)を開き、開発者ツールのコンソールにこのファイルの中身を貼って実行する
//   3. 録音.wav の音量をそろえて roblox/assets/audio/minato-gacha.wav に置き、Roblox に登録する
//
// 曲: 毎分150拍。幕開け2小節(スネアのロールが速くなり、雑音が駆け上がる)→ 主題8小節 × 2周。
// 主題は Am-F-C-G / Am-F-G-E の上で、4つ打ちのキック・手拍子・16分のハイハット・跳ねるベース・
// 16分のアルペジオ・金管の和音。Roblox では 2周目(16〜28.8秒)をくり返す(AudioSheet.gachaLoop)。
(async () => {
  const SR = 44100, B = 60 / 150, BAR = 4 * B, INTRO = 2, BARS = 16;
  const LEN = (INTRO + BARS) * BAR;
  const ctx = new OfflineAudioContext(2, Math.ceil(SR * LEN), SR);
  const comp = ctx.createDynamicsCompressor();
  comp.threshold.value = -14; comp.knee.value = 12; comp.ratio.value = 5; comp.attack.value = 0.003; comp.release.value = 0.15;
  const master = ctx.createGain(); master.gain.value = 0.8; master.connect(comp); comp.connect(ctx.destination);
  const noiseBuf = ctx.createBuffer(1, SR * 2, SR);
  { const d = noiseBuf.getChannelData(0); for (let i = 0; i < d.length; i++) d[i] = Math.random() * 2 - 1; }
  // 残響(短めのホール)
  const hn = Math.floor(SR * 1.6), hall = ctx.createBuffer(2, hn, SR);
  for (let c = 0; c < 2; c++) { const d = hall.getChannelData(c); for (let q = 0; q < hn; q++) d[q] = (Math.random() * 2 - 1) * Math.pow(1 - q / hn, 3); }
  const bus = ctx.createGain(); bus.connect(master);
  const conv = ctx.createConvolver(); conv.buffer = hall;
  const wet = ctx.createGain(); wet.gain.value = 0.22; bus.connect(conv); conv.connect(wet); wet.connect(master);
  const hz = (m) => 440 * 2 ** ((m - 69) / 12);
  const pan = (node, p) => { const s = ctx.createStereoPanner(); s.pan.value = p; node.connect(s); s.connect(bus); };
  const osc = (type, m, t, d, v, opts = {}) => {
    const o = ctx.createOscillator(), g = ctx.createGain(), lp = ctx.createBiquadFilter();
    o.type = type; o.frequency.value = hz(m); o.detune.value = opts.detune || 0;
    lp.type = 'lowpass'; lp.frequency.setValueAtTime(opts.open || 4000, t); lp.frequency.exponentialRampToValueAtTime(opts.close || 1200, t + d + 0.01); lp.Q.value = opts.q || 1;
    g.gain.setValueAtTime(0.0001, t); g.gain.linearRampToValueAtTime(v, t + (opts.a || 0.006));
    g.gain.setValueAtTime(v * (opts.s || 0.7), t + d * 0.6); g.gain.exponentialRampToValueAtTime(0.0006, t + d + (opts.r || 0.06));
    o.connect(lp); lp.connect(g); pan(g, opts.pan || 0); o.start(t); o.stop(t + d + (opts.r || 0.06) + 0.02);
  };
  const noise = (t, d, v, type, f, q, p = 0, sweepTo) => {
    const src = ctx.createBufferSource(), fl = ctx.createBiquadFilter(), g = ctx.createGain();
    src.buffer = noiseBuf; src.loop = true; fl.type = type; fl.frequency.setValueAtTime(f, t); fl.Q.value = q;
    if (sweepTo) fl.frequency.exponentialRampToValueAtTime(sweepTo, t + d);
    g.gain.setValueAtTime(0.0001, t); g.gain.linearRampToValueAtTime(v, t + 0.003); g.gain.exponentialRampToValueAtTime(0.0006, t + d);
    src.connect(fl); fl.connect(g); pan(g, p); src.start(t); src.stop(t + d + 0.03);
  };
  const kick = (t, v = 0.9) => {
    const o = ctx.createOscillator(), g = ctx.createGain(); o.type = 'sine';
    o.frequency.setValueAtTime(150, t); o.frequency.exponentialRampToValueAtTime(45, t + 0.12);
    g.gain.setValueAtTime(v, t); g.gain.exponentialRampToValueAtTime(0.001, t + 0.32);
    o.connect(g); g.connect(bus); o.start(t); o.stop(t + 0.34);
    noise(t, 0.02, v * 0.25, 'highpass', 2500, 0.7);
  };
  const clap = (t, v = 0.32) => { for (const dt of [0, 0.011, 0.022]) noise(t + dt, 0.13, v, 'bandpass', 1500, 0.9); };
  const snare = (t, v = 0.25) => { noise(t, 0.12, v, 'bandpass', 2600, 0.6); osc('triangle', 52, t, 0.06, v * 0.6, { open: 2000, close: 600 }); };
  const hat = (t, v, open) => noise(t, open ? 0.18 : 0.04, v, 'highpass', 8000, 0.8, (Math.random() - 0.5) * 0.3);
  const crash = (t, v = 0.2) => noise(t, 2.2, v, 'highpass', 5000, 0.4);
  const brass = (m, t, d, v, p = 0) => { for (const det of [-7, 7]) osc('sawtooth', m, t, d, v, { detune: det, open: 3600, close: 1400, a: 0.02, s: 0.8, r: 0.12, pan: p }); };

  // 和音(ベースの根音と、上の3つの音)
  const CH = { Am: [45, 69, 72, 76], F: [41, 69, 72, 77], C: [48, 67, 72, 76], G: [43, 67, 71, 74], E: [40, 68, 71, 76] };
  const PROG = ['Am', 'F', 'C', 'G', 'Am', 'F', 'G', 'E'];

  // 幕開け: スネアのロールが速くなり、雑音とシンセが駆け上がる
  for (let q = 0; q < 8; q++) snare(q * B / 2, 0.08 + q * 0.01);
  for (let q = 0; q < 16; q++) snare(BAR + q * B / 4, 0.12 + q * 0.008);
  for (let q = 0; q < 8; q++) snare(BAR + 3 * B + q * B / 8, 0.2);
  noise(0, 2 * BAR, 0.16, 'bandpass', 400, 2.5, 0, 9000);
  for (let q = 0; q < 16; q++) osc('square', 57 + q, q * BAR / 8, BAR / 8 * 0.9, 0.03 + q * 0.002, { open: 3000, close: 2000, pan: q % 2 ? 0.3 : -0.3 });
  [0, 2].forEach((b) => brass(57, BAR + b * B, B * 0.5, 0.05));

  for (let bar = 0; bar < BARS; bar++) {
    const t = (INTRO + bar) * BAR, name = PROG[bar % 8], c = CH[name], last = bar % 8 === 7;
    if (bar % 8 === 0) crash(t, 0.22);
    for (let b = 0; b < 4; b++) kick(t + b * B);
    clap(t + B); clap(t + 3 * B);
    for (let s = 0; s < 16; s++) hat(t + s * B / 4, s % 4 === 2 ? 0.09 : 0.035 + (s % 2) * 0.012, s % 4 === 2);
    // 跳ねるベース(8分のオクターブ)
    for (let e = 0; e < 8; e++) osc('sawtooth', c[0] + (e % 2 ? 12 : 0), t + e * B / 2, B / 2 * 0.85, 0.14, { open: 1400, close: 300, q: 4, s: 0.5 });
    // 16分のアルペジオ(和音の音を上へ、下へ)
    const arp = [c[1], c[2], c[3], c[1] + 12, c[2] + 12, c[3] + 12, c[2] + 12, c[1] + 12];
    for (let s = 0; s < 16; s++) osc('square', arp[s % 8], t + s * B / 4, B / 4 * 0.7, 0.045, { open: 5000, close: 1800, pan: s % 2 ? 0.25 : -0.25 });
    // 金管の和音: 1拍目と、裏の「タッ」
    for (const m of c.slice(1)) { brass(m, t, B * 1.4, 0.035); brass(m, t + 2.5 * B, B * 0.4, 0.03); }
    // 主題(高い金管): 2小節ごとに上がっていく旋律
    const top = c[3] + 12;
    if (bar % 2 === 0) { brass(top, t, B * 1.5, 0.05, 0.1); brass(top + 2, t + 1.5 * B, B * 0.5, 0.045, 0.1); brass(top + 3, t + 2 * B, B * 2, 0.05, 0.1); }
    else { brass(top + 5, t, B, 0.05, 0.1); brass(top + 3, t + B, B, 0.045, 0.1); brass(top, t + 2 * B, B * 2, 0.05, 0.1); }
    // 区切りの小節の終わりはスネアの連打
    if (last) for (let q = 0; q < 8; q++) snare(t + 2 * B + q * B / 4, 0.12 + q * 0.02);
  }

  const buf = await ctx.startRendering();
  const L = buf.getChannelData(0), R = buf.getChannelData(1), n = L.length;
  const out = new ArrayBuffer(44 + n * 4), v = new DataView(out);
  const w = (o, s) => { for (let i = 0; i < s.length; i++) v.setUint8(o + i, s.charCodeAt(i)); };
  w(0, 'RIFF'); v.setUint32(4, 36 + n * 4, true); w(8, 'WAVE'); w(12, 'fmt '); v.setUint32(16, 16, true); v.setUint16(20, 1, true); v.setUint16(22, 2, true);
  v.setUint32(24, SR, true); v.setUint32(28, SR * 4, true); v.setUint16(32, 4, true); v.setUint16(34, 16, true); w(36, 'data'); v.setUint32(40, n * 4, true);
  for (let i = 0; i < n; i++) { v.setInt16(44 + i * 4, Math.max(-1, Math.min(1, L[i])) * 32767, true); v.setInt16(46 + i * 4, Math.max(-1, Math.min(1, R[i])) * 32767, true); }
  const res = await fetch('http://127.0.0.1:8766/', { method: 'POST', body: out });
  console.log('録音できました', res.status, n / SR, '秒');
  return { status: res.status, seconds: n / SR };
})();
