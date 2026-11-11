// ============================================================
//  データ定義: 競馬場・レース・出走馬生成
//  コース諸元(1周距離・直線長・高低差・回り)は実在の競馬場を参考にしている
// ============================================================

export function mulberry32(seed) {
  let a = seed >>> 0;
  return function () {
    a = (a + 0x6d2b79f5) | 0;
    let t = Math.imul(a ^ (a >>> 15), 1 | a);
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}
export const clamp = (x, a, b) => (x < a ? a : x > b ? b : x);
export const lerp = (a, b, t) => a + (b - a) * t;

// 枠色 (1枠白, 2枠黒, 3枠赤, 4枠青, 5枠黄, 6枠緑, 7枠橙, 8枠桃)
export const WAKU_COLORS = ['#f4f4f4', '#1a1a1a', '#e3242b', '#1c53d6', '#f3d500', '#16a045', '#f28a1c', '#f39ac0'];
export const WAKU_TEXT = ['#111', '#fff', '#fff', '#fff', '#111', '#fff', '#111', '#111'];

// 馬番→枠番 (JRA方式: 9頭以上は外枠から2頭ずつ、17・18頭は7,8枠が3頭)
export function wakuOf(num, n) {
  if (n <= 8) return num;
  const sizes = new Array(8).fill(1);
  let extra = n - 8;
  for (let pass = 0; pass < 2 && extra > 0; pass++) {
    for (let w = 7; w >= 0 && extra > 0; w--) { sizes[w]++; extra--; }
  }
  let acc = 0;
  for (let w = 0; w < 8; w++) { acc += sizes[w]; if (num <= acc) return w + 1; }
  return 8;
}

export const STYLES = ['逃げ', '先行', '差し', '追込'];
export const GOING = ['良', '稍重', '重', '不良'];
export const WEATHER = ['晴', '曇', '小雨', '雨'];

// ---- 競馬場 ----
// elev: [ゴール板からの距離(進行方向), 標高m]
export const COURSES = {
  tokyo: {
    id: 'tokyo', name: '東京競馬場', short: '東京', loc: '東京都府中市', dir: 'L',
    lap: 2083.1, straight: 525.9, runoff: 120, width: 31,
    elev: [[0, 2.7], [300, 2.7], [500, 2.4], [750, 0.6], [850, 0.6], [950, 2.1], [1050, 2.1], [1300, 0], [1560, 0], [1623, 0.7], [1783, 2.7], [2083.1, 2.7]],
    feature: '左回り・直線525.9m。残り460m〜300mに高低差2mの上り坂「だんだら坂」。広いコースで紛れが少なく、末脚の持続力が問われる。',
    stand: { len: 400, h: 46, name: 'FUJI VIEW' },
  },
  nakayama: {
    id: 'nakayama', name: '中山競馬場', short: '中山', loc: '千葉県船橋市', dir: 'R',
    lap: 1667.1, straight: 310, runoff: 150, width: 26,
    elev: [[0, 2.7], [200, 4.2], [380, 5.3], [560, 4.6], [950, 0.8], [1150, 0], [1357, 0.5], [1487, 0.3], [1597, 2.5], [1667.1, 2.7]],
    feature: '右回り・直線310mと短い。ゴール前残り180m〜70mに高低差2.2mの急坂。高低差5.3mはJRA最大。小回りで器用さと位置取り、仕掛けの早さが鍵。',
    stand: { len: 300, h: 36, name: 'GRAND PRIX' },
  },
  kyoto: {
    id: 'kyoto', name: '京都競馬場', short: '京都', loc: '京都市伏見区(淀)', dir: 'R',
    lap: 1894.3, straight: 403.7, runoff: 150, width: 30,
    elev: [[0, 0], [700, 0], [800, 0.2], [1094, 4.3], [1194, 3.9], [1400, 0.2], [1490, 0], [1894.3, 0]],
    feature: '右回り・外回り。3コーナーに高低差4.3mの「淀の坂」。「ゆっくり上って、ゆっくり下る」が鉄則。直線403.7mは平坦で、下りの勢いをどう使うかが勝負。',
    stand: { len: 320, h: 38, name: 'GRAND SWAN' },
  },
  hanshin: {
    id: 'hanshin', name: '阪神競馬場', short: '阪神', loc: '兵庫県宝塚市', dir: 'R',
    lap: 2089, straight: 473.6, runoff: 130, width: 28,
    elev: [[0, 2.2], [400, 2.4], [1000, 2.4], [1400, 2.3], [1889, 0], [2009, 1.9], [2089, 2.2]],
    feature: '右回り・外回り。3〜4コーナーから緩やかに下り、残り200m〜80mで高低差1.8mの急坂。長い直線と坂で、スピードとパワーの両方が要る。',
    stand: { len: 300, h: 36, name: 'ROKKO VIEW' },
  },
};

// ---- レース番組 (名称は架空) ----
// season: spring/early_summer/autumn/winter  wx: [晴,曇,小雨,雨]の確率
export const RACES = [
  {
    id: 'tokyo2400', course: 'tokyo', dist: 2400, n: 18, name: '府中ダービーカップ', grade: 'GI', month: 5, season: 'early_summer', time: 'day',
    wx: [0.55, 0.25, 0.1, 0.1], prize: 30000, par: 144.5,
    memo: 'スタンド前発走→1周。世代の頂点を決める2400m。スローの瞬発力勝負になりやすい。',
  },
  {
    id: 'tokyo1600', course: 'tokyo', dist: 1600, n: 16, name: '武蔵野マイル王決定戦', grade: 'GI', month: 6, season: 'rainy', time: 'day',
    wx: [0.25, 0.3, 0.2, 0.25], prize: 18000, par: 93.0,
    memo: '向正面奥のポケット発走。梅雨時で馬場悪化に注意。長い直線での追い比べ。',
  },
  {
    id: 'nakayama2500', course: 'nakayama', dist: 2500, n: 16, name: '歳末グランドドリーム', grade: 'GI', month: 12, season: 'winter', time: 'dusk',
    wx: [0.6, 0.3, 0.05, 0.05], prize: 50000, par: 152.5,
    memo: 'コーナー6回の年末の大一番。短い直線と急坂。西日の中、早めのスパートと立ち回りが明暗を分ける。',
  },
  {
    id: 'nakayama1200', course: 'nakayama', dist: 1200, n: 16, name: '秋風スプリントステークス', grade: 'GI', month: 10, season: 'autumn', time: 'day',
    wx: [0.5, 0.3, 0.1, 0.1], prize: 17000, par: 68.4,
    memo: '下り坂スタートの電撃戦。ゲートと前半の位置取りがほぼ全て。最後の急坂で脚が上がる馬が続出。',
  },
  {
    id: 'kyoto3000', course: 'kyoto', dist: 3000, n: 18, name: '淀ステイヤーズクラウン', grade: 'GI', month: 10, season: 'autumn', time: 'day',
    wx: [0.5, 0.3, 0.1, 0.1], prize: 20000, par: 184.5,
    memo: '淀の坂を2度越える長丁場。1周目スタンド前の大歓声で折り合いを欠くと終わる。「最も強い馬が勝つ」。',
  },
  {
    id: 'hanshin1600', course: 'hanshin', dist: 1600, n: 18, name: '桜冠マイル', grade: 'GI', month: 4, season: 'spring', time: 'day',
    wx: [0.5, 0.25, 0.15, 0.1], prize: 14000, par: 93.2,
    memo: '満開の桜の下、外回りマイル。長い直線と急坂で、仕掛けを我慢できるかが問われる。',
  },
  {
    id: 'hanshin2200', course: 'hanshin', dist: 2200, n: 16, name: '六甲グランドカップ', grade: 'GI', month: 6, season: 'rainy', time: 'day',
    wx: [0.2, 0.3, 0.2, 0.3], prize: 22000, par: 132.0,
    memo: '梅雨の上半期総決算。タフな馬場になりやすく、パワーと道悪適性が物を言う。',
  },
];

// ---- 馬名 (すべて架空) ----
const NAME_A = ['アカツキ', 'シラユキ', 'ハヤテ', 'ミヤビ', 'カグラ', 'ホムラ', 'アオゾラ', 'ツキカゲ', 'コハク', 'スイレン', 'ライメイ', 'ヒスイ', 'ユウナギ', 'アサギリ', 'クレナイ', 'トキワ', 'ミナモ', 'ソラネ', 'キララ', 'ハルカゼ', 'シンゲツ', 'ホシゾラ', 'ヤマブキ', 'セイラン', 'アマツ', 'フウジン', 'リュウセイ', 'ゲッコウ', 'サザナミ', 'カゲロウ', 'ルリ', 'シグレ', 'イブキ', 'ナギサ', 'ヒビキ', 'ムサシノ', 'ヨドノ', 'ロッコウ'];
const NAME_B = ['ブレイブ', 'ロード', 'クイーン', 'スター', 'ウイング', 'ハート', 'ソウル', 'グローリー', 'ダンサー', 'ランナー', 'フラッシュ', 'ノヴァ', 'エース', 'キング', 'ストーム', 'ブリッツ', 'オー', 'アロー', 'ベル', 'ドリーム', 'ジェット', 'マーチ', 'ライト', 'シップ', 'ボーイ', 'レディ', 'ナイト', 'ソング', 'ウェイ', 'クラウン'];
const JOCKEYS = ['高瀬', '三上', '柏木', '早川', '真壁', '氷室', '久遠', '相馬', '鷹野', '御子柴', '風間', '榊原', '結城', '黛', '神代', '葛西', '東雲', '八雲', '霧島', '白鳥', '不破', '一ノ瀬'];
// 毛色
export const COATS = [
  { name: '鹿毛', body: 0x6b3d1e, mane: 0x151010, w: 40 },
  { name: '黒鹿毛', body: 0x3a2416, mane: 0x0c0a0a, w: 18 },
  { name: '栗毛', body: 0x9a5524, mane: 0xa86a32, w: 20 },
  { name: '青鹿毛', body: 0x1f1714, mane: 0x070606, w: 8 },
  { name: '芦毛', body: 0xb9b7b2, mane: 0x8a8884, w: 10 },
  { name: '栃栗毛', body: 0x7a4322, mane: 0xcdb89a, w: 4 },
];
const SILK_COLORS = [0xd92b2b, 0x1d4fd0, 0xf2c500, 0x12924a, 0xffffff, 0x111111, 0xe8792a, 0x8a2fc9, 0xf18fb8, 0x35b7d8, 0x7a1d1d, 0x1b2a6b];

function gauss(rng) { // 近似正規乱数
  return (rng() + rng() + rng() + rng() - 2) * 1.2247;
}
function pickW(rng, items, wf) {
  let tot = 0; for (const it of items) tot += wf(it);
  let r = rng() * tot;
  for (const it of items) { r -= wf(it); if (r <= 0) return it; }
  return items[items.length - 1];
}

export const CONDS = [
  { mark: '絶好調', sym: '↑↑', k: 1.006, cls: 'c4' },
  { mark: '好調', sym: '↑', k: 1.003, cls: 'c3' },
  { mark: '普通', sym: '→', k: 1.0, cls: 'c2' },
  { mark: '不調', sym: '↓', k: 0.996, cls: 'c1' },
];

// 出走馬を生成
export function makeField(race, seed) {
  const rng = mulberry32(seed);
  const n = race.n;
  const stay = clamp((race.dist - 1000) / 2200, 0, 1);
  const used = new Set();
  const horses = [];
  const jk = JOCKEYS.slice().sort(() => rng() - 0.5);
  for (let i = 0; i < n; i++) {
    let name;
    do {
      name = NAME_A[(rng() * NAME_A.length) | 0] + NAME_B[(rng() * NAME_B.length) | 0];
    } while (name.length > 9 || used.has(name));
    used.add(name);
    // 総合能力: 上位数頭が抜けた構成
    const cls = 66 + rng() * 14 + (rng() < 0.22 ? 5 + rng() * 6 : 0);
    const st = (base, sd) => clamp(Math.round(base + gauss(rng) * sd), 35, 99);
    const spd = st(cls + (1 - stay) * 8 - stay * 3, 4);
    const sta = st(cls + stay * 9 - (1 - stay) * 12, 5);
    const acc = st(cls, 8);
    const pow = st(cls, 8);
    const gut = st(70, 12);
    const tmp = st(66, 15); // 気性(高い=素直)
    const mud = st(62, 17); // 道悪適性
    const nim = st(68, 12); // 器用さ(コーナリング)
    const gate = st(68, 13); // ゲート
    // 脚質: ゲート・先行力が高いと前、瞬発力が高いと後ろ
    const front = (gate - 68) / 13 + (spd - acc) / 14 + gauss(rng) * 0.9;
    let style;
    if (front > 1.25) style = 0; else if (front > 0.1) style = 1; else if (front > -1.0) style = 2; else style = 3;
    const cond = pickW(rng, CONDS, (c) => (c.k === 1.0 ? 40 : c.k > 1.004 ? 12 : c.k > 1 ? 28 : 20));
    const coat = pickW(rng, COATS, (c) => c.w);
    const silk1 = SILK_COLORS[(rng() * SILK_COLORS.length) | 0];
    let silk2 = SILK_COLORS[(rng() * SILK_COLORS.length) | 0];
    if (silk2 === silk1) silk2 = 0xffffff;
    horses.push({
      num: i + 1, waku: wakuOf(i + 1, n), name, jockey: jk[i % jk.length],
      spd, sta, acc, pow, gut, tmp, mud, nim, gate, style,
      cond, coat, silk1, silk2, pattern: (rng() * 3) | 0,
      weight: 440 + ((rng() * 90) | 0), wdiff: ((rng() * 5) | 0) * 2 - 4,
      age: 3 + ((rng() * 3) | 0), sex: rng() < 0.25 ? '牝' : '牡',
      bias: gauss(rng) * 0.006, // AI騎手のペース判断の癖
      jskill: 0.55 + rng() * 0.45, // AI騎手の技量
      odds: 0, pop: 0,
    });
  }
  return horses;
}

// 当日の条件を生成
export function makeConditions(race, seed) {
  const rng = mulberry32(seed ^ 0x9e3779b9);
  let r = rng(), wi = 0;
  for (; wi < 3; wi++) { r -= race.wx[wi]; if (r <= 0) break; }
  let going;
  const g = rng();
  if (wi === 0) going = g < 0.82 ? 0 : 1;
  else if (wi === 1) going = g < 0.55 ? 0 : g < 0.9 ? 1 : 2;
  else if (wi === 2) going = g < 0.2 ? 0 : g < 0.65 ? 1 : g < 0.92 ? 2 : 3;
  else going = g < 0.15 ? 1 : g < 0.6 ? 2 : 3;
  const week = 1 + ((rng() * 4) | 0); // 開催何週目か
  let rough = [0, 0.3, 0.65, 1.0][week - 1];
  if (going >= 2) rough = Math.min(1.2, rough + 0.25);
  const windSpeed = Math.round((rng() * rng() * 9 + (wi >= 2 ? 1.5 : 0)) * 10) / 10;
  const windDir = rng() * Math.PI * 2;
  return { weather: wi, going, week, rough, wind: { speed: windSpeed, dir: windDir }, temp: 0 };
}

export function gradeOf(v) { return v >= 90 ? 'S' : v >= 82 ? 'A' : v >= 74 ? 'B' : v >= 66 ? 'C' : v >= 58 ? 'D' : 'E'; }

export function fmtTime(t) {
  if (!isFinite(t)) return '-';
  const m = Math.floor(t / 60), s = t - m * 60;
  return (m > 0 ? m + ':' : '') + (m > 0 && s < 10 ? '0' : '') + s.toFixed(1);
}
// 着差表記
export function marginText(m) {
  if (m < 0.12) return 'ハナ'; if (m < 0.35) return 'アタマ'; if (m < 0.75) return 'クビ';
  const L = m / 2.4;
  if (L < 0.62) return '1/2'; if (L < 0.87) return '3/4'; if (L < 1.12) return '1';
  if (L < 1.37) return '1 1/4'; if (L < 1.62) return '1 1/2'; if (L < 1.87) return '1 3/4';
  if (L < 2.25) return '2'; if (L < 2.75) return '2 1/2'; if (L < 3.25) return '3'; if (L < 3.75) return '3 1/2';
  if (L < 10.5) return String(Math.round(L));
  return '大差';
}
