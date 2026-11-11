// ============================================================
//  観客の声をサンプル単位で合成する (Web Audio にも DOM にも依存しない純粋な関数)
//   一人ひとりの「声」= 声帯の振動(のこぎり波 + 息の成分、ゆらぎ・ビブラート・抑揚) を
//   日本語の母音のフォルマント(声道の共鳴)に通したもの。これを百人単位で重ねる
//   kind:
//     murmur : 発走前のざわめき (話し声。音節ごとに母音が変わる)。ループ用
//     roar   : 直線の大歓声「ワーッ」(叫び声が途切れなく重なる)。ループ用
//     swell  : 一斉に沸く歓声 (立ち上がって沸き、しばらく続いて引く)。単発
//     gasp   : どよめき「おおー」(短く、音程が下がる)。単発
//  同じ母音・性別の声はまとめてからフィルタに通す (フィルタは線形なので結果は同じで、ずっと軽い)
// ============================================================
import { mulberry } from './hoof.js';

// 日本語5母音のフォルマント [F1, F2, F3] (男性の平均。女性は約1.15倍)
const VOWELS = { a: [800, 1250, 2600], i: [300, 2300, 3000], u: [350, 1300, 2300], e: [550, 1850, 2550], o: [500, 900, 2500] };

class BP { // 帯域通過フィルタ (状態変数型)
  constructor(sr, fc, q) { this.f = 2 * Math.sin(Math.PI * Math.min(fc, sr * 0.2) / sr); this.d = 1 / q; this.l = 0; this.b = 0; }
  run(x) { this.l += this.f * this.b; const h = x - this.l - this.d * this.b; this.b += this.f * h; return this.b; }
}

const KIND = {
  murmur: { voices: 80, vow: 'aiueo', shout: 0, seg: [0.5, 2.2], gap: [0.4, 2.4], amp: [0.25, 0.7], loop: true, bright: 0.45 },
  roar: { voices: 110, vow: 'aaoeo', shout: 1, seg: [0.5, 2.6], gap: [0.04, 0.6], amp: [0.35, 1.0], loop: true, bright: 1.0 },
  swell: { voices: 140, vow: 'aaoeu', shout: 1, seg: [1.2, 3.6], gap: [0.1, 0.5], amp: [0.4, 1.0], loop: false, bright: 1.0 },
  gasp: { voices: 100, vow: 'oou', shout: 0.35, seg: [0.7, 1.4], gap: [9, 9], amp: [0.35, 1.0], loop: false, bright: 0.6 },
};

// 単発の全体の盛り上がり (0〜1)
function globalEnv(kind, t, dur) {
  if (kind === 'swell') return t < 0.9 ? Math.pow(t / 0.9, 1.6) : t < dur * 0.55 ? 1 : Math.max(0, 1 - (t - dur * 0.55) / (dur * 0.45));
  if (kind === 'gasp') return t < 0.22 ? t / 0.22 : Math.max(0, 1 - (t - 0.22) / (dur - 0.22));
  return 1;
}

