// もみじ仕分け — 秋の葉っぱ・木の実の仕分けパズル
// 盤面は乱数で生成し、幅優先探索で「必ず解けること」と「最短手数」を確認してから出題する。
(function () {
  'use strict';
  var GK = window.GameKit;
  var CAP = 4;
  var T = GK.t;
  var EN = GK.lang === 'en';
  var NAMES = EN ? ['Maple', 'Ginkgo', 'Acorn', 'Persimmon', 'Grapes', 'Green leaf', 'Gentian']
                 : ['もみじ', 'いちょう', 'どんぐり', 'かき', 'ぶどう', 'あおば', 'りんどう'];

  // ---------------- パズルの純粋ロジック ----------------
  // 盤面 = かごの配列。かご = 文字列（下→上）。各文字 '0'〜'6' が種類。
  function isFullSame(s) { return s.length === CAP && /^(.)\1*$/.test(s); }
  function isGoal(t) { return t.every(function (s) { return s.length === 0 || isFullSame(s); }); }
  function topRun(s) {
    var c = s[s.length - 1], n = 1;
    while (n < s.length && s[s.length - 1 - n] === c) n++;
    return n;
  }
  /** 合法手 [from, to, 個数]。空かごへの移動は1通りに絞る（どの空かごでも同じ） */
  function legalMoves(t) {
    var out = [];
    for (var i = 0; i < t.length; i++) {
      var s = t[i];
      if (!s || isFullSame(s)) continue;
      var c = s[s.length - 1], run = topRun(s), triedEmpty = false;
      for (var j = 0; j < t.length; j++) {
        if (i === j) continue;
        var d = t[j];
        if (d.length >= CAP) continue;
        if (d.length === 0) {
          if (run === s.length || triedEmpty) continue; // 全部同じ種類を空かごへ移すのは無意味
          triedEmpty = true;
        } else if (d[d.length - 1] !== c) continue;
        out.push([i, j, Math.min(run, CAP - d.length)]);
      }
    }
    return out;
  }
  function canMove(t, i, j) {
    if (i === j) return 0;
    var s = t[i], d = t[j];
    if (!s || d.length >= CAP) return 0;
    if (d.length && d[d.length - 1] !== s[s.length - 1]) return 0;
    return Math.min(topRun(s), CAP - d.length);
  }
  function applyMove(t, i, j, n) {
    var r = t.slice();
    r[j] = r[j] + r[i].slice(r[i].length - n);
    r[i] = r[i].slice(0, r[i].length - n);
    return r;
  }
  function canon(t) { return t.slice().sort().join('|'); }

  /** 幅優先探索で最短手順を返す（見つからなければ null）。limit で探索量を制限 */
  function solve(start, limit) {
    if (isGoal(start)) return [];
    var seen = new Map();
    seen.set(canon(start), { parent: null, move: null });
    var frontier = [start];
    var count = 0;
    limit = limit || 300000;
    while (frontier.length) {
      var next = [];
      for (var f = 0; f < frontier.length; f++) {
        var t = frontier[f], kt = canon(t), ms = legalMoves(t);
        for (var m = 0; m < ms.length; m++) {
          var r = applyMove(t, ms[m][0], ms[m][1], ms[m][2]);
          var k = canon(r);
          if (seen.has(k)) continue;
          seen.set(k, { parent: kt, move: ms[m], state: t });
          if (isGoal(r)) {
            // 手順を復元（各手は、その時点の盤面のかご番号で記録されている）
            var path = [], cur = k;
            while (seen.get(cur).parent !== null) { path.unshift(seen.get(cur).move); cur = seen.get(cur).parent; }
            return path;
          }
          if (++count > limit) return null;
          next.push(r);
        }
      }
      frontier = next;
    }
    return null;
  }

  function generate(seedKey, colors, empties) {
    var rand = GK.rng(seedKey);
    for (var attempt = 0; attempt < 300; attempt++) {
      var items = [];
      for (var c = 0; c < colors; c++) for (var k = 0; k < CAP; k++) items.push(String(c));
      rand.shuffle(items);
      var t = [];
      for (var b = 0; b < colors; b++) t.push(items.slice(b * CAP, (b + 1) * CAP).join(''));
      for (var e = 0; e < empties; e++) t.push('');
      // 最初から揃っているかごがある盤面や、簡単すぎる盤面は捨てる
      if (t.some(isFullSame)) continue;
      var path = solve(t);
      if (path && path.length >= colors + 2) return { tubes: t, par: path.length, empties: empties };
    }
    // 空きかご1つで解けない組み合わせが続いた場合は、空きかご2つで作り直す
    return empties > 1 ? null : generate(seedKey + ':retry', colors, 2);
  }

  // 曜日ごとの難しさ（0=日曜）
  var DAILY_RULES = [
    { colors: 5, empties: 1, label: T('日曜・空きかご1つ', 'Sunday · only 1 empty basket') },
    { colors: 4, empties: 2, label: T('月曜・やさしい', 'Monday · easy') },
    { colors: 5, empties: 2, label: T('火曜', 'Tuesday') },
    { colors: 5, empties: 2, label: T('水曜', 'Wednesday') },
    { colors: 6, empties: 2, label: T('木曜', 'Thursday') },
    { colors: 6, empties: 2, label: T('金曜', 'Friday') },
    { colors: 7, empties: 2, label: T('土曜・むずかしい', 'Saturday · hard') }
  ];
  function dailyRule(dateStr) { return DAILY_RULES[new Date(dateStr + 'T00:00:00Z').getUTCDay()]; }
  function dailyPuzzle(dateStr) {
    var r = dailyRule(dateStr);
    return generate('momiji-daily:' + dateStr, r.colors, r.empties);
  }
  function practicePuzzle(level) {
    var colors = Math.min(3 + Math.floor((level - 1) / 2), 7);
    var empties = level >= 14 && level % 2 === 0 ? 1 : 2;
    return generate('momiji-practice:' + level, colors, empties);
  }
  function stars(moves, par) { return moves <= par ? 3 : moves <= par + 3 ? 2 : 1; }

  // ---------------- 画面 ----------------
  var $ = function (id) { return document.getElementById(id); };
  var boardEl = $('board'), msgEl = $('msg');
  var S = {
    mode: 'daily', date: GK.today(), level: GK.store.get('level', 1),
    puzzle: null, tubes: [], history: [], selected: -1, hint: null, hintsUsed: 0, done: false, lastTo: -1, lastN: 0
  };

  function svgItem(type) {
    return '<svg viewBox="0 0 40 40" role="img" aria-label="' + NAMES[type] + '"><use href="#ms-i' + type + '"/></svg>';
  }

  function load(mode) {
    S.mode = mode;
    S.puzzle = mode === 'daily' ? dailyPuzzle(S.date) : practicePuzzle(S.level);
    S.tubes = S.puzzle.tubes.slice();
    S.history = []; S.selected = -1; S.hint = null; S.hintsUsed = 0; S.done = false; S.lastTo = -1;
    $('tab-daily').setAttribute('aria-selected', String(mode === 'daily'));
    $('tab-practice').setAttribute('aria-selected', String(mode === 'practice'));
    var used = {};
    S.tubes.join('').split('').forEach(function (c) { used[c] = 1; });
    $('legend').innerHTML = Object.keys(used).sort().map(function (c) { return '<span>' + svgItem(+c) + NAMES[+c] + '</span>'; }).join('');
    if (mode === 'daily') {
      var rec = GK.store.get('daily:' + S.date, null);
      setMsg(rec ? T('今日はクリア済み（' + rec.moves + '手）。もっと少ない手数にも挑戦できます', 'Solved today in ' + rec.moves + ' moves. Try for fewer!')
                 : dailyRule(S.date).label + T('：同じ種類を1つのかごに4つ集めよう', ': collect 4 of a kind in each basket'));
    } else {
      setMsg(T('レベル ' + S.level + '：同じ種類を1つのかごに4つ集めよう', 'Level ' + S.level + ': collect 4 of a kind in each basket'));
    }
    GK.track('start', { mode: mode });
    render();
    GK.gameplayStart();
  }

  function setMsg(t) { msgEl.textContent = t; }

  function render() {
    var n = S.tubes.length;
    var narrow = boardEl.clientWidth < 520;
    var cols = narrow && n > 6 ? Math.ceil(n / 2) : n;
    boardEl.style.setProperty('--cols', cols);
    var html = '';
    for (var i = 0; i < n; i++) {
      var s = S.tubes[i];
      var lift = i === S.selected ? topRun(s) : 0;
      var cls = 'ms-basket' + (i === S.selected ? ' is-selected' : '') + (isFullSame(s) ? ' is-done' : '') +
        (S.hint && S.hint[0] === i ? ' is-hint-from' : '') + (S.hint && S.hint[1] === i ? ' is-hint' : '');
      html += '<div class="' + cls + '" role="button" tabindex="0" data-i="' + i + '" aria-label="' + T('かご', 'Basket ') + (i + 1) + T('：', ': ') +
        (s ? s.split('').map(function (c) { return NAMES[+c]; }).join(T('、', ', ')) : T('空', 'empty')) + '">';
      for (var k = 0; k < s.length; k++) {
        var isLift = k >= s.length - lift;
        var isNew = i === S.lastTo && k >= s.length - S.lastN;
        html += '<div class="ms-item' + (isLift ? ' is-lift' : '') + (isNew ? ' is-new' : '') + '">' + svgItem(+s[k]) + '</div>';
      }
      if (n <= 9 && !narrow) html += '<span class="ms-key">' + (i + 1) + '</span>';
      html += '</div>';
    }
    boardEl.innerHTML = html;
    $('moves').textContent = S.history.length;
    if (S.mode === 'daily') {
      $('hud-mid').innerHTML = T('最短 <strong>' + S.puzzle.par + '</strong> 手', 'Best possible <strong>' + S.puzzle.par + '</strong>');
      var st = GK.streak.get();
      $('hud-right').innerHTML = st ? T('🔥 <strong>' + st + '</strong> 日連続', '🔥 <strong>' + st + '</strong>-day streak') : '';
    } else {
      $('hud-mid').innerHTML = T('レベル', 'Level') + ' <strong>' + S.level + '</strong>';
      var b = GK.store.get('best:level', 0);
      $('hud-right').innerHTML = b ? T('最高', 'Best') + ' <strong>' + b + '</strong>' : '';
    }
    $('undo').disabled = !S.history.length || S.done;
    $('hint').disabled = S.done;
    S.lastTo = -1;
  }

  function shake(i) {
    var el = boardEl.querySelector('[data-i="' + i + '"]');
    if (!el) return;
    el.classList.remove('is-shake'); void el.offsetWidth; el.classList.add('is-shake');
  }

  function tap(i) {
    if (S.done || i < 0 || i >= S.tubes.length) return;
    var s = S.tubes[i];
    if (S.selected === -1) {
      if (!s || isFullSame(s)) { shake(i); return; }
      S.selected = i; GK.sfx.play('tap'); render(); return;
    }
    if (S.selected === i) { S.selected = -1; render(); return; }
    var n = canMove(S.tubes, S.selected, i);
    if (n) {
      S.history.push(S.tubes);
      S.tubes = applyMove(S.tubes, S.selected, i, n);
      S.lastTo = i; S.lastN = n;
      S.selected = -1; S.hint = null;
      GK.sfx.play(isFullSame(S.tubes[i]) ? 'pop' : 'move');
      render();
      if (isGoal(S.tubes)) win();
    } else if (s && !isFullSame(s)) {
      S.selected = i; GK.sfx.play('tap'); render(); // 別のかごを選び直し
    } else {
      GK.sfx.play('bad'); shake(i);
    }
  }

  function win() {
    S.done = true;
    GK.gameplayStop();
    GK.happy();
    var moves = S.history.length;
    render();
    GK.sfx.play('win');
    GK.track('clear', { mode: S.mode, moves: moves });
    if (S.mode === 'daily') {
      var par = S.puzzle.par, key = 'daily:' + S.date;
      var prev = GK.store.get(key, null);
      if (!prev || moves < prev.moves) GK.store.set(key, { moves: moves, par: par, hints: S.hintsUsed });
      var rec = GK.store.get(key);
      var streak = GK.streak.record();
      var sc = stars(rec.moves, par);
      var md = S.date.slice(5).replace('-', '/').replace(/^0/, '');
      var starStr = '★★★'.slice(0, sc) + '☆☆☆'.slice(0, 3 - sc);
      var body = document.createElement('div');
      body.innerHTML = '<div class="ms-result-stars">' + starStr + '</div>' +
        '<div>' + T(moves + '手（最短 ' + par + '手）', moves + ' moves (best possible ' + par + ')') +
        (S.hintsUsed ? T('・ヒント' + S.hintsUsed + '回', ' · ' + S.hintsUsed + ' hint(s)') : '') + '</div>' +
        (prev && prev.moves <= moves ? '<div>' + T('今日のベスト：' + prev.moves + '手', 'Today\'s best: ' + prev.moves + ' moves') + '</div>' : '') +
        '<div>' + T('🔥 ' + streak + '日連続', '🔥 ' + streak + '-day streak') + '</div>' +
        '<div style="margin-top:6px">' + (sc < 3 ? T('最短まであと ' + (rec.moves - par) + '手。もう一度挑戦できます', (rec.moves - par) + ' moves above the best. Try again!') : T('最短手数で完璧です！', 'Perfect — the fewest moves possible!')) + '</div>';
      GK.modal({
        title: T('今日の1問 クリア！', 'Daily puzzle solved!'),
        body: body,
        buttons: [
          { label: T('結果をシェア', 'Copy result'), primary: true, keepOpen: true, onClick: function () {
            GK.share(T('🍁もみじ仕分け ' + md + '\n' + starStr + ' ' + rec.moves + '手（最短' + par + '手）' + (rec.hints ? ' ヒント' + rec.hints : '') + '\n🔥' + streak + '日連続',
                       '🍁 Autumn Leaf Sort ' + md + '\n' + starStr + ' ' + rec.moves + ' moves (best ' + par + ')' + (rec.hints ? ' hints ' + rec.hints : '') + '\n🔥 ' + streak + '-day streak'));
          } },
          { label: T('もう一度', 'Play again'), onClick: function () { load('daily'); } },
          { label: T('練習モードへ', 'Practice mode'), onClick: function () { load('practice'); } }
        ]
      });
    } else {
      var cleared = S.level;
      var b = GK.best('level', cleared);
      S.level = cleared + 1;
      GK.store.set('level', S.level);
      GK.modal({
        title: T('レベル ' + cleared + ' クリア！', 'Level ' + cleared + ' cleared!'),
        body: T(moves + '手（最短 ' + S.puzzle.par + '手）', moves + ' moves (best possible ' + S.puzzle.par + ')') + (b.isNew && cleared > 1 ? T('\n最高レベル更新！', '\nNew best level!') : ''),
        buttons: [
          { label: T('次のレベルへ', 'Next level'), primary: true, onClick: function () {
            // 3レベルごとの区切りでだけ広告（設定がなければ即座に次へ）
            var p = cleared % 3 === 0 ? GK.adBreak('next', 'practice-level-' + cleared) : Promise.resolve();
            p.then(function () { load('practice'); });
          } },
          { label: T('シェア', 'Copy result'), onClick: function () {
            GK.share(T('🍁もみじ仕分け 練習レベル' + cleared + 'をクリア！', '🍁 Autumn Leaf Sort: cleared practice level ' + cleared + '!'));
          } }
        ]
      });
    }
  }

  function undo() {
    if (!S.history.length || S.done) return;
    S.tubes = S.history.pop();
    S.selected = -1; S.hint = null;
    GK.sfx.play('move');
    render();
  }

  function hint() {
    if (S.done) return;
    GK.adBreak('reward', 'hint').then(function (ok) {
      GK.gameplayStart(); // 広告の前に止めたプレイ状態を再開
      if (!ok) { GK.toast(T('広告を最後まで見るとヒントが出ます', 'Watch the whole ad to get a hint')); return; }
      var path = solve(S.tubes, 200000);
      if (!path || !path.length) { GK.toast(T('ここからは解けません。「1手もどす」で戻ってみよう', 'No solution from here. Try Undo.')); return; }
      S.hint = path[0]; S.selected = -1; S.hintsUsed++;
      setMsg(T('ヒント：オレンジの点線のかご → 緑の点線のかごへ', 'Hint: move from the orange dashed basket to the green one'));
      render();
    });
  }

  // ---------------- 入力 ----------------
  boardEl.addEventListener('click', function (e) {
    var el = e.target.closest('.ms-basket');
    if (el) tap(+el.dataset.i);
  });
  boardEl.addEventListener('keydown', function (e) {
    if ((e.key === 'Enter' || e.key === ' ') && e.target.classList.contains('ms-basket')) { e.preventDefault(); tap(+e.target.dataset.i); }
  });
  document.addEventListener('keydown', function (e) {
    if (document.querySelector('.gk-modal')) {
      if (e.key === 'Escape') { var m = document.querySelector('.gk-modal'); if (m) m.remove(); }
      return;
    }
    if (/^[1-9]$/.test(e.key)) tap(+e.key - 1);
    else if (e.key === 'Escape') { S.selected = -1; render(); }
    else if ((e.key === 'z' || e.key === 'Z') && (e.ctrlKey || e.metaKey)) { e.preventDefault(); undo(); }
  });
  $('undo').addEventListener('click', undo);
  $('restart').addEventListener('click', function () { load(S.mode); });
  $('hint').addEventListener('click', hint);
  $('tab-daily').addEventListener('click', function () { if (S.mode !== 'daily') load('daily'); });
  $('tab-practice').addEventListener('click', function () { if (S.mode !== 'practice') load('practice'); });
  var resizeTimer;
  window.addEventListener('resize', function () { clearTimeout(resizeTimer); resizeTimer = setTimeout(render, 120); });

  // ---------------- 自己テスト（smoke-test から実行） ----------------
  window.__GAME_TEST__ = {
    // 実際の入力処理（tap）を通して最短手順でクリアし、結果画面まで到達するか確認する
    autoplay: function () {
      load('daily');
      var path = solve(S.tubes);
      path.forEach(function (m) { tap(m[0]); tap(m[1]); });
      var ok = S.done && !!document.querySelector('.gk-modal') && S.history.length === S.puzzle.par;
      var rec = GK.store.get('daily:' + S.date, null);
      return { ok: ok && !!rec && rec.moves === S.puzzle.par, details: 'cleared daily in ' + S.history.length + ' moves (par ' + S.puzzle.par + ')' };
    },
    selfTest: function () {
      var t0 = Date.now(), checked = 0, maxPar = 0;
      function verify(p, label) {
        if (!p) throw new Error(label + ': 盤面を生成できない');
        if (isGoal(p.tubes)) throw new Error(label + ': 最初から完成している');
        var path = solve(p.tubes);
        if (!path || path.length !== p.par) throw new Error(label + ': 最短手数が一致しない');
        var t = p.tubes;
        path.forEach(function (m) {
          var n = canMove(t, m[0], m[1]);
          if (n !== m[2]) throw new Error(label + ': 解答手順に不正な手');
          t = applyMove(t, m[0], m[1], n);
        });
        if (!isGoal(t)) throw new Error(label + ': 解答手順で完成しない');
        var counts = {};
        p.tubes.join('').split('').forEach(function (c) { counts[c] = (counts[c] || 0) + 1; });
        Object.keys(counts).forEach(function (c) { if (counts[c] !== CAP) throw new Error(label + ': 種類の数が不正'); });
        checked++; maxPar = Math.max(maxPar, p.par);
      }
      var base = Date.parse(S.date + 'T00:00:00Z');
      for (var d = 0; d < 14; d++) {
        var ds = new Date(base + d * 86400000).toISOString().slice(0, 10);
        verify(dailyPuzzle(ds), 'daily ' + ds);
      }
      for (var lv = 1; lv <= 24; lv++) verify(practicePuzzle(lv), 'level ' + lv);
      // 同じ日付なら同じ盤面（全員共通の1問）
      if (dailyPuzzle(S.date).tubes.join() !== dailyPuzzle(S.date).tubes.join()) throw new Error('日替わり盤面が決定的でない');
      // 不正な手は拒否される
      if (canMove(['01', '1', ''], 0, 1) !== 1 || canMove(['01', '0', ''], 0, 1) !== 0) throw new Error('移動判定が不正');
      var ms = Date.now() - t0;
      if (ms > 4000) throw new Error('盤面生成が遅すぎる: ' + ms + 'ms');
      return { ok: true, details: checked + ' puzzles solvable, max par ' + maxPar + ', ' + ms + 'ms' };
    }
  };

  load('daily');
  GK.ready();
})();
