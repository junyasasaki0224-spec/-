#!/usr/bin/env python3
"""鳴き声の音(assets/sounds/YokaiCries.ogg)と表(Config/Cries.luau)が合っているかを確かめる。

ogg を実際にほどいて(エンコードの後の音で)次を調べる。1つでも外れたら終了コード 1。
  - Roblox に上げられる形か: Vorbis・モノラル・44.1kHz・7分未満・20MB未満
  - 魚ごとの区間に、その魚の鳴き声が入っているか: レシピから作り直した音と重ね合わせて、
    ずれ(1ms 以内)と似ている度合い(相関 0.97 以上)を見る(別の魚の声が鳴る・頭が欠ける のを防ぐ)
  - 区間の外にはみ出していないか(区間の前後 0.25 秒に音が残っていない)
  - 区間どうしの間は無音か / 音割れしていないか / 大きさがそろっているか(±2dB)
  - 参考: 声の高さ(基本周波数)の中央値。デザインした高さの範囲に入っているか

使い方:
  python3 tools/cries/check_cries.py --defs build/fish.json
"""

import argparse
import json
import math
import os
import re
import subprocess
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import yokai_cries as Y  # noqa: E402

SR = Y.SR

# 参考: 主役の声の高さ(Hz)の範囲と、測る部分(区間の何割目から何割目)。デザインどおりの高さで鳴いているか。
# 伝説以上は1オクターブ下の声も重ねているので、下の範囲はその分広い。龍神は最後の鐘(196Hz)を除いて吠え声だけ測る
PITCH = {
    "ashi_medaka": (1500, 2700, 0.0, 1.0),
    "hasu_koi": (700, 1300, 0.0, 1.0),
    "ko_namazu": (110, 270, 0.0, 1.0),
    "kitsunebi_ayu": (560, 960, 0.0, 1.0),
    "nekomata_koi": (400, 780, 0.0, 1.0),
    "nure_unagi": (220, 320, 0.0, 1.0),
    "kappa_haze": (1250, 2000, 0.0, 1.0),
    "houou_koi": (420, 1750, 0.0, 0.5),
    "ushioni_ei": (100, 200, 0.0, 1.0),
    "ryujin": (25, 110, 0.0, 0.3),
}


def read_table(path):
    src = open(path, encoding="utf-8").read()
    pat = re.compile(r'(\w+) = \{\s*start = ([\d.]+),\s*length = ([\d.]+),\s*ja = "([^"]*)",\s*en = "([^"]*)",?\s*\}', re.S)
    rows = {m.group(1): (float(m.group(2)), float(m.group(3))) for m in pat.finditer(src)}
    total = float(re.search(r"\blength = ([\d.]+), --", src).group(1))
    sound_id = re.search(r'soundId = "([^"]*)"', src).group(1)
    return rows, total, sound_id


def probe(path):
    out = subprocess.run(
        ["ffprobe", "-v", "error", "-show_entries", "stream=codec_name,sample_rate,channels:format=duration,size", "-of", "json", path],
        capture_output=True,
        check=True,
    ).stdout
    j = json.loads(out)
    st = j["streams"][0]
    return st["codec_name"], int(st["sample_rate"]), int(st["channels"]), float(j["format"]["duration"]), int(j["format"]["size"])


def decode(path):
    raw = subprocess.run(["ffmpeg", "-v", "error", "-i", path, "-f", "f32le", "-ac", "1", "-ar", str(SR), "-"], capture_output=True, check=True).stdout
    return np.frombuffer(raw, dtype="<f4").astype(np.float64)


def best_lag(ref, seg, max_lag):
    """ref と seg のずれ(サンプル)と、そのずれでの相関"""
    n = min(len(ref), len(seg))
    a, b = ref[:n], seg[:n]
    size = 1 << int(math.ceil(math.log2(2 * n)))
    xc = np.fft.irfft(np.fft.rfft(b, size) * np.conj(np.fft.rfft(a, size)), size)
    lags = np.concatenate([np.arange(0, max_lag + 1), np.arange(-max_lag, 0)])
    vals = np.concatenate([xc[: max_lag + 1], xc[-max_lag:]])
    k = int(np.argmax(vals))
    lag = int(lags[k])
    if lag >= 0:
        x, y = a[: n - lag], b[lag:n]
    else:
        x, y = a[-lag:n], b[: n + lag]
    corr = float(np.dot(x, y) / (np.linalg.norm(x) * np.linalg.norm(y) + 1e-12))
    return lag, corr


def active_rms_db(x):
    win = int(0.05 * SR)
    pw = np.convolve(x * x, np.ones(win) / win, mode="same")
    act = pw > np.max(pw) * 0.05
    return 10 * math.log10(float(np.mean(pw[act])) + 1e-12)


