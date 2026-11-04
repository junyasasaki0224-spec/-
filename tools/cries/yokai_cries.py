#!/usr/bin/env python3
"""妖怪魚の鳴き声を作る(numpy だけで音を合成する。録音や外部の音素材は使わない)。

1匹ずつ「レシピ」(下の CRIES)で鳴き声を組み立てる。
  - voice : 生き物の声(倍音に母音の響き=フォルマントをかけたもの。母音を変えながら鳴ける)
  - bell  : 鈴・風鈴・小判・提灯の「ちりん」(金属の響き)
  - clack : 下駄・瓦・骨の「からん」「かたっ」(木や陶器の響き)
  - thump : 太鼓・どすん(低い打音)
  - bubbles / crackle / zap / whoosh / hiss : 泡・火の粉・雷・風・砂
レア度で残響・厚み(コーラス、1オクターブ下の声)が増え、属性で泡・火の粉・雷・地鳴り・霊気が少し混ざる。

全魚の鳴き声は1本の音(スプライト)にまとめ、Config/Cries.luau に「始まり・長さ・文字」を書き出す。
ゲームはその区間だけを鳴らすので、Roblox にアップロードする音は1つで済む。

使い方:
  lune run tools/export_fish.luau build/fish.json
  python3 tools/cries/yokai_cries.py --defs build/fish.json --out build/cries \\
      --sprite assets/sounds/YokaiCries.ogg --luau src/shared/Config/Cries.luau
  (確認用に1匹ずつの mp3 が build/cries/<id>.mp3 にできる。--ids a,b で一部だけ作る)
"""

import argparse
import hashlib
import json
import math
import os
import re
import shutil
import subprocess
import sys
import wave

import numpy as np

SR = 44100
TAU = 2 * math.pi
# 鳴き声の頭に入れる短い無音(秒)。区間の頭で少し遅れて鳴り始めても、最初の「からん」が欠けないように
LEAD = 0.03

# ---------------------------------------------------------------------------
# 小さな道具


def smooth(u):
    u = np.clip(u, 0.0, 1.0)
    return u * u * (3 - 2 * u)


def contour(f, n):
    """音の高さの動き。数 → 一定、数の列 → 等間隔に通る、(位置, 高さ) の列 → その位置を通る。
    点の間は対数(音程)でなめらかにつなぐ"""
    if isinstance(f, (int, float)):
        return np.full(n, float(f))
    pts = list(f)
    if not isinstance(pts[0], (tuple, list)):
        pts = [(i / (len(pts) - 1), v) for i, v in enumerate(pts)]
    xs = np.array([p[0] for p in pts], dtype=float)
    ys = np.log(np.array([p[1] for p in pts], dtype=float))
    x = np.linspace(0, 1, n)
    idx = np.clip(np.searchsorted(xs, x, side="right") - 1, 0, len(xs) - 2)
    x0, x1 = xs[idx], xs[idx + 1]
    u = smooth((x - x0) / np.maximum(1e-9, x1 - x0))
    return np.exp(ys[idx] + (ys[idx + 1] - ys[idx]) * u)


def env(n, attack=0.012, release=0.08, swell=False, decay=None):
    t = np.arange(n) / SR
    dur = n / SR
    a = np.sin(0.5 * math.pi * np.clip(t / max(attack, 1e-4), 0, 1)) ** 2
    r = np.sin(0.5 * math.pi * np.clip((dur - t) / max(release, 1e-4), 0, 1)) ** 2
    e = a * r
    if swell:
        e *= 0.25 + 0.75 * smooth(t / dur * 1.6)
    if decay:
        e *= np.exp(-t / decay)
    return e


def fft_filter(x, fn):
    if len(x) == 0:
        return x
    X = np.fft.rfft(x)
    fr = np.fft.rfftfreq(len(x), 1 / SR)
    return np.fft.irfft(X * fn(fr), len(x))


def bandpass_gain(lo, hi, soft=1.4):
    def fn(fr):
        g = np.ones_like(fr)
        if lo:
            g *= 1 / (1 + (lo / np.maximum(fr, 1)) ** (2 * soft))
        if hi:
            g *= 1 / (1 + (fr / hi) ** (2 * soft))
        return g

    return fn


def soft_noise(n, rng, cutoff):
    """ゆっくり揺れる乱数(声のゆらぎ・風のゆらぎ用)"""
    x = fft_filter(rng.standard_normal(n), bandpass_gain(None, cutoff, 2))
    return x / (np.max(np.abs(x)) + 1e-9)


# 母音の響き(フォルマント): (周波数, 強さ)
VOWELS = {
    "a": ((800, 1.0), (1250, 0.55), (2650, 0.25)),
    "i": ((320, 1.0), (2400, 0.5), (3100, 0.3)),
    "u": ((360, 1.0), (850, 0.35), (2350, 0.12)),
    "e": ((480, 1.0), (1950, 0.5), (2650, 0.25)),
    "o": ((520, 1.0), (880, 0.55), (2500, 0.15)),
    "n": ((260, 1.0), (1800, 0.08), (2600, 0.05)),
    "m": ((240, 1.0), (1100, 0.06), (2500, 0.03)),
}


def vowel_tracks(vowel, n):
    """母音の列(例 "iua")を時間に沿って変化させた、3つのフォルマントの周波数と強さ"""
    seq = list(vowel)
    F = np.zeros((3, n))
    G = np.zeros((3, n))
    x = np.linspace(0, 1, n)
    if len(seq) == 1:
        for j, (fq, g) in enumerate(VOWELS[seq[0]]):
            F[j] = fq
            G[j] = g
        return F, G
    pos = np.linspace(0, 1, len(seq))
    idx = np.clip(np.searchsorted(pos, x, side="right") - 1, 0, len(seq) - 2)
    u = smooth((x - pos[idx]) / (pos[1] - pos[0]))
    for j in range(3):
        f_a = np.array([VOWELS[seq[i]][j][0] for i in idx])
        f_b = np.array([VOWELS[seq[i + 1]][j][0] for i in idx])
        g_a = np.array([VOWELS[seq[i]][j][1] for i in idx])
        g_b = np.array([VOWELS[seq[i + 1]][j][1] for i in idx])
        F[j] = np.exp(np.log(f_a) + (np.log(f_b) - np.log(f_a)) * u)
        G[j] = g_a + (g_b - g_a) * u
    return F, G


# ---------------------------------------------------------------------------
# 音の部品


def voice_raw(dur, f, vowel, tilt, shift, breath, vib, trill, rough, drive, attack, release, swell, rng):
    n = int(dur * SR)
    t = np.arange(n) / SR
    u = t / dur
    f0 = contour(f, n)
    if vib:
        rate, depth = vib
        f0 = f0 * (1 + depth * np.sin(TAU * rate * t) * smooth(u * 3))
    f0 = f0 * (1 + 0.004 * soft_noise(n, rng, 12))  # 生き物らしいゆらぎ
    phase = TAU * np.cumsum(f0) / SR
    F, G = vowel_tracks(vowel, n)
    F = F * shift
    out = np.zeros(n)
    kmax = int(min(56, 0.45 * SR / max(40.0, float(np.min(f0)))))
    widen = 1 + f0 / 500
    for k in range(1, kmax + 1):
        fk = k * f0
        a = 0.12
        for j in range(3):
            bw = (70 + 0.12 * F[j]) * widen
            a = a + G[j] / (1 + ((fk - F[j]) / bw) ** 2)
        a = a * k ** (-tilt) * (fk < 0.45 * SR)
        out += a * np.sin(k * phase + rng.uniform(0, TAU))
    out /= np.max(np.abs(out)) + 1e-9
    if breath:
        b = fft_filter(rng.standard_normal(n), bandpass_gain(900 * shift, 7000, 1.2))
        b /= np.max(np.abs(b)) + 1e-9
        out = out * (1 - breath * 0.6) + b * breath
    if trill:
        rate, depth = trill
        out *= 1 - depth * (0.5 + 0.5 * np.sin(TAU * rate * t))
    if rough:
        r = 38 + 18 * soft_noise(n, rng, 6)
        out *= 1 - rough * (0.5 + 0.5 * np.sin(TAU * np.cumsum(r) / SR))
    if drive:
        k = 1 + drive * 5
        out = np.tanh(out * k) / math.tanh(k)
    return out * env(n, attack, release, swell)


def bell_raw(dur, f, partials, decay, bright, rng):
    n = int(dur * SR)
    t = np.arange(n) / SR
    out = np.zeros(n)
    for ratio, amp, dk in partials:
        fr = f * ratio
        if fr >= 0.45 * SR:
            continue
        out += amp * np.sin(TAU * fr * t + rng.uniform(0, TAU)) * np.exp(-t / (decay * dk))
    if bright:
        out += bright * fft_filter(rng.standard_normal(n), bandpass_gain(4000, None)) * np.exp(-t / 0.01)
    return out * env(n, 0.002, min(0.05, dur / 3))


def clack_raw(freqs, decay, noise, rng):
    dur = decay * 7
    n = int(dur * SR)
    t = np.arange(n) / SR
    out = np.zeros(n)
    for i, fq in enumerate(freqs):
        out += (1 / (1 + i * 0.6)) * np.sin(TAU * fq * t + rng.uniform(0, TAU)) * np.exp(-t / (decay / (1 + i * 0.3)))
    out += noise * fft_filter(rng.standard_normal(n), bandpass_gain(1500, 9000)) * np.exp(-t / 0.004)
    return out * env(n, 0.0008, dur / 4)


