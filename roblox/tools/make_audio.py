"""Roblox 版の音をすべて合成して作る(このゲームのためのオリジナル。外部の音素材は使わない)。

  python roblox/tools/make_audio.py

出力:
  roblox/assets/audio/minato-sfx.wav    効果音を1本に並べた物(1つずつ PlaybackRegion で鳴らす)
  roblox/assets/audio/minato-loops.wav  くり返す音(エンジン・水切り・観客)。LoopRegion で使う
  roblox/assets/audio/minato-music.wav  ホームの BGM(ステレオ・ループ)
  roblox/src/AudioSheet.lua             それぞれの音の位置(秒)。自動で書き出す

Roblox には上の3つを登録し、出た ID を roblox/src/AudioConfig.lua に入れる(PUBLISH.md)。
ブラウザ版(src/audio.js)と同じ考え方: 2ストロークのエンジン、水切り、館内チャイムとファンファーレ、ゴールのジングル。
"""
import wave
from pathlib import Path

import numpy as np

SR = 44100
ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "assets" / "audio"
rng = np.random.default_rng(20261115)


def t(dur):
    return np.arange(int(SR * dur)) / SR


def note(n):
    """MIDI の番号 → 周波数"""
    return 440.0 * 2 ** ((n - 69) / 12)


def spectrum_filter(x, shape):
    """周波数ごとの倍率(関数)をかける"""
    spec = np.fft.rfft(x)
    f = np.fft.rfftfreq(len(x), 1 / SR)
    return np.fft.irfft(spec * shape(f), len(x))


def lowpass(x, fc, order=4):
    return spectrum_filter(x, lambda f: 1 / np.sqrt(1 + (f / fc) ** (2 * order)))


def highpass(x, fc, order=2):
    return spectrum_filter(x, lambda f: 1 / np.sqrt(1 + (fc / np.maximum(f, 1e-6)) ** (2 * order)))


def band(x, lo, hi, order=3):
    return highpass(lowpass(x, hi, order), lo, order)


def noise(dur):
    return rng.standard_normal(int(SR * dur))


def env(dur, attack=0.005, release=0.05, curve=1.0, hold=None):
    """立ち上がり → (保つ) → 指数で消える包絡"""
    n = int(SR * dur)
    x = np.arange(n) / SR
    a = np.clip(x / max(attack, 1e-5), 0, 1)
    start = attack if hold is None else attack + hold
    d = np.exp(-np.maximum(x - start, 0) * curve / max(dur - start, 1e-5) * 5)
    r = np.clip((dur - x) / max(release, 1e-5), 0, 1)
    return a * d * r


