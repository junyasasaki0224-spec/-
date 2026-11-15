// コイン・ガチャ・レート・ミッション・メールの計算を確かめる: node tools/meta-test.mjs
import assert from 'node:assert/strict';
import * as M from '../src/meta.js';
const S = {}; const m = M.ensureMeta(S);
assert.equal(m.coins, 0); assert.equal(M.claimMail(m, 'welcome'), 500); assert.equal(m.coins, 500); assert.equal(M.claimMail(m, 'welcome'), 0);
assert.ok(M.dailyRefresh(m, '2026-01-01')); assert.ok(!M.dailyRefresh(m, '2026-01-01')); assert.equal(m.mail[0].coins, 100);
// 確率の合計は1。ガチャ: コインが足りないと引けない、引くと減る、かぶりはコインに変わる
assert.ok(Math.abs(Object.values(M.RARITY).reduce((s, r) => s + r.rate, 0) - 1) < 1e-9);
assert.equal(M.pull({ ...M.newMeta(), coins: 50 }, 1), null);
let seed = 7; const rnd = () => (seed = (seed * 16807) % 2147483647) / 2147483647;
const g = M.newMeta(); g.coins = 1000000; const cnt = { N: 0, R: 0, SR: 0, SSR: 0 };
for (let k = 0; k < 300; k++) for (const r of M.pull(g, 10, rnd)) cnt[r.item.r]++;
assert.ok(cnt.N > 1600 && cnt.N < 2000 && cnt.SSR > 25 && cnt.SSR < 110, JSON.stringify(cnt));
assert.equal(new Set(g.own).size, g.own.length); assert.equal(g.own.length, M.ITEMS.length, 'all items obtainable');
assert.ok(g.coins < 1000000 && g.coins > 1000000 - 300 * 900);
assert.ok(M.equip(g, 's11') && g.skin === 's11' && M.equip(g, 'h9') && g.helmet === 'h9'); assert.ok(!M.equip(M.newMeta(), 's11'));
// レート: 1着で上がり、失格で下がり、0より下がらない。昇級でメールが届く
const s = M.newMeta(); s.mail = [];
assert.equal(M.applyResult(s, { mode: 'season', place: 6, out: true, st: -0.1, lane: 0 }).rate, -20); assert.equal(s.rate, 0);
let up = null; for (let k = 0; k < 10; k++) { const r = M.applyResult(s, { mode: 'season', place: 1, st: 0.1, lane: 0, time: 100 }); if (r.grade) up = r.grade; }
assert.equal(s.rate, 300); assert.equal(up, 'B1'); assert.ok(s.mail.some((x) => x.title.includes('B1')));
assert.equal(M.GRADES[M.gradeOf(799)].name, 'B1'); assert.equal(M.GRADES[M.gradeOf(1500)].name, 'A1');
// ミッション: 条件を満たすと受け取れ、2回は受け取れない
assert.ok(M.missionsReady(s) >= 3); const c0 = s.coins; assert.equal(M.claimMission(s, 'top3'), 80); assert.equal(M.claimMission(s, 'top3'), 0); assert.equal(s.coins, c0 + 80);
// タイムアタック: ベスト更新でボーナス。シーズンパス: 100経験値で1段
const t = M.newMeta(); assert.ok(M.applyResult(t, { mode: 'ta', place: 1, lane: 2, time: 101.5 }).taBest); assert.ok(!M.applyResult(t, { mode: 'ta', place: 1, lane: 2, time: 102 }).taBest); assert.equal(t.ta[2], 101.5);
const p = M.newMeta(); p.mail = []; let tiers = 0; for (let k = 0; k < 10; k++) tiers += M.applyResult(p, { mode: 'single', place: 1, st: 0.3, lane: 0 }).tiers.length;
assert.equal(tiers, 3); assert.equal(p.tier, 3); assert.equal(p.mail.length, 3);
assert.equal(M.applyResult(M.newMeta(), { mode: 'single', place: 1, st: 0.3, lane: 0, event: true }).coins, 120);
assert.equal(M.applyResult(M.newMeta(), { mode: 'practice', place: 1 }).coins, 0);
assert.ok(M.eventOf('2026-11-15').id && M.eventOf('2026-11-15') === M.eventOf('2026-11-15'));
const board = M.rateBoard(s, [{ name: 'a', cls: 'A1' }, { name: 'b', cls: 'A1' }, { name: 'c', cls: 'B1' }]); assert.equal(board.length, 4); assert.ok(board[0].rate >= board[1].rate);
console.log('meta rules passed', JSON.stringify(cnt));
