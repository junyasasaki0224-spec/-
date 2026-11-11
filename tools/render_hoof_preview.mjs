// 蹄音の試聴用ファイルを書き出す: 馬群がゲートから飛び出し、スタンド前を駆け抜ける約9秒
//   node tools/render_hoof_preview.mjs out.wav
import { writeFileSync } from 'node:fs';
import { synthHoof, synthBreath, synthTack, mulberry, GALLOP_BEATS, GALLOP_ACCENT, GALLOP_RATE } from '../js/hoof.js';

const OUT = process.argv[2] || 'hoof_preview.wav';
const SOLO = process.argv[3] === 'solo'; // solo: 自分の馬だけ
const sr = 48000, DUR = 9.5, n = Math.floor(sr * DUR);
const L = new Float32Array(n), Rch = new Float32Array(n);
const R = mulberry(42);
let t0 = Date.now();
const bank = { dry: [], breath: [], inhale: [], tack: [] };
for (let k = 0; k < 8; k++) bank.dry.push(synthHoof(sr, 101 + k, false));
for (let k = 0; k < 4; k++) bank.breath.push(synthBreath(sr, 301 + k));
for (let k = 0; k < 3; k++) bank.inhale.push(synthBreath(sr, 401 + k, true));
for (let k = 0; k < 4; k++) bank.tack.push(synthTack(sr, 501 + k));
console.log('bank synth ms', Date.now() - t0);
const pick = (a) => a[(R() * a.length) | 0];

// 再生速度(音程)・距離による高域減衰・定位をつけて書き込む
function add(smp, t, gain, pan = 0, rate = 1, lpHz = 0) {
  const s0 = Math.floor(t * sr); if (s0 >= n) return;
  const gl = gain * Math.cos((pan + 1) * Math.PI / 4), gr = gain * Math.sin((pan + 1) * Math.PI / 4);
  const a = lpHz ? 1 - Math.exp(-2 * Math.PI * lpHz / sr) : 1;
  let y = 0;
  for (let j = 0; ; j++) {
    const x = j * rate, i0 = Math.floor(x); if (i0 + 1 >= smp.length || s0 + j >= n) break;
    const v = smp[i0] + (smp[i0 + 1] - smp[i0]) * (x - i0);
    y += a * (v - y);
    L[s0 + j] += y * gl; Rch[s0 + j] += y * gr;
  }
}

// ゲートの扉
add(pick(bank.tack), 0.35, 0.5, -0.2, 0.33); add(pick(bank.tack), 0.37, 0.45, 0.25, 0.38);
// 馬: [横位置(左右), 前後の距離, 速度の個体差]  0番が自分の馬
const horses = [[0, 0, 1]];
for (let k = 1; k < (SOLO ? 1 : 10); k++) horses.push([(R() - 0.5) * 2, (R() - 0.5) * 2 * (2 + k * 1.8), 0.97 + R() * 0.06]);
const START = 0.5;
for (const [hi, h] of horses.entries()) {
  let ph = R() * 0.3, v = 0, t = START + R() * 0.12;
  const dt = 1 / 1000;
  let lastPh = ph, exhaled = -1;
  while (t < DUR) {
    v = 17.5 * h[2] * (1 - Math.exp(-(t - START) / 1.2));
    ph += dt * (0.9 + v * 0.085);
    const dist = Math.hypot(h[0] * 3, h[1]);
    for (let b = 0; b < 4; b++) {
      for (let k = Math.floor(lastPh); k <= Math.floor(ph); k++) {
        const x = k + GALLOP_BEATS[b];
        if (x > lastPh && x <= ph) {
          const speed = 0.45 + 0.55 * Math.min(1, v / 16);
          const g = hi === 0 ? GALLOP_ACCENT[b] * speed : (0.6 / Math.pow(1 + dist * 0.25, 1.5)) * GALLOP_ACCENT[b] * speed;
          const pan = hi === 0 ? (b % 2 ? 0.12 : -0.12) : Math.max(-1, Math.min(1, h[0] / 1.2));
          add(pick(bank.dry), t + R() * 0.004, g, pan, GALLOP_RATE[b] * (0.95 + R() * 0.1), hi === 0 ? 0 : 7000 / (1 + dist * 0.12));
        }
      }
    }
    // 呼吸と馬具 (自分の馬と、すぐ隣の馬)
    if (v > 8 && (hi === 0 || dist < 4)) {
      const k = Math.floor(ph);
      if (ph - k >= 0.42 && exhaled !== k) {
        exhaled = k; const eff = Math.min(1, (t - START) / 6);
        add(pick(bank.breath), t, (hi === 0 ? 0.16 + eff * 0.3 : 0.1) , hi === 0 ? 0 : h[0] / 1.2, 0.95 + R() * 0.1);
        add(pick(bank.inhale), t + 0.15, hi === 0 ? 0.1 + eff * 0.15 : 0.05, hi === 0 ? 0 : h[0] / 1.2);
        if (hi === 0 && R() < 0.45) add(pick(bank.tack), t - 0.05, 0.08 + R() * 0.05, (R() - 0.5) * 0.4, 0.9 + R() * 0.2);
      }
    }
    lastPh = ph; t += dt;
  }
}
// スタンドからの反響 (3.5〜8秒)
const D = Math.floor(0.105 * sr);
for (const ch of [L, Rch]) {
  let y = 0; const a = 1 - Math.exp(-2 * Math.PI * 2000 / sr);
  const src = Float32Array.from(ch);
  for (let i = D; i < n; i++) { const t = i / sr, w = t > 3.5 && t < 8 ? 0.3 : 0.06; y += a * (src[i - D] - y); ch[i] += y * w; }
}
// 仕上げ: ソフトクリップして -1dBFS に揃える
let pk = 0;
for (let i = 0; i < n; i++) { L[i] = Math.tanh(L[i] * 0.9); Rch[i] = Math.tanh(Rch[i] * 0.9); pk = Math.max(pk, Math.abs(L[i]), Math.abs(Rch[i])); }
const g = 0.89 / pk;
const buf = Buffer.alloc(44 + n * 4), w = (o, s) => buf.write(s, o, 'ascii');
w(0, 'RIFF'); buf.writeUInt32LE(36 + n * 4, 4); w(8, 'WAVEfmt '); buf.writeUInt32LE(16, 16); buf.writeUInt16LE(1, 20); buf.writeUInt16LE(2, 22);
buf.writeUInt32LE(sr, 24); buf.writeUInt32LE(sr * 4, 28); buf.writeUInt16LE(4, 32); buf.writeUInt16LE(16, 34); w(36, 'data'); buf.writeUInt32LE(n * 4, 40);
for (let i = 0; i < n; i++) { buf.writeInt16LE(Math.round(L[i] * g * 32767), 44 + i * 4); buf.writeInt16LE(Math.round(Rch[i] * g * 32767), 46 + i * 4); }
writeFileSync(OUT, buf);
console.log('wrote', OUT, (buf.length / 1024 | 0) + 'KB', 'total ms', Date.now() - t0);
