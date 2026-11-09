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

  // ---------- 共有（Web Share → X → クリップボードの順） ----------
  function share(text) {
    var url = location.href.split('#')[0].split('?')[0];
    var full = text + '\n' + url;
    track('share');
    if (navigator.share) {
      return navigator.share({ text: text, url: url }).catch(function () {});
    }
    var intent = 'https://twitter.com/intent/tweet?text=' + encodeURIComponent(full);
    var w = window.open(intent, '_blank', 'noopener');
    if (!w && navigator.clipboard) {
      return navigator.clipboard.writeText(full).then(function () { toast('結果をコピーしました'); });
    }
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

  // ---------- 広告（H5 Games Ads の adBreak。未設定なら即スキップ） ----------
  var adsReady = false;
  var adPlaying = false;
  var ads = CONFIG.adsense || {};
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
    if (!adsReady) return Promise.resolve(type === 'reward' ? true : undefined);
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

  // ---------- 計測（Cookie不要のGoatCounterを想定。未設定なら no-op） ----------
  var an = CONFIG.analytics || {};
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
    (opts.buttons || [{ label: 'とじる', primary: true }]).forEach(function (bt) {
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
  }

  window.GameKit = {
    config: CONFIG,
    slug: slug,
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

  function boot() {
    if (slug !== 'site') mountHeader();
    fillDisplaySlots();
  }
  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', boot); else boot();
})();