def thump_raw(f, dur, click, rng):
    n = int(dur * SR)
    t = np.arange(n) / SR
    f0 = f[1] + (f[0] - f[1]) * np.exp(-t / 0.04)
    out = np.sin(TAU * np.cumsum(f0) / SR) * np.exp(-t / (dur * 0.35))
    out += click * fft_filter(rng.standard_normal(n), bandpass_gain(200, 3000)) * np.exp(-t / 0.008)
    return out * env(n, 0.001, dur / 4)


def band_noise_raw(dur, center, width, rng, a=0.02, r=0.1, swell=False):
    """中心の高さが動く帯のノイズ(風・ひゅう・しゃー)。細いノイズに中心の音を掛けて帯にする"""
    n = int(dur * SR)
    t = np.arange(n) / SR
    lp = fft_filter(rng.standard_normal(n), bandpass_gain(None, width / 2, 1.5))
    lp /= np.max(np.abs(lp)) + 1e-9
    fc = contour(center, n)
    out = lp * np.cos(TAU * np.cumsum(fc) / SR)
    return out * env(n, a, r, swell)


# ---------------------------------------------------------------------------
# 1つの鳴き声を組み立てる入れ物


class Cry:
    def __init__(self, d, seed):
        self.d = d
        self.rng = np.random.default_rng(seed)
        self.layers = []  # (開始秒, 音)
        r = RARITY[d["rarity"]]
        self.rich = r["rich"]
        self.reverb = r["reverb"]
        self.rt = r["rt"]
        self.echo = 0.0
        self.texture = True

    def add(self, at, x, gain):
        self.layers.append((at, x * gain))

    # --- 声 ---
    def voice(self, at, dur, f, vowel="a", gain=1.0, tilt=1.1, shift=1.0, breath=0.0, vib=None, trill=None, rough=0.0, drive=0.0, attack=0.015, release=0.08, swell=False, plain=False):
        args = (vowel, tilt, shift, breath, vib, trill, rough, drive, attack, release, swell, self.rng)
        x = voice_raw(dur, f, *args)
        if not plain and self.rich >= 1:
            # コーラス: 少しずらした声を2つ重ねて厚くする
            for cents, delay in ((8, 0.011), (-8, 0.017)):
                k = 2 ** (cents / 1200)
                ff = scale_f(f, k)
                y = voice_raw(dur, ff, *args)
                self.add(at + delay, y, gain * 0.45)
        if not plain and self.rich >= 2:
            # 1オクターブ下の声(大物の重み)
            self.add(at, voice_raw(dur, scale_f(f, 0.5), *args), gain * 0.4)
        self.add(at, x, gain)

    def syllables(self, at, specs, gap=0.03, **kw):
        """短い音節を続けて鳴らす。specs = [(長さ, 高さ, 母音), ...]"""
        t = at
        for spec in specs:
            dur, f, v = spec[0], spec[1], spec[2]
            extra = dict(kw)
            if len(spec) > 3:
                extra.update(spec[3])
            self.voice(t, dur, f, v, **extra)
            t += dur + gap
        return t

    # --- 物の音 ---
    def bell(self, at, f, dur=1.2, gain=0.5, partials=None, decay=0.5, bright=0.0):
        p = partials or [(1, 1, 1), (2.76, 0.45, 0.6), (5.4, 0.25, 0.35), (8.93, 0.12, 0.2)]
        self.add(at, bell_raw(dur, f, p, decay, bright, self.rng), gain)

    def chime(self, at, f, gain=0.4):
        """風鈴・かんざし(ガラスや金属の高い響き)"""
        self.bell(at, f, 1.4, gain, [(1, 1, 1), (2.32, 0.5, 0.7), (4.25, 0.3, 0.4), (6.63, 0.15, 0.25)], 0.45, 0.3)

    def coin(self, at, gain=0.45):
        self.bell(at, 2900, 0.6, gain, [(1, 1, 1), (1.51, 0.7, 0.8), (2.43, 0.4, 0.5), (3.7, 0.2, 0.3)], 0.18, 0.5)

    def clack(self, at, freqs, decay=0.03, gain=0.6, noise=0.4):
        self.add(at, clack_raw(freqs, decay, noise, self.rng), gain)

    def thump(self, at, f=(110, 55), dur=0.45, gain=0.8, click=0.3):
        self.add(at, thump_raw(f, dur, click, self.rng), gain)

    def bubbles(self, at, dur, count, f=(400, 1400), gain=0.25):
        for _ in range(count):
            t0 = at + self.rng.uniform(0, dur)
            f0 = math.exp(self.rng.uniform(math.log(f[0]), math.log(f[1])))
            d = self.rng.uniform(0.018, 0.05)
            n = int(d * 1.6 * SR)
            t = np.arange(n) / SR
            fr = f0 * (1 + 2.2 * t / d)
            x = np.sin(TAU * np.cumsum(fr) / SR) * np.exp(-t / (d * 0.45)) * env(n, 0.001, 0.005)
            self.add(t0, x, gain * self.rng.uniform(0.5, 1.0))

    def crackle(self, at, dur, rate=30, gain=0.2):
        count = int(dur * rate)
        for _ in range(count):
            t0 = at + self.rng.uniform(0, dur)
            n = int(self.rng.uniform(0.001, 0.004) * SR)
            x = fft_filter(self.rng.standard_normal(n), bandpass_gain(1800, None)) * env(n, 0.0003, 0.001)
            self.add(t0, x, gain * min(1.5, self.rng.pareto(2.5) * 0.4))

    def zap(self, at, dur=0.18, gain=0.4):
        n = int(dur * SR)
        t = np.arange(n) / SR
        f0 = 95 * (1 + 0.5 * soft_noise(n, self.rng, 40))
        ph = TAU * np.cumsum(f0) / SR
        saw = sum(np.sin(k * ph) / k for k in range(1, 30))
        nz = fft_filter(self.rng.standard_normal(n), bandpass_gain(2500, None))
        x = (0.5 * saw / 1.7 + 0.6 * nz / (np.max(np.abs(nz)) + 1e-9) * (0.5 + 0.5 * np.sign(np.sin(TAU * 23 * t)))) * env(n, 0.002, dur * 0.6, decay=dur * 0.5)
        self.add(at, x, gain)

    def whoosh(self, at, dur, center=(300, 1400), width=900, gain=0.3, swell=True):
        self.add(at, band_noise_raw(dur, center, width, self.rng, 0.03, dur * 0.4, swell), gain)

    def hiss(self, at, dur, lo=3000, gain=0.3, attack=0.02):
        n = int(dur * SR)
        x = fft_filter(self.rng.standard_normal(n), bandpass_gain(lo, 11000))
        x /= np.max(np.abs(x)) + 1e-9
        self.add(at, x * env(n, attack, dur * 0.5), gain)

    def whistle(self, at, dur, f, gain=0.35, vib=None, breath=0.25):
        n = int(dur * SR)
        t = np.arange(n) / SR
        f0 = contour(f, n)
        if vib:
            f0 = f0 * (1 + vib[1] * np.sin(TAU * vib[0] * t) * smooth(t / dur * 3))
        x = np.sin(TAU * np.cumsum(f0) / SR) + 0.08 * np.sin(2 * TAU * np.cumsum(f0) / SR)
        x += breath * band_noise_raw(dur, f, 500, self.rng, 0.01, 0.05)
        self.add(at, x * env(n, 0.03, dur * 0.35), gain)

    def rumble(self, at, dur, gain=0.35, f=55):
        n = int(dur * SR)
        t = np.arange(n) / SR
        x = fft_filter(self.rng.standard_normal(n), bandpass_gain(25, 160))
        x /= np.max(np.abs(x)) + 1e-9
        x = 0.7 * x + 0.5 * np.sin(TAU * f * t) * (0.6 + 0.4 * soft_noise(n, self.rng, 3))
        self.add(at, x * env(n, dur * 0.3, dur * 0.5), gain)

    def rattle(self, at, dur, rate=18, gain=0.4):
        """骨・歯の「かたかた」"""
        t = at
        while t < at + dur:
            fq = self.rng.uniform(1600, 2600)
            self.clack(t, (fq, fq * 1.47, fq * 2.3), decay=0.008, gain=gain * self.rng.uniform(0.6, 1), noise=0.6)
            t += 1 / rate * self.rng.uniform(0.6, 1.4)

    # --- 仕上げ ---
    def render(self):
        d = self.d
        if self.texture:
            add_texture(self, d)
        end = max(at + len(x) / SR for at, x in self.layers)
        tail = self.rt * 0.9 + 0.1
        n = int((end + tail) * SR) + 1
        out = np.zeros(n)
        for at, x in self.layers:
            i = int(at * SR)
            out[i : i + len(x)] += x[: n - i]
        out = fft_filter(out, bandpass_gain(70, 14000, 1.2))
        if self.echo:
            for k, (dl, g) in enumerate(((0.17, self.echo), (0.34, self.echo * 0.55), (0.51, self.echo * 0.3))):
                i = int(dl * SR)
                out[i:] += g * out[: n - i] * (0.92 ** k)
        dry = out / (np.max(np.abs(out)) + 1e-9)
        wet = reverb(dry, self.rt, self.rng)
        out = dry * (1 - self.reverb * 0.5) + wet * self.reverb * 2.2
        out = trim_tail(out)
        return loudness(out)