def median_f0(x, fmin=25, fmax=3000):
    """とても簡単な YIN(声の部分の基本周波数の中央値)"""
    frame, hop = 2048, 512
    f0s = []
    tmin, tmax = int(SR / fmax), int(SR / fmin)
    for i in range(0, len(x) - frame - tmax, hop):
        w = x[i : i + frame + tmax]
        if np.sqrt(np.mean(w[:frame] ** 2)) < 0.02:
            continue
        d = np.array([np.sum((w[:frame] - w[t : t + frame]) ** 2) for t in range(tmin, tmax)])
        cm = d * np.arange(1, len(d) + 1) / (np.cumsum(d) + 1e-12)
        below = np.nonzero(cm < 0.15)[0]
        if len(below) == 0:
            continue
        k = below[0]
        while k + 1 < len(cm) and cm[k + 1] < cm[k]:
            k += 1
        f0s.append(SR / (k + tmin))
    return float(np.median(f0s)) if f0s else None


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--defs", required=True)
    ap.add_argument("--sprite", default="assets/sounds/YokaiCries.ogg")
    ap.add_argument("--luau", default="src/shared/Config/Cries.luau")
    a = ap.parse_args()
    defs = json.load(open(a.defs))
    defs = defs["fish"] if isinstance(defs, dict) else defs
    rows, total, sound_id = read_table(a.luau)
    problems = []

    codec, rate, ch, dur, size = probe(a.sprite)
    print(f"音のファイル: {codec} / {rate}Hz / {ch}ch / {dur:.1f}秒 / {size / 1024:.0f}KB / soundId={sound_id}")
    if codec != "vorbis" or ch != 1 or rate != SR:
        problems.append(f"形式が想定外: {codec} {rate}Hz {ch}ch")
    if dur >= 7 * 60 or size >= 20 * 1024 * 1024:
        problems.append("Roblox に上げられる長さ・大きさを超えています")
    if abs(dur - total) > 0.05:
        problems.append(f"表の長さ {total:.3f} と音の長さ {dur:.3f} が合いません")

    x = decode(a.sprite)
    peak = float(np.max(np.abs(x)))
    if peak >= 0.999:
        problems.append(f"音割れ(最大 {peak:.3f})")
    ids = [d["id"] for d in defs]
    missing = [i for i in ids if i not in rows]
    if missing:
        problems.append("表に無い魚: " + ", ".join(missing))

    # 区間の外(=間の無音)
    inside = np.zeros(len(x), dtype=bool)
    for s0, ln in rows.values():
        inside[int(s0 * SR) : int((s0 + ln) * SR)] = True
    gap_peak = float(np.max(np.abs(x[~inside]))) if np.any(~inside) else 0.0
    if gap_peak > 0.004:
        problems.append(f"区間どうしの間に音があります(最大 {gap_peak:.4f})")

    print(f"{'魚':18} {'ずれ':>7} {'相関':>6} {'大きさ':>8} {'最大':>7} {'声の高さ':>9}")
    levels = []
    for d in defs:
        fid = d["id"]
        if fid not in rows:
            continue
        s0, ln = rows[fid]
        i0, i1 = int(round(s0 * SR)), int(round((s0 + ln) * SR))
        seg = x[i0:i1]
        ref, _, _ = Y.make(d)
        lag, corr = best_lag(ref, seg, int(0.02 * SR))
        lvl = active_rms_db(seg)
        levels.append(lvl)
        pk = 20 * math.log10(float(np.max(np.abs(seg))) + 1e-12)
        # 区間の前後 0.25 秒(=間)に、この魚の音がはみ出していないか
        pad = int(0.25 * SR)
        around = np.concatenate([x[max(0, i0 - pad) : i0], x[i1 : i1 + pad]])
        spill = float(np.max(np.abs(around))) if len(around) else 0.0
        part = PITCH.get(fid, (0, 0, 0.0, 1.0))
        f0 = median_f0(seg[int(len(seg) * part[2]) : int(len(seg) * part[3])])
        note = ""
        if fid in PITCH and f0 is not None:
            lo, hi = PITCH[fid][0], PITCH[fid][1]
            note = "" if lo <= f0 <= hi else f"  ← 想定 {lo}〜{hi}Hz"
        f0s = f"{f0:7.0f}Hz" if f0 else "      -"
        print(f"{fid:18} {lag / SR * 1000:5.1f}ms {corr:6.3f} {lvl:6.1f}dB {pk:5.1f}dB {f0s}{note}")
        if abs(lag) > int(0.001 * SR):
            problems.append(f"{fid}: 区間が {lag / SR * 1000:.1f}ms ずれています")
        if corr < 0.97:
            problems.append(f"{fid}: 区間の音がレシピの音と違います(相関 {corr:.3f})")
        if spill > 0.004:
            problems.append(f"{fid}: 区間の外に音がはみ出しています({spill:.4f})")
        if note:
            print(f"   (参考) {fid} の声の高さがデザインの範囲外です", file=sys.stderr)
    med = float(np.median(levels))
    for d, lvl in zip([d for d in defs if d["id"] in rows], levels):
        if abs(lvl - med) > 2.0:
            problems.append(f"{d['id']}: 大きさが他とそろっていません({lvl:.1f}dB / 中央値 {med:.1f}dB)")

    print()
    if problems:
        print("問題:")
        for p in problems:
            print("  -", p)
        sys.exit(1)
    print(f"OK: {len(levels)} 匹の鳴き声が区間どおりに入っていて、間は無音、大きさは中央値 {med:.1f}dB ±2dB 以内")


if __name__ == "__main__":
    main()
