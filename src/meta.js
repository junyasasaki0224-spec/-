// ゲームの外側の仕組み: コイン・ガチャ・倉庫・レートと級別・シーズンパス・ミッション・メール・イベント。
// 画面に依存しない計算だけを置く(tools/meta-test.mjs で確かめる)。データは設定と同じ場所(S.meta)に保存する。
// コインはレースやミッションでだけ手に入る(お金では買えない)。

export const RARITY = { N: { name: 'N', rate: 0.6, dupe: 15 }, R: { name: 'R', rate: 0.28, dupe: 40 }, SR: { name: 'SR', rate: 0.1, dupe: 120 }, SSR: { name: 'SSR', rate: 0.02, dupe: 400 } };
export const GACHA_COST = 100, GACHA_COST10 = 900;

// 艇の塗装: hull(船体)・trim(縁の帯)・deck(甲板)・cowl(モーターの覆い)
export const SKINS = [
  { id: 's0', name: 'スタンダード', r: 'N', hull: 0xf2f2ee, trim: 0xc81e2a, deck: 0xe9e9e4, cowl: 0xc81e2a },
  { id: 's1', name: 'マリンブルー', r: 'N', hull: 0xf2f2ee, trim: 0x1b50d4, deck: 0xdfe8f2, cowl: 0x1b50d4 },
  { id: 's2', name: 'フォレスト', r: 'N', hull: 0xf0efe6, trim: 0x18803c, deck: 0xe6ecdf, cowl: 0x18803c },
  { id: 's3', name: 'サンセット', r: 'N', hull: 0xfff1dc, trim: 0xf07a12, deck: 0xffe2bd, cowl: 0xf07a12 },
  { id: 's4', name: 'グラファイト', r: 'R', hull: 0x3a3f47, trim: 0xd9dde2, deck: 0x2a2e34, cowl: 0x8d949c },
  { id: 's5', name: 'チェリーレッド', r: 'R', hull: 0xc61b2b, trim: 0xffffff, deck: 0xa81422, cowl: 0x1a1a1e },
  { id: 's6', name: 'ディープシー', r: 'R', hull: 0x103a7a, trim: 0x39c6e8, deck: 0x0c2c5e, cowl: 0x39c6e8 },
  { id: 's7', name: 'ライムフラッシュ', r: 'R', hull: 0x16181c, trim: 0xb6f23a, deck: 0x202329, cowl: 0xb6f23a },
  { id: 's8', name: 'ミッドナイト', r: 'SR', hull: 0x0d1020, trim: 0x8a5cff, deck: 0x151a33, cowl: 0x8a5cff },
  { id: 's9', name: 'パールホワイト', r: 'SR', hull: 0xfbfaf5, trim: 0xd6b970, deck: 0xf3efe2, cowl: 0xd6b970 },
  { id: 's10', name: 'クリムゾンゴールド', r: 'SR', hull: 0x7a0f1c, trim: 0xffd23c, deck: 0x5c0b15, cowl: 0xffd23c },
  { id: 's11', name: 'みなとゴールド', r: 'SSR', hull: 0xe2b23a, trim: 0xfff4c4, deck: 0xc99a22, cowl: 0x1a1200 },
  { id: 's12', name: 'オーロラ', r: 'SSR', hull: 0x12c2b0, trim: 0xff5fa8, deck: 0x0e8f9c, cowl: 0x6a4cff },
];
// ヘルメット: base(地色)・stripe(帯)
export const HELMETS = [
  { id: 'h0', name: 'オレンジ', r: 'N', base: 0xff7a1a, stripe: 0x101010 },
  { id: 'h1', name: 'ホワイト', r: 'N', base: 0xf4f4f2, stripe: 0x1e4fd0 },
  { id: 'h2', name: 'ブラック', r: 'N', base: 0x16171b, stripe: 0xf2c200 },
  { id: 'h3', name: 'スカイ', r: 'N', base: 0x39a8e8, stripe: 0xffffff },
  { id: 'h4', name: 'ファイア', r: 'R', base: 0xd91e2e, stripe: 0xffd23c },
  { id: 'h5', name: 'ミント', r: 'R', base: 0x35d6a0, stripe: 0x0b3a2c },
  { id: 'h6', name: 'バイオレット', r: 'R', base: 0x6a2fa8, stripe: 0xffffff },
  { id: 'h7', name: 'カーボン', r: 'SR', base: 0x24272c, stripe: 0xe03a3a },
  { id: 'h8', name: 'シャンパン', r: 'SR', base: 0xe9dcb4, stripe: 0x8a6a1c },
  { id: 'h9', name: 'チャンピオン', r: 'SSR', base: 0xffd23c, stripe: 0xc81e2a },
];
export const ITEMS = [...SKINS.map((s) => ({ ...s, kind: 'skin' })), ...HELMETS.map((h) => ({ ...h, kind: 'helmet' }))];
export const item = (id) => ITEMS.find((x) => x.id === id);