def scale_f(f, k):
    if isinstance(f, (int, float)):
        return f * k
    pts = list(f)
    if isinstance(pts[0], (tuple, list)):
        return [(p, v * k) for p, v in pts]
    return [v * k for v in pts]


def reverb(x, rt, rng):
    m = int(rt * SR)
    t = np.arange(m) / SR
    lo = fft_filter(rng.standard_normal(m), bandpass_gain(None, 3500)) * np.exp(-t * 6.9 / rt)
    hi = fft_filter(rng.standard_normal(m), bandpass_gain(3500, None)) * np.exp(-t * 6.9 / (rt * 0.45))
    ir = lo + 0.6 * hi
    ir[: int(0.012 * SR)] = 0  # 少し遅れて響き始める
    ir /= np.sqrt(np.sum(ir**2)) + 1e-9
    size = len(x) + m
    y = np.fft.irfft(np.fft.rfft(x, size) * np.fft.rfft(ir, size), size)[: len(x)]
    return y / (np.max(np.abs(y)) + 1e-9) * 0.7


def trim_tail(x, thresh=0.0008):
    a = np.abs(x) / (np.max(np.abs(x)) + 1e-9)
    idx = np.nonzero(a > thresh)[0]
    end = (idx[-1] + int(0.05 * SR)) if len(idx) else len(x)
    x = x[: min(len(x), end)]
    fade = int(0.04 * SR)
    x[-fade:] *= np.linspace(1, 0, fade)
    x[: int(0.003 * SR)] *= np.linspace(0, 1, int(0.003 * SR))
    return x


def loudness(x, target_db=-17.0, peak_db=-1.0):
    """聞こえる部分の平均の大きさをそろえ、最大でも -1dB を超えないようにする"""
    a = np.abs(x)
    win = int(0.05 * SR)
    pw = np.convolve(x * x, np.ones(win) / win, mode="same")
    active = pw > np.max(pw) * 0.05
    rms = math.sqrt(float(np.mean(pw[active]))) if np.any(active) else float(np.sqrt(np.mean(x * x)))
    g = 10 ** (target_db / 20) / (rms + 1e-9)
    y = x * g
    peak = np.max(np.abs(y))
    lim = 10 ** (peak_db / 20)
    if peak > lim:
        # 強い所だけやわらかく抑える
        y = np.tanh(y / lim * 0.9) * lim / math.tanh(0.9)
        y *= lim / (np.max(np.abs(y)) + 1e-9)
    return y


RARITY = {
    "common": {"reverb": 0.08, "rt": 0.7, "rich": 0},
    "uncommon": {"reverb": 0.11, "rt": 0.9, "rich": 0},
    "rare": {"reverb": 0.15, "rt": 1.1, "rich": 1},
    "epic": {"reverb": 0.19, "rt": 1.4, "rich": 1},
    "legendary": {"reverb": 0.25, "rt": 1.8, "rich": 2},
    "mythic": {"reverb": 0.31, "rt": 2.3, "rich": 2},
    "secret": {"reverb": 0.34, "rt": 2.7, "rich": 2},
}


def add_texture(c, d):
    """属性の気配を少しだけ混ぜる(主役の声を邪魔しない大きさ)"""
    end = max(at + len(x) / SR for at, x in c.layers)
    el = d.get("element")
    if el == "water":
        c.bubbles(0.0, min(0.5, end), 3, (500, 1500), 0.12)
    elif el == "fire":
        c.crackle(0.0, end, 18, 0.16)
    elif el == "thunder":
        c.zap(0.0, 0.1, 0.12)
    elif el == "earth":
        c.thump(0.0, (70, 40), 0.3, 0.18, 0.05)
    elif el == "spirit":
        c.whoosh(0.0, end, (1800, 2600), 1400, 0.05)
        c.echo = max(c.echo, 0.16)


# ---------------------------------------------------------------------------
# 全魚の鳴き声のレシピ。文字はゲームの吹き出し・図鑑に出る(日本語・英語)

CRIES = {}


def cry(fid, ja, en):
    def deco(fn):
        CRIES[fid] = (ja, en, fn)
        return fn

    return deco


# ---- 沼(並) ----
@cry("doro_funa", "ぼこぉ…", "Bohko...")
def _(c):
    c.voice(0.0, 0.16, (170, 140), "uo", tilt=1.7, gain=0.8)
    c.bubbles(0.05, 0.25, 4, (180, 420), 0.35)
    c.voice(0.2, 0.42, [(0, 150), (0.3, 132), (1, 100)], "ou", tilt=1.8, vib=(4, 0.02), release=0.18)


@cry("ashi_medaka", "ぴぃぴぃ♪", "Pee-pee!")
def _(c):
    c.voice(0.0, 0.11, (1700, 2300), "i", tilt=1.5, gain=0.8, release=0.04)
    c.voice(0.16, 0.16, (1800, 2500, 2200), "i", tilt=1.5, release=0.06)
    c.whistle(0.0, 0.32, (2400, 2600), 0.1)


@cry("ko_namazu", "むにゃ…ぐぅ", "Munya... guu")
def _(c):
    c.syllables(0.0, [(0.14, (220, 240), "mu"), (0.18, (240, 200), "ia")], gap=0.0, tilt=1.4)
    c.voice(0.42, 0.55, [(0, 190), (0.5, 170), (1, 120)], "u", tilt=1.7, vib=(3, 0.03), swell=True, release=0.25)


@cry("hotaru_dojo", "ぽわっ、ぽわっ", "Pwah, pwah")
def _(c):
    for i, t0 in enumerate((0.0, 0.26)):
        c.voice(t0, 0.17, (560 + i * 60, 820 + i * 60), "oa", tilt=1.9, attack=0.03, release=0.09)
        c.bell(t0 + 0.04, 1900 + i * 240, 0.5, 0.12, decay=0.15)


@cry("ame_gaeru", "けろろっ", "Kerorro!")
def _(c):
    c.voice(0.0, 0.12, (480, 520), "e", tilt=1.2, rough=0.3, release=0.03)
    c.voice(0.14, 0.32, (460, 520, 400), "oo", tilt=1.2, trill=(30, 0.85), release=0.05)
    c.bubbles(0.42, 0.1, 1, (700, 900), 0.3)


@cry("kiri_shirauo", "ふぃ〜…", "Fwee...")
def _(c):
    c.voice(0.0, 0.62, [(0, 1100), (0.4, 1300), (1, 950)], "ui", tilt=1.6, breath=0.75, attack=0.12, release=0.3, swell=True)


@cry("hasu_koi", "ぴゅるる〜", "Pyururu~")
def _(c):
    c.voice(0.0, 0.16, (880, 1180), "iu", tilt=1.4, release=0.03)
    c.voice(0.16, 0.48, [(0, 1180), (1, 760)], "u", tilt=1.4, trill=(18, 0.55), vib=(6, 0.02), release=0.18)


@cry("kappa_haze", "きゅっきゅー!", "Kyukkyu!")
def _(c):
    c.voice(0.0, 0.08, (1300, 1650), "iu", tilt=1.3, release=0.02)
    c.voice(0.12, 0.08, (1350, 1700), "iu", tilt=1.3, release=0.02)
    c.voice(0.25, 0.3, (1450, 1950), "iu", tilt=1.3, vib=(9, 0.02), release=0.1)


# ---- 沼(上) ----
@cry("kappa_koi", "クワッ! カッパッパ", "Kwah! Kappa-pa!")
def _(c):
    c.voice(0.0, 0.17, (420, 380), "ua", tilt=0.9, shift=1.15, rough=0.35, drive=0.3, release=0.04)
    c.syllables(0.3, [(0.07, 560, "a"), (0.07, 520, "a"), (0.11, 470, "a")], gap=0.04, tilt=1.0, shift=1.1, release=0.02, attack=0.004)


@cry("hitotsume_namazu", "ぎょろ…ろろ", "Gyoro... rorro")
def _(c):
    c.voice(0.0, 0.25, (210, 180), "io", tilt=1.5, rough=0.25)
    c.voice(0.32, 0.6, [(0, 175), (0.5, 160), (1, 140)], "o", tilt=1.6, trill=(22, 0.7), vib=(2.5, 0.04), release=0.25)


@cry("bake_fugu", "ぽんぽこぷー!", "Ponpoko-poo!")
def _(c):
    c.thump(0.0, (180, 110), 0.25, 0.7, 0.15)
    c.thump(0.17, (170, 100), 0.25, 0.7, 0.15)
    c.voice(0.38, 0.4, [(0, 380), (0.7, 720), (1, 690)], "uu", tilt=1.5, breath=0.25, release=0.1)
    c.whoosh(0.38, 0.35, (500, 1200), 700, 0.12)


@cry("nure_unagi", "おぉ〜い…", "Oooi...")
def _(c):
    c.voice(0.0, 0.85, [(0, 250), (0.45, 300), (1, 230)], "ooi", tilt=1.3, vib=(5, 0.025), breath=0.2, attack=0.08, release=0.3)
    c.echo = 0.22


@cry("kitsunebi_ayu", "こーん…", "Kohn...")
def _(c):
    c.voice(0.0, 0.7, [(0, 680), (0.3, 900), (1, 600)], "oon", tilt=1.2, vib=(6, 0.03), release=0.25)


