"""Run the Roblox simulation with the official Luau CLI.

Usage: python roblox/tools/run_sim.py 60
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
    source = f'local NUM_RACES = {args.races}\n'
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