// 級別(レートで決まる)と、その級で当たる相手の強さ(難易度の番号)
export const GRADES = [{ name: 'B2', rate: 0, diff: 0 }, { name: 'B1', rate: 300, diff: 1 }, { name: 'A2', rate: 800, diff: 2 }, { name: 'A1', rate: 1500, diff: 3 }];
export const gradeOf = (rate) => { let g = 0; for (let k = 0; k < GRADES.length; k++) if (rate >= GRADES[k].rate) g = k; return g; };
const RATE_DELTA = [30, 20, 10, 0, -10, -15], RATE_DQ = -20;
const COIN_PLACE = [60, 40, 30, 20, 15, 15], XP_PLACE = [30, 24, 20, 16, 12, 12];
export const PASS_STEP = 100;                       // シーズンパス: 100経験値で1段
export const passReward = (tier) => (tier % 5 === 0 ? 300 : 100);

// 場内ランキングに並ぶ AI 選手のレート(級別に合わせた固定値)
export const AI_RATES = { A1: [1720, 1610], A2: [1180, 960], B1: [540, 410] };

// 日替わりイベント(日付で決まる)。コイン2倍
export const EVENTS = [
  { id: 'night-gale', name: 'ナイター強風戦', desc: '夜・向かい風7mの荒れた水面', env: 'night', weather: { wind: 7, windDir: Math.PI, wave: 7, cover: 0.6 } },
  { id: 'outside', name: '大外まくり指令', desc: '6コースから勝負。薄暮・追い風', env: 'evening', lane: 5, weather: { wind: 4, windDir: 0, wave: 3, cover: 0.3 } },
  { id: 'glass', name: '無風スピード戦', desc: '無風・波なし。タイムが出る水面', env: 'day', weather: { wind: 0, windDir: 0, wave: 0, cover: 0.1 } },
  { id: 'rough', name: '荒水面サバイバル', desc: '横風6m・波高8cm。沈没に注意', env: 'evening', weather: { wind: 6, windDir: Math.PI / 2, wave: 8, cover: 0.8 } },
  { id: 'inside', name: 'イン逃げ指令', desc: '1コースを守り切れ。達人が相手', env: 'night', lane: 0, difficulty: 3, weather: { wind: 2, windDir: Math.PI, wave: 2, cover: 0.4 } },
];
export const dayKey = (d = new Date()) => `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`;
export const eventOf = (key) => { let h = 0; for (const c of key) h = (h * 31 + c.charCodeAt(0)) >>> 0; return EVENTS[h % EVENTS.length]; };

export const MISSIONS = [
  { id: 'race1', name: 'レースに1回出る', goal: 1, coins: 50 },
  { id: 'top3', name: '3着以内に入る', goal: 1, coins: 80 },
  { id: 'st20', name: 'ST 0.20 以内でスタートする', goal: 1, coins: 80 },
  { id: 'race3', name: 'レースに3回出る', goal: 3, coins: 120 },
];

export function newMeta() {
  return { coins: 0, own: ['s0', 'h0'], skin: 's0', helmet: 'h0', rate: 0, peak: 0, seasonRaces: 0, seasonWins: 0, xp: 0, tier: 0, ta: [null, null, null, null, null, null],
    day: '', mis: {}, misDone: {}, mail: [{ id: 'welcome', title: 'ようこそ みなとグランプリへ', body: '出走の記念に、ガチャ5回ぶんのコインを贈ります。', coins: 500 }], mailSeq: 1, pulls: 0 };
}
// 保存データを今の形にそろえる(足りない項目を足す)
export function ensureMeta(S) {
  const d = newMeta();
  S.meta = Object.assign(d, S.meta || {});
  if (!Array.isArray(S.meta.ta) || S.meta.ta.length !== 6) S.meta.ta = d.ta;
  return S.meta;
}
export function sendMail(m, title, body, coins) { m.mail.unshift({ id: 'm' + (m.mailSeq++), title, body, coins }); if (m.mail.length > 30) m.mail.length = 30; }
// 日付が変わったら: ミッションを新しくし、ログインボーナスをメールで届ける
export function dailyRefresh(m, key = dayKey()) {
  if (m.day === key) return false;
  m.day = key; m.mis = {}; m.misDone = {};
  sendMail(m, 'ログインボーナス', `${key} の出走ボーナスです。`, 100);
  return true;
}
export function claimMail(m, id) {
  const k = m.mail.findIndex((x) => x.id === id); if (k < 0) return 0;
  const c = m.mail[k].coins || 0; m.coins += c; m.mail.splice(k, 1); return c;
}
export function claimMission(m, id) {
  const ms = MISSIONS.find((x) => x.id === id);
  if (!ms || m.misDone[id] || (m.mis[id] || 0) < ms.goal) return 0;
  m.misDone[id] = true; m.coins += ms.coins; return ms.coins;
}