@cry("sunakake_dojo", "ざざっ! シャーッ", "Zazza! Shaa!")
def _(c):
    c.hiss(0.0, 0.08, 1500, 0.55, 0.004)
    c.hiss(0.1, 0.09, 1500, 0.55, 0.004)
    c.voice(0.28, 0.42, (260, 230), "a", tilt=1.2, rough=0.5, drive=0.4, gain=0.5)
    c.hiss(0.28, 0.42, 2800, 0.6, 0.02)


@cry("tengu_ei", "ふふん! ヒュオッ", "Hmph! Hyuoh!")
def _(c):
    c.voice(0.0, 0.1, (230, 220), "n", tilt=1.6, breath=0.3, release=0.03)
    c.voice(0.13, 0.2, (250, 340), "n", tilt=1.6, breath=0.2)
    c.whoosh(0.4, 0.38, (500, 2200), 900, 0.5, swell=False)
    c.whistle(0.42, 0.3, (900, 1800), 0.25)


# ---- 沼(特上) ----
@cry("chochin_anko", "ぴかっ♪ けけけっ", "Pika! Kekeke!")
def _(c):
    c.bell(0.0, 1500, 0.9, 0.4, decay=0.3, bright=0.3)
    c.syllables(0.22, [(0.07, 760, "e"), (0.07, 700, "e"), (0.1, 640, "e")], gap=0.05, tilt=1.1, rough=0.2, attack=0.004, release=0.03)


@cry("karakasa_fugu", "ばさぁっ! べろ〜ん", "Basaa! Berohn~")
def _(c):
    c.whoosh(0.0, 0.28, (400, 1800), 1600, 0.6, swell=False)
    c.clack(0.24, (300, 520), 0.03, 0.3, 0.2)
    c.voice(0.38, 0.62, [(0, 440), (0.4, 360), (1, 300)], "eon", tilt=1.3, vib=(7, 0.06), release=0.2)


@cry("raijin_namazu", "ドドン! ゴロゴロ…", "Dodon! Gorogoro...")
def _(c):
    c.thump(0.0, (130, 62), 0.5, 1.0, 0.4)
    c.thump(0.15, (125, 58), 0.6, 1.0, 0.4)
    c.zap(0.3, 0.14, 0.3)
    c.voice(0.42, 0.8, [(0, 120), (1, 95)], "o", tilt=1.5, trill=(24, 0.6), rough=0.3, drive=0.3, release=0.3)
    c.rumble(0.42, 0.9, 0.35)


@cry("yukionna_ei", "ひゅぅ…りぃん", "Hyuu... riin")
def _(c):
    c.whoosh(0.0, 0.55, (900, 1500, 1100), 700, 0.35)
    c.voice(0.15, 0.55, [(0, 520), (1, 470)], "u", tilt=1.6, breath=0.55, vib=(5, 0.02), attack=0.1, release=0.25)
    c.chime(0.62, 2600, 0.3)
    c.chime(0.7, 3500, 0.18)


@cry("nekomata_koi", "にゃ〜ご♪", "Nyaa-go!")
def _(c):
    c.voice(0.0, 0.62, [(0, 520), (0.35, 720), (1, 430)], "iaao", tilt=1.0, vib=(6, 0.03), release=0.18)
    c.bell(0.5, 2300, 0.8, 0.25, [(1, 1, 1), (1.5, 0.6, 0.6), (2.5, 0.3, 0.4)], 0.25)
    c.bell(0.58, 2350, 0.8, 0.18, [(1, 1, 1), (1.5, 0.6, 0.6), (2.5, 0.3, 0.4)], 0.25)


@cry("nopperabo", "…………ぬぅ", "......Nuu")
def _(c):
    c.voice(0.25, 0.85, [(0, 185), (1, 165)], "nmu", tilt=1.9, swell=True, attack=0.4, release=0.3)
    c.echo = 0.3


# ---- 沼(極) ----
@cry("oni_unagi", "グオォォッ!", "Guoooh!")
def _(c):
    c.voice(0.0, 0.85, [(0, 120), (0.25, 150), (1, 92)], "uoo", tilt=1.1, rough=0.55, drive=0.6, release=0.25)
    c.clack(0.0, (420, 1080, 2210), 0.08, 0.35, 0.3)  # 金棒の「がきん」


@cry("tsuchinoko_fugu", "チー! チー! ころころ", "Chee! Chee! Korokoro")
def _(c):
    c.voice(0.0, 0.12, (2000, 2300), "i", tilt=1.5, release=0.04)
    c.voice(0.2, 0.14, (2050, 2400), "i", tilt=1.5, release=0.04)
    for i in range(5):
        c.clack(0.45 + i * 0.08, (700 + i * 30, 1650), 0.02, 0.35, 0.3)
    c.coin(0.85, 0.3)


@cry("rokurokubi_unagi", "うふふ… にょろろ〜ん", "Ufufu... nyororon~")
def _(c):
    c.syllables(0.0, [(0.08, 400, "u"), (0.08, 380, "u"), (0.12, 360, "u")], gap=0.05, tilt=1.4, breath=0.35, attack=0.01, release=0.03)
    c.voice(0.5, 0.9, [(0, 300), (0.7, 900), (1, 860)], "ion", tilt=1.3, vib=(5, 0.025), release=0.25)
    c.chime(1.2, 3000, 0.2)


@cry("kodama_koi", "ころろん…ろん…ろん", "Kororon... ron... ron")
def _(c):
    notes = (784, 659, 880, 587)
    for i, f in enumerate(notes):
        c.bell(i * 0.11, f, 0.9, 0.5, [(1, 1, 1), (3.98, 0.3, 0.35), (9.1, 0.06, 0.15)], 0.28)
    # こだま(だんだん遠くなる)
    c.bell(0.6, 587, 0.9, 0.22, [(1, 1, 1), (3.98, 0.2, 0.35)], 0.3)
    c.bell(0.95, 587, 0.9, 0.1, [(1, 1, 1), (3.98, 0.15, 0.35)], 0.3)
    c.echo = 0.25


# ---- 沼(伝説・神話・秘伝) ----
@cry("nue_namazu", "ヒョー…ヒョー…", "Hyoh... hyoh...")
def _(c):
    c.whistle(0.0, 0.55, [(0, 2300), (0.2, 2350), (1, 2050)], 0.5, vib=(5, 0.01))
    c.whistle(0.75, 0.6, [(0, 2250), (0.2, 2300), (1, 1950)], 0.45, vib=(5, 0.01))
    c.voice(0.1, 1.2, (110, 90), "o", tilt=1.6, rough=0.4, gain=0.35, swell=True, release=0.4)
    c.rumble(0.6, 1.0, 0.3)


@cry("kyubi_koi", "こぉぉん…!", "Kooohn...!")
def _(c):
    c.voice(0.0, 1.3, [(0, 600), (0.25, 860), (0.7, 820), (1, 540)], "ooun", tilt=1.15, vib=(5.5, 0.028), release=0.35)
    c.whoosh(0.05, 0.9, (300, 1400, 600), 900, 0.18)


@cry("umibozu_ei", "ぼおぉぉぉ…", "Boooooh...")
def _(c):
    c.voice(0.0, 1.5, [(0, 78), (0.3, 72), (1, 64)], "ouo", tilt=1.2, rough=0.2, attack=0.25, release=0.45)
    c.whoosh(0.0, 1.6, (180, 400, 250), 500, 0.3)
    c.bubbles(0.9, 0.7, 5, (150, 400), 0.3)


@cry("numa_mizuchi", "キュオオォン!", "Kyuoooon!")
def _(c):
    c.voice(0.0, 1.15, [(0, 480), (0.3, 1080), (0.6, 960), (1, 700)], "iuoon", tilt=1.0, vib=(6, 0.03), rough=0.15, release=0.3)
    c.voice(0.0, 1.0, (160, 120), "o", tilt=1.6, rough=0.5, gain=0.3, plain=True)
    c.zap(0.05, 0.2, 0.35)


@cry("yamata_chochin", "ボッ、ボッ、ボッ… グワァッハッハ!", "Boh-boh-boh... Gwahahaha!")
def _(c):
    for i in range(8):  # 八つの灯りがともる
        c.whoosh(i * 0.075, 0.12, (300 + i * 60, 900 + i * 90), 600, 0.35, swell=False)
        c.bell(i * 0.075 + 0.02, 520 * 2 ** (i / 12 * 1.5), 0.4, 0.12, decay=0.12)
    c.syllables(0.85, [(0.3, (170, 150), "ua", {"rough": 0.5}), (0.16, 160, "a"), (0.16, 150, "a"), (0.3, (150, 120), "a")], gap=0.05, tilt=1.1, drive=0.5, release=0.06)


# ---- ぬしの湖(並) ----
@cry("koban_funa", "ちゃりん♪ ぷく", "Ching! Puku")
def _(c):
    c.coin(0.0, 0.5)
    c.coin(0.06, 0.3)
    c.voice(0.4, 0.16, (300, 360), "u", tilt=1.8, release=0.06)
    c.bubbles(0.45, 0.1, 2, (500, 700), 0.3)


@cry("furin_kingyo", "ちりりん♪", "Chiririn!")
def _(c):
    for i, f in enumerate((2600, 3100, 2850)):
        c.chime(i * 0.09, f, 0.35)
    c.voice(0.3, 0.2, (700, 780), "o", tilt=1.7, release=0.08, gain=0.6)


