// 実況: 画面下のテロップと、ブラウザの音声合成による読み上げ(対応していれば)。
export class Commentary {
  constructor(hud) {
    this.hud = hud; this.voice = true; this.volume = 0.8;
    this.synth = typeof window !== 'undefined' && 'speechSynthesis' in window ? window.speechSynthesis : null;
    this.jp = null; this.last = 0;
    if (this.synth) {
      const pick = () => { try { const v = this.synth.getVoices(); this.jp = v.find((x) => /^ja/i.test(x.lang)) || null; } catch (e) { /* 使えない環境 */ } };
      pick();
      try { this.synth.addEventListener('voiceschanged', pick); } catch (e) { /* 古いブラウザ */ }
    }
  }
  // priority: 2 = 進行中の読み上げを打ち切ってでも言う / 1 = 空いていれば言う / 0 = テロップだけ
  say(text, dur = 3, priority = 1, spoken = null) {
    this.hud.say(text, dur);
    if (!this.voice || !this.synth || priority === 0 || this.volume <= 0) return;
    try {
      if (this.synth.speaking || this.synth.pending) { if (priority < 2) return; this.synth.cancel(); }
      const u = new SpeechSynthesisUtterance(spoken || text.replace(/[！!]/g, '。'));
      u.lang = 'ja-JP'; if (this.jp) u.voice = this.jp;
      u.rate = 1.25; u.pitch = 1.05; u.volume = Math.min(1, this.volume);
      this.synth.speak(u);
    } catch (e) { /* 読み上げ不可 */ }
  }
  stop() { try { if (this.synth) this.synth.cancel(); } catch (e) { /* noop */ } }
}
