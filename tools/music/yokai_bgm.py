"""あやかし釣りの BGM を numpy だけで作る(和の音階・琴/三味線/尺八/太鼓ふうの音)。

場所ごとに1曲(ループ):
  village : 釣り村とぬしの湖。陽音階、のんびり。琴のアルペジオ + 尺八 + 木魚
  swamp   : 沼。陰音階(都節)、ゆっくり・少しあやしい。低い持続音 + まばらな琴 + 風鈴
  river   : 川。陽音階、流れるような三味線 + 小太鼓
  sea     : 海。琉球音階、明るい三線ふう + 波の音
  battle  : バトル。陰音階、速い。太鼓 + 三味線のリフ + 尺八
  boss    : ボス戦。和の音は使わない。短調・168BPM。ドラム + 歪んだギター + 金管 + 弦 + 合唱
継ぎ目なくループする(最後の残響は曲の頭に重ねる)。

使い方:
  python tools/music/yokai_bgm.py                       # assets/sounds/bgm/*.ogg と Config/Music.luau を作る
  python tools/music/yokai_bgm.py --preview build/bgm   # 試し聞き用の mp3 も書き出す
  python tools/music/yokai_bgm.py --only battle

Roblox に .ogg をアップロードしたら Config/Music.luau の各曲の soundId を書き換える。
音を作り直すと audioHash が変わり、その曲の soundId は 0 に戻る(古い音のままにならないように)。
"""

import argparse
import hashlib
import math
import os
import re
import shutil
import subprocess
import sys
import wave

import numpy as np

SR = 44100
ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

# 音階(半音、主音からの距離)
SCALES = {
    "yo": [0, 2, 5, 7, 9],  # 陽音階
    "in": [0, 1, 5, 7, 8],  # 陰音階(都節)
    "ryukyu": [0, 4, 5, 7, 11],  # 琉球音階
}


def midi_hz(m):
    return 440.0 * 2 ** ((m - 69) / 12)


def degree(scale, root, d):
    """音階の d 番目の音(d は負でもよい)の MIDI 番号"""
    s = SCALES[scale]
    o, i = divmod(d, len(s))
    return root + 12 * o + s[i]


# 楽器 ---------------------------------------------------------------------


def pluck(f, dur, bright=1.0, decay=1.0, buzz=0.0, rng=None):
    """琴・三味線ふうのはじく音(倍音ごとに減衰の速さが違う)"""
    n = int(dur * SR)
    t = np.arange(n) / SR
    out = np.zeros(n)
    for k in range(1, 14):
        fk = f * k * (1 + 0.0007 * k * k)  # 弦の少しのずれ
        if fk > SR * 0.45:
            break
        amp = (1.0 / k ** (1.25 - 0.35 * bright)) * (1 + buzz * (k > 4) * 0.8)
        d = (1.6 + 0.9 * k) / decay
        out += amp * np.exp(-t * d) * np.sin(2 * math.pi * fk * t + k * 0.7)
    # はじいた瞬間の雑音
    if rng is not None:
        m = min(n, int(0.012 * SR))
        out[:m] += rng.standard_normal(m) * np.linspace(0.35, 0, m) * bright
    att = np.minimum(1, t / 0.003)
    return out * att * 0.35


def flute(f, dur, rng, vib=1.0, breath=0.35, bend=True):
    """尺八ふう: やわらかい音 + 息の音 + 遅れてかかるビブラート、下からすくい上げ"""
    n = int(dur * SR)
    t = np.arange(n) / SR
    vdepth = 0.012 * vib * np.clip((t - 0.25) / 0.5, 0, 1)
    pitch = f * (1 + vdepth * np.sin(2 * math.pi * 5.2 * t))
    if bend:
        pitch *= 1 - 0.035 * np.exp(-t / 0.07)
    ph = 2 * math.pi * np.cumsum(pitch) / SR
    tone = np.sin(ph) + 0.25 * np.sin(2 * ph) + 0.08 * np.sin(3 * ph)
    noise = lowpass(rng.standard_normal(n), 0.25) * breath
    env = np.minimum(1, t / 0.09) * np.minimum(1, (dur - t) / 0.18).clip(0, 1)
    swell = 0.8 + 0.2 * np.sin(math.pi * np.clip(t / max(dur, 0.01), 0, 1))
    return (tone + noise * (0.6 + 0.4 * np.exp(-t / 0.15))) * env * swell * 0.22


