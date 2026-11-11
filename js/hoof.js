// ============================================================
//  馬の音をサンプル単位で合成する (Web Audio にも DOM にも依存しない純粋な関数)
//   synthHoof   : 蹄が芝を叩く1発。地面の共鳴 + 踏み抜く音 + かかと→つま先の二段の当たり
//                 + 跳ね上がる芝と土の粒 + 落ちてくる土塊。道悪用は水を含んだ音
//   synthBreath : 襲歩の呼吸。完歩ごとの強い呼気(鼻翼が震える音)と、短い吸気
//   synthTack   : ハミや鐙(あぶみ)が鳴る金属音
//  返り値はモノラルの Float32Array (ピーク ≒ 0.95)
// ============================================================
export function mulberry(seed) {
  let a = seed >>> 0;
  return function () {
    a = (a + 0x6d2b79f5) | 0;
    let t = Math.imul(a ^ (a >>> 15), 1 | a);
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

// 状態変数フィルタ (Chamberlin)。fc は毎サンプル変えてよい
class SVF {
  constructor(sr) { this.sr = sr; this.l = 0; this.b = 0; this.h = 0; }
  run(x, fc, q) {
    if (fc !== this.fc) { this.fc = fc; this.f = 2 * Math.sin(Math.PI * Math.min(fc, this.sr * 0.16) / this.sr); }
    const f = this.f;
    this.l += f * this.b;
    this.h = x - this.l - this.b / q;
    this.b += f * this.h;
    return this;
  }
}

function finish(out, sr, drive, peak) {
  let pk = 1e-9;
  for (let i = 0; i < out.length; i++) { out[i] = Math.tanh(out[i] * drive); pk = Math.max(pk, Math.abs(out[i])); }
  const fade = Math.floor(sr * 0.015), k = peak / pk;
  for (let i = 0; i < out.length; i++) out[i] *= k * (i > out.length - fade ? (out.length - i) / fade : 1);
  return out;
}

export function synthHoof(sr, seed, wet = false) {
  const R = mulberry(seed), N = () => R() * 2 - 1, TP = Math.PI * 2;
  const len = Math.floor(sr * 0.45), off = Math.floor(sr * 0.002);
  const imp = new Float32Array(len), crunch = new Float32Array(len), click = new Float32Array(len);
  const spray = new Float32Array(len), clod = new Float32Array(len), suck = new Float32Array(len), thud = new Float32Array(len);
  const fs = wet ? 0.86 : 1, dk = wet ? 1.45 : 1;
  // 地面と蹄の共鳴: 低いほど長く残る。着地の瞬間は音程が少し高い
  const modes = [[52, 0.8, 24], [84, 0.8, 30], [128, 0.85, 36], [190, 0.75, 44], [280, 0.55, 55], [415, 0.36, 70], [620, 0.2, 90], [910, 0.1, 120]]
    .map(([f, a, d]) => ({ f: f * fs * (0.9 + R() * 0.2), a: a * (0.8 + R() * 0.4), d: d * dk * (0.85 + R() * 0.3), ph: R() * TP }));
  // かかと → つま先 (蹄が転がる)、ときどき軽く滑る
  const contacts = [[0, 1], [0.008 + R() * 0.009, 0.42 + R() * 0.2]];
  if (R() < 0.35) contacts.push([0.024 + R() * 0.012, 0.15 + R() * 0.1]);
  const am = Math.exp(-2200 / sr), gm = Math.exp(-60 / sr);
  for (const [tc, ca] of contacts) {
    const s0 = off + Math.floor(tc * sr);
    for (const m of modes) {
      let env = ca * m.a, g = 1, a1 = 1, c = Math.cos(m.ph), sn = Math.sin(m.ph), cw = 1, sw = 0;
      const dm = Math.exp(-m.d / sr), gm16 = Math.pow(gm, 16);
      for (let i = s0, j = 0; i < len && env > 2e-4; i++, j++) {
        if ((j & 15) === 0) { const w = TP * m.f * (1 + 0.32 * g) / sr; cw = Math.cos(w); sw = Math.sin(w); g *= gm16; }
        imp[i] += env * (1 - a1) * sn;
        const c2 = c * cw - sn * sw; sn = c * sw + sn * cw; c = c2; env *= dm; a1 *= am;
      }
    }
    let e = ca, e2 = ca, a1 = 1, e3 = ca;
    const tm = Math.exp(-36 / sr);
    const cm = Math.exp(-(wet ? 34 : 48) / sr), km = Math.exp(-650 / sr);
    for (let i = s0; i < len && e3 > 2e-4; i++) { crunch[i] += N() * e * (1 - a1); click[i] += N() * e2; thud[i] += N() * e3 * (1 - a1); e *= cm; e2 *= km; e3 *= tm; a1 *= am; }
  }
  // 跳ね上がる芝・土の粒
  const nG = wet ? 46 : 32;
  for (let k = 0; k < nG; k++) {
    const t0 = 0.016 + Math.pow(R(), 1.6) * (wet ? 0.3 : 0.24), n = Math.floor((0.003 + R() * 0.009) * sr), a = (0.05 + R() * 0.14) * (1 - t0 / 0.36);
    const s0 = off + Math.floor(t0 * sr);
    for (let j = 0; j < n && s0 + j < len; j++) spray[s0 + j] += N() * a * Math.sin(Math.PI * j / n);
  }
  { // 粒の下地 (シャッという擦れ)
    const s0 = off + Math.floor(0.012 * sr), up = Math.exp(-60 / sr), dn = Math.exp(-(wet ? 9 : 14) / sr), amp = wet ? 0.32 : 0.16;
    let u = 1, d = 1;
    for (let i = s0; i < len; i++) { spray[i] += N() * (1 - u) * d * amp; u *= up; d *= dn; }
  }
  // 落ちてくる土塊
  const nC = 4 + Math.floor(R() * 5);
  for (let k = 0; k < nC; k++) {
    const s0 = off + Math.floor((0.16 + R() * 0.24) * sr), n = Math.floor((0.008 + R() * 0.01) * sr), a = 0.05 + R() * 0.07;
    for (let j = 0; j < n && s0 + j < len; j++) clod[s0 + j] += N() * a * Math.exp(-j / n * 4);
  }
  // 道悪: 蹄を抜くときの吸いつく音
  if (wet) {
    const s0 = off + Math.floor(0.03 * sr), up = Math.exp(-40 / sr), dn = Math.exp(-16 / sr);
    let u = 1, d = 1;
    for (let i = s0; i < len; i++) { suck[i] = N() * (1 - u) * d; u *= up; d *= dn; }
  }
  // フィルタして混ぜる
  const out = new Float32Array(len);
  const fT = new SVF(sr), fT2 = new SVF(sr), fC = new SVF(sr), fK = new SVF(sr), fS = new SVF(sr), fS2 = new SVF(sr), fL = new SVF(sr), fU = new SVF(sr);
  const cTop = wet ? 2200 : 3600, cBot = wet ? 320 : 480, sprayF = wet ? 3000 + R() * 1500 : 1500 + R() * 1100;
  let sweep = 1;
  const sm = Math.exp(-45 / sr);
  for (let i = 0; i < len; i++) {
    const t = Math.max(0, (i - off) / sr);
    const c = fC.run(crunch[i], (i & 3) ? fC.fc : cTop * sweep + cBot, 0.8).l; sweep *= sm;
    const k = fK.run(click[i], 3800, 0.7).l;
    const th = fT.run(thud[i], wet ? 330 : 420, 1.3).b + fT2.run(thud[i], wet ? 640 : 780, 1.6).b * 0.6;
    fS.run(spray[i], sprayF, 0.9); fS2.run(spray[i], 6500, 0.7);
    const s = fS.b * 1.5 + fS2.h * 0.08;
    const l = fL.run(clod[i], 380, 0.7).l;
    const u = wet ? fU.run(suck[i], (i & 7) ? (fU.fc || 520) : 520 + 900 * (1 - Math.exp(-t * 12)), 3).b : 0;
    out[i] = imp[i] * 0.5 + th * 2.6 + c * 1.6 + k * 0.4 + s * 1.3 + l * 1.6 + u * 0.9;
  }
  return finish(out, sr, 2.1, 0.95);
}

// 襲歩の呼吸 (呼気は完歩ごとに強く吐き、鼻翼が震えて「ブルル」と鳴る)
export function synthBreath(sr, seed, inhale = false) {
  const R = mulberry(seed), N = () => R() * 2 - 1;
  const len = Math.floor(sr * (inhale ? 0.22 : 0.34)), out = new Float32Array(len);
  const forms = inhale ? [[1300 * (0.9 + R() * 0.2), 3, 0.6], [3200, 2, 0.4]] : [[360 * (0.9 + R() * 0.2), 4, 1], [980 * (0.9 + R() * 0.2), 5, 0.55], [2600, 2, 0.25]];
  const fl = forms.map(() => new SVF(sr)), chest = new SVF(sr);
  const flut = 22 + R() * 14, depth = inhale ? 0.2 : 0.55, ph0 = R() * 6.28;
  for (let i = 0; i < len; i++) {
    const t = i / sr;
    let env;
    if (inhale) env = (1 - Math.exp(-t * 20)) * Math.exp(-Math.max(0, t - 0.05) * 22);
    else env = (1 - Math.exp(-t * 45)) * (t < 0.08 ? 1 : Math.exp(-(t - 0.08) * 18));
    const n = N();
    let x = 0;
    for (let k = 0; k < forms.length; k++) x += fl[k].run(n, forms[k][0], forms[k][1]).b * forms[k][2];
    if (!inhale) x += chest.run(n, 160, 0.7).l * 0.4;
    out[i] = x * env * (1 - depth / 2 + (depth / 2) * Math.sin(Math.PI * 2 * flut * t + ph0));
  }
  return finish(out, sr, 1.2, 0.9);
}

// ハミ・鐙の金属音 (非整数倍音の短い響き + 二度目の跳ね返り)
export function synthTack(sr, seed) {
  const R = mulberry(seed), N = () => R() * 2 - 1;
  const len = Math.floor(sr * 0.32), out = new Float32Array(len), base = 2400 + R() * 900;
  const parts = [[1, 0.5, 18], [1.47, 0.35, 24], [2.09, 0.25, 30], [2.76, 0.15, 40], [3.6, 0.1, 55]].map(([r, a, d]) => [base * r * (0.97 + R() * 0.06), a, d, R() * 6.28]);
  const hits = [[0, 1], [0.04 + R() * 0.03, 0.45]];
  for (const [th, ha] of hits) {
    const s0 = Math.floor(th * sr);
    for (const [f, a, d, ph] of parts) {
      const w = Math.PI * 2 * f / sr, cw = Math.cos(w), sw = Math.sin(w), dm = Math.exp(-d / sr);
      let c = Math.cos(ph), sn = Math.sin(ph), e = ha * a;
      for (let i = s0; i < len && e > 1e-4; i++) { out[i] += e * sn; const c2 = c * cw - sn * sw; sn = c * sw + sn * cw; c = c2; e *= dm; }
    }
    for (let j = 0; j < sr * 0.002 && s0 + j < len; j++) out[s0 + j] += N() * 0.3 * ha;
  }
  return finish(out, sr, 1.0, 0.8);
}

// 襲歩の4拍: 後肢(反手前→手前) → 前肢(反手前→手前) をほぼ等間隔で畳みかけ、残りは空中期 (「パカラッ」)
// サラブレッドの競走速度(1完歩 約0.42秒)での着地間隔 0.04〜0.07秒 に合わせた位相。最後の手前前肢が一番重い
export const GALLOP_BEATS = [0, 0.11, 0.26, 0.39];
export const GALLOP_ACCENT = [0.78, 0.86, 0.93, 1.12];
export const GALLOP_RATE = [0.95, 0.97, 1.0, 1.02];
