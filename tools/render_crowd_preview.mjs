// 歓声の試聴用ファイルを書き出す: 発走前のざわめき → ゲートが開いて沸く → 直線の大歓声と馬群 → どよめき → ゴールで爆発
//   node tools/render_crowd_preview.mjs out.wav [kind]   (kind を指定するとその素材だけ)
import { writeFileSync } from 'node:fs';
import { synthCrowd, CROWD_SR } from '../js/crowd.js';
import { synthHoof, mulberry, GALLOP_BEATS, GALLOP_ACCENT } from '../js/hoof.js';
import { synthPhrase, SHOUTS, CHATS } from '../js/voice.js';

const OUT = process.argv[2] || 'crowd_preview.wav', ONLY = process.argv[3];
const sr = 48000;
const t0 = Date.now(), tm = {};
const make = (kind, seed, dur) => { const a = Date.now(); const x = synthCrowd(CROWD_SR, seed, kind, dur); tm[kind] = (tm[kind] || 0) + Date.now() - a; return x; };
const up = (x) => { const k = sr / CROWD_SR, y = new Float32Array(Math.floor(x.length * k)); for (let i = 0; i < y.length; i++) { const p = i / k, i0 = Math.floor(p), f = p - i0; y[i] = x[i0] + ((x[i0 + 1] ?? x[0]) - x[i0]) * f; } return y; };
const S = {};
for (const [k, d] of [['murmur', 8], ['roar', 8], ['swell', 6], ['gasp', 2.5]]) S[k] = [up(make(k, 11, d)), up(make(k, 23, d))];
const VSR = 22050, upV = (x) => { const k = sr / VSR, y = new Float32Array(Math.floor(x.length * k)); for (let i = 0; i < y.length; i++) { const p = i / k, i0 = Math.floor(p), f = p - i0; y[i] = x[i0] + ((x[i0 + 1] ?? 0) - x[i0]) * f; } return y; };
const shouts = [], chats = [];
SHOUTS.forEach(([ph], i) => { for (let v = 0; v < 2; v++) shouts.push(upV(synthPhrase(VSR, 1000 + i * 7 + v, ph, { female: (i + v) % 3 === 2, effort: 0.85 + ((i * 3 + v) % 4) * 0.05 }))); });
CHATS.forEach(([ph], i) => { for (let v = 0; v < 2; v++) chats.push(upV(synthPhrase(VSR, 2000 + i * 7 + v, ph, { female: (i + v) % 2 === 0, effort: 0.15 + v * 0.1 }))); });
console.log('synth ms', tm, 'total', Date.now() - t0);
const DUR = ONLY ? S[ONLY][0].length / sr : 16, n = Math.floor(sr * DUR), L = new Float32Array(n), Rc = new Float32Array(n);
function add([a, b], t, gain, loop = false, from = 0, to = DUR, fadeIn = 0.6, fadeOut = 0.6) {
  for (let i = Math.floor(from * sr); i < Math.floor(to * sr) && i < n; i++) {
    const j = loop ? (i % a.length) : i - Math.floor(t * sr); if (j < 0 || j >= a.length) continue;
    const tt = i / sr, g = gain * Math.min(1, (tt - from) / fadeIn) * Math.min(1, (to - tt) / fadeOut);
    L[i] += a[j] * g; Rc[i] += b[j] * g;
  }
}
// 観客ひとりの声 (近い人ははっきり、遠い人はこもって小さく、左右に散らばる)
const RV = mulberry(77);
function voiceAt(list, t, level) {
  const x = list[(RV() * list.length) | 0], near = RV() < 0.22, d = near ? 0 : RV(), g = level * (near ? 0.85 + RV() * 0.3 : 0.22 + (1 - d) * 0.45);
  const pan = (RV() - 0.5) * 1.4, a = 1 - Math.exp(-2 * Math.PI * (near ? 7000 : 4200 - d * 2600) / sr), rate = 0.93 + RV() * 0.14;
  let y = 0; const i0 = Math.floor(t * sr);
  for (let j = 0; ; j++) { const p = j * rate, k = Math.floor(p); if (k + 1 >= x.length || i0 + j >= n) break; y += a * (x[k] + (x[k + 1] - x[k]) * (p - k) - y); L[i0 + j] += y * g * (1 - pan) * 0.75; Rc[i0 + j] += y * g * (1 + pan) * 0.75; }
}
if (ONLY) add(S[ONLY], 0, 1, false, 0, DUR, 0.01, 0.01);
else {
  add(S.murmur, 0, 0.9, true, 0, 4.2, 0.3, 1.2);
  add(S.gasp, 1.6, 0.55);
  add(S.swell, 3.0, 1.0);                                  // ゲートが開いた
  add(S.murmur, 0, 0.35, true, 4, 7.5, 1, 1);
  add(S.roar, 0, 0.6, true, 6.5, 16, 1.5, 0.8);            // 直線
  add(S.gasp, 10.2, 0.5);                                  // 先頭が入れ替わる
  add(S.swell, 12.2, 1.3);                                 // ゴール
  for (let t = 0.2; t < 3.2; t += 0.25 + RV() * 0.6) voiceAt(chats, t, 0.6);                      // 発走前の話し声
  for (let k = 0; k < 6; k++) voiceAt(shouts, 3.1 + RV() * 1.5, 1);                                // ゲートが開いた
  for (let t = 4.5; t < 12.2; t += 1 / (1.2 + 3.6 * Math.min(1, (t - 4.5) / 5)) * (0.4 + RV() * 1.2)) voiceAt(shouts, t, 1);   // レース中 → 直線
  for (let k = 0; k < 8; k++) voiceAt(shouts, 12.2 + RV() * 1.8, 1.1);                             // ゴール
  // 馬群の足音 (6〜13秒)
  const R = mulberry(5), bank = [0, 1, 2, 3].map((k) => synthHoof(sr, 101 + k));
  for (let h = 0; h < 8; h++) {
    let ph = R(); const dist = h === 0 ? 0 : 3 + h * 3, g0 = h === 0 ? 0.9 : 0.6 / Math.pow(1 + dist * 0.25, 1.5), pan = h === 0 ? 0 : (R() - 0.5) * 1.6;
    for (let t = 6; t < 13; t += 0.001) {
      const lp = ph; ph += 0.001 * 2.35;
      for (let b = 0; b < 4; b++) { const x = Math.floor(ph) + GALLOP_BEATS[b]; if (x > lp && x <= ph) {
        const s = bank[(R() * 4) | 0], i0 = Math.floor(t * sr), g = g0 * GALLOP_ACCENT[b] * Math.min(1, (t - 6) / 1.2) * Math.min(1, (13 - t) / 1.5);
        for (let j = 0; j < s.length && i0 + j < n; j++) { L[i0 + j] += s[j] * g * (1 - pan) * 0.7; Rc[i0 + j] += s[j] * g * (1 + pan) * 0.7; } } }
    }
  }
}
let pk = 0; for (let i = 0; i < n; i++) { L[i] = Math.tanh(L[i]); Rc[i] = Math.tanh(Rc[i]); pk = Math.max(pk, Math.abs(L[i]), Math.abs(Rc[i])); }
const g = 0.89 / pk, buf = Buffer.alloc(44 + n * 4), w = (o, s) => buf.write(s, o, 'ascii');
w(0, 'RIFF'); buf.writeUInt32LE(36 + n * 4, 4); w(8, 'WAVEfmt '); buf.writeUInt32LE(16, 16); buf.writeUInt16LE(1, 20); buf.writeUInt16LE(2, 22);
buf.writeUInt32LE(sr, 24); buf.writeUInt32LE(sr * 4, 28); buf.writeUInt16LE(4, 32); buf.writeUInt16LE(16, 34); w(36, 'data'); buf.writeUInt32LE(n * 4, 40);
for (let i = 0; i < n; i++) { buf.writeInt16LE(Math.round(L[i] * g * 32767), 44 + i * 4); buf.writeInt16LE(Math.round(Rc[i] * g * 32767), 46 + i * 4); }
writeFileSync(OUT, buf); console.log('wrote', OUT);
