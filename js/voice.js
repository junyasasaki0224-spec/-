// ============================================================
//  人の掛け声をフォルマント合成する (Web Audio にも DOM にも依存しない純粋な関数)
//   声帯の脈動(Rosenberg 波形) → 声道の共鳴 F1〜F4 を直列に通す (母音)
//   子音: か・た行の破裂と息、さ・し行の擦れ、ま・な・ん行の鼻音、ら行のはじき、わ・や行のわたり
//   抑揚: 叫ぶと声が張り上がり、伸ばした語尾で揺れて落ちる。周期ごとの揺らぎ(ジッター・シマー)
//  synthPhrase(sr, seed, phrase, {female, effort}) → Float32Array (モノラル, ピーク 0.9)
// ============================================================
import { mulberry } from './hoof.js';

// 日本語の音素の目標値 (成人男性)。F: フォルマント周波数, B: 帯域幅, AV: 声の強さ
const V = {
  a: { F: [760, 1220, 2550, 3500], B: [90, 110, 150, 220], AV: 1 },
  i: { F: [300, 2250, 2950, 3550], B: [60, 110, 170, 220], AV: 0.82 },
  u: { F: [350, 1350, 2300, 3400], B: [70, 110, 150, 220], AV: 0.82 },
  e: { F: [480, 1900, 2550, 3500], B: [70, 110, 150, 220], AV: 0.95 },
  o: { F: [490, 860, 2500, 3400], B: [80, 100, 150, 220], AV: 0.95 },
};
const C = {
  k: { kind: 'stop', voiced: 0, burst: 2600, asp: 0.035, clo: 0.055 },
  t: { kind: 'stop', voiced: 0, burst: 4300, asp: 0.025, clo: 0.05 },
  g: { kind: 'stop', voiced: 1, burst: 2300, asp: 0.0, clo: 0.04 },
  d: { kind: 'stop', voiced: 1, burst: 3800, asp: 0.0, clo: 0.04 },
  z: { kind: 'fric', f: 5000, bw: 1800, dur: 0.06 },
  b: { kind: 'stop', voiced: 1, burst: 900, asp: 0.0, clo: 0.045 },
  s: { kind: 'fric', f: 5200, bw: 1600, dur: 0.1 },
  sh: { kind: 'fric', f: 3300, bw: 1300, dur: 0.1 },
  h: { kind: 'fric', f: 1500, bw: 3000, dur: 0.07, asp: 1 },
  m: { kind: 'nasal', F: [250, 1000, 2200, 3400], dur: 0.065 },
  n: { kind: 'nasal', F: [250, 1500, 2600, 3400], dur: 0.06 },
  N: { kind: 'nasal', F: [260, 1150, 2350, 3400], dur: 0.085 },
  r: { kind: 'flap', dur: 0.028 },
  w: { kind: 'glide', F: [330, 760, 2300, 3400], dur: 0.06 },
  j: { kind: 'glide', F: [290, 2200, 2900, 3500], dur: 0.06 },
};

// 競馬場の掛け声 ("ー" は伸ばす)。カナは確認用
export const SHOUTS = [
  ['i ke ー', 'いけー'], ['i ke i ke ー', 'いけいけー'], ['so no ma ma ー', 'そのままー'], ['sa se ー', 'させー'],
  ['sa se sa se ー', 'させさせー'], ['no ko se ー', 'のこせー'], ['ki ta ー', 'きたー'], ['ga N ba re ー', 'がんばれー'],
  ['ko i ー', 'こいー'], ['ma ku re ー', 'まくれー'], ['u o ー', 'うおー'], ['wa ー', 'わー'], ['jo sh i', 'よし'],
  ['a ー', 'あー'], ['o o ー', 'おおー'], ['i ke ー ー', 'いけーー'], ['so no ma ma ー ー', 'そのままーー'], ['ha sh i re ー', 'はしれー'],
];
// 発走前の話し声 (普通の声の高さ・抑揚)
export const CHATS = [
  ['do re ka na', 'どれかな'], ['ku ru jo', 'くるよ'], ['so u da ne', 'そうだね'], ['ha ja ku', 'はやく'], ['i ke ru ka na', 'いけるかな'],
  ['ki ta ne', 'きたね'], ['su go i ne', 'すごいね'], ['a re da jo', 'あれだよ'],
];

