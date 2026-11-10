// 出走するレーサー。成績はゲーム内の強さ(AI の腕・スタートの鋭さ・得意戦法)に対応する。
export const ROSTER = [
  { id: 0, name: '青波 隼人', cls: 'A1', st: 0.13, skill: 1.03, style: '逃げ', sashi: 0.3, win: 7.42, helmet: 0 },
  { id: 1, name: '水城 拓海', cls: 'A1', st: 0.15, skill: 1.01, style: '差し', sashi: 0.8, win: 6.98, helmet: 1 },
  { id: 2, name: '潮見 蓮', cls: 'A2', st: 0.14, skill: 0.99, style: 'まくり', sashi: 0.15, win: 6.11, helmet: 2 },
  { id: 3, name: '汐崎 航', cls: 'A2', st: 0.16, skill: 0.985, style: 'まくり差し', sashi: 0.55, win: 5.87, helmet: 3 },
  { id: 4, name: '風間 颯太', cls: 'B1', st: 0.18, skill: 0.965, style: '差し', sashi: 0.7, win: 4.93, helmet: 4 },
  { id: 5, name: '帆足 大河', cls: 'B1', st: 0.17, skill: 0.955, style: 'まくり', sashi: 0.2, win: 4.61, helmet: 5 },
];
export const PLAYER = { id: 'P', name: 'あなた', cls: '—', st: null, skill: 1, style: '—', sashi: 0, win: null, helmet: 6 };

// 難易度: 相手の腕前・スタートの遅れ・モーターの差
export const DIFFS = [
  { name: '初級', skill: 0.88, st: 0.1, motor: -0.055 },
  { name: '中級', skill: 0.955, st: 0.04, motor: -0.02 },
  { name: '上級', skill: 1.015, st: -0.01, motor: 0.006 },
];
export const POINTS = [10, 8, 6, 4, 2, 1];

// モーター2連率(%) → 出力係数
export const motorFactor = (rate) => 0.985 + (rate - 30) / 18 * 0.03;

// 風向きをホームストレッチ基準の言葉にする
export function windLabel(w) {
  if (w.wind < 0.5) return '無風';
  const wx = Math.cos(w.windDir), wz = Math.sin(w.windDir);
  const dir = Math.abs(wx) > Math.abs(wz) ? (wx > 0 ? '追い風' : '向かい風') : (wz > 0 ? '横風(スタンドへ)' : '横風(対岸へ)');
  return `${dir} ${w.wind.toFixed(0)}m`;
}
export function randomWeather(rng) {
  const wind = Math.round(Math.pow(rng(), 1.4) * 6);
  const dirs = [0, Math.PI, Math.PI, 0, Math.PI / 2, -Math.PI / 2];     // 追い風/向かい風が多め
  return { wind, windDir: dirs[(rng() * dirs.length) | 0] + (rng() - 0.5) * 0.3, wave: Math.round(wind * (0.6 + rng() * 0.6)), cover: 0.3 + rng() * 0.35 };
}