// ガチャ1回。rnd は 0〜1 の乱数を返す関数。持っている物が出たらコインに変わる
export function rollGacha(m, rnd = Math.random) {
  let x = rnd(), rar = 'N';
  for (const k of ['SSR', 'SR', 'R', 'N']) { if (x < RARITY[k].rate) { rar = k; break; } x -= RARITY[k].rate; }
  const pool = ITEMS.filter((it) => it.r === rar), it = pool[Math.min(pool.length - 1, Math.floor(rnd() * pool.length))];
  m.pulls++;
  if (m.own.includes(it.id)) { m.coins += RARITY[rar].dupe; return { item: it, dupe: RARITY[rar].dupe }; }
  m.own.push(it.id); return { item: it, dupe: 0 };
}
export function pull(m, n, rnd = Math.random) {
  const cost = n === 10 ? GACHA_COST10 : GACHA_COST * n;
  if (m.coins < cost) return null;
  m.coins -= cost;
  const out = []; for (let k = 0; k < n; k++) out.push(rollGacha(m, rnd));
  return out;
}
export function equip(m, id) { const it = item(id); if (!it || !m.own.includes(id)) return false; if (it.kind === 'skin') m.skin = id; else m.helmet = id; return true; }

// レースの結果を反映する。r = { mode, place(1〜6), out(失格), st, lane, time(完走タイム), event(イベントか) }
// 戻り値: 結果画面に出す内容
export function applyResult(m, r) {
  const res = { coins: 0, xp: 0, rate: 0, grade: null, taBest: false, tiers: [], lines: [] };
  if (r.mode === 'practice') return res;
  const pi = Math.max(0, Math.min(5, (r.place || 6) - 1));
  if (r.mode === 'ta') {
    res.coins = r.out || !r.time ? 5 : 20; res.xp = r.out ? 5 : 12;
    if (!r.out && r.time > 0 && (m.ta[r.lane] === null || r.time < m.ta[r.lane])) { m.ta[r.lane] = r.time; res.taBest = true; res.coins += 30; }
  } else {
    res.coins = r.out ? 5 : COIN_PLACE[pi]; res.xp = r.out ? 6 : XP_PLACE[pi];
    if (r.event) res.coins *= 2;
    if (r.mode === 'season') {
      const g0 = gradeOf(m.rate);
      res.rate = r.out ? RATE_DQ : RATE_DELTA[pi];
      m.rate = Math.max(0, m.rate + res.rate); m.peak = Math.max(m.peak, m.rate);
      m.seasonRaces++; if (!r.out && r.place === 1) m.seasonWins++;
      const g1 = gradeOf(m.rate);
      if (g1 > g0) { res.grade = GRADES[g1].name; sendMail(m, `${GRADES[g1].name} 級に昇級`, '昇級おめでとうございます。記念のコインです。', 200 * g1); }
    }
    // ミッション
    const add = (id, v = 1) => { m.mis[id] = (m.mis[id] || 0) + v; };
    add('race1'); add('race3');
    if (!r.out && r.place <= 3) add('top3');
    if (!r.out && r.st !== null && r.st !== undefined && r.st >= 0 && r.st <= 0.2) add('st20');
  }
  m.coins += res.coins; m.xp += res.xp;
  while (m.xp >= (m.tier + 1) * PASS_STEP) { m.tier++; const c = passReward(m.tier); res.tiers.push(m.tier); sendMail(m, `シーズンパス ${m.tier}段 到達`, 'ごほうびのコインです。', c); }
  return res;
}
export const missionsReady = (m) => MISSIONS.filter((x) => !m.misDone[x.id] && (m.mis[x.id] || 0) >= x.goal).length;

// 場内ランキング(レート順)。roster: [{name, cls}]
export function rateBoard(m, roster) {
  const used = { A1: 0, A2: 0, B1: 0 };
  const rows = roster.map((r) => ({ name: r.name, cls: r.cls, rate: (AI_RATES[r.cls] || [300])[used[r.cls]++ % 2] ?? 300, me: false }));
  rows.push({ name: 'あなた', cls: GRADES[gradeOf(m.rate)].name, rate: m.rate, me: true });
  return rows.sort((a, b) => b.rate - a.rate);
}
