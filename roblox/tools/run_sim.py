"""Run the Roblox boat simulation using Luau, or a local Lua 5.1 runtime.

Usage: python roblox/tools/run_sim.py 60
The simulation loads the same physics, collision, AI and roster sources as the game.
"""
import argparse
import ctypes
import ctypes.util
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]


def source(name):
    return (ROOT / 'src' / name).read_text(encoding='utf-8')


def script(races, lua51=False):
    modules = {
        'AI': source('RaceAI.lua'),
        'collision': source('BoatCollision.lua'),
        'physics': source('BoatPhysics.lua'),
        'createRoster': source('RaceRoster.lua'),
    }
    if lua51:
        # Lua 5.1 lacks Luau's compound assignment. Only the shared physics
        # module uses it, and each assignment occupies its own line.
        modules['physics'] = re.sub(
            r'^(\s*)([\w.]+)\s*([+\-])=\s*(.+)$',
            lambda m: f'{m[1]}{m[2]} = {m[2]} {m[3]} {m[4]}',
            modules['physics'], flags=re.MULTILINE,
        )
    prefix = 'math.clamp = math.clamp or function(x,a,b) return math.max(a,math.min(b,x)) end\n'
    prefix += f'local NUM_RACES = {races}\n'
    for name, contents in modules.items():
        prefix += f'local {name} = (function()\n{contents}\nend)()\n'
    return prefix + (ROOT / 'tools' / 'simulation.lua').read_text(encoding='utf-8')


def run_lua51(contents):
    candidates = [ctypes.util.find_library('lua5.1')]
    if os.name == 'nt':
        candidates.append(r'C:\Program Files\obs-studio\bin\64bit\lua51.dll')
    library = next((name for name in candidates if name and (os.path.isfile(name) or os.name != 'nt')), None)
    if not library:
        raise SystemExit('Install the official Luau CLI and put luau on PATH to run this simulation.')
    if os.name == 'nt' and os.path.isfile(library):
        os.add_dll_directory(str(Path(library).parent))
    lua = ctypes.CDLL(library)
    lua.luaL_newstate.restype = ctypes.c_void_p
    lua.luaL_openlibs.argtypes = [ctypes.c_void_p]
    lua.luaL_loadstring.argtypes = [ctypes.c_void_p, ctypes.c_char_p]
    lua.lua_pcall.argtypes = [ctypes.c_void_p, ctypes.c_int, ctypes.c_int, ctypes.c_int]
    lua.lua_tolstring.argtypes = [ctypes.c_void_p, ctypes.c_int, ctypes.c_void_p]
    lua.lua_tolstring.restype = ctypes.c_char_p
    lua.lua_close.argtypes = [ctypes.c_void_p]
    state = lua.luaL_newstate()
    if not state:
        raise RuntimeError('Could not initialize Lua')
    try:
        lua.luaL_openlibs(state)
        code = lua.luaL_loadstring(state, contents.encode('utf-8'))
        if code == 0:
            code = lua.lua_pcall(state, 0, 0, 0)
        if code:
            raise RuntimeError(lua.lua_tolstring(state, -1, None).decode('utf-8', errors='replace'))
    finally:
        lua.lua_close(state)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('races', nargs='?', type=int, default=60)
    args = parser.parse_args()
    if args.races < 1:
        parser.error('races must be positive')
    executable = shutil.which('luau')
    if executable:
        print('Runtime: official Luau CLI', flush=True)
        with tempfile.TemporaryDirectory(prefix='minato-sim-') as directory:
            path = Path(directory) / 'simulation.luau'
            path.write_text(script(args.races), encoding='utf-8')
            subprocess.run([executable, str(path)], check=True)
    else:
        print('Runtime: Lua 5.1 compatibility fallback', flush=True)
        run_lua51(script(args.races, lua51=True))


if __name__ == '__main__':
    main()
