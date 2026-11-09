// __TITLE__ — ゲーム本体
// 外部ライブラリ・外部素材は使わない。グラフィックはCanvas/DOM/CSSで描き、音は GameKit.sfx を使う。
// 文字は必ず日英対応: JSでは T('日本語', 'English')、HTMLでは data-en="English"。
(function () {
  'use strict';
  var GK = window.GameKit;
  var T = GK.t;

  var state = { score: 0, over: false };

  function reset() {
    state.score = 0;
    state.over = false;
    render();
    GK.gameplayStart(); // 操作できる状態になった
  }

  function render() {
    document.getElementById('score').textContent = state.score;
  }

  function gameOver() {
    state.over = true;
    GK.gameplayStop(); // 結果画面に入る前に必ず止める
    var b = GK.best('score', state.score);
    if (b.isNew) GK.happy();
    GK.modal({
      title: T('結果', 'Result'),
      body: T('スコア ' + state.score, 'Score ' + state.score),
      buttons: [
        { label: T('もう一回', 'Play again'), primary: true, onClick: function () {
          GK.adBreak('next', 'replay').then(reset); // 区切りでだけ広告
        } },
        { label: T('結果をシェア', 'Copy result'), keepOpen: true, onClick: function () {
          GK.share(T('__TITLE__ スコア ' + state.score, 'TODO score ' + state.score));
        } }
      ]
    });
  }

  document.getElementById('restart').addEventListener('click', reset);

  // smoke-test / portal-test から呼ばれる（どちらも実装必須）
  window.__GAME_TEST__ = {
    // ゲーム固有ロジックの検証（例: 生成した盤面が必ず解ける）
    selfTest: function () { return { ok: true, details: 'TODO' }; },
    // 実際の入力処理を通して最後まで遊び、結果画面に到達することを確認
    autoplay: function () { gameOver(); return { ok: !!document.querySelector('.gk-modal'), details: 'TODO' }; }
  };

  reset();
  GK.ready();
})();