@cry("dango_unagi", "もっちも〜ち", "Mocchi-mochi~")
def _(c):
    c.syllables(0.0, [(0.1, 600, "oi"), (0.12, 680, "oi"), (0.28, (760, 700), "oi")], gap=0.05, tilt=1.4, attack=0.02, release=0.05, vib=(6, 0.02))


@cry("kawara_ei", "カタッ…コトッ", "Kata... koto")
def _(c):
    c.clack(0.0, (1250, 2900, 4300), 0.035, 0.7, 0.4)
    c.clack(0.28, (900, 2150, 3400), 0.04, 0.6, 0.4)
    c.voice(0.4, 0.35, (160, 140), "o", tilt=1.8, gain=0.35, release=0.15)


@cry("geta_fugu", "からん、ころん", "Karan, koron")
def _(c):
    c.clack(0.0, (1050, 2400), 0.06, 0.7, 0.3)
    c.clack(0.3, (780, 1900), 0.07, 0.7, 0.3)
    c.voice(0.62, 0.18, (340, 420), "u", tilt=1.6, breath=0.3, gain=0.6)


# ---- ぬしの湖(上) ----
@cry("akaname_namazu", "ぺろぺろ〜ん", "Pero-pero~n")
def _(c):
    c.syllables(0.0, [(0.09, 520, "eo"), (0.09, 500, "eo"), (0.09, 540, "eo")], gap=0.02, tilt=1.3, breath=0.2, attack=0.004, release=0.02)
    c.voice(0.38, 0.45, (420, 640), "eon", tilt=1.3, vib=(7, 0.03), release=0.15)
    c.hiss(0.0, 0.3, 3500, 0.12, 0.005)


@cry("zashiki_koi", "くすくす♪ あそぼ?", "Hee-hee! Play?")
def _(c):
    c.syllables(0.0, [(0.06, 920, "u"), (0.06, 900, "u"), (0.08, 880, "u")], gap=0.05, tilt=1.4, breath=0.4, attack=0.004, release=0.03)
    c.syllables(0.42, [(0.12, 700, "a"), (0.12, 760, "o"), (0.24, (800, 1000), "o")], gap=0.03, tilt=1.2, release=0.05)


@cry("ittan_ei", "ひらひら〜…", "Flutter-flutter~")
def _(c):
    n = int(0.9 * SR)
    t = np.arange(n) / SR
    flap = 0.35 + 0.65 * (0.5 + 0.5 * np.sin(TAU * 7.5 * t))
    x = band_noise_raw(0.9, (700, 1200, 800), 1400, c.rng, 0.05, 0.3) * flap
    c.add(0.0, x, 0.55)
    c.whistle(0.15, 0.6, (850, 650), 0.18, vib=(4, 0.02))


@cry("tsurube_fugu", "どすんっ! ギギッ", "Thud! Gigi!")
def _(c):
    c.thump(0.0, (95, 45), 0.6, 1.0, 0.5)
    c.voice(0.4, 0.13, (130, 120), "i", tilt=0.9, rough=0.8, drive=0.4, release=0.03)
    c.voice(0.57, 0.18, (140, 115), "i", tilt=0.9, rough=0.8, drive=0.4, release=0.06)


# ---- ぬしの湖(特上) ----
@cry("kasha_namazu", "ニャゴォォッ! ゴロゴロ", "Nyagooh! Gorogoro")
def _(c):
    c.voice(0.0, 0.62, [(0, 420), (0.3, 560), (1, 320)], "iao", tilt=1.0, rough=0.35, drive=0.35, release=0.12)
    c.rumble(0.55, 0.7, 0.4, 60)
    c.crackle(0.55, 0.7, 40, 0.25)


@cry("ushioni_ei", "ブモォォッ!", "Bumoooh!")
def _(c):
    c.voice(0.0, 0.95, [(0, 135), (0.3, 175), (1, 118)], "muoo", tilt=1.2, rough=0.35, drive=0.3, release=0.25)


@cry("komainu_koi", "ガウッ! …ウゥ〜", "Gau! ...Grrr~")
def _(c):
    c.voice(0.0, 0.14, (330, 280), "ao", tilt=0.95, rough=0.4, drive=0.5, release=0.03)
    c.voice(0.3, 0.7, (150, 140), "u", tilt=1.5, rough=0.6, release=0.25, gain=0.8)
    c.bell(0.32, 1250, 1.0, 0.18, [(1, 1, 1), (2.1, 0.5, 0.6), (3.3, 0.25, 0.4)], 0.35)


@cry("nurari_unagi", "ぬらり…ひょん", "Nurari... hyon")
def _(c):
    c.voice(0.0, 0.7, [(0, 240), (1, 190)], "nua", tilt=1.6, vib=(3.5, 0.02), breath=0.15, release=0.2)
    c.voice(0.85, 0.16, (380, 900), "io", tilt=1.3, release=0.04)


# ---- ぬしの湖(極) ----
@cry("fujin_ei", "ビュオォォォ!", "Byuoooh!")
def _(c):
    c.whoosh(0.0, 1.0, (300, 1700, 700), 1600, 0.7)
    c.whistle(0.1, 0.8, [(0, 600), (0.4, 1500), (1, 900)], 0.25)
    c.voice(0.15, 0.7, (150, 120), "uo", tilt=1.3, rough=0.4, drive=0.3, gain=0.4)


@cry("gasha_unagi", "がしゃ…がしゃがしゃ!", "Gasha... gasha-gasha!")
def _(c):
    c.rattle(0.0, 0.18, 20, 0.5)
    c.rattle(0.42, 0.35, 22, 0.55)
    c.voice(0.1, 1.0, [(0, 190), (1, 160)], "oou", tilt=1.6, breath=0.3, gain=0.35, swell=True)


@cry("kingyo_hime", "ほほほ♪", "Ohohoho!")
def _(c):
    c.syllables(0.0, [(0.14, (900, 860), "o"), (0.14, (820, 780), "o"), (0.26, (760, 640), "o")], gap=0.04, tilt=1.3, vib=(7, 0.02), release=0.06)
    c.chime(0.62, 3200, 0.2)
    c.bubbles(0.62, 0.3, 2, (700, 1000), 0.25)


# ---- ぬしの湖(伝説・神話・秘伝) ----
@cry("yatagarasu_ei", "カァァーッ!", "Caaaw!")
def _(c):
    c.voice(0.0, 0.32, (470, 430), "aa", tilt=0.85, shift=1.2, rough=0.5, drive=0.4, release=0.06)
    c.voice(0.42, 0.55, [(0, 480), (1, 400)], "aa", tilt=0.85, shift=1.2, rough=0.5, drive=0.4, release=0.15)
    for i, f in enumerate((1047, 1319, 1568)):  # 日輪の光(明るい和音)
        c.bell(0.9 + i * 0.05, f, 1.2, 0.18, decay=0.6)


@cry("houou_koi", "ピィィーヨロロ〜", "Pyeeeh-yororo~")
def _(c):
    c.voice(0.0, 0.5, [(0, 900), (1, 1650)], "ii", tilt=1.2, vib=(6, 0.02), release=0.05)
    c.voice(0.5, 0.75, [(0, 1600), (1, 1050)], "iou", tilt=1.2, trill=(16, 0.6), release=0.25)
    c.whoosh(0.0, 1.0, (400, 2000), 1200, 0.2)


@cry("ryujin", "ゴオォォォン……", "Gooooohn...")
def _(c):
    c.voice(0.0, 1.6, [(0, 72), (0.3, 92), (1, 58)], "ooon", tilt=1.15, rough=0.35, drive=0.35, attack=0.12, release=0.45)
    c.whoosh(0.0, 1.5, (150, 500, 200), 600, 0.35)
    c.bell(1.25, 196, 2.2, 0.45, [(1, 1, 1), (2.0, 0.5, 0.8), (2.92, 0.35, 0.6), (4.1, 0.2, 0.4)], 1.1)


@cry("tsukuyomi_koi", "しゃらん…ら〜ら〜…", "Shalan... la~la~")
def _(c):
    for i in range(6):  # 錫杖のような「しゃらん」
        c.chime(i * 0.035, 3000 + 300 * ((i * 7) % 5), 0.12)
    notes = ((0.5, 0.42, 659), (0.95, 0.42, 587), (1.4, 0.75, 784))
    for t0, dur, f in notes:
        c.voice(t0, dur, (f, f * 1.003), "a", tilt=1.5, vib=(5, 0.012), breath=0.25, attack=0.08, release=0.2)
    c.echo = 0.2


# ---- 川 ----
@cry("azukiarai_haze", "しょきしょき…", "Shoki-shoki...")
def _(c):
    c.rattle(0.0, 0.32, 16, 0.4)
    c.rattle(0.42, 0.32, 16, 0.4)
    c.voice(0.82, 0.16, (900, 980), "i", tilt=1.5, release=0.06)


@cry("seoto_ayu", "さらさら♪ ぴっ", "Sara-sara! Pip")
def _(c):
    c.whoosh(0.0, 0.5, (900, 2200), 1400, 0.2)
    c.voice(0.5, 0.12, (1500, 1900), "i", tilt=1.5, release=0.05)


@cry("koke_iwana", "もそ…もそ…", "Moso... moso...")
def _(c):
    c.voice(0.0, 0.24, (240, 210), "o", tilt=1.7, attack=0.04)
    c.voice(0.38, 0.32, (230, 180), "ou", tilt=1.7, vib=(3, 0.03), release=0.2)


