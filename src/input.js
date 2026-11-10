// 入力: キーボード / タッチ(ハンドルレバー + スロットルレバー) / ゲームパッド
export class Input {
  constructor() {
    this.keys = new Set();
    this.touch = { steer: 0, throttle: 0 };
    this.onKey = null;
    this.state = { steer: 0, throttle: 0, brake: 0 };
    window.addEventListener('keydown', (e) => {
      if (e.target && /INPUT|SELECT|TEXTAREA/.test(e.target.tagName)) return;
      if (['ArrowUp', 'ArrowDown', 'ArrowLeft', 'ArrowRight', 'Space'].includes(e.code)) e.preventDefault();
      if (!e.repeat && this.onKey) this.onKey(e.code);
      this.keys.add(e.code);
    });
    window.addEventListener('keyup', (e) => this.keys.delete(e.code));
    window.addEventListener('blur', () => this.clear());
    // ---- レバー式のタッチ操作 ----
    // ハンドルレバー: 支点から指への角度ぶん倒れる。離すと中立へ戻る
    const sp = document.getElementById('lv-steer'), arm = document.getElementById('lv-steer-arm');
    const MAX = 42 * Math.PI / 180;
    if (sp) {
      let id = null;
      const set = (e) => {
        const r = sp.getBoundingClientRect();
        const dx = e.clientX - (r.left + r.width / 2), dy = Math.max(r.height * 0.3, r.bottom - 30 - e.clientY);
        const v = Math.max(-1, Math.min(1, Math.atan2(dx, dy) / MAX));
        this.touch.steer = -v;                       // 右へ倒すと右旋回(steer は左が正)
        arm.style.transform = `rotate(${v * 42}deg)`;
      };
      const end = () => { id = null; this.touch.steer = 0; arm.style.transform = 'rotate(0deg)'; sp.classList.remove('on'); };
      sp.addEventListener('pointerdown', (e) => { e.preventDefault(); id = e.pointerId; try { sp.setPointerCapture(id); } catch (err) { /* noop */ } sp.classList.add('on'); set(e); });
      sp.addEventListener('pointermove', (e) => { if (e.pointerId === id) { e.preventDefault(); set(e); } });
      sp.addEventListener('pointerup', end); sp.addEventListener('pointercancel', end);
      sp.addEventListener('contextmenu', (e) => e.preventDefault());
      this._steerEnd = end;
    }
    // スロットルレバー: 押し上げるほど開き、離してもその位置で止まる(微調整できる)。
    // つまみを掴んで動かすと指の移動ぶんだけ動き、つまみ以外を押すとその高さへ一気に動く
    const tp = document.getElementById('lv-thr'), grip = document.getElementById('lv-thr-grip'), fill = document.getElementById('lv-thr-fill');
    this.holdThrottle = true;
    if (tp) {
      let id = null, off = 0;
      const travel = () => parseFloat(getComputedStyle(tp).getPropertyValue('--travel')) || 100;
      const show = (v) => { const t = travel(); grip.style.transform = `translateY(${-v * t}px)`; fill.style.height = `${8 + v * t}px`; };
      const raw = (e) => (tp.getBoundingClientRect().bottom - 34 - e.clientY) / travel();
      const set = (e) => {
        let v = raw(e) - off;
        v = v > 0.97 ? 1 : v < 0.03 ? 0 : v;
        this.touch.throttle = v; show(v);
      };
      const end = () => { id = null; tp.classList.remove('on'); if (!this.holdThrottle) { this.touch.throttle = 0; show(0); } };
      tp.addEventListener('pointerdown', (e) => {
        e.preventDefault(); id = e.pointerId;
        try { tp.setPointerCapture(id); } catch (err) { /* noop */ }
        tp.classList.add('on');
        const d = raw(e) - this.touch.throttle;
        off = Math.abs(d) < 0.3 ? d : 0;           // つまみの近くなら掴んだ位置を保つ
        set(e);
      });
      tp.addEventListener('pointermove', (e) => { if (e.pointerId === id) { e.preventDefault(); set(e); } });
      tp.addEventListener('pointerup', end); tp.addEventListener('pointercancel', end);
      tp.addEventListener('contextmenu', (e) => e.preventDefault());
      this._thrReset = () => { id = null; tp.classList.remove('on'); this.touch.throttle = 0; show(0); };
    }
  }

  // resetThrottle: スロットルレバーも閉じる(レース開始時)。それ以外は「止まる」設定ならレバー位置を保つ
  clear(resetThrottle = false) { this.keys.clear(); if (this._steerEnd) this._steerEnd(); if (this._thrReset && (resetThrottle || !this.holdThrottle)) this._thrReset(); }

  get() {
    const k = this.keys, t = this.touch, s = this.state;
    let steer = t.steer, throttle = t.throttle, brake = 0;
    if (k.has('ArrowLeft') || k.has('KeyA')) steer += 1;
    if (k.has('ArrowRight') || k.has('KeyD')) steer -= 1;
    if (k.has('ArrowUp') || k.has('KeyW') || k.has('Space')) throttle = 1;
    if (k.has('ArrowDown') || k.has('KeyS')) { brake = 1; throttle = 0; }
    const pads = navigator.getGamepads ? navigator.getGamepads() : [];
    for (const p of pads) {
      if (!p || !p.connected) continue;
      const ax = p.axes[0] || 0;
      if (Math.abs(ax) > 0.12) steer = -ax;
      const rt = p.buttons[7] ? p.buttons[7].value : 0, lt = p.buttons[6] ? p.buttons[6].value : 0;
      if (rt > 0.05 || (p.buttons[0] && p.buttons[0].pressed)) throttle = Math.max(throttle, rt || 1);
      if (lt > 0.05 || (p.buttons[2] && p.buttons[2].pressed)) { brake = Math.max(brake, lt || 1); throttle = 0; }
      break;
    }
    s.steer = Math.max(-1, Math.min(1, steer)); s.throttle = throttle; s.brake = brake;
    return s;
  }
}