// 声帯の脈動 (Rosenberg の声門流を微分したもの = 口から出る音の源)。1周期を 512 点で
const GL = (() => {
  const n = 512, g = new Float32Array(n + 1), d = new Float32Array(n);
  for (let i = 0; i <= n; i++) {
    const x = i / n, tp = 0.42, tn = 0.16;
    g[i] = x < tp ? 0.5 * (1 - Math.cos(Math.PI * x / tp)) : x < tp + tn ? Math.cos(Math.PI * (x - tp) / (2 * tn)) : 0;
  }
  let pk = 0; for (let i = 0; i < n; i++) { d[i] = g[i + 1] - g[i]; pk = Math.max(pk, Math.abs(d[i])); }
  for (let i = 0; i < n; i++) d[i] /= pk;
  return { d, g };
})();

class Reso { // 2次の共鳴器 (Klatt)
  constructor(sr) { this.T = 1 / sr; this.y1 = 0; this.y2 = 0; this.set(500, 100); }
  set(f, bw) { const T = this.T; this.C = -Math.exp(-2 * Math.PI * bw * T); this.B = 2 * Math.exp(-Math.PI * bw * T) * Math.cos(2 * Math.PI * f * T); this.A = 1 - this.B - this.C; }
  run(x) { const y = this.A * x + this.B * this.y1 + this.C * this.y2; this.y2 = this.y1; this.y1 = y; return y; }
}

// 音素列 → 時間に沿った目標の並び
function plan(phrase, R, effort) {
  const toks = phrase.split(/\s+/), seg = [];
  for (let k = 0; k < toks.length; k++) {
    const tk = toks[k];
    if (tk === 'ー') { const last = seg[seg.length - 1]; last.dur += (effort > 0.5 ? 0.38 : 0.2) + R() * (effort > 0.5 ? 0.45 : 0.15); last.long = 1; continue; }
    let p = tk;
    const cons = p.length > 1 && !V[p] ? (C[p.slice(0, 2)] ? p.slice(0, 2) : p[0]) : (C[p] ? p : null);
    if (cons && C[cons]) {
      const c = C[cons];
      seg.push({ c: cons, kind: c.kind, dur: (c.dur || c.clo) * (0.85 + R() * 0.3), info: c });
      p = p.slice(cons.length);
    }
    if (p && V[p]) seg.push({ v: p, kind: 'vowel', dur: (effort > 0.5 ? 0.1 : 0.085) * (0.85 + R() * 0.3) });
  }
  // 最後が子音・短い母音の語は、少しだけ余韻を持たせる
  return seg;
}