def pad(freqs, dur):
    """持続音(ゆっくりうなる)"""
    n = int(dur * SR)
    t = np.arange(n) / SR
    out = np.zeros(n)
    for f in freqs:
        for det in (-0.6, 0.6):
            ff = f + det
            out += np.sin(2 * math.pi * ff * t) + 0.3 * np.sin(4 * math.pi * ff * t)
    env = np.minimum(1, t / 1.2) * np.minimum(1, (dur - t) / 1.2).clip(0, 1)
    return out * env * 0.05 / max(1, len(freqs))


def taiko(dur=0.9, f0=70, rng=None, hard=1.0):
    """大太鼓: 下がっていく低い音 + 皮をたたく音"""
    n = int(dur * SR)
    t = np.arange(n) / SR
    f = f0 * (1 + 0.6 * np.exp(-t / 0.03))
    ph = 2 * math.pi * np.cumsum(f) / SR
    body = np.sin(ph) * np.exp(-t / (0.28 * hard))
    hit = lowpass(rng.standard_normal(n), 0.15) * np.exp(-t / 0.02) * 0.5
    return (body + hit) * 0.9


def shime(rng, dur=0.18):
    """締太鼓: 高く短い音"""
    n = int(dur * SR)
    t = np.arange(n) / SR
    body = np.sin(2 * math.pi * 330 * t) * np.exp(-t / 0.04)
    hit = rng.standard_normal(n) * np.exp(-t / 0.012) * 0.6
    return (body + lowpass(hit, 0.5)) * 0.35


def woodblock(f=900, dur=0.12):
    n = int(dur * SR)
    t = np.arange(n) / SR
    return (np.sin(2 * math.pi * f * t) + 0.4 * np.sin(2 * math.pi * f * 2.7 * t)) * np.exp(-t / 0.025) * 0.25


def bell(f, dur=3.0):
    """風鈴・鐘(倍音がずれた金属の音)"""
    n = int(dur * SR)
    t = np.arange(n) / SR
    out = np.zeros(n)
    for r, a, d in ((1, 1, 1.2), (2.76, 0.5, 0.7), (5.4, 0.25, 0.4), (8.9, 0.12, 0.25)):
        out += a * np.sin(2 * math.pi * f * r * t) * np.exp(-t / d)
    return out * np.minimum(1, t / 0.002) * 0.12


def waves(n, rng, rate=0.09):
    """波の音(ゆっくり寄せては返す雑音)"""
    t = np.arange(n) / SR
    noise = lowpass(rng.standard_normal(n), 0.06)
    swell = 0.5 + 0.5 * np.sin(2 * math.pi * rate * t) ** 2
    return noise * swell * 0.25


# 道具 -----------------------------------------------------------------------


def lowpass(x, a):
    """1次のローパス(a: 0〜1、小さいほどこもる)。FFT でまとめて計算する"""
    n = len(x)
    X = np.fft.rfft(x)
    freqs = np.fft.rfftfreq(n, 1 / SR)
    fc = -SR * math.log(1 - a) / (2 * math.pi) if a < 1 else SR
    H = 1 / np.sqrt(1 + (freqs / max(fc, 1)) ** 2)
    return np.fft.irfft(X * H, n)


def reverb(x, rt, rng, wet=0.3):
    """やわらかい残響(雑音を減衰させた IR を畳み込む)"""
    m = int(rt * SR)
    t = np.arange(m) / SR
    ir = rng.standard_normal(m) * np.exp(-t * 6.9 / rt)
    ir = lowpass(ir, 0.35)
    ir /= np.sqrt(np.sum(ir**2)) + 1e-9
    n = len(x) + m
    size = 1 << (n - 1).bit_length()
    y = np.fft.irfft(np.fft.rfft(x, size) * np.fft.rfft(ir, size), size)[:n]
    out = np.zeros(n)
    out[: len(x)] += x * (1 - wet)
    out += y * wet
    return out


