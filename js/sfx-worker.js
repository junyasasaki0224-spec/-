// 観客の声の合成を裏のスレッドで行う (画面が固まらないように)
import { synthCrowd } from './crowd.js';
self.onmessage = (e) => {
  const { id, sr, kind, seeds, dur } = e.data;
  const chans = seeds.map((s) => synthCrowd(sr, s, kind, dur));
  self.postMessage({ id, chans }, chans.map((c) => c.buffer));
};