export function synthPhrase(sr, seed, phrase, opt = {}) {
  const R = mulberry(seed), N = () => R() * 2 - 1;
  const female = !!opt.female, effort = opt.effort ?? 1;
  const seg = plan(phrase, R, effort);
  let t = 0.03; for (const s of seg) { s.t0 = t; t += s.dur; }
  const total = t + 0.12, len = Math.floor(total * sr), out = new Float32Array(len);
  const fsc = female ? [1.17, 1.17, 1.15, 1.1] : [1, 1, 1, 1];
  const f1up = 1 + 0.13 * effort; // 叫ぶと口が大きく開き F1 が上がる
  // 声の高さ: 叫ぶと張り上がる
  const base = female ? 210 + R() * 50 : 105 + R() * 30;
  const peak = base * (1 + effort * (0.75 + R() * 0.45));
  const vowelTargets = (s) => {
    if (s.v) return { F: V[s.v].F.map((f, i) => f * fsc[i] * (i === 0 ? f1up : 1)), B: V[s.v].B, AV: V[s.v].AV, AH: 0.04, AF: 0 };
    return null;
  };
  // 子音は次の母音の形へ向かいながら鳴る
  const nextVowel = (k) => { for (let j = k + 1; j < seg.length; j++) if (seg[j].v) return seg[j]; for (let j = k - 1; j >= 0; j--) if (seg[j].v) return seg[j]; return { v: 'a' }; };
  const targetAt = (k) => {
    const s = seg[k];
    if (s.v) return vowelTargets(s);
    const nv = vowelTargets(nextVowel(k)), c = s.info;
    if (c.kind === 'nasal' || c.kind === 'glide') return { F: c.F.map((f, i) => f * fsc[i]), B: c.kind === 'nasal' ? [110, 260, 300, 300] : [70, 110, 160, 220], AV: c.kind === 'nasal' ? 0.42 : 0.75, AH: 0.02, AF: 0 };
    if (c.kind === 'flap') return { ...nv, AV: nv.AV * 0.35 };
    if (c.kind === 'fric') return { ...nv, AV: 0, AH: c.asp ? 0.5 : 0.02, AF: c.asp ? 0 : 0.55 };
    return { ...nv, AV: c.voiced ? 0.12 : 0, AH: 0, AF: 0 }; // 破裂音の閉鎖
  };
  const res = [0, 1, 2, 3].map(() => new Reso(sr)), fr = new Reso(sr), br = new Reso(sr);
  const cur = { ...targetAt(0) }; cur.F = cur.F.slice(); cur.B = cur.B.slice();
  let ph = 0, per = 1, amp = 1, k = 0, burstLeft = 0, burstF = 2500, aspLeft = 0, prevX = 0, hp = 0, frameN = 0;
  const FR = Math.floor(sr * 0.0025); // 2.5ms ごとに声道の形を更新
  const lastV = seg.reduce((a, s, i) => (s.v ? i : a), 0);
  for (let i = 0; i < len; i++) {
    const tt = i / sr;
    while (k < seg.length - 1 && tt >= seg[k + 1].t0) {
      k++;
      const s = seg[k - 1];
      if (s.kind === 'stop') { burstLeft = Math.floor(sr * 0.012); burstF = s.info.burst; aspLeft = Math.floor(sr * s.info.asp); } // 閉鎖が開く
    }
    const s = seg[k];
    if (frameN-- <= 0) {
      frameN = FR;
      const tg = tt < seg[0].t0 ? targetAt(0) : targetAt(k), rate = s.kind === 'vowel' ? 0.11 : 0.22;
      for (let j = 0; j < 4; j++) { cur.F[j] += (tg.F[j] - cur.F[j]) * rate; cur.B[j] += (tg.B[j] - cur.B[j]) * rate; res[j].set(cur.F[j], cur.B[j] * (1 + 0.3 * (1 - effort))); }
      const av = tt > t ? 0 : tg.AV; cur.AV = (cur.AV ?? av) + (av - (cur.AV ?? av)) * (s.kind === 'stop' ? 0.6 : 0.3);
      cur.AH = tg.AH; cur.AF = tg.AF;
      if (s.kind === 'fric') fr.set(s.info.f * (female ? 1.08 : 1), s.info.bw);
    }
    // 抑揚: 最初の音節で張り上げ、伸ばす語尾で揺れて最後に落ちる (話し声はゆるやかに下がる)
    const x = (tt - 0.03) / (t - 0.03);
    let f0;
    if (effort > 0.5) f0 = base + (peak - base) * Math.min(1, x * 3.2) * (x > 0.82 ? 1 - (x - 0.82) * 1.6 : 1);
    else f0 = base * (1.18 - 0.3 * x + 0.12 * Math.sin(Math.PI * Math.min(1, x * 2)));
    if (seg[k].long || (k === lastV && seg[k].v)) f0 *= 1 + 0.025 * Math.sin(2 * Math.PI * 5.5 * tt) * Math.min(1, (tt - seg[k].t0) * 4);
    // 声帯の脈動 (周期ごとに少し揺らぐ)
    ph += (f0 * per) / sr;
    if (ph >= 1) { ph -= 1; per = 1 + N() * 0.012 * (0.5 + effort); amp = 1 + N() * 0.07; }
    const gi = (ph * 512) | 0, src = GL.d[gi] * amp, flow = GL.g[gi];
    let env = 1;
    if (tt < 0.03 + 0.04) env = Math.max(0, (tt - 0.03) / 0.04);
    if (tt > t - (effort > 0.5 ? 0.25 : 0.1)) env *= Math.max(0, (t - tt) / (effort > 0.5 ? 0.25 : 0.1));
    const voice = src * (cur.AV || 0) * env;
    const breath = N() * ((cur.AH || 0) + 0.06 + 0.1 * flow * effort) * env;
    let y = voice + breath * 0.5;
    if (aspLeft > 0) { y += N() * 0.22 * env; aspLeft--; }
    for (let j = 0; j < 4; j++) y = res[j].run(y);
    // 擦れ(さ・し)と破裂(か・た)は声道の前の方で鳴るので並列に足す
    let z = 0;
    if (cur.AF) z += fr.run(N()) * cur.AF * 0.6;
    if (burstLeft > 0) { br.set(burstF, 900); z += br.run(N()) * 0.75 * (burstLeft / (sr * 0.012)); burstLeft--; }
    // 叫び声は高域が強い (声門が鋭く閉じる)
    const yy = y + effort * 0.55 * (y - prevX); prevX = y;
    const o = yy + z;
    hp += (o - hp) * (1 - Math.exp(-2 * Math.PI * 90 / sr));
    out[i] = o - hp;
  }
  let pk = 1e-9; for (let i = 0; i < len; i++) pk = Math.max(pk, Math.abs(out[i]));
  const g = 0.9 / pk; for (let i = 0; i < len; i++) out[i] = Math.tanh(out[i] * g * 1.15) * 0.9;
  return out;
}
