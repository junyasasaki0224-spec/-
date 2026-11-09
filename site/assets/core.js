/*
 * GameKit — 全ゲーム共通ランタイム（依存なし）
 *
 * 各ゲームはこのAPIだけを使って、保存・共有・広告・効果音・計測を行う。
 * 広告や計測の設定は site.config.json → (build) → assets/config.js から読む。
 * 設定が空なら全部 no-op で動くので、開発中も本番前もゲームは壊れない。
 */
(function () {
  'use strict';

  var CONFIG = window.SITE_CONFIG || {};
  var slug = document.documentElement.getAttribute('data-slug') || 'site';

  // ---------- 配信先と言語 ----------
  // portal: 大手サイト向けビルドで設定される（'crazygames' | 'poki'）。自サイトでは空。
  var PORTAL = CONFIG.portal || '';
  var lang = (function () {
    try {
      var q = new URLSearchParams(location.search).get('lang');
      if (q === 'en' || q === 'ja') return q;
    } catch (e) {}
    return CONFIG.lang === 'en' ? 'en' : 'ja';
  })();
  document.documentElement.setAttribute('lang', lang);
  /** 表示文言の切り替え。GameKit.t('日本語', 'English') */
  function t(ja, en) { return lang === 'en' && en !== undefined ? en : ja; }
  /** HTML側の data-en="..."（文字）/ data-en-label="..."（aria-label）を英語に差し替える */
  function applyI18n(root) {
    if (lang !== 'en') return;
    (root || document).querySelectorAll('[data-en]').forEach(function (el) { el.textContent = el.getAttribute('data-en'); });
    (root || document).querySelectorAll('[data-en-label]').forEach(function (el) { el.setAttribute('aria-label', el.getAttribute('data-en-label')); });
  }

  // ---------- storage（localStorage が使えない環境でも落ちない） ----------
  var memory = {};
  function key(k) { return 'gk:' + slug + ':' + k; }
  var store = {
    get: function (k, fallback) {
      try {
        var raw = window.localStorage.getItem(key(k));
        return raw === null ? fallback : JSON.parse(raw);
      } catch (e) {
        return key(k) in memory ? memory[key(k)] : fallback;
      }
    },
    set: function (k, v) {
      memory[key(k)] = v;
      try { window.localStorage.setItem(key(k), JSON.stringify(v)); } catch (e) { /* private mode etc. */ }
    }
  };

  // ---------- 日付・乱数（「今日の1問」は全員同じ盤面になる） ----------
  function today() {
    // 日本時間の日付。日替わり問題は JST 0:00 で切り替わる
    var d = new Date(Date.now() + 9 * 3600 * 1000);
    return d.toISOString().slice(0, 10);
  }
  function hashSeed(str) {
    var h = 1779033703 ^ str.length;
    for (var i = 0; i < str.length; i++) {
      h = Math.imul(h ^ str.charCodeAt(i), 3432918353);
      h = (h << 13) | (h >>> 19);
    }
    h = Math.imul(h ^ (h >>> 16), 2246822507);
    h = Math.imul(h ^ (h >>> 13), 3266489909);
    return (h ^= h >>> 16) >>> 0;
  }
  function rng(seed) {
    var a = typeof seed === 'string' ? hashSeed(seed) : seed >>> 0;
    var r = function () { // mulberry32
      a |= 0; a = (a + 0x6D2B79F5) | 0;
      var t = Math.imul(a ^ (a >>> 15), 1 | a);
      t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
      return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
    };
    r.int = function (n) { return Math.floor(r() * n); };
    r.pick = function (arr) { return arr[r.int(arr.length)]; };
    r.shuffle = function (arr) {
      for (var i = arr.length - 1; i > 0; i--) { var j = r.int(i + 1); var t = arr[i]; arr[i] = arr[j]; arr[j] = t; }
      return arr;
    };
    return r;
  }

  // ---------- 自己ベスト・連続プレイ日数 ----------
  function best(name, value, higherIsBetter) {
    var hib = higherIsBetter !== false;
    var cur = store.get('best:' + name, null);
    var isNew = cur === null || (hib ? value > cur : value < cur);
    if (isNew) store.set('best:' + name, value);
    return { best: isNew ? value : cur, isNew: isNew };
  }
  var streak = {
    record: function () {
      var t = today();
      var s = store.get('streak', { last: null, count: 0 });
      if (s.last === t) return s.count;
      var y = new Date(Date.parse(t) - 86400000).toISOString().slice(0, 10);
      s.count = s.last === y ? s.count + 1 : 1;
      s.last = t;
      store.set('streak', s);
      return s.count;
    },
    get: function () { return store.get('streak', { count: 0 }).count; }
  };

  // ---------- 共有（自サイト: Web Share → X → コピー / 大手サイト: コピーのみ） ----------
  function copyText(text) {
    var ok = function () { toast(t('結果をコピーしました', 'Result copied to clipboard')); };
    var ng = function () { toast(t('コピーできませんでした', 'Could not copy')); };
    try {
      if (navigator.clipboard) return navigator.clipboard.writeText(text).then(ok, ng);
    } catch (e) {}
    ng();
    return Promise.resolve();
  }
  function share(text) {
    track('share');
    // 大手サイトは外部リンク・外部共有を嫌うため、結果テキストのコピーだけにする
    if (PORTAL) return copyText(text);
    var url = location.href.split('#')[0].split('?')[0];
    var full = text + '\n' + url;
    if (navigator.share) {
      return navigator.share({ text: text, url: url }).catch(function () {});
    }
    var intent = 'https://twitter.com/intent/tweet?text=' + encodeURIComponent(full);
    var w = null;
    try { w = window.open(intent, '_blank', 'noopener'); } catch (e) {}
    if (!w) return copyText(full);
    return Promise.resolve();
  }

  // ---------- 効果音（WebAudioで合成。外部音源ファイルは使わない） ----------
  var audioCtx = null;
  var muted = store.get('muted', false);
  var SFX = {
    tap:  [[660, 0.05, 'square', 0.04]],
    pop:  [[520, 0.06, 'triangle', 0.08], [780, 0.06, 'triangle', 0.06]],
    move: [[440, 0.04, 'sine', 0.06]],
    bad:  [[180, 0.12, 'sawtooth', 0.05]],
    win:  [[523, 0.1, 'triangle', 0.08], [659, 0.1, 'triangle', 0.08], [784, 0.18, 'triangle', 0.08]],
    lose: [[392, 0.12, 'sine', 0.07], [311, 0.2, 'sine', 0.07]]
  };
  function play(name) {
    if (muted || adPlaying) return;
    var seq = SFX[name];
    if (!seq) return;
    try {
      audioCtx = audioCtx || new (window.AudioContext || window.webkitAudioContext)();
      var t = audioCtx.currentTime;
      seq.forEach(function (n) {
        var o = audioCtx.createOscillator();
        var g = audioCtx.createGain();
        o.type = n[2]; o.frequency.value = n[0];
        g.gain.setValueAtTime(n[3], t);
        g.gain.exponentialRampToValueAtTime(0.0001, t + n[1]);
        o.connect(g); g.connect(audioCtx.destination);
        o.start(t); o.stop(t + n[1]);
        t += n[1] * 0.9;
      });
    } catch (e) { /* audio unavailable */ }
  }

  // ---------- 広告 ----------
  // 自サイト: AdSense の H5 Games Ads（adBreak）
  // 大手サイト: 各サイトのSDK（CrazyGames SDK v3 / Poki SDK v2）。SDKが読めなければ何もしない。
  var adsReady = false;
  var adPlaying = false;
  var ads = PORTAL ? {} : (CONFIG.adsense || {});
  var cg = function () { return window.CrazyGames && window.CrazyGames.SDK; };
  var poki = function () { return window.PokiSDK; };
  var sdkReady = Promise.resolve().then(function () {
    if (PORTAL === 'crazygames' && cg()) return cg().init();
    if (PORTAL === 'poki' && poki()) return poki().init();
  }).catch(function () { /* SDKの初期化失敗時も遊べるようにする */ });
  if (ads.client && /^ca-pub-\d+$/.test(ads.client)) {
    var s = document.createElement('script');
    s.async = true;
    s.src = 'https://pagead2.googlesyndication.com/pagead/js/adsbygoogle.js?client=' + ads.client;
    s.crossOrigin = 'anonymous';
    if (ads.h5GamesAds) {
      s.setAttribute('data-ad-client', ads.client);
      if (ads.testMode) s.setAttribute('data-adbreak-test', 'on');
    }
    document.head.appendChild(s);
    window.adsbygoogle = window.adsbygoogle || [];
    if (ads.h5GamesAds) {
      window.adBreak = window.adConfig = function (o) { window.adsbygoogle.push(o); };
      window.adConfig({ preloadAdBreaks: 'on', sound: 'on' });
      adsReady = true;
    }
  }
  /**
   * ラウンド間などの「自然な区切り」でだけ呼ぶ。操作中には絶対に呼ばない。
   * type: 'start' | 'next' | 'pause' | 'reward'
   * 戻り値の Promise は広告が終わった（または出なかった）ときに解決する。
   * reward の場合は視聴完了なら true で解決する。
   */
  function adBreak(type, name) {
    track('adbreak', { type: type, name: name });
    var isReward = type === 'reward';
    var none = isReward ? false : undefined;
    if (PORTAL && type === 'start') return Promise.resolve(); // 開始前広告は大手サイト側が出す
    if (PORTAL && playing) gameplayStop();
    if (PORTAL === 'crazygames' && cg()) {
      return sdkReady.then(function () {
        return new Promise(function (resolve) {
          var done = false;
          var fin = function (v) { if (!done) { done = true; adPlaying = false; resolve(v); } };
          try {
            cg().ad.requestAd(isReward ? 'rewarded' : 'midgame', {
              adStarted: function () { adPlaying = true; },
              adFinished: function () { fin(isReward ? true : undefined); },
              adError: function () { fin(none); }
            });
          } catch (e) { fin(none); }
        });
      });
    }
    if (PORTAL === 'poki' && poki()) {
      return sdkReady.then(function () {
        var p = isReward ? poki().rewardedBreak(function () { adPlaying = true; })
                         : poki().commercialBreak(function () { adPlaying = true; });
        return p.then(function (ok) { adPlaying = false; return isReward ? !!ok : undefined; });
      }).catch(function () { adPlaying = false; return none; });
    }
    if (PORTAL) return Promise.resolve(isReward ? true : undefined); // SDKなし（テスト環境など）
    if (!adsReady) return Promise.resolve(isReward ? true : undefined);
    return new Promise(function (resolve) {
      var rewarded = false;
      var opts = {
        type: type,
        name: name || type,
        beforeAd: function () { adPlaying = true; },
        afterAd: function () { adPlaying = false; },
        adBreakDone: function () { adPlaying = false; resolve(type === 'reward' ? rewarded : undefined); }
      };
      if (type === 'reward') {
        opts.beforeReward = function (showAdFn) { showAdFn(); };
        opts.adViewed = function () { rewarded = true; };
        opts.adDismissed = function () { rewarded = false; };
      }
      window.adBreak(opts);
    });
  }
  function fillDisplaySlots() {
    if (!ads.client) return;
    var slots = ads.displaySlots || {};
    document.querySelectorAll('[data-ad-slot-name]').forEach(function (el) {
      var id = slots[el.getAttribute('data-ad-slot-name')];
      if (!id) return;
      var ins = document.createElement('ins');
      ins.className = 'adsbygoogle';
      ins.style.display = 'block';
      ins.setAttribute('data-ad-client', ads.client);
      ins.setAttribute('data-ad-slot', id);
      ins.setAttribute('data-ad-format', 'auto');
      ins.setAttribute('data-full-width-responsive', 'true');
      el.appendChild(ins);
      el.classList.add('is-filled');
      try { (window.adsbygoogle = window.adsbygoogle || []).push({}); } catch (e) {}
    });
  }

  // ---------- プレイ中の通知（大手サイトの必須要件。自サイトでは何もしない） ----------
  var playing = false;
  /** 実際に操作できる状態になったら呼ぶ（レベル開始時など） */
  function gameplayStart() {
    if (playing) return;
    playing = true;
    try {
      if (PORTAL === 'crazygames' && cg()) cg().game.gameplayStart();
      if (PORTAL === 'poki' && poki()) poki().gameplayStart();
    } catch (e) {}
  }
  /** 結果画面・メニュー・ポーズに入ったら呼ぶ */
  function gameplayStop() {
    if (!playing) return;
    playing = false;
    try {
      if (PORTAL === 'crazygames' && cg()) cg().game.gameplayStop();
      if (PORTAL === 'poki' && poki()) poki().gameplayStop();
    } catch (e) {}
  }
  /** クリアや記録更新など、盛り上がった瞬間に呼ぶ */
  function happy() {
    try { if (PORTAL === 'crazygames' && cg() && cg().game.happytime) cg().game.happytime(); } catch (e) {}
  }

  // ---------- 計測（Cookie不要のGoatCounterを想定。未設定なら no-op） ----------
  var an = PORTAL ? {} : (CONFIG.analytics || {});
  if (an.goatcounterCode && /^[a-z0-9-]+$/.test(an.goatcounterCode)) {
    var g = document.createElement('script');
    g.async = true;
    g.src = 'https://gc.zgo.at/count.js';
    g.setAttribute('data-goatcounter', 'https://' + an.goatcounterCode + '.goatcounter.com/count');
    document.head.appendChild(g);
  }
  function track(event, props) {
    try {
      if (window.goatcounter && window.goatcounter.count) {
        window.goatcounter.count({ path: slug + '/' + event, title: event, event: true });
      }
      if (window.__GK_EVENTS__) window.__GK_EVENTS__.push({ event: event, props: props || {} });
    } catch (e) {}
  }

  // ---------- UI部品 ----------
  function toast(msg, ms) {
    var el = document.createElement('div');
    el.className = 'gk-toast';
    el.textContent = msg;
    document.body.appendChild(el);
    requestAnimationFrame(function () { el.classList.add('is-on'); });
    setTimeout(function () { el.classList.remove('is-on'); setTimeout(function () { el.remove(); }, 300); }, ms || 1800);
  }
  /** 結果画面などのモーダル。buttons: [{label, primary, onClick}] */
  function modal(opts) {
    var wrap = document.createElement('div');
    wrap.className = 'gk-modal';
    wrap.setAttribute('role', 'dialog');
    wrap.setAttribute('aria-modal', 'true');
    var box = document.createElement('div');
    box.className = 'gk-modal__box';
    if (opts.title) { var h = document.createElement('h2'); h.textContent = opts.title; box.appendChild(h); }
    if (opts.body) {
      var b = document.createElement('div');
      b.className = 'gk-modal__body';
      if (typeof opts.body === 'string') b.textContent = opts.body; else b.appendChild(opts.body);
      box.appendChild(b);
    }
    var row = document.createElement('div');
    row.className = 'gk-modal__actions';
    (opts.buttons || [{ label: t('とじる', 'Close'), primary: true }]).forEach(function (bt) {
      var btn = document.createElement('button');
      btn.type = 'button';
      btn.className = 'gk-btn' + (bt.primary ? ' gk-btn--primary' : '');
      btn.textContent = bt.label;
      btn.addEventListener('click', function () {
        if (bt.keepOpen !== true) close();
        if (bt.onClick) bt.onClick();
      });
      row.appendChild(btn);
    });
    box.appendChild(row);
    wrap.appendChild(box);
    document.body.appendChild(wrap);
    var first = row.querySelector('.gk-btn--primary') || row.querySelector('button');
    if (first) first.focus();
    function close() { wrap.remove(); }
    return { close: close, el: wrap };
  }

  function mountHeader() {
    var title = (document.querySelector('meta[name="gk-title"]') || {}).content || document.title;
    var bar = document.createElement('header');
    bar.className = 'gk-bar';
    var home = document.createElement('a');
    home.className = 'gk-bar__home';
    home.href = slug === 'site' ? './' : '../../';
    home.textContent = '← ' + (CONFIG.siteName || 'ゲーム一覧');
    var h1 = document.createElement('h1');
    h1.className = 'gk-bar__title';
    h1.textContent = title;
    var mute = document.createElement('button');
    mute.type = 'button';
    mute.className = 'gk-bar__mute';
    function paint() { mute.textContent = muted ? '🔇' : '🔊'; mute.setAttribute('aria-label', muted ? '音を出す' : '消音'); }
    paint();
    mute.addEventListener('click', function () { muted = !muted; store.set('muted', muted); paint(); });
    bar.appendChild(home); bar.appendChild(h1); bar.appendChild(mute);
    document.body.insertBefore(bar, document.body.firstChild);
  }

  function ready() {
    window.__GAME_READY__ = true;
    track('ready');
    sdkReady.then(function () {
      try {
        if (PORTAL === 'poki' && poki()) poki().gameLoadingFinished();
        if (PORTAL === 'crazygames' && cg() && cg().game.loadingStop) cg().game.loadingStop();
      } catch (e) {}
    });
  }

  window.GameKit = {
    config: CONFIG,
    slug: slug,
    lang: lang,
    portal: PORTAL,
    t: t,
    gameplayStart: gameplayStart,
    gameplayStop: gameplayStop,
    happy: happy,
    store: store,
    today: today,
    rng: rng,
    hashSeed: hashSeed,
    best: best,
    streak: streak,
    share: share,
    sfx: { play: play },
    adBreak: adBreak,
    track: track,
    toast: toast,
    modal: modal,
    ready: ready
  };

  // core.js は body の末尾で読み込むので、静的な文言はゲーム本体より先に差し替えておく
  var i18nDone = false;
  if (document.body) { applyI18n(); i18nDone = true; }
  function boot() {
    if (!i18nDone) applyI18n();
    if (slug !== 'site' && !PORTAL) mountHeader();
    if (!PORTAL) fillDisplaySlots();
  }
  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', boot); else boot();
})();
