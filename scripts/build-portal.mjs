#!/usr/bin/env node
// 大手ゲームサイト（CrazyGames / Poki）提出用のパッケージを作る。
// 使い方: node scripts/build-portal.mjs [--only <slug>] [--target crazygames|poki]
//
// 出力: portal-dist/<target>/<slug>/      … アップロードするフォルダ（英語版・サイトのSDK組み込み済み）
//       portal-dist/<target>/<slug>.zip   … 上のフォルダのzip（アップロード用）
//       portal-dist/<target>/<slug>-SUBMISSION.md … 投稿フォームに貼る英語の文章と手順
// スクリーンショットは portal-test.mjs が portal-dist/<target>/<slug>-*.png に保存する。
import fs from 'node:fs';
import path from 'node:path';
import { execFileSync } from 'node:child_process';
import { ROOT, SITE, listGames, escapeHtml } from './lib.mjs';

export const TARGETS = {
  crazygames: {
    name: 'CrazyGames',
    sdk: 'https://sdk.crazygames.com/crazygames-sdk-v3.js',
    upload: 'https://developer.crazygames.com/',
    notes: [
      'まず「Basic Launch（お試し公開）」で実際の利用者の反応が測られ、良ければ Full Launch（本公開・収益化）に招待される。',
      '審査で「真似・素材の差し替えだけの作品（clone / reskin）」は落とされる。説明文で独自の工夫を明記する。',
      '他サイトのロゴ・広告・外部リンクは入れない（このパッケージは対応済み）。'
    ]
  },
  poki: {
    name: 'Poki',
    sdk: 'https://game-cdn.poki.com/scripts/v2/poki-sdk.js',
    upload: 'https://developers.poki.com/',
    notes: [
      '原則として Web 独占（Poki 以外の Web サイトに出せなくなる。期間は契約で決まる）。自サイトからも外す必要があるため、出すのは「当たり」が確定した作品だけにする。',
      '開発者向け機能は招待制の時期があるため、申し込み状況を確認する。',
      '人による審査とプレイテストがある。'
    ]
  }
};

const PORTAL_CSS = `
  /* 大手サイト向け: 画面いっぱいにゲームだけを表示 */
  .gk-page { padding-top: 8px; padding-bottom: 16px; }
  .gk-howto, .gk-ad-slot, .gk-foot, .gk-bar { display: none !important; }
`;

