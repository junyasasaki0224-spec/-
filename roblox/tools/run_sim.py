"""Run the Roblox simulation with the official Luau CLI.

Usage: python -I roblox/tools/run_sim.py 120 4 --seed 2001
"""
import argparse
from pathlib import Path
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('races', nargs='?', type=int, default=60)
    # 難易度 1〜4(初級・中級・上級・達人)。オンライン対戦の空きを埋める AI は 4(達人)
    parser.add_argument('difficulty', nargs='?', type=int, default=2, choices=[1, 2, 3, 4])
    parser.add_argument("--seed", type=int, default=1, help="first race seed")
    args = parser.parse_args()
    if args.races < 1:
        parser.error('races must be positive')

    executable = shutil.which('luau')
    if not executable:
        raise SystemExit('公式 Luau CLI (luau) をインストールし、PATH に追加してください。')

    modules = {
        'AI': 'RaceAI.lua',
        'collision': 'BoatCollision.lua',
        'physics': 'BoatPhysics.lua',
        'createRoster': 'RaceRoster.lua',
    }
    source = f'local FIRST_SEED = {args.seed}\nlocal NUM_RACES = {args.races}\nlocal DIFFICULTY = {args.difficulty}\n'
    # Recorded with the unmodified c720e4b AI and the same interpolated timing.
    references = {(2, 1): 100.780, (2, 2001): 100.687, (4, 1): 98.641, (4, 2001): 98.623}
    baseline = references.get((args.difficulty, args.seed)) if args.races == 120 else None
    source += f"local BASELINE_TIME = {baseline or 'nil'}\n"
    for name, filename in modules.items():
        contents = (ROOT / 'src' / filename).read_text(encoding='utf-8')
        source += f'local {name} = (function()\n{contents}\nend)()\n'
    source += (ROOT / 'tools' / 'simulation.lua').read_text(encoding='utf-8')

    with tempfile.TemporaryDirectory(prefix='minato-sim-') as directory:
        path = Path(directory) / 'simulation.luau'
        path.write_text(source, encoding='utf-8')
        subprocess.run([executable, str(path)], check=True)


if __name__ == '__main__':
    main()
