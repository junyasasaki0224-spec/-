"""画面の言語の表(roblox/i18n/*.txt)から、ゲームが読む roblox/src/LangData.lua を作る。

表の作り(i18n/*.txt。欄は | で区切る。前後の半角の空白は取る): 1行目が言語の列(ja|en|es|pt|id|fr|de|ko|zhcn|zhtw|th|vi)。1列目がゲームの中の日本語(訳す元)、
ほかの列がその言語の訳。数や名前が入る所は {1} {2}(元と訳で同じ番号を使う。順番は言語ごとに入れ替えてよい)。
改行は \n と書く。空の欄は英語の訳を使う。# で始まる行は書き手のメモ。

使い方: python roblox/tools/build_lang.py
"""
import glob
import io
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
LANGS = ["ja", "en", "es", "pt", "id", "fr", "de", "ko", "zhcn", "zhtw", "th", "vi"]
SLOT = re.compile(r"\{(\d)\}")


def lua(s):
    return '"' + s.replace('"', '\\"') + '"'


def main():
    rows, seen, problems = [], {}, []
    for path in sorted(glob.glob(os.path.join(ROOT, "i18n", "*.txt"))):
        name = os.path.basename(path)
        lines = io.open(path, encoding="utf-8").read().split("\n")
        head = [c.strip(" ") for c in lines[0].rstrip("\r").split("|")]
        if head != LANGS:
            sys.exit(f"{name}: 1行目は {' '.join(LANGS)} にする")
        for number, line in enumerate(lines[1:], 2):
            line = line.rstrip("\r")
            if not line.strip() or line.startswith("#"):
                continue
            cells = [c.strip(" ") for c in line.split("|")]
            if len(cells) != len(LANGS):
                problems.append(f"{name}:{number}: 欄の数が {len(cells)}(正しくは {len(LANGS)})")
                continue
            source = cells[0]
            slots = sorted(SLOT.findall(source))
            for code, cell in zip(LANGS[1:], cells[1:]):
                if cell and sorted(SLOT.findall(cell)) != slots:
                    problems.append(f"{name}:{number}: {code} の {{}} が元と違う: {source} → {cell}")
            if source in seen:
                if seen[source] != cells:
                    problems.append(f"{name}:{number}: 同じ元の文がちがう訳で2回ある: {source}")
                continue
            if slots and not re.sub(r"\{\d\}", "", source).strip(" "):
                problems.append(f"{name}:{number}: {{}} だけの文は当てはめられない: {source}")
            seen[source] = cells
            rows.append(cells)
    if problems:
        print("\n".join(problems))
        sys.exit(1)
    out = ["-- 画面の言語の訳の表(tools/build_lang.py が roblox/i18n/*.txt から作る。手で書き換えない)",
           "return {", "\tlangs = {" + ", ".join(lua(c) for c in LANGS[1:]) + "},", "\trows = {"]
    for cells in rows:
        out.append("\t\t{" + ", ".join(lua(c) for c in cells) + "},")
    out += ["\t},", "}", ""]
    io.open(os.path.join(ROOT, "src", "LangData.lua"), "w", encoding="utf-8", newline="\n").write("\n".join(out))
    print(len(rows), "rows ->", "src/LangData.lua")


if __name__ == "__main__":
    main()
