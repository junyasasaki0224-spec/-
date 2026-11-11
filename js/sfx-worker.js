// 観客の声の合成を裏のスレッドで行う (画面が固まらないように)
import { synthCrowd } from './crowd.js';
import { synthPhrase } from './voice.js';
self.onmessage = (e) => {
  const d = e.data;
  const chans = d.type === 'phrase' ? [synthPhrase(d.sr, d.seed, d.phrase, d.opt)] : d.seeds.map((s) => synthCrowd(d.sr, s, d.kind, d.dur));
  self.postMessage({ id: d.id, chans }, chans.map((c) => c.buffer));
};
