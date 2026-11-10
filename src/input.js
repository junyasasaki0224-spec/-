// 入力: キーボード / タッチ / ゲームパッド
export class Input {
  constructor() {
    this.keys = new Set();
    this.touch = { left: false, right: false, gas: false, brake: false };
    this.onKey = null;
    this.state = { steer: 0, throttle: 0, brake: 0 };
    window.addEventListener('keydown', (e) => {
      if (['ArrowUp', 'ArrowDown', 'ArrowLeft', 'ArrowRight', 'Space'].includes(e.code)) e.preventDefault();
      if (!e.repeat && this.onKey) this.onKey(e.code);
      this.keys.add(e.code);
    });
    window.addEventListener('keyup', (e) => this.keys.delete(e.code));
    window.addEventListener('blur', () => { this.keys.clear(); for (const k in this.touch) this.touch[k] = false; });
    for (const [id, k] of [['t-left', 'left'], ['t-right', 'right'], ['t-gas', 'gas'], ['t-brake', 'brake']]) {
      const el = document.getElementById(id);
      if (!el) continue;
      const on = (e) => { e.preventDefault(); this.touch[k] = true; el.classList.add('on'); };
      const off = (e) => { e.preventDefault(); this.touch[k] = false; el.classList.remove('on'); };
      el.addEventListener('pointerdown', on); el.addEventListener('pointerup', off);
      el.addEventListener('pointercancel', off); el.addEventListener('pointerleave', off);
      el.addEventListener('contextmenu', (e) => e.preventDefault());
    }
  }

  get() {
    const k = this.keys, t = this.touch, s = this.state;
    let steer = 0, throttle = 0, brake = 0;
    if (k.has('ArrowLeft') || k.has('KeyA') || t.left) steer += 1;
    if (k.has('ArrowRight') || k.has('KeyD') || t.right) steer -= 1;
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
    s.steer = steer; s.throttle = throttle; s.brake = brake;
    return s;
  }
}
