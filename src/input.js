// 入力: キーボード / タッチ(スライド式ハンドル + ボタン) / ゲームパッド
export class Input {
  constructor() {
    this.keys = new Set();
    this.touch = { steer: 0, gas: false, brake: false };
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
    for (const [id, k] of [['t-gas', 'gas'], ['t-brake', 'brake']]) {
      const el = document.getElementById(id);
      if (!el) continue;
      const on = (e) => { e.preventDefault(); this.touch[k] = true; el.classList.add('on'); };
      const off = (e) => { e.preventDefault(); this.touch[k] = false; el.classList.remove('on'); };
      el.addEventListener('pointerdown', on); el.addEventListener('pointerup', off);
      el.addEventListener('pointercancel', off); el.addEventListener('pointerleave', off);
      el.addEventListener('contextmenu', (e) => e.preventDefault());
    }
    // ハンドル: パッド上を左右にスライド。離すと中立に戻る
    const pad = document.getElementById('t-steer'), knob = document.getElementById('t-knob');
    if (pad) {
      let id = null;
      const set = (e) => {
        const r = pad.getBoundingClientRect();
        const v = Math.max(-1, Math.min(1, (e.clientX - (r.left + r.width / 2)) / (r.width / 2 - 26)));
        this.touch.steer = -Math.sign(v) * Math.pow(Math.abs(v), 0.8);       // 右へ倒すと右旋回(steer は左が正)
        if (knob) knob.style.transform = `translateX(${v * (r.width / 2 - 34)}px)`;
      };
      const end = () => { id = null; this.touch.steer = 0; if (knob) knob.style.transform = 'translateX(0px)'; pad.classList.remove('on'); };
      pad.addEventListener('pointerdown', (e) => { e.preventDefault(); id = e.pointerId; try { pad.setPointerCapture(id); } catch (err) { /* noop */ } pad.classList.add('on'); set(e); });
      pad.addEventListener('pointermove', (e) => { if (e.pointerId === id) { e.preventDefault(); set(e); } });
      pad.addEventListener('pointerup', end); pad.addEventListener('pointercancel', end);
      pad.addEventListener('contextmenu', (e) => e.preventDefault());
      this._steerEnd = end;
    }
  }

  clear() { this.keys.clear(); this.touch.gas = this.touch.brake = false; if (this._steerEnd) this._steerEnd(); }

  get() {
    const k = this.keys, t = this.touch, s = this.state;
    let steer = t.steer, throttle = 0, brake = 0;
    if (k.has('ArrowLeft') || k.has('KeyA')) steer += 1;
    if (k.has('ArrowRight') || k.has('KeyD')) steer -= 1;
    if (k.has('ArrowUp') || k.has('KeyW') || k.has('Space') || t.gas) throttle = 1;
    if (k.has('ArrowDown') || k.has('KeyS') || t.brake) { brake = 1; throttle = 0; }
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
