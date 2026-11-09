#!/usr/bin/env node
// 既存ゲームのポートフォリオ分析。日次の企画で「何が足りないか」を判断する材料を出す。
// 使い方: node scripts/portfolio.mjs
import { listGames, GENRES, LANES } from './lib.mjs';

// 直近10本でのレーン目標比率（automation/STRATEGY.md と一致させる）
const LANE_TARGET = { 'proven-twist': 0.4, 'search-demand': 0.3, 'trend-season': 0.15, experiment: 0.15 };

const games = listGames().filter((g) => g.meta);
const recent = games.slice(0, 10);
const last7 = games.slice(0, 7);

const count = (arr, key) => arr.reduce((m, g) => ((m[g.meta[key]] = (m[g.meta[key]] || 0) + 1), m), {});
const laneRecent = count(recent, 'lane');
const genreAll = count(games, 'genre');
const genreLast7 = count(last7, 'genre');

console.log(`# Portfolio (${games.length} games)\n`);
console.log('## 直近10本のレーン配分 vs 目標');
console.log('| lane | 実績 | 目標 | 不足 |');
console.log('|---|---|---|---|');
const deficits = [];
for (const l of LANES) {
  const have = recent.length ? (laneRecent[l] || 0) / recent.length : 0;
  const gap = LANE_TARGET[l] - have;
  deficits.push([l, gap]);
  console.log(`| ${l} | ${Math.round(have * 100)}% (${laneRecent[l] || 0}) | ${LANE_TARGET[l] * 100}% | ${gap > 0 ? '+' + Math.round(gap * 100) + '%' : '-'} |`);
}
deficits.sort((a, b) => b[1] - a[1]);
console.log(`\n→ 今日優先するレーン: **${deficits[0][0]}**（次点 ${deficits[1][0]}）\n`);

console.log('## ジャンル');
console.log('| genre | 全体 | 直近7本 |');
console.log('|---|---|---|');
for (const g of GENRES) console.log(`| ${g} | ${genreAll[g] || 0} | ${genreLast7[g] || 0} |`);
const blocked = Object.entries(genreLast7).filter(([, n]) => n >= 2).map(([g]) => g);
const untouched = GENRES.filter((g) => !genreAll[g]);
console.log(`\n→ 直近7本で2本以上（今日は避ける）: ${blocked.join(', ') || 'なし'}`);
console.log(`→ 未着手ジャンル: ${untouched.join(', ') || 'なし'}\n`);

console.log('## 既存タイトル（重複企画の回避用）');
for (const g of games) console.log(`- ${g.meta.created} ${g.meta.title} [${g.meta.genre}/${g.meta.subgenre || '-'}] ${g.meta.lane} — ${g.meta.twist}`);