@cry("sasabune_medaka", "ぷかぷか♪", "Puka-puka!")
def _(c):
    c.syllables(0.0, [(0.09, (1300, 1450), "u"), (0.09, (1500, 1350), "a"), (0.09, (1300, 1450), "u"), (0.12, (1500, 1300), "a")], gap=0.05, tilt=1.5)
    c.bubbles(0.0, 0.6, 3, (900, 1600), 0.2)


@cry("ishinage_kajika", "どぼんっ!", "Doboon!")
def _(c):
    c.thump(0.0, (120, 50), 0.45, 0.8, 0.5)
    c.bubbles(0.08, 0.45, 6, (200, 600), 0.35)
    c.voice(0.5, 0.18, (320, 260), "u", tilt=1.6)


@cry("yamanba_yamame", "けけけっ…", "Kekeke...")
def _(c):
    c.syllables(0.0, [(0.09, (820, 760), "e"), (0.09, (800, 740), "e"), (0.14, (780, 640), "e")], gap=0.05, tilt=0.9, rough=0.45, drive=0.3)


@cry("kawaakago_namazu", "おぎゃあ〜", "Waaah~")
def _(c):
    c.voice(0.0, 0.18, (420, 520), "o", tilt=1.2)
    c.voice(0.2, 0.7, [(0, 560), (0.3, 640), (1, 470)], "aa", tilt=1.1, vib=(7, 0.04), release=0.2)


@cry("kawauso_haze", "おらだよ〜", "It's me~")
def _(c):
    c.syllables(0.0, [(0.12, (520, 560), "o"), (0.1, (560, 600), "a"), (0.1, (600, 560), "a"), (0.28, (560, 470), "ou")], gap=0.03, tilt=1.4)


@cry("hashihime_ayu", "うらめしや…", "Uramesiya...")
def _(c):
    c.voice(0.0, 1.0, [(0, 330), (0.5, 300), (1, 250)], "uaei", tilt=1.6, breath=0.35, vib=(4, 0.02), attack=0.1, release=0.3)
    c.echo = 0.22


@cry("shirohebi_unagi", "しゅるる… ちりん", "Shururu... ting")
def _(c):
    c.hiss(0.0, 0.55, 3500, 0.3)
    c.chime(0.6, 2637, 0.35)
    c.coin(0.75, 0.25)


@cry("kawatengu_yamame", "ヒュオッ! かかか", "Hyuoh! Kakaka")
def _(c):
    c.whoosh(0.0, 0.35, (600, 2400), 1400, 0.35)
    c.zap(0.05, 0.12, 0.25)
    c.syllables(0.4, [(0.09, (700, 650), "a"), (0.09, (690, 640), "a"), (0.13, (680, 560), "a")], gap=0.04, tilt=1.0, rough=0.3)


@cry("kawaguma_namazu", "グルル…ガウッ!", "Grrr... Gau!")
def _(c):
    c.voice(0.0, 0.55, (110, 100), "uo", tilt=1.0, rough=0.7, drive=0.4, attack=0.06)
    c.voice(0.62, 0.22, (240, 170), "ao", tilt=0.9, rough=0.5, drive=0.5)


@cry("ikada_ei", "ぎぃ…ぎぃ…", "Creak... creak...")
def _(c):
    for t0 in (0.0, 0.45):
        c.voice(t0, 0.3, (260, 300, 240), "i", tilt=0.9, rough=0.8, drive=0.2, attack=0.03)
        c.clack(t0 + 0.28, (300, 520), 0.05, 0.3, 0.6)


@cry("kappa_oyabun", "おうっ! カッパッパァ!", "Oi! Kappappaa!")
def _(c):
    c.voice(0.0, 0.2, (300, 260), "o", tilt=1.0, rough=0.4, drive=0.3)
    c.syllables(0.3, [(0.1, (420, 440), "a"), (0.1, (440, 460), "a"), (0.1, (460, 480), "a"), (0.3, (480, 380), "aa")], gap=0.03, tilt=1.0, rough=0.2)
    c.bubbles(0.9, 0.3, 3, (300, 700), 0.3)


@cry("kawahime_koi", "ふふ…こちらへ…", "Fufu... this way...")
def _(c):
    c.syllables(0.0, [(0.12, (620, 600), "u"), (0.16, (600, 560), "u")], gap=0.08, tilt=1.6, breath=0.4)
    c.voice(0.5, 0.8, [(0, 560), (1, 470)], "oiae", tilt=1.6, breath=0.3, vib=(5, 0.015), release=0.3)
    c.chime(1.2, 2093, 0.2)
    c.echo = 0.2


@cry("toryu_koi", "えいっ! ざっぱーん!", "Hup! Splaaash!")
def _(c):
    c.voice(0.0, 0.16, (700, 900), "ei", tilt=1.2)
    c.whoosh(0.2, 0.6, (400, 1800, 600), 1200, 0.4)
    c.bubbles(0.35, 0.5, 8, (300, 1200), 0.3)


@cry("maboroshi_itou", "ゴボォッ…!", "Goboh...!")
def _(c):
    c.voice(0.0, 0.7, [(0, 120), (0.4, 140), (1, 90)], "oo", tilt=1.1, rough=0.4, drive=0.3, attack=0.05, release=0.2)
    c.bubbles(0.1, 0.8, 10, (120, 500), 0.4)


@cry("suiko", "ガアァァッ!", "Gaaah!")
def _(c):
    c.voice(0.0, 0.75, [(0, 260), (0.3, 300), (1, 200)], "aa", tilt=0.85, rough=0.8, drive=0.55, release=0.15)
    c.zap(0.05, 0.16, 0.3)


@cry("o_hanzaki", "オォ…ン…", "Ooo...n...")
def _(c):
    c.voice(0.0, 1.4, [(0, 70), (0.4, 82), (1, 58)], "ooun", tilt=1.2, rough=0.3, drive=0.2, attack=0.15, release=0.4)
    c.rumble(0.0, 1.2, 0.35, 48)
    c.bell(1.1, 220, 1.8, 0.35, decay=0.9)


@cry("sake_no_osuke", "鮭の大助、今のぼる!", "Osuke the salmon, coming up!")
def _(c):
    c.thump(0.0, (90, 45), 0.5, 0.7, 0.4)
    notes = [(0.12, 392, "a"), (0.12, 392, "e"), (0.12, 440, "o"), (0.18, 392, "oo"), (0.12, 349, "u"), (0.3, 330, "e")]
    c.syllables(0.15, [(d, (f, f * 1.01), v) for d, f, v in notes], gap=0.04, tilt=1.0, rough=0.25, vib=(5, 0.02))
    c.whoosh(1.2, 0.8, (300, 1600, 500), 1200, 0.35)
    c.bubbles(1.3, 0.6, 6, (200, 800), 0.3)


# ---- 海 ----
@cry("ebisu_dai", "めでたい♪", "Medetai!")
def _(c):
    c.syllables(0.0, [(0.1, (660, 700), "e"), (0.1, (700, 740), "e"), (0.1, (740, 784), "a"), (0.22, (784, 880), "i")], gap=0.03, tilt=1.3)
    c.coin(0.62, 0.4)


@cry("iwashi_kozo", "ちぴちぴ♪", "Chipi-chipi!")
def _(c):
    for i in range(4):
        c.voice(i * 0.1, 0.06, (2000 + (i % 2) * 300, 2400), "i", tilt=1.5, release=0.03)


@cry("kaze_tobiuo", "ひゅーん!", "Hyuun!")
def _(c):
    c.whistle(0.0, 0.5, [(0, 1200), (1, 2600)], 0.35)
    c.whoosh(0.0, 0.55, (600, 2400), 1600, 0.3)


@cry("hako_fugu", "ぷっぷく!", "Puppuku!")
def _(c):
    c.syllables(0.0, [(0.08, (620, 600), "u"), (0.08, (600, 580), "u"), (0.14, (640, 520), "u")], gap=0.06, tilt=1.6)
    c.clack(0.45, (700, 1100), 0.04, 0.35, 0.3)


@cry("kage_tachiuo", "すぱっ…", "Swish...")
def _(c):
    c.hiss(0.0, 0.18, 4000, 0.45, attack=0.005)
    c.chime(0.12, 3520, 0.25)
    c.voice(0.4, 0.4, (500, 380), "u", tilt=1.7, breath=0.3, release=0.2)


@cry("kaminari_katsuo", "ビリビリッ!", "Bzzt-bzzt!")
def _(c):
    c.zap(0.0, 0.15, 0.4)
    c.zap(0.2, 0.15, 0.4)
    c.voice(0.38, 0.18, (900, 1100), "i", tilt=1.1, rough=0.3)


@cry("ningyo", "ら〜ら〜♪", "La~ la~")
def _(c):
    for t0, dur, f in ((0.0, 0.4, 784), (0.45, 0.4, 880), (0.9, 0.7, 659)):
        c.voice(t0, dur, (f, f * 1.003), "a", tilt=1.5, vib=(5, 0.015), breath=0.2, attack=0.06, release=0.18)
    c.bubbles(0.0, 1.5, 4, (800, 1500), 0.15)


@cry("funayurei_ei", "ひしゃく…かせぇ…", "Ladle... lend it...")
def _(c):
    c.voice(0.0, 1.1, [(0, 300), (0.5, 270), (1, 220)], "iae", tilt=1.6, breath=0.5, vib=(3, 0.03), attack=0.12, release=0.35)
    c.whoosh(0.0, 1.1, (300, 900), 600, 0.25)
    c.echo = 0.25