def tone(freq, dur, kind="sine", harmonics=12, vib=0.0, vib_rate=5.5):
    x = t(dur)
    f = freq * (1 + vib * np.sin(2 * np.pi * vib_rate * x) * np.clip(x / 0.25, 0, 1))
    phase = 2 * np.pi * np.cumsum(f) / SR
    if kind == "sine":
        return np.sin(phase)
    out = np.zeros_like(x)
    for k in range(1, harmonics + 1):
        if freq * k > SR * 0.45:
            break
        if kind == "saw":
            out += np.sin(k * phase) / k
        elif kind == "square" and k % 2 == 1:
            out += np.sin(k * phase) / k
        elif kind == "tri" and k % 2 == 1:
            out += ((-1) ** ((k - 1) // 2)) * np.sin(k * phase) / (k * k)
    return out


def reverb(x, t60=1.2, mix=0.25, tail=None, seed=7):
    """残響(減っていく雑音との畳み込み)"""
    tail = t60 if tail is None else tail
    r = np.random.default_rng(seed)
    n = int(SR * tail)
    ir = r.standard_normal(n) * np.exp(-6.9 * np.arange(n) / (SR * t60))
    ir = lowpass(ir, 5200, 2)
    ir[: int(SR * 0.012)] *= np.linspace(0, 1, int(SR * 0.012))
    size = len(x) + n
    wet = np.fft.irfft(np.fft.rfft(x, size) * np.fft.rfft(ir, size), size)
    wet /= np.sqrt(np.sum(ir ** 2)) + 1e-9
    dry = np.concatenate([x, np.zeros(n)])
    return dry * (1 - mix) + wet * mix


def mix_at(buf, x, at, gain=1.0):
    i = int(SR * at)
    if i + len(x) > len(buf):
        x = x[: len(buf) - i]
    buf[i : i + len(x)] += x * gain


def norm(x, peak=0.89):
    m = np.max(np.abs(x))
    return x * (peak / m) if m > 0 else x


def fade(x, a=0.004, r=0.02):
    x = x.copy()
    na, nr = int(SR * a), int(SR * r)
    x[:na] *= np.linspace(0, 1, na)
    x[-nr:] *= np.linspace(1, 0, nr)
    return x


def periodic_noise(dur, shape, seed):
    """継ぎ目なくくり返せる雑音(周波数ごとに大きさを決め、位相を乱数にする)"""
    n = int(SR * dur)
    r = np.random.default_rng(seed)
    f = np.fft.rfftfreq(n, 1 / SR)
    spec = shape(f) * np.exp(1j * r.uniform(0, 2 * np.pi, len(f)))
    spec[0] = 0
    return np.fft.irfft(spec, n)


# ---------------- くり返す音 ----------------
def engine_loop(dur=2.0, f0=62.0):
    """2ストロークの船外機。全部の成分を 1/dur Hz の整数倍にして、継ぎ目をなくす"""
    x = t(dur)
    out = np.zeros_like(x)
    r = np.random.default_rng(11)
    for k in range(1, 46):
        amp = 1 / k ** 0.85 * (1.6 if k in (2, 3, 5) else 1.0)
        out += amp * np.sin(2 * np.pi * f0 * k * x + r.uniform(0, 6.28))
    # 2気筒のばらつき(半分の速さのうなり)と、排気のざらつき
    out *= 1 + 0.22 * np.sin(2 * np.pi * (f0 / 2) * x) + 0.08 * np.sin(2 * np.pi * (f0 / 4) * x + 1.0)
    rasp = periodic_noise(dur, lambda f: np.exp(-((np.log(np.maximum(f, 1) / 1700)) ** 2) / 0.5), 12)
    rasp *= 0.5 + 0.5 * np.maximum(0, np.sin(2 * np.pi * f0 * x)) ** 3
    out = norm(out) + 0.26 * norm(rasp)
    # 軽く歪ませてから高い音を落とす(船外機らしい太い音にする)。くり返しの波のままなので継ぎ目は出ない
    return norm(lowpass(np.tanh(out * 1.5), 2600, 2), 0.8)


def water_loop(dur=3.0):
    """艇が水を切る音"""
    x = t(dur)
    hiss = periodic_noise(dur, lambda f: (f / 900) / (1 + (f / 900) ** 2) * np.exp(-f / 6500), 21)
    wash = periodic_noise(dur, lambda f: np.exp(-((np.log(np.maximum(f, 1) / 420)) ** 2) / 0.9), 22)
    mod = 1 + 0.18 * np.sin(2 * np.pi * x / dur * 2) + 0.12 * np.sin(2 * np.pi * x / dur * 5 + 1)
    return norm((norm(hiss) + 0.7 * norm(wash)) * mod, 0.7)


def crowd_loop(dur=6.0):
    """観客のざわめき"""
    x = t(dur)
    base = periodic_noise(dur, lambda f: np.exp(-((np.log(np.maximum(f, 1) / 650)) ** 2) / 0.55), 31)
    air = periodic_noise(dur, lambda f: np.exp(-((np.log(np.maximum(f, 1) / 2300)) ** 2) / 0.4), 32)
    mod = 1 + 0.25 * np.sin(2 * np.pi * x / dur * 1) + 0.15 * np.sin(2 * np.pi * x / dur * 3 + 2) + 0.1 * np.sin(2 * np.pi * x / dur * 7)
    return norm((norm(base) + 0.25 * norm(air)) * mod, 0.6)


# ---------------- 効果音 ----------------
def bell(freq, dur, bright=1.0):
    x = t(dur)
    out = np.zeros_like(x)
    for ratio, amp, decay in [(1, 1, 3.5), (2.0, 0.5 * bright, 5), (2.76, 0.32 * bright, 7), (5.4, 0.18 * bright, 10), (8.9, 0.08 * bright, 14)]:
        out += amp * np.sin(2 * np.pi * freq * ratio * x) * np.exp(-x * decay)
    return out * np.clip(x / 0.002, 0, 1)


def brass(freq, dur, vol=1.0):
    raw = tone(freq, dur, "saw", 24, vib=0.004) + 0.5 * tone(freq * 1.003, dur, "saw", 24)
    x = t(dur)
    cutoff = 900 + 2600 * np.clip(x / 0.07, 0, 1) * np.exp(-x * 0.9)
    # 時間で変わるフィルターの代わりに、明るい音と暗い音を混ぜる
    brightness = (cutoff - 900) / 2600
    out = lowpass(raw, 3400, 2) * brightness + lowpass(raw, 1100, 2) * (1 - brightness)
    return out * env(dur, 0.03, 0.08, 0.35) * vol


def sfx_click():
    x = t(0.06)
    return (np.sin(2 * np.pi * 1900 * x) * np.exp(-x * 90) + 0.3 * band(noise(0.06), 2500, 8000) * np.exp(-x * 140)) * 0.8


def sfx_select():
    out = np.zeros(int(SR * 0.3))
    mix_at(out, bell(note(81), 0.16, 0.6), 0.0, 0.6)
    mix_at(out, bell(note(88), 0.22, 0.6), 0.07, 0.7)
    return out


def sfx_back():
    out = np.zeros(int(SR * 0.26))
    mix_at(out, bell(note(81), 0.14, 0.4), 0.0, 0.6)
    mix_at(out, bell(note(76), 0.18, 0.4), 0.06, 0.6)
    return out


def sfx_coin():
    out = np.zeros(int(SR * 0.6))
    mix_at(out, bell(note(95), 0.3, 1.2), 0.0, 0.7)
    mix_at(out, bell(note(100), 0.5, 1.2), 0.08, 0.8)
    return out


def sfx_beep():
    x = t(0.16)
    return (np.sin(2 * np.pi * 880 * x) + 0.25 * np.sin(2 * np.pi * 1760 * x)) * env(0.16, 0.004, 0.05, 0.6)


def sfx_go():
    x = t(0.7)
    return (np.sin(2 * np.pi * 1320 * x) + 0.3 * np.sin(2 * np.pi * 2640 * x) + 0.2 * np.sin(2 * np.pi * 660 * x)) * env(0.7, 0.004, 0.2, 0.5, hold=0.2)


def sfx_buzzer():
    x = t(0.9)
    raw = tone(146, 0.9, "square", 30) + tone(153, 0.9, "square", 30)
    return lowpass(raw, 2400, 2) * env(0.9, 0.01, 0.08, 0.05, hold=0.7) * 0.7


def sfx_hit():
    x = t(0.4)
    thud = np.sin(2 * np.pi * (95 * np.exp(-x * 9) + 42) * x) * np.exp(-x * 13)
    crack = band(noise(0.4), 600, 5000) * np.exp(-x * 30)
    return thud + 0.55 * crack


def sfx_splash(dur=1.5):
    x = t(dur)
    body = band(noise(dur), 180, 2600) * (np.clip(x / 0.03, 0, 1) * np.exp(-x * 3.2))
    spray = band(noise(dur), 2500, 9000) * (np.clip(x / 0.08, 0, 1) * np.exp(-x * 2.2)) * 0.5
    boom = np.sin(2 * np.pi * (70 * np.exp(-x * 6) + 38) * x) * np.exp(-x * 7) * 0.9
    return body + spray + boom


def sfx_whoosh(dur=0.5):
    x = t(dur)
    raw = noise(dur)
    out = np.zeros_like(x)
    # 高い方へ動く帯を、4つの帯の重ね合わせで作る
    for k, (lo, hi) in enumerate([(300, 900), (700, 1800), (1400, 3600), (2800, 7000)]):
        center = 0.15 + 0.2 * k
        out += band(raw, lo, hi) * np.exp(-((x / dur - center) ** 2) / 0.02)
    return out


def sfx_equip():
    out = np.zeros(int(SR * 0.9))
    mix_at(out, norm(sfx_whoosh(0.45), 0.5), 0.0)
    mix_at(out, bell(note(88), 0.6, 1.0), 0.28, 0.7)
    mix_at(out, bell(note(93), 0.5, 1.0), 0.36, 0.5)
    return out


def arpeggio(notes, step, length, bright=1.0, final_chord=None):
    out = np.zeros(int(SR * (step * len(notes) + length + 1.5)))
    for i, n in enumerate(notes):
        mix_at(out, bell(note(n), length, bright), i * step, 0.6)
    if final_chord:
        at = step * len(notes)
        for n in final_chord:
            mix_at(out, bell(note(n), length + 0.8, bright), at, 0.45)
            mix_at(out, tone(note(n), length + 0.6, "tri") * env(length + 0.6, 0.02, 0.3, 0.5), at, 0.18)
    return out


def sparkle(dur, seed):
    r = np.random.default_rng(seed)
    out = np.zeros(int(SR * (dur + 0.5)))
    for _ in range(int(dur * 22)):
        f = note(r.choice([96, 98, 100, 103, 105, 108]))
        mix_at(out, bell(f, 0.25, 1.4), r.uniform(0, dur), r.uniform(0.08, 0.2))
    return out


def sfx_gacha(rarity):
    if rarity == "N":
        return reverb(arpeggio([79, 84], 0.07, 0.4, 0.7), 0.6, 0.15)
    if rarity == "R":
        return reverb(arpeggio([76, 81, 88], 0.07, 0.5, 0.9), 0.8, 0.2)
    if rarity == "SR":
        x = arpeggio([74, 78, 81, 86, 90], 0.07, 0.6, 1.1, [86, 90, 93])
        mix_at(x, sparkle(0.9, 5), 0.3)
        return reverb(x, 1.2, 0.25)
    x = arpeggio([72, 76, 79, 84, 88, 91, 96], 0.065, 0.7, 1.3, [84, 88, 91, 96])
    mix_at(x, sparkle(1.6, 6), 0.35, 1.2)
    mix_at(x, norm(sfx_whoosh(0.6), 0.35), 0.0)
    return reverb(x, 1.8, 0.3)


def sfx_drumroll(dur=1.0):
    x = t(dur)
    out = np.zeros_like(x)
    hit = band(noise(0.05), 180, 3500) * np.exp(-t(0.05) * 90)
    at = 0.0
    while at < dur - 0.06:
        mix_at(out, hit, at, 0.3 + 0.7 * (at / dur) ** 1.5)
        at += 0.045 - 0.02 * (at / dur)
    return out


def sfx_lap():
    return reverb(bell(note(88), 0.9, 1.1) + 0.6 * bell(note(93), 0.9, 1.1), 0.9, 0.2)


def sfx_notice():
    out = np.zeros(int(SR * 0.6))
    mix_at(out, bell(note(84), 0.3, 0.6), 0.0, 0.6)
    mix_at(out, bell(note(91), 0.45, 0.6), 0.12, 0.6)
    return reverb(out, 0.6, 0.15)


def sfx_rankup():
    return reverb(arpeggio([72, 76, 79, 84, 88], 0.09, 0.5, 1.0, [84, 88, 91]), 1.2, 0.25)


def sfx_fanfare():
    """館内チャイム + オリジナルのファンファーレ(変ロ長調)"""
    out = np.zeros(int(SR * 6.2))
    for i, n in enumerate([77, 82, 86, 89]):       # チャイム: ファ・シ♭・レ・ファ
        mix_at(out, bell(note(n), 1.2, 0.8), i * 0.28, 0.5)
    beat = 0.19
    start = 1.5
    # 主題: タタタ ター / タタ タ ターーー
    line = [(70, 1), (70, 1), (70, 1), (74, 3), (72, 1), (74, 1), (77, 1), (82, 6)]
    harmony = {70: (65, 62), 74: (70, 65), 72: (69, 65), 77: (74, 70), 82: (77, 74)}
    at = start
    for n, beats in line:
        dur = beat * beats * (0.92 if beats <= 1 else 1.0) + (0.5 if beats >= 6 else 0)
        mix_at(out, brass(note(n), dur), at, 0.5)
        for h in harmony[n]:
            mix_at(out, brass(note(h), dur), at, 0.3)
        mix_at(out, brass(note(n - 24), dur), at, 0.28)
        at += beat * beats
    # ティンパニ
    for when in [start, start + beat * 3, start + beat * 9]:
        x = t(0.6)
        mix_at(out, np.sin(2 * np.pi * (58 + 20 * np.exp(-x * 20)) * x) * np.exp(-x * 5), when, 0.6)
    return reverb(out, 1.6, 0.28)


def sfx_finish(win):
    out = np.zeros(int(SR * 3.2))
    if win:
        seq = [(72, 0.0), (76, 0.12), (79, 0.24), (84, 0.36), (88, 0.52)]
        for n, at in seq:
            mix_at(out, brass(note(n), 0.3), at, 0.45)
        for n in (72, 76, 79, 84):
            mix_at(out, brass(note(n), 1.6), 0.7, 0.33)
        mix_at(out, sparkle(1.2, 9), 0.7, 0.8)
    else:
        for n, at in [(72, 0.0), (76, 0.16), (79, 0.32)]:
            mix_at(out, bell(note(n), 0.8, 0.8), at, 0.5)
        for n in (72, 76, 79):
            mix_at(out, tone(note(n), 1.0, "tri") * env(1.0, 0.03, 0.4, 0.5), 0.48, 0.25)
    return reverb(out, 1.4, 0.25)


def sfx_cheer(dur=2.6):
    x = t(dur)
    base = band(noise(dur), 350, 3200)
    swell = np.clip(x / 0.5, 0, 1) * np.exp(-np.maximum(x - 0.9, 0) * 1.5)
    wob = 1 + 0.3 * np.sin(2 * np.pi * 3.1 * x) + 0.2 * np.sin(2 * np.pi * 5.3 * x + 1)
    return base * swell * wob


# ---------------- BGM(ホーム) ----------------
def music():
    """ホームの BGM。ニ長調・毎分104拍・16小節。やわらかい和音、はじく音の分散和音、ベース、軽い打楽器"""
    bpm = 104
    beat = 60 / bpm
    bars = 16
    length = bars * 4 * beat
    n = int(SR * length)
    left, right = np.zeros(n * 2), np.zeros(n * 2)

    def put(x, at, gain=1.0, pan=0.0):
        for rep in (0, 1):                      # 2周ぶん書いて、2周目を取り出す(残響を継ぎ目に回す)
            i = int(SR * (at + rep * length))
            seg = x[: max(0, len(left) - i)]
            left[i : i + len(seg)] += seg * gain * (1 - max(pan, 0))
            right[i : i + len(seg)] += seg * gain * (1 + min(pan, 0))

    # 和音の進行(1小節ずつ): D  A/C#  Bm7  Gmaj7 | D  F#m7  G  A | Bm7  G  D/F#  A | G  A  D  Dsus
    chords = [
        (50, [62, 66, 69, 73]), (49, [61, 64, 69, 73]), (47, [62, 66, 69, 74]), (43, [62, 66, 71, 74]),
        (50, [62, 66, 69, 74]), (54, [61, 64, 69, 73]), (43, [62, 67, 71, 74]), (45, [61, 64, 69, 73]),
        (47, [62, 66, 69, 74]), (43, [62, 67, 71, 74]), (54, [62, 66, 69, 74]), (45, [61, 64, 69, 76]),
        (43, [62, 67, 71, 74]), (45, [64, 69, 73, 76]), (50, [62, 66, 69, 74]), (50, [62, 67, 69, 74]),
    ]
    melody = [  # (小節, 拍, 音, 長さ[拍])
        (0, 0, 81, 1.5), (0, 1.5, 78, 0.5), (0, 2, 81, 2), (1, 0, 80, 1), (1, 1, 76, 1), (1, 2, 73, 2),
        (2, 0, 74, 1.5), (2, 1.5, 78, 0.5), (2, 2, 81, 2), (3, 0, 83, 1), (3, 1, 81, 1), (3, 2, 78, 2),
        (4, 0, 81, 1.5), (4, 1.5, 78, 0.5), (4, 2, 86, 2), (5, 0, 85, 1), (5, 1, 81, 1), (5, 2, 76, 2),
        (6, 0, 79, 1), (6, 1, 83, 1), (6, 2, 86, 2), (7, 0, 85, 1.5), (7, 1.5, 83, 0.5), (7, 2, 81, 2),
        (8, 0, 78, 1), (8, 1, 81, 1), (8, 2, 86, 1.5), (8, 3.5, 85, 0.5), (9, 0, 83, 2), (9, 2, 79, 2),
        (10, 0, 81, 1), (10, 1, 78, 1), (10, 2, 74, 2), (11, 0, 76, 1), (11, 1, 80, 1), (11, 2, 85, 2),
        (12, 0, 86, 1.5), (12, 1.5, 83, 0.5), (12, 2, 79, 2), (13, 0, 85, 1), (13, 1, 81, 1), (13, 2, 88, 2),
        (14, 0, 86, 3), (15, 0, 81, 1), (15, 1, 79, 1), (15, 2, 78, 2),
    ]
    for bar, (root, tones) in enumerate(chords):
        at = bar * 4 * beat
        # やわらかい和音(のこぎり波を重ねて暗くした音)
        dur = 4 * beat + 0.3
        pad = np.zeros(int(SR * dur))
        for tn in tones:
            pad += tone(note(tn), dur, "saw", 10, vib=0.003) + tone(note(tn) * 1.004, dur, "saw", 10)
        pad = lowpass(pad, 1300, 2) * env(dur, 0.25, 0.4, 0.12)
        put(pad, at, 0.045, 0.0)
        # ベース(1拍目と、3拍目の裏)
        for b, length_b in ((0, 1.4), (2.5, 1.2)):
            x = tone(note(root - 12), length_b * beat, "tri") + 0.4 * tone(note(root - 12), length_b * beat, "saw", 6)
            put(lowpass(x, 600, 2) * env(length_b * beat, 0.008, 0.08, 0.5), at + b * beat, 0.32)
        # はじく音の分散和音(8分音符)
        order = [0, 2, 1, 3, 2, 3, 1, 2]
        for k, idx in enumerate(order):
            f = note(tones[idx] + 12)
            x = t(0.5)
            pluck = (np.sin(2 * np.pi * f * x) + 0.4 * np.sin(2 * np.pi * 2 * f * x) * np.exp(-x * 9) + 0.15 * np.sin(2 * np.pi * 4 * f * x) * np.exp(-x * 18)) * np.exp(-x * 6.5) * np.clip(x / 0.003, 0, 1)
            put(pluck, at + k * beat / 2, 0.11, -0.45 if k % 2 == 0 else 0.45)
        # 打楽器: やわらかいキック(1・3拍)、シェイカー(8分)、リム(2・4拍)
        for b in (0, 2):
            x = t(0.3)
            put(np.sin(2 * np.pi * (48 + 60 * np.exp(-x * 28)) * x) * np.exp(-x * 11), at + b * beat, 0.5)
        for k in range(8):
            x = t(0.07)
            sh = highpass(noise(0.07), 5000) * np.exp(-x * (55 if k % 2 else 75))
            put(sh, at + k * beat / 2, 0.05 if k % 2 == 0 else 0.085, 0.3)
        for b in (1, 3):
            x = t(0.12)
            rim = (np.sin(2 * np.pi * 820 * x) + 0.6 * band(noise(0.12), 1500, 6000)) * np.exp(-x * 45)
            put(rim, at + b * beat, 0.12, -0.25)
    for bar, b, n_, beats in melody:
        dur = beats * beat + 0.25
        f = note(n_)
        x = t(dur)
        lead = (tone(f, dur, "tri", vib=0.004) + 0.35 * np.sin(2 * np.pi * 2 * f * x) + 0.6 * bell(f, dur, 0.5)) * env(dur, 0.012, 0.2, 0.45)
        put(lead, (bar * 4 + b) * beat, 0.16, 0.12)
    # 残響をかけて、2周目を取り出す
    stereo = []
    for ch, seed in ((left, 41), (right, 43)):
        wet = reverb(ch, 1.7, 0.22, seed=seed)[: n * 2]
        stereo.append(wet[n : n * 2])
    m = max(np.max(np.abs(stereo[0])), np.max(np.abs(stereo[1])))
    return np.stack([stereo[0], stereo[1]], axis=1) * (0.8 / m)


# ---------------- 書き出し ----------------
def opening():
    """Twelve bars in 4/4 at 120 BPM, with alternating bass and brass answers."""
    mix = np.zeros((24 * SR, 2))
    drum = np.random.default_rng(217)
    def voice(start, duration, pitch, gain, pan, snare=False):
        x = t(duration)
        phase = 2 * np.pi * note(pitch) * x
        wavelet = (np.sin(phase) + .32*np.sin(2*phase) + .2*np.sin(3*phase))
        if snare:
            wavelet = drum.standard_normal(len(x)) * np.exp(-28*x)
        envelope = np.minimum(x/.018, 1) * np.minimum((duration-x)/.055, 1)
        samples = wavelet * envelope * gain
        pos = round(start*SR)
        mix[pos:pos+len(x)] += samples[:,None] * np.array([1-pan,1+pan])
    for bar, root in enumerate([50,55,52,57,54,55,59,57,55,52,57,50]):
        for beat in range(4):
            at = 2*bar+.5*beat
            voice(at,.36,root-12+(7 if beat==2 else 0),.21,-.15)
            third = 3 if root in (52,54,59) else 4
            lead = ([7,12,third+12,14],[12,third+12,7,9],[14,7,12,third])[bar%3][beat]
            voice(at,.28,root+lead,.24,.15)
            voice(at+.31,.16,root+(third if beat%2 else 7),.13,-.28)
            if beat%2:
                voice(at,.14,50,.12,.2,True)
    return mix * (.82/np.abs(mix).max())


def write_wav(path, data):
    data = np.clip(data, -1, 1)
    pcm = (data * 32767).astype("<i2")
    with wave.open(str(path), "wb") as w:
        w.setnchannels(1 if pcm.ndim == 1 else pcm.shape[1])
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(pcm.tobytes())


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    regions = {}

    # 効果音の列(間に 0.3 秒の無音)
    sounds = [
        ("click", norm(sfx_click(), 0.6)), ("select", norm(sfx_select(), 0.6)), ("back", norm(sfx_back(), 0.55)),
        ("coin", norm(sfx_coin(), 0.7)), ("notice", norm(sfx_notice(), 0.6)), ("equip", norm(sfx_equip(), 0.75)),
        ("beep", norm(sfx_beep(), 0.7)), ("go", norm(sfx_go(), 0.8)), ("buzzer", norm(sfx_buzzer(), 0.7)),
        ("hit", norm(sfx_hit(), 0.85)), ("splash", norm(sfx_splash(), 0.85)), ("lap", norm(sfx_lap(), 0.7)),
        ("fanfare", norm(sfx_fanfare(), 0.85)), ("finishWin", norm(sfx_finish(True), 0.85)),
        ("finish", norm(sfx_finish(False), 0.7)), ("cheer", norm(sfx_cheer(), 0.6)),
        ("drumroll", norm(sfx_drumroll(), 0.6)), ("gachaN", norm(sfx_gacha("N"), 0.6)),
        ("gachaR", norm(sfx_gacha("R"), 0.7)), ("gachaSR", norm(sfx_gacha("SR"), 0.8)),
        ("gachaSSR", norm(sfx_gacha("SSR"), 0.88)), ("rankup", norm(sfx_rankup(), 0.8)),
        ("whoosh", norm(sfx_whoosh(), 0.5)),
    ]
    parts, at = [np.zeros(int(SR * 0.3))], 0.3
    for name, x in sounds:
        x = fade(x)
        regions[name] = (round(at, 3), round(at + len(x) / SR, 3))
        parts += [x, np.zeros(int(SR * 0.3))]
        at += len(x) / SR + 0.3
    write_wav(OUT / "minato-sfx.wav", np.concatenate(parts))

    # くり返す音: 同じ波を3回続けて書き、真ん中をくり返す(区切りが少しずれても継ぎ目が出ない)
    loops = [("engine", engine_loop()), ("water", water_loop()), ("crowd", crowd_loop())]
    parts, at = [np.zeros(int(SR * 0.3))], 0.3
    loop_regions = {}
    for name, x in loops:
        d = len(x) / SR
        loop_regions[name] = (round(at + d, 3), round(at + 2 * d, 3))
        parts += [x, x, x, np.zeros(int(SR * 0.3))]
        at += 3 * d + 0.3
    write_wav(OUT / "minato-loops.wav", np.concatenate(parts))

    write_wav(OUT / "minato-opening.wav", opening())
    bgm = music()
    write_wav(OUT / "minato-music.wav", bgm)

    lines = ["-- 自動で作ったファイル(roblox/tools/make_audio.py)。手で書き換えない。", "-- 効果音とくり返す音の位置(秒): {始まり, 終わり}", "return {", "    sfx = {"]
    for name, (a, b) in regions.items():
        lines.append(f"        {name} = {{{a}, {b}}},")
    lines += ["    },", "    loops = {"]
    for name, (a, b) in loop_regions.items():
        lines.append(f"        {name} = {{{a}, {b}}},")
    lines += ["    },", "    openingLength = 24,", f"    musicLength = {round(len(bgm) / SR, 3)},", "}", ""]
    (ROOT / "src" / "AudioSheet.lua").write_text("\n".join(lines), encoding="utf-8", newline="\n")
    for f in sorted(OUT.glob("minato-*.wav")):
        print(f.name, f"{f.stat().st_size / 1024:.0f} KB")
    print("regions:", len(regions), "loops:", len(loop_regions))


if __name__ == "__main__":
    import sys
    if sys.argv[1:] == ["--opening-only"]:
        OUT.mkdir(parents=True, exist_ok=True)
        write_wav(OUT / "minato-opening.wav", opening())
    else:
        main()