class Track:
    """左右の音を置いていく台。最後に残響を足してループの頭に重ねる"""

    def __init__(self, bpm, bars, beats=4, tail=4.0):
        self.bpm = bpm
        self.beat = 60.0 / bpm
        self.length = bars * beats * self.beat
        self.n = int(round(self.length * SR))
        self.buf = np.zeros((2, self.n + int(tail * SR) + SR))

    def add(self, at_beat, sig, gain=1.0, pan=0.0):
        i = int(round(at_beat * self.beat * SR))
        if i >= self.buf.shape[1] or i < 0:
            return
        j = min(self.buf.shape[1], i + len(sig))
        l = math.cos((pan + 1) * math.pi / 4)
        r = math.sin((pan + 1) * math.pi / 4)
        self.buf[0, i:j] += sig[: j - i] * gain * l
        self.buf[1, i:j] += sig[: j - i] * gain * r

    def render(self, rng, rt=2.2, wet=0.28):
        out = []
        for ch in range(2):
            y = reverb(self.buf[ch], rt, rng, wet)
            loop = y[: self.n].copy()
            rest = y[self.n :]
            # 継ぎ目: はみ出した残響を頭に重ねる
            k = min(len(rest), self.n)
            loop[:k] += rest[:k]
            out.append(loop)
        x = np.stack(out)
        peak = np.max(np.abs(x)) + 1e-9
        return x * (0.8 / peak)


# 旋律づくり(決まった種から毎回同じ曲になる) ----------------------------------


def motif(rng, steps, span=4, rest=0.15):
    """1小節ぶんの音の動き: [(拍, 長さ, 音階の段)]"""
    out = []
    pos, d = 0.0, int(rng.integers(0, 3))
    for dur in steps:
        if rng.random() > rest:
            out.append((pos, dur, d))
        pos += dur
        d = int(np.clip(d + rng.choice([-2, -1, -1, 1, 1, 2]), -1, span))
    return out


def melody_bars(rng, bars, rhythms, span=4):
    """AABA' の形の旋律(各要素が1小節)"""
    a = motif(rng, rhythms[0], span)
    b = motif(rng, rhythms[1 % len(rhythms)], span)
    a2 = [(p, du, d + (1 if i == len(a) - 1 else 0)) for i, (p, du, d) in enumerate(a)]
    c = motif(rng, rhythms[0], span)
    form = [a, a2, b, c]
    return [form[i % 4] for i in range(bars)]


# 曲 --------------------------------------------------------------------------


def song_village(rng):
    tr = Track(bpm=84, bars=16)
    sc, root = "yo", 62  # D
    prog = [0, 0, 3, 2, 0, 3, 4, 0] * 2
    mel = melody_bars(rng, 16, [[1, 0.5, 0.5, 1, 1], [1.5, 0.5, 1, 1]])
    for bar in range(16):
        b0 = bar * 4
        ch = prog[bar]
        # 琴のアルペジオ(8分)
        for i in range(8):
            d = ch + [0, 2, 4, 2, 5, 4, 2, 4][i]
            f = midi_hz(degree(sc, root - 12, d))
            tr.add(b0 + i * 0.5, pluck(f, 1.6, bright=0.8, rng=rng), 0.55, pan=-0.35)
        # 低音
        tr.add(b0, pluck(midi_hz(degree(sc, root - 24, ch)), 2.5, bright=0.4, decay=0.6, rng=rng), 0.7, 0.1)
        # 尺八の旋律(後半8小節から、前半は琴の高音で)
        for p, du, d in mel[bar]:
            m = degree(sc, root, d + ch % 2)
            if bar >= 8:
                tr.add(b0 + p, flute(midi_hz(m), du * tr.beat * 1.05, rng), 0.9, pan=0.25)
            else:
                tr.add(b0 + p, pluck(midi_hz(m + 12), 1.4, bright=1.0, rng=rng), 0.45, pan=0.3)
        # 木魚(2・4拍)
        for k in (1, 3):
            tr.add(b0 + k, woodblock(820), 0.35, pan=0.5)
        tr.add(b0, pad([midi_hz(degree(sc, root - 12, ch)), midi_hz(degree(sc, root - 12, ch + 2))], 4 * tr.beat + 1), 1.0)
    return tr.render(rng, rt=2.4, wet=0.3)


def song_swamp(rng):
    tr = Track(bpm=66, bars=16)
    sc, root = "in", 57  # A
    mel = melody_bars(rng, 16, [[2, 1, 1], [1, 1, 2]], span=3)
    for bar in range(16):
        b0 = bar * 4
        # 低い持続音(主音と5度)
        if bar % 4 == 0:
            tr.add(b0, pad([midi_hz(root - 24), midi_hz(root - 17)], 16 * tr.beat + 1.5), 1.6)
        # まばらな琴
        for i in range(4):
            if rng.random() < 0.6:
                d = int(rng.integers(0, 6))
                tr.add(b0 + i + rng.choice([0, 0.5]), pluck(midi_hz(degree(sc, root - 12, d)), 2.4, bright=0.6, rng=rng), 0.5, pan=float(rng.uniform(-0.6, 0.6)))
        # 尺八(息多め)
        if bar % 2 == 1 or bar >= 8:
            for p, du, d in mel[bar]:
                tr.add(b0 + p, flute(midi_hz(degree(sc, root, d)), du * tr.beat * 1.1, rng, vib=1.4, breath=0.55), 0.8, pan=0.2)
        # 風鈴
        if bar % 2 == 0:
            tr.add(b0 + 2.5, bell(midi_hz(degree(sc, root + 12, int(rng.integers(0, 5))))), 0.6, pan=-0.5)
        # 遠くで鳴る小さな太鼓
        if bar % 4 == 3:
            tr.add(b0 + 3, taiko(1.2, 60, rng, hard=1.4), 0.35)
    return tr.render(rng, rt=3.2, wet=0.42)