@cry("umi_osho", "なむ…なむ…", "Namu... namu...")
def _(c):
    for t0 in (0.0, 0.5):
        c.clack(t0, (380, 600), 0.05, 0.4, 0.2)  # 木魚
        c.voice(t0 + 0.05, 0.32, (150, 140), "au", tilt=1.5, attack=0.04)


@cry("maguro_daimyo", "下に〜、下に〜", "Make way~ make way~")
def _(c):
    for t0 in (0.0, 0.7):
        c.syllables(t0, [(0.14, (330, 330), "i"), (0.36, (370, 330), "ao")], gap=0.03, tilt=1.2, vib=(5, 0.02))


@cry("kurage_anko", "ぽわわ〜ん", "Powawaan")
def _(c):
    c.voice(0.0, 0.6, [(0, 500), (0.5, 700), (1, 450)], "oaa", tilt=1.8, attack=0.08, swell=True, vib=(6, 0.03))
    c.chime(0.3, 1760, 0.18)
    c.bubbles(0.0, 0.7, 4, (600, 1300), 0.2)


@cry("tomokazuki", "おいで…おいで…", "Come... come...")
def _(c):
    for t0, g in ((0.0, 1.0), (0.55, 0.6)):
        c.voice(t0, 0.45, [(0, 420), (1, 360)], "oie", tilt=1.6, breath=0.35, gain=g, attack=0.06, release=0.2)
    c.echo = 0.3


@cry("shima_umihebi", "シャーッ!", "Hssss!")
def _(c):
    c.hiss(0.0, 0.6, 2800, 0.5)
    c.voice(0.0, 0.12, (600, 500), "a", tilt=1.0, rough=0.5, gain=0.5)


@cry("jinbe_zame", "のほほ〜ん", "Nohoho~n")
def _(c):
    c.syllables(0.0, [(0.12, (200, 210), "o"), (0.12, (210, 220), "o"), (0.5, (220, 170), "oon")], gap=0.04, tilt=1.6, vib=(3, 0.03))
    c.bubbles(0.2, 0.8, 5, (150, 500), 0.3)


@cry("shiranui_ei", "ぼうっ…ぼうっ…", "Fwoom... fwoom...")
def _(c):
    for t0 in (0.0, 0.5):
        c.whoosh(t0, 0.35, (200, 800), 500, 0.35)
        c.crackle(t0, 0.35, 24, 0.25)


@cry("ryugu_tsukai", "お知らせ〜…", "A message~...")
def _(c):
    c.syllables(0.0, [(0.12, (520, 540), "o"), (0.1, (540, 560), "i"), (0.1, (560, 580), "a"), (0.4, (580, 470), "ee")], gap=0.03, tilt=1.4, vib=(5, 0.02))
    c.chime(0.9, 2349, 0.25)
    c.chime(1.05, 3136, 0.2)


@cry("isonade", "ザザァッ! グオォッ", "Splash! Guooh!")
def _(c):
    c.whoosh(0.0, 0.6, (300, 1500, 400), 1200, 0.45)
    c.voice(0.5, 0.6, [(0, 160), (0.4, 180), (1, 120)], "oo", tilt=0.95, rough=0.6, drive=0.45, release=0.15)


@cry("kin_shachi", "ガオォッ! ざばぁ", "Gaoh! Splash")
def _(c):
    c.voice(0.0, 0.45, [(0, 320), (0.4, 380), (1, 260)], "ao", tilt=0.9, rough=0.5, drive=0.45)
    c.whoosh(0.45, 0.6, (500, 2500), 1500, 0.4)
    c.bubbles(0.5, 0.5, 8, (400, 1400), 0.3)
    c.bell(0.6, 1318, 1.0, 0.25, decay=0.5)


@cry("akaei", "ズゥゥン……", "Zuuuun...")
def _(c):
    c.thump(0.0, (70, 32), 0.9, 0.9, 0.2)
    c.rumble(0.05, 1.4, 0.45, 40)
    c.voice(0.2, 1.0, [(0, 66), (1, 52)], "oon", tilt=1.3, attack=0.2, release=0.4, gain=0.6)


@cry("bake_kujira", "ボオォォォ……", "Booooooh...")
def _(c):
    c.voice(0.0, 1.8, [(0, 90), (0.3, 140), (0.6, 110), (1, 70)], "ooou", tilt=1.2, vib=(2, 0.04), attack=0.25, release=0.5)
    c.rattle(0.9, 0.5, 12, 0.3)  # 骨の鳴る音
    c.echo = 0.3


@cry("ayakashi", "あやかしぃぃ……", "Ayakashiii...")
def _(c):
    c.syllables(0.0, [(0.18, (180, 190), "a"), (0.16, (190, 200), "ia"), (0.16, (200, 210), "a")], gap=0.04, tilt=1.1, rough=0.35, drive=0.3)
    c.voice(0.6, 1.4, [(0, 210), (0.5, 240), (1, 150)], "ii", tilt=1.1, breath=0.3, vib=(4, 0.03), rough=0.3, release=0.5)
    c.whoosh(0.0, 2.0, (150, 700, 200), 600, 0.35)
    c.bell(1.5, 147, 2.4, 0.4, decay=1.2)
    c.echo = 0.3


# ---- 実際の生息地に合わせて足した淡水魚 ----
@cry("yomeiri_tanago", "こんこん…ちりん♪", "Kon-kon... ting!")
def _(c):
    c.syllables(0.0, [(0.1, (900, 950), "o"), (0.12, (950, 880), "o")], gap=0.06, tilt=1.4)
    c.chime(0.38, 2637, 0.3)
    c.chime(0.5, 3136, 0.22)


@cry("yukimi_wakasagi", "ぴちぴち…しーん", "Pichi-pichi... hush")
def _(c):
    for i in range(3):
        c.voice(i * 0.09, 0.05, (2200, 2500), "i", tilt=1.5, release=0.03, gain=0.7)
    c.whoosh(0.35, 0.5, (1500, 3000), 1200, 0.12)


@cry("tsukimi_himemasu", "ふわぁ…", "Fwaah...")
def _(c):
    c.voice(0.0, 0.6, [(0, 520), (0.4, 600), (1, 460)], "uaa", tilt=1.6, breath=0.3, attack=0.08, release=0.25)
    c.chime(0.55, 1760, 0.18)


@cry("yoroi_chouzame", "ガチン…ゴォォ", "Clank... Goooh")
def _(c):
    c.clack(0.0, (420, 760, 1300), 0.06, 0.6, 0.3)
    c.voice(0.2, 0.9, [(0, 120), (0.5, 135), (1, 95)], "oo", tilt=1.2, rough=0.4, drive=0.25, attack=0.1, release=0.3)
    c.bubbles(0.3, 0.6, 5, (150, 500), 0.3)


# ---- 百鬼の祠の限定の魚(どれも鈴や鐘の「神さまの気配」が混ざる) ----
@cry("gin_kitsune", "こぉん…しゃらん♪", "Ko-on... shalan!")
def _(c):
    c.voice(0.0, 0.5, [(0, 820), (0.3, 1050), (1, 760)], "oo", tilt=1.4, vib=(5, 0.02), release=0.2)
    for i, f in enumerate((2400, 2900, 3500)):
        c.bell(0.45 + i * 0.07, f, 0.9, 0.22, decay=0.4)
    c.echo = 0.22


@cry("yozakura_ei", "ふわぁ…はらはら", "Fwaah... hara-hara")
def _(c):
    c.voice(0.0, 0.9, [(0, 300), (0.5, 340), (1, 260)], "ua", tilt=1.6, breath=0.5, attack=0.2, release=0.4, swell=True)
    for i in range(6):
        c.chime(0.5 + i * 0.12, 1800 + (i % 3) * 300, 0.12)
    c.echo = 0.25


@cry("raijin_fugu", "ゴロゴロ…ドン!", "Goro-goro... DON!")
def _(c):
    c.rumble(0.0, 0.7, 0.4, 60)
    c.voice(0.1, 0.4, (300, 260), "o", tilt=1.2, rough=0.4, release=0.1)
    c.thump(0.75, (120, 45), 0.6, 1.0, 0.4)
    c.zap(0.72, 0.2, 0.35)


@cry("hi_no_tori", "キュオォォン!", "Kyuoooon!")
def _(c):
    c.voice(0.0, 0.9, [(0, 900), (0.2, 1400), (0.7, 1250), (1, 980)], "iuo", tilt=1.2, vib=(6, 0.03), drive=0.2, release=0.3)
    c.crackle(0.0, 1.2, 30, 0.25)
    c.bell(0.6, 1760, 1.4, 0.3, decay=0.6)
    c.echo = 0.25


@cry("koku_ryu", "グルォォォ…", "Gruoooh...")
def _(c):
    c.voice(0.0, 1.3, [(0, 110), (0.4, 150), (1, 90)], "uoo", tilt=1.0, rough=0.5, drive=0.4, vib=(3, 0.03), release=0.4)
    c.rumble(0.2, 1.1, 0.35, 45)
    c.zap(0.9, 0.25, 0.3)
    c.echo = 0.28


