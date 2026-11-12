"""GPT とのファイルのやりとりを安全にする道具(Claude が使う)。

  python3 -I tools/handoff.py make <出力.zip>
      今の版(HEAD)の ZIP を作る。中に BASE.txt(どの版から作ったかの印)を入れる。

  python3 -I tools/handoff.py intake <受け取った.zip> [--base <コミット>]
      GPT から戻ってきた ZIP を、作業ツリーに 3-way マージする(コミットはしない)。
      1. ZIP を一時フォルダに安全に展開する(フォルダ外への書き出しを拒否)
      2. BASE.txt の版(なければ、ファイルの一致から推定)を土台に、一時ブランチへ GPT の変更を載せる
      3. それを今のブランチへマージする。最新版の変更は消えない。衝突した所は git が示す
      ZIP に無いファイルは「変更なし」とみなす(GPT が変更したファイルだけ返しても大丈夫)。
      dist/ と node_modules/ と BASE.txt は取り込まない(dist はビルドし直す)。
ZIP の中身は実行しない。読み取って git に渡すだけ。"""
import os, subprocess, sys, tempfile, time, zipfile, shutil, hashlib
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SKIP_DIRS = ('dist/', 'node_modules/', '.git/', '__pycache__/')
SKIP_FILES = {'BASE.txt'}
MAX_BYTES = 200 * 1024 * 1024


def git(*args, cwd=ROOT, check=True):
    return subprocess.run(['git', *args], cwd=cwd, check=check, capture_output=True, text=True).stdout.strip()


def make(out):
    head, branch = git('rev-parse', 'HEAD'), git('rev-parse', '--abbrev-ref', 'HEAD')
    if git('status', '--porcelain'):
        print('注意: コミットしていない変更は ZIP に入りません')
    tmp = Path(tempfile.mkdtemp()) / 'a.zip'
    git('archive', '--format=zip', '--prefix=minato-grand-prix/', '-o', str(tmp), 'HEAD')
    stamp = (f'commit: {head}\nbranch: {branch}\ndate: {git("log", "-1", "--format=%cI")}\n'
             '# この ZIP がどの版から作られたかの印です。消したり書き換えたりしないでください。\n')
    with zipfile.ZipFile(tmp, 'a') as z:
        z.writestr('minato-grand-prix/BASE.txt', stamp)
    shutil.move(str(tmp), out)
    print(f'作成: {out}  (版 {head[:7]})')


def safe_extract(zpath, dest):
    dest = Path(dest).resolve()
    with zipfile.ZipFile(zpath) as z:
        total = sum(i.file_size for i in z.infolist())
        if total > MAX_BYTES:
            raise SystemExit(f'ZIP が大きすぎます ({total} bytes)')
        for i in z.infolist():
            target = (dest / i.filename).resolve()
            if not str(target).startswith(str(dest) + os.sep) and target != dest:
                raise SystemExit(f'フォルダ外へのパスを含むため中止: {i.filename}')
        z.extractall(dest)
    # 中身が1つのフォルダに入っていれば、そこを根とする
    entries = [p for p in dest.iterdir() if p.name != '__MACOSX']
    return entries[0] if len(entries) == 1 and entries[0].is_dir() else dest


def files_in(root):
    out = {}
    for p in root.rglob('*'):
        if p.is_file() and not p.is_symlink():
            rel = p.relative_to(root).as_posix()
            if rel in SKIP_FILES or any(rel.startswith(d) or f'/{d}' in f'/{rel}' for d in SKIP_DIRS):
                continue
            out[rel] = p
    return out


def blob_hash(path):
    data = path.read_bytes()
    return hashlib.sha1(b'blob %d\0' % len(data) + data).hexdigest()


def guess_base(files):
    """ZIP のファイルと最もよく一致する過去のコミットを探す"""
    best, best_score = None, -1
    for c in git('log', '--format=%H', '-n', '60').split():
        score = 0
        for rel, p in files.items():
            h = git('rev-parse', f'{c}:{rel}', check=False)
            if h and h == blob_hash(p):
                score += 1
        if score > best_score:
            best, best_score = c, score
    return best, best_score


def intake(zpath, base=None):
    if git('status', '--porcelain'):
        raise SystemExit('作業ツリーにコミットしていない変更があります。先にコミットしてください')
    work = Path(tempfile.mkdtemp(prefix='intake-'))
    root = safe_extract(zpath, work / 'zip')
    files = files_in(root)
    stamp = root / 'BASE.txt'
    if not base and stamp.exists():
        for line in stamp.read_text(encoding='utf-8', errors='replace').splitlines():
            if line.startswith('commit:'):
                base = line.split(':', 1)[1].strip()
    how = 'BASE.txt'
    if base:
        if git('cat-file', '-t', base, check=False) != 'commit':
            raise SystemExit(f'BASE の版 {base} がリポジトリにありません')
    else:
        base, score = guess_base(files)
        how = f'推定(一致 {score}/{len(files)} ファイル)'
    print(f'土台の版: {base[:7]}  [{how}]  /  ZIP 内のファイル: {len(files)}')
    branch = f'intake/{time.strftime("%Y%m%d-%H%M%S")}'
    wt = work / 'wt'
    git('worktree', 'add', '-q', '-b', branch, str(wt), base)
    try:
        changed = []
        for rel, p in files.items():
            dst = wt / rel
            if dst.exists() and dst.read_bytes() == p.read_bytes():
                continue
            dst.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(p, dst)
            changed.append(rel)
        if not changed:
            print('土台の版から変わったファイルはありません')
            return
        print('GPT が変えたファイル(土台の版との差):')
        for rel in sorted(changed):
            print('  ', rel)
        git('add', '-A', cwd=wt)
        git('-c', 'user.name=handoff', '-c', 'user.email=handoff@localhost', 'commit', '-q', '-m', f'GPT changes on {base[:7]} ({Path(zpath).name})', cwd=wt)
    finally:
        git('worktree', 'remove', '--force', str(wt), check=False)
    r = subprocess.run(['git', 'merge', '--no-ff', '--no-commit', branch], cwd=ROOT, capture_output=True, text=True)
    git('branch', '-D', branch, check=False) if r.returncode == 0 else None
    print(r.stdout.strip() or '')
    if r.returncode != 0:
        print('衝突があります。git status で確認し、直してからコミットしてください。')
        print(r.stderr.strip())
        sys.exit(2)
    print('マージしました(未コミット)。確認してからコミットしてください。')


if __name__ == '__main__':
    if len(sys.argv) >= 3 and sys.argv[1] == 'make':
        make(sys.argv[2])
    elif len(sys.argv) >= 3 and sys.argv[1] == 'intake':
        b = sys.argv[sys.argv.index('--base') + 1] if '--base' in sys.argv else None
        intake(sys.argv[2], b)
    else:
        print(__doc__)