def song_river(rng):
    tr = Track(bpm=108, bars=16)
    sc, root = "yo", 64  # E
    prog = [0, 3, 2, 0, 0, 3, 4, 4] * 2
    mel = melody_bars(rng, 16, [[0.5, 0.5, 1, 0.5, 0.5, 1], [1, 0.5, 0.5, 2]])
    for bar in range(16):
        b0 = bar * 4
        ch = prog[bar]
        # 流れるような三味線(16分の動き)
        for i in range(16):
            if i % 4 == 3 and rng.random() < 0.5:
                continue
            d = ch + [0, 2, 4, 5, 4, 2, 1, 2][i % 8] + (2 if i >= 8 else 0)
            tr.add(b0 + i * 0.25, pluck(midi_hz(degree(sc, root - 12, d)), 0.7, bright=1.2, decay=1.6, buzz=0.6, rng=rng), 0.38, pan=-0.3)
        tr.add(b0, pluck(midi_hz(degree(sc, root - 24, ch)), 1.8, bright=0.5, decay=0.8, rng=rng), 0.7)
        tr.add(b0 + 2, pluck(midi_hz(degree(sc, root - 24, ch + 2)), 1.6, bright=0.5, decay=0.8, rng=rng), 0.55)
        for p, du, d in mel[bar]:
            m = degree(sc, root, d + ch)
            if bar >= 4:
                tr.add(b0 + p, flute(midi_hz(m), du * tr.beat * 1.05, rng, vib=0.8), 0.75, pan=0.3)
        # 小太鼓
        for k in range(8):
            if k % 2 == 1 or rng.random() < 0.25:
                tr.add(b0 + k * 0.5, shime(rng), 0.45 if k % 2 else 0.3, pan=0.4)
        tr.add(b0, taiko(0.8, 80, rng), 0.45)
        tr.add(b0 + 2.5, taiko(0.6, 85, rng, hard=0.7), 0.25)
    return tr.render(rng, rt=1.8, wet=0.24)