export function synthCrowd(sr, seed, kind = 'roar', dur = 8) {
  const K = KIND[kind], R = mulberry(seed), N = () => R() * 2 - 1, len = Math.floor(sr * dur);
  const rr = (a) => a[0] + R() * (a[1] - a[0]);
  const groups = {}; // 母音+性別 → 声を足し合わせる場所
  const groupOf = (v, fem) => (groups[v + fem] ||= { v, fem, buf: new Float32Array(len) });
  let ns = (seed * 2654435761) | 0; // 声の息成分用の軽い乱数
  for (let n = 0; n < K.voices; n++) {
    const fem = R() < 0.4 ? 1 : 0;
    const base = fem ? 185 + R() * 110 : 92 + R() * 68;      // 地声の高さ
    const near = K.shout && R() < 0.1 ? 2.3 : 1;            // すぐ近くで叫ぶ人
    const amp0 = rr(K.amp) * (0.35 + 0.65 * R() * R()) * near;
    const vib = 4.5 + R() * 2.5, vibD = 0.008 + R() * 0.018, breath = K.shout ? 0.12 : 0.2;
    let ph = R(), jit = 0;
    // 単発は最初の1秒前後に一斉に声が上がる / ループは全体に散らす
    let t = K.loop ? -R() * 3 : kind === 'swell' ? R() * R() * 1.1 : R() * 0.25;
    while (t < dur) {
      const segDur = rr(K.seg);
      let s0 = Math.floor(t * sr); const sn = Math.floor(segDur * sr);
      if (K.loop) s0 = ((s0 % len) + len) % len;
      // 叫ぶと声が高く張る。叫びの中で音程が少し上がり、終わりで落ちる
      const f0 = base * (1 + K.shout * (0.25 + R() * 0.45)), rise = K.shout ? 0.06 + R() * 0.12 : (R() - 0.5) * 0.08;
      const att = Math.floor(sr * (K.shout ? 0.06 + R() * 0.2 : 0.04 + R() * 0.08)), rel = Math.floor(sr * (0.12 + R() * 0.3));
      const syl = 3.5 + R() * 3.5, sylPh = R(); // 話し声の音節
      let g = groupOf(K.vow[(R() * K.vow.length) | 0], fem), sylIdx = -1;
      const ampAt = (j) => {
        let a = amp0 * Math.min(1, j / att) * Math.min(1, Math.max(0, sn - j) / rel);
        if (kind === 'murmur') { const sp = (j / sr) * syl + sylPh; a *= Math.pow(Math.abs(Math.sin(Math.PI * (sp - Math.floor(sp)))), 1.5); }
        if (!K.loop) a *= globalEnv(kind, (s0 + j) / sr, dur);
        return a;
      };
      let a0 = ampAt(0);
      for (let j0 = 0; j0 < sn; j0 += 32) {               // 32サンプル(2ms)ごとに音量・音程を更新
        const jm = Math.min(sn, j0 + 32), a1 = ampAt(jm), da = (a1 - a0) / (jm - j0);
        if (kind === 'murmur') { const si = Math.floor((j0 / sr) * syl + sylPh); if (si !== sylIdx) { sylIdx = si; g = groupOf(K.vow[(R() * K.vow.length) | 0], fem); } }
        jit += (N() * 0.004 - jit * 0.05);
        const x = j0 / sn, vf = 1 + vibD * Math.sin(2 * Math.PI * vib * j0 / sr) + jit;
        let f = f0 * vf * (1 + rise * Math.sin(Math.PI * Math.min(1, x * 1.15)));
        if (kind === 'gasp') f *= 1.12 - 0.22 * ((s0 + j0) / len);    // どよめきは下がる
        const inc = f / sr, buf = g.buf;
        let a = a0;
        for (let j = j0; j < jm; j++) {
          let i = s0 + j;
          if (K.loop) { if (i >= len) i -= len; } else if (i >= len) break;
          ph += inc; if (ph >= 1) ph -= 1;
          ns = (Math.imul(ns, 1664525) + 1013904223) | 0;
          buf[i] += a * ((2 * ph - 1) * 0.8 + (ns / 2147483648) * breath);   // 声帯の振動 + 息
          a += da;
        }
        a0 = a1;
      }
      t += segDur + rr(K.gap);
    }
  }
  // 母音の響きをつけて混ぜる
  const out = new Float32Array(len);
  for (const key in groups) {
    const G = groups[key], fm = VOWELS[G.v].map((f) => f * (G.fem ? 1.15 : 1));
    const f1 = new BP(sr, fm[0], fm[0] / 90), f2 = new BP(sr, fm[1], fm[1] / 110), f3 = new BP(sr, fm[2], fm[2] / 160);
    const g2 = 0.45 + 0.2 * K.bright, g3 = 0.08 + 0.14 * K.bright, buf = G.buf;
    for (let i = 0; i < len; i++) { const x = buf[i]; out[i] += f1.run(x) + f2.run(x) * g2 + f3.run(x) * g3; }
  }
  // 低域の濁りと 3.4kHz より上を落とす
  let hp = 0, lp = 0, pk = 1e-9, rms = 0;
  const a = 1 - Math.exp(-2 * Math.PI * 90 / sr), b = 1 - Math.exp(-2 * Math.PI * 3400 / sr);
  for (let i = 0; i < len; i++) { hp += a * (out[i] - hp); lp += b * (out[i] - hp - lp); out[i] = lp; pk = Math.max(pk, Math.abs(lp)); rms += lp * lp; }
  rms = Math.sqrt(rms / len);
  // ループ用は実効値で、単発はピークで揃える (どちらも同じくらいの聞こえ方になるように)
  const k = K.loop ? 0.22 / rms : 0.9 / pk;
  const fade = K.loop ? 0 : Math.floor(sr * 0.05);
  for (let i = 0; i < len; i++) out[i] = Math.tanh(out[i] * k * 1.1) * (fade && i > len - fade ? (len - i) / fade : 1);
  return out;
}

export const CROWD_SR = 16000; // 声の成分は 4kHz 程度までなので軽いサンプリングレートで作る