@cry("yuki_hime", "しんしん…ふぅ…", "Shin-shin... fuu...")
def _(c):
    c.voice(0.0, 1.1, [(0, 1250), (0.5, 1100), (1, 900)], "ii", tilt=1.6, breath=0.7, attack=0.25, release=0.5, swell=True)
    c.hiss(0.6, 0.8, 4500, 0.15)
    for i in range(4):
        c.chime(0.3 + i * 0.25, 3000 + i * 250, 0.1)
    c.echo = 0.3


@cry("amaterasu_kujira", "オォォ…ン(光の音)", "Ooooh... (light)")
def _(c):
    c.voice(0.0, 2.0, [(0, 110), (0.4, 165), (0.8, 220), (1, 196)], "oooa", tilt=1.3, vib=(2.5, 0.02), attack=0.4, release=0.6, swell=True)
    c.voice(0.3, 1.7, [(0, 330), (1, 392)], "a", tilt=1.5, breath=0.2, gain=0.4, attack=0.5, release=0.6)
    c.bell(1.0, 523, 2.4, 0.45, decay=1.2)
    c.bell(1.3, 784, 2.0, 0.3, decay=1.0)
    c.echo = 0.34


@cry("yamata_shachi", "ガアアァァ!!(八つの声)", "GAAAAH!! (eight voices)")
def _(c):
    for i in range(4):
        c.voice(i * 0.08, 1.2 - i * 0.1, [(0, 140 + i * 30), (0.4, 190 + i * 35), (1, 110 + i * 20)], "aao", tilt=1.0, rough=0.45, drive=0.45, gain=0.55, release=0.4)
    c.thump(0.0, (90, 40), 0.8, 0.8, 0.3)
    c.rumble(0.3, 1.2, 0.4, 40)
    c.bell(1.2, 98, 2.4, 0.5, decay=1.4)
    c.echo = 0.32


def auto_recipe(c, d):
    """レシピの無い魚(新しく足した魚)の鳴き声。体の形・目・レア度から作る"""
    base = {"koi": 700, "catfish": 220, "puffer": 450, "eel": 380, "angler": 300, "ray": 260, "shark": 200, "orca": 330, "salmon": 260, "salamander": 120, "whale": 110, "sturgeon": 160}.get(d["shape"], 400)
    base *= (1.0 / max(0.5, d.get("visualScale", 1))) ** 0.5
    vowel = {"koi": "iu", "catfish": "uo", "puffer": "uu", "eel": "ion", "angler": "ea", "ray": "ou", "shark": "ao", "orca": "ia", "salmon": "oa", "salamander": "ou", "whale": "oou", "sturgeon": "uo"}.get(d["shape"], "a")
    eyes = d.get("eyes") or "normal"
    dur = 0.4 + 0.12 * RARITY_ORDER[d["rarity"]]
    if eyes == "angry":
        c.voice(0.0, dur, (base * 0.7, base * 0.55), "ao", tilt=1.1, rough=0.5, drive=0.4)
    elif eyes == "sleepy":
        c.voice(0.0, dur * 1.2, (base, base * 0.7), vowel, tilt=1.5, vib=(4, 0.03), swell=True)
    elif eyes in ("cute", "dot"):
        c.syllables(0.0, [(0.1, base * 1.2, vowel), (dur * 0.6, (base * 1.25, base * 1.5), vowel)], gap=0.05, tilt=1.4)
    else:
        c.voice(0.0, dur, (base, base * 1.2, base * 0.9), vowel, tilt=1.3, vib=(6, 0.02))


RARITY_ORDER = {"common": 1, "uncommon": 2, "rare": 3, "epic": 4, "legendary": 5, "mythic": 6, "secret": 7}

# ---------------------------------------------------------------------------
# 書き出し


def make(d):
    seed = int(hashlib.sha1(d["id"].encode()).hexdigest()[:8], 16)
    c = Cry(d, seed)
    if d["id"] in CRIES:
        ja, en, fn = CRIES[d["id"]]
        fn(c)
    else:
        name = d.get("ja") or d["id"]
        ja, en = "…!", "...!"
        print(f"  {d['id']}: レシピが無いので形から自動で作りました({name})", file=sys.stderr)
        auto_recipe(c, d)
    x = np.concatenate([np.zeros(int(LEAD * SR)), c.render()])
    return x, ja, en


def write_wav(path, x):
    pcm = (np.clip(x, -1, 1) * 32767).astype("<i2")
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(pcm.tobytes())
    return pcm


def ffmpeg(args):
    subprocess.run(["ffmpeg", "-hide_banner", "-loglevel", "error", "-y", *args], check=True)


def lua_str(s):
    return '"' + s.replace("\\", "\\\\").replace('"', '\\"') + '"'


def write_luau(path, rows, total, digest):
    old_id, old_hash = "rbxassetid://0", ""
    if os.path.exists(path):
        src = open(path, encoding="utf-8").read()
        m = re.search(r'soundId = "([^"]*)"', src)
        h = re.search(r'audioHash = "([^"]*)"', src)
        old_id = m.group(1) if m else old_id
        old_hash = h.group(1) if h else ""
    sound_id = old_id if old_hash == digest else "rbxassetid://0"
    if old_hash and old_hash != digest and old_id != "rbxassetid://0":
        print("  音が変わりました。YokaiCries.ogg をアップロードし直して soundId を入れ直してください", file=sys.stderr)
    lines = [
        "--!strict",
        "-- 妖怪魚の鳴き声(tools/cries/yokai_cries.py が作る表。手で書き換えるのは soundId だけ)",
        "-- 全魚の鳴き声は assets/sounds/YokaiCries.ogg の1本にまとめてあり、魚ごとに start 秒から length 秒だけ鳴らす。",
        '-- Roblox に音をアップロードしたら soundId を "rbxassetid://<番号>" にする(0 のままなら文字の吹き出しだけ出る)。',
        "-- audioHash は音の中身の印。音を作り直すと変わり、そのときは soundId が 0 に戻る(古い音と区間がずれないように)",
        "return {",
        f"\tsoundId = {lua_str(sound_id)},",
        f"\taudioHash = {lua_str(digest)},",
        f"\tlength = {total:.3f}, -- 音のファイル全体の長さ(秒)",
        "\tcries = {",
    ]
    for fid, start, length, ja, en in rows:
        lines.append(f"\t\t{fid} = {{ start = {start:.3f}, length = {length:.3f}, ja = {lua_str(ja)}, en = {lua_str(en)} }},")
    lines.append("\t} :: { [string]: { start: number, length: number, ja: string, en: string } },")
    lines.append("}")
    open(path, "w", encoding="utf-8").write("\n".join(lines) + "\n")
    # 長い行は StyLua の形にそろえる(CI の stylua --check に通るように)
    if shutil.which("stylua"):
        subprocess.run(["stylua", path], check=True)
    else:
        print("  stylua が見つかりません。stylua src を実行してから commit してください", file=sys.stderr)
    print("wrote", path)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--defs", required=True, help="tools/export_fish.luau の出力")
    ap.add_argument("--out", required=True, help="1匹ずつの確認用 mp3 を置く場所")
    ap.add_argument("--ids", default="")
    ap.add_argument("--sprite", default="", help="全魚をまとめた音(.ogg)の書き出し先")
    ap.add_argument("--luau", default="", help="Config/Cries.luau の書き出し先")
    ap.add_argument("--gap", type=float, default=0.5, help="鳴き声どうしの間の無音(秒)")
    a = ap.parse_args()
    defs = json.load(open(a.defs))
    if isinstance(defs, dict):
        defs = defs["fish"]
    ids = [x for x in a.ids.split(",") if x]
    if ids and (a.sprite or a.luau):
        # 一部の魚だけの音で、全魚の音と表を上書きしてしまわないように
        ap.error("--ids は確認用(mp3 だけ作る)です。--sprite / --luau と一緒には使えません")
    os.makedirs(a.out, exist_ok=True)
    gap = np.zeros(int(a.gap * SR))
    parts = [gap]
    rows = []
    pos = a.gap
    for d in defs:
        if ids and d["id"] not in ids:
            continue
        x, ja, en = make(d)
        wav = os.path.join(a.out, d["id"] + ".wav")
        write_wav(wav, x)
        ffmpeg(["-i", wav, "-c:a", "libmp3lame", "-b:a", "96k", os.path.join(a.out, d["id"] + ".mp3")])
        os.remove(wav)
        length = len(x) / SR
        rows.append((d["id"], pos, length, ja, en))
        parts += [x, gap]
        pos += length + a.gap
        print(f"{d['id']}: {length:.2f}s  {ja}")
    missing = [k for k in CRIES if k not in {d['id'] for d in defs}]
    if missing:
        print("  表に無い魚のレシピ:", ", ".join(missing), file=sys.stderr)
    if a.sprite:
        sprite = np.concatenate(parts)
        tmp = os.path.join(a.out, "_sprite.wav")
        pcm = write_wav(tmp, sprite)
        digest = hashlib.sha1(pcm.tobytes()).hexdigest()[:12]
        os.makedirs(os.path.dirname(os.path.abspath(a.sprite)), exist_ok=True)
        ffmpeg(["-i", tmp, "-c:a", "libvorbis", "-q:a", "6", a.sprite])
        os.remove(tmp)
        print(f"sprite {a.sprite}: {len(sprite) / SR:.1f}s, {os.path.getsize(a.sprite) // 1024} KB")
        if a.luau:
            write_luau(a.luau, rows, len(sprite) / SR, digest)


if __name__ == "__main__":
    main()