def song_sea(rng):
    tr = Track(bpm=96, bars=16)
    sc, root = "ryukyu", 60  # C
    prog = [0, 3, 1, 3, 0, 3, 4, 0] * 2
    mel = melody_bars(rng, 16, [[1, 0.5, 0.5, 1, 1], [0.5, 0.5, 1, 2]])
    total_n = tr.buf.shape[1]
    w = waves(total_n, rng)
    tr.buf[0] += w * 0.55
    tr.buf[1] += np.roll(w, SR // 3) * 0.55
    for bar in range(16):
        b0 = bar * 4
        ch = prog[bar]
        # 三線ふうのはずむ伴奏(裏拍)
        for k in range(4):
            tr.add(b0 + k, pluck(midi_hz(degree(sc, root - 24, ch)), 1.0, bright=0.6, decay=1.1, rng=rng), 0.55)
            for dd in (2, 4):
                tr.add(b0 + k + 0.5, pluck(midi_hz(degree(sc, root - 12, ch + dd)), 0.6, bright=1.1, decay=1.8, buzz=0.3, rng=rng), 0.28, pan=-0.35)
        for p, du, d in mel[bar]:
            m = degree(sc, root, d + ch % 3)
            tr.add(b0 + p, pluck(midi_hz(m), 1.2, bright=1.1, decay=1.0, buzz=0.4, rng=rng), 0.6, pan=0.3)
            if bar >= 8 and du >= 1:
                tr.add(b0 + p, flute(midi_hz(m + 12), du * tr.beat, rng, vib=0.9, breath=0.25), 0.35, pan=0.15)
        # 指笛ふうの合いの手
        if bar % 4 == 3:
            tr.add(b0 + 3, flute(midi_hz(root + 31), 0.35, rng, vib=0, breath=0.1), 0.25, pan=0.6)
        for k in (1, 3):
            tr.add(b0 + k, woodblock(1100), 0.25, pan=0.5)
    return tr.render(rng, rt=2.0, wet=0.26)


def song_battle(rng):
    tr = Track(bpm=152, bars=16)
    sc, root = "in", 62  # D
    prog = [0, 0, -1, 0, 0, 0, 1, 2] * 2
    riff = [0, 0, 2, 0, 3, 2, 0, 1]
    mel = melody_bars(rng, 16, [[1, 0.5, 0.5, 1, 1], [0.5, 0.5, 0.5, 0.5, 2]])
    for bar in range(16):
        b0 = bar * 4
        ch = prog[bar]
        # 太鼓: どん・どどん
        for p, g in ((0, 1.0), (1.5, 0.7), (2, 0.9), (3, 0.6), (3.5, 0.6)):
            tr.add(b0 + p, taiko(0.7, 66, rng), g * 0.7)
        for k in range(8):
            tr.add(b0 + k * 0.5, shime(rng), 0.5 if k % 2 else 0.32, pan=0.35)
        if bar % 4 == 3:
            for k in range(4):
                tr.add(b0 + 2 + k * 0.5, taiko(0.4, 90, rng, hard=0.6), 0.45, pan=-0.2)
        # 三味線のリフ(8分、強く)
        for i, d in enumerate(riff):
            tr.add(b0 + i * 0.5, pluck(midi_hz(degree(sc, root - 12, d + ch)), 0.6, bright=1.4, decay=2.0, buzz=0.9, rng=rng), 0.42, pan=-0.35)
        tr.add(b0, pluck(midi_hz(degree(sc, root - 24, ch)), 1.0, bright=0.6, decay=1.2, rng=rng), 0.8)
        # 尺八の旋律(5小節目から)
        if bar >= 4:
            for p, du, d in mel[bar]:
                tr.add(b0 + p, flute(midi_hz(degree(sc, root + 12, d)), du * tr.beat * 1.02, rng, vib=0.7, breath=0.3), 0.6, pan=0.25)
        # 鐘(区切り)
        if bar % 8 == 0:
            tr.add(b0, bell(midi_hz(root + 12), 2.5), 0.7, pan=0.0)
    return tr.render(rng, rt=1.4, wet=0.2)



# ボス戦(和の音は使わない): 短調・速い。キック/スネア/タム、歪んだパワーコード、金管、弦の刻み、合唱、ティンパニ
def saw_add(f, dur, bright_env=None, nharm=28):
    """倍音を足したのこぎり波(折り返しなし)。bright_env(t) で高い倍音の強さを時間で変える"""
    n = int(dur * SR)
    t = np.arange(n) / SR
    out = np.zeros(n)
    for k in range(1, nharm + 1):
        if f * k > SR * 0.45:
            break
        a = 1.0 / k
        if bright_env is not None:
            a = a * bright_env(t) ** (0.15 * (k - 1))
        out += a * np.sin(2 * math.pi * f * k * t)
    return out


def adsr(n, a=0.005, d=0.08, s=0.7, r=0.08):
    t = np.arange(n) / SR
    dur = n / SR
    env = np.where(t < a, t / max(a, 1e-4), s + (1 - s) * np.exp(-(t - a) / max(d, 1e-4)))
    rel = np.clip((dur - t) / max(r, 1e-4), 0, 1)
    return env * rel


def kick(rng):
    n = int(0.45 * SR)
    t = np.arange(n) / SR
    f = 45 + 110 * np.exp(-t / 0.035)
    ph = 2 * math.pi * np.cumsum(f) / SR
    click = rng.standard_normal(n) * np.exp(-t / 0.003) * 0.3
    return (np.sin(ph) * np.exp(-t / 0.18) + click) * 1.0


def snare(rng):
    n = int(0.3 * SR)
    t = np.arange(n) / SR
    noise = rng.standard_normal(n)
    noise = noise - lowpass(noise, 0.08)  # 低い所を抜く
    tone = np.sin(2 * math.pi * 190 * t) * np.exp(-t / 0.05)
    return (noise * np.exp(-t / 0.09) * 0.55 + tone * 0.6) * 0.8


def tom(f0, rng):
    n = int(0.5 * SR)
    t = np.arange(n) / SR
    f = f0 * (1 + 0.5 * np.exp(-t / 0.04))
    ph = 2 * math.pi * np.cumsum(f) / SR
    return (np.sin(ph) * np.exp(-t / 0.22) + lowpass(rng.standard_normal(n), 0.2) * np.exp(-t / 0.02) * 0.3) * 0.8


def crash(rng, dur=2.2):
    n = int(dur * SR)
    t = np.arange(n) / SR
    noise = rng.standard_normal(n)
    noise = noise - lowpass(noise, 0.35)
    return noise * np.exp(-t / 0.7) * 0.28


def timpani(f, rng):
    n = int(1.4 * SR)
    t = np.arange(n) / SR
    out = np.zeros(n)
    for r, a, d in ((1, 1, 0.6), (1.5, 0.5, 0.4), (1.99, 0.3, 0.3), (2.44, 0.2, 0.2)):
        out += a * np.sin(2 * math.pi * f * r * t) * np.exp(-t / d)
    out += lowpass(rng.standard_normal(n), 0.1) * np.exp(-t / 0.03) * 0.6
    return out * 0.6


def power_chord(f, dur, rng, mute=True):
    """歪んだギターのパワーコード(根音・5度・オクターブ)"""
    n = int(dur * SR)
    x = np.zeros(n)
    for ratio in (1, 1.4983, 2):
        for det in (-0.004, 0.004):
            x += saw_add(f * ratio * (1 + det), dur, nharm=18)
    x = np.tanh(x * 2.2)
    x = lowpass(x, 0.18 if mute else 0.32)
    env = adsr(n, 0.004, 0.06 if mute else 0.3, 0.35 if mute else 0.8, 0.03)
    return x * env * 0.32


def brass(f, dur):
    n = int(dur * SR)
    t = np.arange(n) / SR
    bright = lambda tt: np.clip(0.35 + 0.65 * np.minimum(1, tt / 0.12), 0, 1)
    x = saw_add(f, dur, bright, nharm=22) + saw_add(f * 1.003, dur, bright, nharm=22)
    return x * adsr(n, 0.03, 0.2, 0.75, 0.08) * 0.16


def strings(f, dur):
    n = int(dur * SR)
    x = saw_add(f, dur, nharm=14) + saw_add(f * 1.004, dur, nharm=14) + saw_add(f * 0.996, dur, nharm=14)
    return lowpass(x, 0.3) * adsr(n, 0.01, 0.05, 0.6, 0.04) * 0.1


def choir(freqs, dur):
    """「アー」の合唱(倍音を母音の形で強める + ゆれ)"""
    n = int(dur * SR)
    t = np.arange(n) / SR
    out = np.zeros(n)
    for f in freqs:
        for v in range(3):
            vib = 1 + 0.006 * np.sin(2 * math.pi * (4.6 + v * 0.4) * t + v)
            ph = 2 * math.pi * np.cumsum(f * (1 + (v - 1) * 0.003) * vib) / SR
            for k in range(1, 16):
                fk = f * k
                w = sum(a * math.exp(-((fk - fm) / bw) ** 2) for fm, bw, a in ((700, 130, 1.0), (1150, 150, 0.6), (2600, 300, 0.25)))
                out += (w + 0.02) / k**0.3 * np.sin(k * ph)
    env = np.minimum(1, t / 0.4) * np.clip((dur - t) / 0.4, 0, 1)
    return out * env * 0.03 / max(1, len(freqs))


def song_boss(rng):
    bpm = 168
    tr = Track(bpm=bpm, bars=24, tail=3.0)
    root = 50  # D (短調)
    minor = [0, 2, 3, 5, 7, 8, 10]
    def nm(d, base=root):
        o, i = divmod(d, 7)
        return base + 12 * o + minor[i]
    # 和音の根音(音階の段): i - VI - VII - i / i - iv - V(和声的短音階で緊張) - V
    prog_a = [0, 0, 5, 5, 6, 6, 0, 0]
    prog_b = [0, 3, 5, 4, 0, 3, 4, 4]
    for bar in range(24):
        b0 = bar * 4
        section = "intro" if bar < 4 else ("A" if bar < 12 else ("B" if bar < 20 else "bridge"))
        if section == "intro":
            ch = [0, 0, 5, 6][bar]
        elif section == "A":
            ch = prog_a[bar - 4]
        elif section == "B":
            ch = prog_b[bar - 12]
        else:
            ch = [0, 5, 6, 4][bar - 20]
        root_m = nm(ch, root - 12)
        if ch == 4:
            root_m = root - 12 + 9  # A(属和音)
        f_root = midi_hz(root_m)
        # ドラム
        if section == "intro":
            for p in (0, 1.5, 3):
                tr.add(b0 + p, timpani(f_root, rng), 0.9)
            if bar == 3:
                for k in range(8):
                    tr.add(b0 + 2 + k * 0.25, tom(140 - k * 10, rng), 0.5, pan=(k - 4) / 6)
        else:
            for k in range(8):
                if k % 4 == 0 or k in (3, 6) or (section == "B" and k == 7):
                    tr.add(b0 + k * 0.5, kick(rng), 0.9)
            for k in (1, 3):
                tr.add(b0 + k, snare(rng), 0.75)
            for k in range(8):
                tr.add(b0 + k * 0.5 + 0.25 * 0, crash(rng, 0.12) * 0.6, 0.25, pan=0.4)  # ハイハットふう
            if bar % 4 == 0:
                tr.add(b0, crash(rng), 0.8, pan=-0.2)
            if bar % 4 == 3:
                for k in range(4):
                    tr.add(b0 + 2 + k * 0.5, tom(160 - k * 22, rng), 0.55, pan=0.5 - k * 0.3)
        # 歪んだギター(8分の刻み、小節の頭はのばす)
        if section != "intro":
            for k in range(8):
                mute = k not in (0, 6)
                tr.add(b0 + k * 0.5, power_chord(f_root, 0.5 * tr.beat * (0.95 if mute else 1.9), rng, mute), 0.8, pan=-0.45 if k % 2 else 0.45)
        else:
            tr.add(b0, power_chord(f_root, 4 * tr.beat, rng, mute=False), 0.6)
        # 弦の刻み(16分)
        if section in ("A", "B", "bridge"):
            pattern = [0, 2, 4, 2, 7, 4, 2, 4] if section != "B" else [0, 4, 7, 9, 7, 4, 2, 4]
            for k in range(16):
                d = ch + pattern[k % 8] // 1
                tr.add(b0 + k * 0.25, strings(midi_hz(nm(d, root + 12)), 0.25 * tr.beat), 0.55, pan=0.3)
        # 金管(A は合いの手、B は旋律)
        if section == "A" and bar % 2 == 1:
            for p, d in ((2, 0), (2.5, 2), (3, 4)):
                tr.add(b0 + p, brass(midi_hz(nm(ch + d, root)), 0.45 * tr.beat), 0.8, pan=-0.2)
        if section == "B":
            mel = [(0, 1.5, 4), (1.5, 0.5, 3), (2, 2, 2)] if bar % 2 == 0 else [(0, 1, 4), (1, 1, 5), (2, 2, 7)]
            for p, du, d in mel:
                f = midi_hz(nm(ch + d, root + 12))
                tr.add(b0 + p, brass(f, du * tr.beat), 0.85)
                tr.add(b0 + p, brass(f / 2, du * tr.beat), 0.5)
        # 合唱(B と終わり)
        if section in ("B", "bridge", "intro") and bar % 2 == 0:
            fs = [midi_hz(nm(ch, root + 12)), midi_hz(nm(ch + 2, root + 12)), midi_hz(nm(ch + 4, root + 12))]
            tr.add(b0, choir(fs, 8 * tr.beat + 0.3), 1.0)
        # ベース
        if section != "intro":
            for k in range(8):
                tr.add(b0 + k * 0.5, pluck(midi_hz(root_m - 12), 0.4, bright=0.7, decay=2.5, rng=rng), 0.9)
    x = tr.render(rng, rt=1.6, wet=0.18)
    # 迫力を出すため軽く圧縮して音圧を上げる(太鼓の山だけが目立たないように)
    x = np.tanh(x * 2.4)
    return x * (0.82 / (np.max(np.abs(x)) + 1e-9))

SONGS = {
    "village": (song_village, 11),
    "swamp": (song_swamp, 23),
    "river": (song_river, 37),
    "sea": (song_sea, 41),
    "battle": (song_battle, 53),
    "boss": (song_boss, 67),
}

# 場所 → 曲
AREA_TRACK = {"nushi_lake": "village", "swamp": "swamp", "river": "river", "sea": "sea"}


# 書き出し -------------------------------------------------------------------


def write_wav(path, x):
    pcm = (np.clip(x.T, -1, 1) * 32767).astype("<i2")
    with wave.open(path, "wb") as w:
        w.setnchannels(2)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(pcm.tobytes())
    return pcm


def ffmpeg(args):
    subprocess.run(["ffmpeg", "-hide_banner", "-loglevel", "error", "-y", *args], check=True)


def lua_str(s):
    return '"' + s.replace("\\", "\\\\").replace('"', '\\"') + '"'


def old_ids(path):
    """今の Config/Music.luau から 曲 → (soundId, audioHash)"""
    out = {}
    if not os.path.exists(path):
        return out
    src = open(path, encoding="utf-8").read()
    for m in re.finditer(r'(\w+) = \{\s*soundId = "([^"]*)",\s*audioHash = "([^"]*)"', src):
        out[m.group(1)] = (m.group(2), m.group(3))
    return out


def write_luau(path, rows):
    prev = old_ids(path)
    lines = [
        "--!strict",
        "-- BGM(tools/music/yokai_bgm.py が作る表。手で書き換えるのは各曲の soundId だけ)",
        "-- assets/sounds/bgm/<曲>.ogg を Roblox にアップロードして soundId を \"rbxassetid://<番号>\" にする(0 なら鳴らない)。",
        "-- audioHash は音の中身の印。曲を作り直すと変わり、その曲の soundId は 0 に戻る",
        "return {",
        "\ttracks = {",
    ]
    for name, length, digest in rows:
        sid, h = prev.get(name, ("rbxassetid://0", ""))
        if h != digest:
            if sid != "rbxassetid://0":
                print(f"  {name} の音が変わりました。アップロードし直して soundId を入れ直してください", file=sys.stderr)
            sid = "rbxassetid://0"
        lines.append(f"\t\t{name} = {{ soundId = {lua_str(sid)}, audioHash = {lua_str(digest)}, length = {length:.3f} }},")
    lines.append("\t} :: { [string]: { soundId: string, audioHash: string, length: number } },")
    lines.append("\t-- 釣り場 → 曲(ここにない場所は village)")
    lines.append("\tareaTrack = {")
    for k, v in AREA_TRACK.items():
        lines.append(f"\t\t{k} = {lua_str(v)},")
    lines.append("\t} :: { [string]: string },")
    lines.append("\tbattleTrack = \"battle\",")
    lines.append("\tbossTrack = \"boss\", -- ボス戦(協力のボス・各地のぬし)")
    lines.append("\tvolume = 0.35, -- 曲の音量(効果音より小さく)")
    lines.append("\tfade = 1.5, -- 曲を切り替える時のフェード(秒)")
    lines.append("}")
    open(path, "w", encoding="utf-8").write("\n".join(lines) + "\n")
    if shutil.which("stylua"):
        subprocess.run(["stylua", path], check=True)
    print("wrote", path)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", default=os.path.join(ROOT, "assets", "sounds", "bgm"))
    ap.add_argument("--luau", default=os.path.join(ROOT, "src", "shared", "Config", "Music.luau"))
    ap.add_argument("--preview", default="", help="試し聞き用 mp3 の書き出し先")
    ap.add_argument("--only", default="")
    a = ap.parse_args()
    os.makedirs(a.out, exist_ok=True)
    tmp = os.path.join(a.out, "_tmp.wav")
    rows = []
    prev = old_ids(a.luau)
    for name, (fn, seed) in SONGS.items():
        if a.only and name != a.only:
            # 作らない曲は今の印のまま残す
            sid, h = prev.get(name, ("rbxassetid://0", ""))
            if h:
                ogg = os.path.join(a.out, name + ".ogg")
                length = float(subprocess.run(["ffprobe", "-v", "error", "-show_entries", "format=duration", "-of", "csv=p=0", ogg], capture_output=True, text=True).stdout or 0)
                rows.append((name, length, h))
            continue
        rng = np.random.default_rng(seed)
        x = fn(rng)
        pcm = write_wav(tmp, x)
        digest = hashlib.sha1(pcm.tobytes()).hexdigest()[:12]
        ogg = os.path.join(a.out, name + ".ogg")
        ffmpeg(["-i", tmp, "-c:a", "libvorbis", "-q:a", "4", ogg])
        if a.preview:
            os.makedirs(a.preview, exist_ok=True)
            ffmpeg(["-i", tmp, "-c:a", "libmp3lame", "-b:a", "128k", os.path.join(a.preview, name + ".mp3")])
        length = x.shape[1] / SR
        rows.append((name, length, digest))
        print(f"{name}: {length:.1f}s  {os.path.getsize(ogg) // 1024} KB")
    os.remove(tmp)
    write_luau(a.luau, rows)


if __name__ == "__main__":
    main()
