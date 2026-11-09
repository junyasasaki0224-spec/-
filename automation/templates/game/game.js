// __TITLE__ — ゲーム本体
// 外部ライブラリ・外部素材は使わない。グラフィックはCanvas/DOM/CSSで描き、音は GameKit.sfx を使う。
(function () {
  'use strict';
  var GK = window.GameKit;

  var state = { score: 0 };

  function reset() {
    state.score = 0;
    render();
  }

  function render() {
    document.getElementById('score').textContent = state.score;
  }

  document.getElementById('restart').addEventListener('click', reset);

  // ゲーム固有の自己テスト（smoke-test から呼ばれる）。例: 生成盤面が必ず解けるか検証する
  window.__GAME_TEST__ = {
    selfTest: function () { return { ok: true, details: 'TODO' }; }
  };

  reset();
  GK.ready();
})();