function buildOne(game, targetKey) {
  const target = TARGETS[targetKey];
  const meta = game.meta;
  const outRoot = path.join(ROOT, 'portal-dist', targetKey);
  const out = path.join(outRoot, game.slug);
  fs.rmSync(out, { recursive: true, force: true });
  fs.mkdirSync(out, { recursive: true });

  // ゲームのファイル（meta.json 以外）をコピー
  for (const f of fs.readdirSync(game.dir)) {
    if (f === 'meta.json') continue;
    fs.cpSync(path.join(game.dir, f), path.join(out, f), { recursive: true });
  }
  fs.copyFileSync(path.join(SITE, 'assets', 'core.css'), path.join(out, 'core.css'));
  fs.copyFileSync(path.join(SITE, 'assets', 'core.js'), path.join(out, 'core.js'));

  let html = fs.readFileSync(path.join(out, 'index.html'), 'utf8');
  const cfg = { portal: targetKey, lang: 'en', siteName: '' };
  html = html
    .replace(/<html([^>]*)lang="ja"/, '<html$1lang="en"')
    .replace(/<title>[\s\S]*?<\/title>/, `<title>${escapeHtml(meta.title_en)}</title>`)
    .replace(/<meta name="description" content="[^"]*">/, `<meta name="description" content="${escapeHtml(meta.description_en)}">`)
    .replace(/<meta name="gk-title" content="[^"]*">/, `<meta name="gk-title" content="${escapeHtml(meta.title_en)}">`)
    .replace('../../assets/core.css', 'core.css')
    .replace('</head>', `<style>${PORTAL_CSS}</style>\n</head>`)
    .replace(/<article class="gk-howto"[\s\S]*?<\/article>/, '')
    .replace(/<div class="gk-ad-slot"[^>]*><\/div>/g, '')
    .replace('<script src="../../assets/config.js"></script>',
      `<script>window.SITE_CONFIG = ${JSON.stringify(cfg)};</script>\n<script src="${target.sdk}"></script>`)
    .replace('../../assets/core.js', 'core.js')
    .replaceAll('%SITE_NAME%', '');
  if (html.includes('../../')) throw new Error(`${game.slug}: index.html にサイト内リンク (../../) が残っています`);
  fs.writeFileSync(path.join(out, 'index.html'), html);

  // zip（アップロード用）
  const zipPath = path.join(outRoot, `${game.slug}.zip`);
  fs.rmSync(zipPath, { force: true });
  try {
    execFileSync('zip', ['-r', '-X', '-q', zipPath, '.'], { cwd: out });
  } catch {
    console.warn(`WARN zip コマンドがないため ${game.slug}.zip を作れませんでした（フォルダごとアップロードしてください）`);
  }

  // 投稿フォーム用の文章
  const sub = `# ${target.name} 提出シート：${meta.title}（${meta.title_en}）

> 自動生成。英語の欄はそのまま投稿フォームにコピーして使う。

## アップロードするもの
- ゲーム本体：\`portal-dist/${targetKey}/${game.slug}.zip\`（中に index.html がある）
- 画面写真：\`portal-dist/${targetKey}/${game.slug}-landscape.png\`（横 1280×720）、\`${game.slug}-portrait.png\`（縦 720×1280）
  - サイトが別のサイズを指定している場合は、その指示に従う。

## 投稿フォームに入れる内容（英語）

**Title**
${meta.title_en}

**Description**
${meta.description_en}

**How to play / Controls**
${meta.howto_en}

**Category**: ${meta.portal_category || 'Casual'}
**Tags**: ${(meta.portal_tags || []).join(', ')}
**Platforms**: Desktop and mobile (touch + mouse${meta.controls.includes('keyboard') ? ' + keyboard' : ''})
**Orientation**: Both
**What makes it different**
${meta.twist_en || meta.twist}

**Assets / originality statement**
All code, graphics (drawn in code) and sounds (synthesized at runtime) are original and made for this game. No third-party assets, fonts or libraries are used, except the ${target.name} SDK.

## このパッケージで対応済みのこと
- 英語表示（lang=en）
- ${target.name} SDK の組み込み（初期化／読み込み完了／プレイ開始・終了の通知／ゲーム内広告／報酬付き広告）
- 外部リンク・外部共有なし（シェアボタンは結果のコピーに変更）
- 自サイトの広告・計測・ヘッダー・説明文は除外

## ${target.name} の注意点
${target.notes.map((n) => `- ${n}`).join('\n')}

## 提出前にあなたが確認すること
- [ ] スマホとPCで、最初から最後まで遊べる
- [ ] 英語の文章に不自然なところがない
- [ ] 提出先の最新の規約（収益分配・独占・技術要件）を読んだ

投稿ページ：${target.upload}
`;
  fs.writeFileSync(path.join(outRoot, `${game.slug}-SUBMISSION.md`), sub);
  return out;
}

const args = process.argv.slice(2);
const only = args.includes('--only') ? args[args.indexOf('--only') + 1] : null;
const targetArg = args.includes('--target') ? args[args.indexOf('--target') + 1] : null;
const targets = targetArg ? [targetArg] : Object.keys(TARGETS);
for (const t of targets) if (!TARGETS[t]) { console.error(`unknown target: ${t}`); process.exit(1); }

const games = listGames().filter((g) => g.meta && !g.error && (!only || g.slug === only));
let n = 0;
for (const g of games) {
  for (const t of targets) { buildOne(g, t); n++; }
}
console.log(`built ${n} portal package(s) → portal-dist/ (${targets.join(', ')})`);
