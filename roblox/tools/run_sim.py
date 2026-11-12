"""Roblox 版の計算部分(物理・AI・衝突)を、Roblox なしで回して勝率を測る。
  python3 roblox/tools/run_sim.py [レース数]
Luau の公式 CLI(https://github.com/luau-lang/luau/releases の luau)が PATH に必要。
Race.server.lua の reset()/step() と同じ手順を、Roblox の API を除いて再現している。
Race.server.lua の手順を変えたら、下の HARNESS も合わせて直すこと。"""
import os, subprocess, sys, tempfile
SRC = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'src')
mod = lambda n: open(os.path.join(SRC, n + '.lua'), encoding='utf-8').read()
N = int(sys.argv[1]) if len(sys.argv) > 1 else 60
HARNESS = open(os.path.join(os.path.dirname(os.path.abspath(__file__)), 'harness_body.luau'), encoding='utf-8').read()
code = ("local stepBoat = (function() %s end)()\nlocal collision = (function() %s end)()\nlocal RaceAI = (function() %s end)()\nlocal N = %d\n"
        % (mod('BoatPhysics'), mod('BoatCollision'), mod('RaceAI'), N)) + HARNESS
with tempfile.NamedTemporaryFile('w', suffix='.luau', delete=False, encoding='utf-8') as f:
    f.write(code)
try:
    subprocess.run(['luau', f.name], check=True)
finally:
    os.unlink(f.name)
