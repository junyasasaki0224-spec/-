// ブラウザ版のオープニング曲(src/audio.js の startOpening / _scheduleOpening)を、そのまま録音して WAV にする。
// Roblox 版の roblox/assets/audio/minato-opening.wav はこれで作った(ブラウザ版と同じ曲にするため)。
//
// 使い方:
//   1. python -I roblox/tools/receive_wav.py 録音.wav   (この PC の中だけの受け口。1回受け取ったら終わる)
//   2. ブラウザ版(index.html)を開き、開発者ツールのコンソールにこのファイルの中身を貼って実行する
//   3. 録音.wav の音量をそろえて(いちばん大きい所 0.82)roblox/assets/audio/minato-opening.wav に置き、Roblox に登録する
//
// 中身: 幕開け1小節(2秒)+ 主題16小節 × 2周 = 66秒。Roblox では 34〜66秒(2周目)をくり返す(AudioSheet.openingLoop)。
// 2周目は1周目の残響を引き継いでいるので、くり返しのつなぎ目が切れない。
// 曲は src/audio.js から写した物。あちらの曲を変えたら、ここも同じに直す。
(async () => {
  const SR = 44100, B = 60 / 120, BARS = 32, LEN = 2 + BARS * 2;
  const ctx = new OfflineAudioContext(2, SR * LEN, SR);
  // ブラウザ版と同じ出口(全体の音量 0.8 → コンプレッサー)
  const comp = ctx.createDynamicsCompressor();
  comp.threshold.value = -16; comp.knee.value = 18; comp.ratio.value = 5; comp.attack.value = 0.004; comp.release.value = 0.2;
  const master = ctx.createGain(); master.gain.value = 0.8; master.connect(comp); comp.connect(ctx.destination);
  const noiseBuf = ctx.createBuffer(1, SR * 2, SR);
  { const d = noiseBuf.getChannelData(0); for (let i = 0; i < d.length; i++) d[i] = Math.random() * 2 - 1; }
  const gain = ctx.createGain(); gain.gain.value = 0.85; gain.connect(master);
  const bus = ctx.createGain(); bus.connect(gain);
  const hn = Math.floor(SR * 2.6), hallBuf = ctx.createBuffer(2, hn, SR);
  for (let c = 0; c < 2; c++) { const d = hallBuf.getChannelData(c); for (let q = 0; q < hn; q++) d[q] = (Math.random() * 2 - 1) * Math.pow(1 - q / hn, 2.6); }
  const hall = ctx.createConvolver(); hall.buffer = hallBuf;
  const wet = ctx.createGain(); wet.gain.value = 0.32; bus.connect(hall); hall.connect(wet); wet.connect(gain);
  const hz = (m) => 440 * 2 ** ((m - 69) / 12);
  const track = (src, t0, t1) => { src.start(t0); src.stop(t1); };
  const brass = (m, t, d, v) => {
    const lp = ctx.createBiquadFilter(), g = ctx.createGain();
    lp.type = 'lowpass'; lp.Q.value = 0.8; lp.frequency.setValueAtTime(500, t); lp.frequency.linearRampToValueAtTime(3200, t + 0.07); lp.frequency.linearRampToValueAtTime(1500, t + d);
    g.gain.setValueAtTime(0.0001, t); g.gain.linearRampToValueAtTime(v, t + 0.035); g.gain.setValueAtTime(v * 0.82, t + d * 0.75); g.gain.exponentialRampToValueAtTime(0.0008, t + d + 0.12);
    lp.connect(g); g.connect(bus);
    for (const det of [-5, 6]) { const o = ctx.createOscillator(); o.type = 'sawtooth'; o.frequency.value = hz(m); o.detune.value = det; o.connect(lp); track(o, t, t + d + 0.15); }
  };
  const strings = (m, t, d, v) => {
    const lp = ctx.createBiquadFilter(), g = ctx.createGain();
    lp.type = 'lowpass'; lp.frequency.value = 2100;
    g.gain.setValueAtTime(0.0001, t); g.gain.linearRampToValueAtTime(v, t + 0.22); g.gain.setValueAtTime(v, t + d - 0.1); g.gain.linearRampToValueAtTime(0.0001, t + d + 0.25);
    lp.connect(g); g.connect(bus);
    for (const det of [-9, 0, 8]) { const o = ctx.createOscillator(); o.type = 'sawtooth'; o.frequency.value = hz(m); o.detune.value = det; o.connect(lp); track(o, t, t + d + 0.3); }
  };
  const bass = (m, t, d, v) => {
    const o = ctx.createOscillator(), g = ctx.createGain(); o.type = 'triangle'; o.frequency.value = hz(m);
    g.gain.setValueAtTime(0.0001, t); g.gain.linearRampToValueAtTime(v, t + 0.02); g.gain.exponentialRampToValueAtTime(0.001, t + d);
    o.connect(g); g.connect(bus); track(o, t, t + d + 0.05);
  };
  const timp = (m, t, v) => {
    const o = ctx.createOscillator(), g = ctx.createGain(); o.type = 'sine';
    o.frequency.setValueAtTime(hz(m) * 1.35, t); o.frequency.exponentialRampToValueAtTime(hz(m), t + 0.06);
    g.gain.setValueAtTime(0.0001, t); g.gain.linearRampToValueAtTime(v, t + 0.006); g.gain.exponentialRampToValueAtTime(0.001, t + 0.7);
    o.connect(g); g.connect(bus); track(o, t, t + 0.75);
  };
  const noise = (t, d, v, type, f, q) => {
    const src = ctx.createBufferSource(), fl = ctx.createBiquadFilter(), g = ctx.createGain();
    src.buffer = noiseBuf; src.loop = true; fl.type = type; fl.frequency.value = f; fl.Q.value = q;
    g.gain.setValueAtTime(0.0001, t); g.gain.linearRampToValueAtTime(v, t + 0.004); g.gain.exponentialRampToValueAtTime(0.0006, t + d);
    src.connect(fl); fl.connect(g); g.connect(bus); track(src, t, t + d + 0.05);
  };
  const snare = (t, v) => { noise(t, 0.11, v, 'bandpass', 2400, 0.7); };
  const crash = (t, v) => { noise(t, 2.4, v, 'highpass', 5200, 0.5); };
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
  const under = (m, c) => { for (let x = m - 3; x > m - 12; x--) if (c.slice(1).some((n) => (x - n) % 12 === 0)) return x; return m - 12; };
  for (let bar = -1, t = 0; bar < BARS; bar++, t += 4 * B) {
    if (bar < 0) {
      for (let q = 0; q < 16; q++) timp(q % 2 ? 43 : 36, t + q * B / 4, 0.05 + 0.2 * (q / 15) ** 2);
      [[2, 67], [2.5, 72], [3, 76], [3.5, 79]].forEach(([b, m]) => { brass(m, t + b * B, B * 0.45, 0.1); brass(m - 12, t + b * B, B * 0.45, 0.08); });
      for (let q = 0; q < 8; q++) snare(t + 2 * B + q * B / 4, 0.03 + 0.012 * q);
      continue;
    }
    const [name, mel] = bars[bar % 16], c = CH[name], big = bar % 16 >= 8;
    if (bar % 8 === 0) crash(t, 0.16);
    for (const [b, d, m] of mel) { brass(m, t + b * B, d * B * 0.92, 0.1); brass(m - 12, t + b * B, d * B * 0.92, 0.075); if (big) brass(under(m, c), t + b * B, d * B * 0.92, 0.045); }
    for (const m of c.slice(1)) { strings(m, t, 4 * B, 0.034); strings(m + 12, t, 4 * B, 0.02); }
    strings(c[0] + 12, t, 4 * B, 0.05);
    for (const b of [0, 1, 2, 3]) bass(b % 2 ? c[0] + 7 : c[0], t + b * B, B * 0.9, 0.16);
    timp(c[0], t, 0.26); timp(c[0] + 7, t + 2 * B, 0.17); if (bar % 4 === 3) { timp(c[0] + 7, t + 3 * B, 0.15); timp(c[0] + 7, t + 3.5 * B, 0.2); }
    for (const [b, v] of [[0, 0.06], [1, 0.075], [1.5, 0.04], [2, 0.06], [3, 0.075], [3.5, 0.04], [3.75, 0.04]]) snare(t + b * B, v);
  }
  // 録音して 16bit ステレオの WAV にし、この PC の中の受け口へ送る
  const buf = await ctx.startRendering();
  const L = buf.getChannelData(0), R = buf.getChannelData(1), n = L.length;
  const out = new ArrayBuffer(44 + n * 4), v = new DataView(out);
  const w = (o, s) => { for (let i = 0; i < s.length; i++) v.setUint8(o + i, s.charCodeAt(i)); };
  w(0, 'RIFF'); v.setUint32(4, 36 + n * 4, true); w(8, 'WAVE'); w(12, 'fmt '); v.setUint32(16, 16, true); v.setUint16(20, 1, true); v.setUint16(22, 2, true);
  v.setUint32(24, SR, true); v.setUint32(28, SR * 4, true); v.setUint16(32, 4, true); v.setUint16(34, 16, true); w(36, 'data'); v.setUint32(40, n * 4, true);
  for (let i = 0; i < n; i++) { v.setInt16(44 + i * 4, Math.max(-1, Math.min(1, L[i])) * 32767, true); v.setInt16(46 + i * 4, Math.max(-1, Math.min(1, R[i])) * 32767, true); }
  const res = await fetch('http://127.0.0.1:8766/', { method: 'POST', body: out });
  console.log('録音できました', res.status, n / SR, '秒');
})();
