// ============================================================
//  コース形状: 2本の直線と2つの半円コーナーからなる周回 + 高低差プロファイル
//  u    : 4コーナー出口(ホームストレッチ入口)を0とする周回距離
//  lapS : ゴール板を0とする周回距離 (進行方向)
//  s    : スタートからの走破距離 (内ラチ沿い基準)
//  d    : 内ラチからの横位置[m] (外へ正)
// ============================================================

export class Track {
  constructor(course, dist) {
    this.course = course;
    this.t = course.dir === 'R' ? 1 : -1; // 右回り:+1 左回り:-1 (内馬場がz=t側)
    this.lap = course.lap;
    this.straight = course.straight;
    this.L = course.straight + course.runoff;
    this.R = (this.lap - 2 * this.L) / (2 * Math.PI);
    this.half = this.lap / 2;
    this.W = course.width;
    this.D = dist;

    // 高低差テーブル (1m刻み)
    const n = Math.ceil(this.lap) + 2;
    this.ys = new Float32Array(n);
    this.sl = new Float32Array(n);
    const e = course.elev;
    for (let i = 0; i < n; i++) {
      const s = Math.min(i, this.lap);
      let k = 0;
      while (k < e.length - 2 && s > e[k + 1][0]) k++;
      const a = e[k], b = e[k + 1];
      let f = (s - a[0]) / Math.max(1e-6, b[0] - a[0]);
      f = f < 0 ? 0 : f > 1 ? 1 : f;
      f = f * f * (3 - 2 * f);
      this.ys[i] = a[1] + (b[1] - a[1]) * f;
    }
    for (let i = 0; i < n; i++) {
      const i0 = Math.max(0, i - 2), i1 = Math.min(n - 1, i + 2);
      this.sl[i] = (this.ys[i1] - this.ys[i0]) / (i1 - i0);
    }

    // スタート位置。コーナー途中になる距離は直線を延長したポケット(引き込み線)から発走
    let u0 = (((this.straight - dist) % this.lap) + this.lap) % this.lap;
    this.chute = 0; this.joinU = 0;
    if (u0 >= this.L && u0 < this.half) { this.chute = this.half - u0 + 0.01; this.joinU = this.half; }
    else if (u0 >= this.half + this.L) { this.chute = this.lap - u0 + 0.01; this.joinU = 0; }
    this.u0 = this.chute > 0 ? this.joinU - this.chute : u0;
    this.straightStartS = dist - this.straight; // 最後の直線入口
    this._tmp = {};
  }

  elevAt(lapS) {
    let s = lapS % this.lap; if (s < 0) s += this.lap;
    const i = s | 0, f = s - i;
    return this.ys[i] + (this.ys[i + 1] - this.ys[i]) * f;
  }
  slopeAt(lapS) {
    let s = lapS % this.lap; if (s < 0) s += this.lap;
    return this.sl[s | 0];
  }

  // 周回座標 → ワールド座標
  point(u, d, o) {
    o = o || {};
    const t = this.t, L = this.L, R = this.R;
    u = u % this.lap; if (u < 0) u += this.lap;
    let x, z, hx, hz, nx, nz, k = 0;
    if (u < L) { x = u; z = 0; hx = 1; hz = 0; nx = 0; nz = -t; }
    else if (u < this.half) {
      const th = (u - L) / R, s = Math.sin(th), c = Math.cos(th);
      x = L + R * s; z = t * R - t * R * c; hx = c; hz = t * s; nx = s; nz = -t * c; k = 1 / R;
    } else if (u < this.half + L) { x = L - (u - this.half); z = 2 * t * R; hx = -1; hz = 0; nx = 0; nz = t; }
    else {
      const th = (u - this.half - L) / R, s = Math.sin(th), c = Math.cos(th);
      x = -R * s; z = t * R + t * R * c; hx = -c; hz = -t * s; nx = -s; nz = t * c; k = 1 / R;
    }
    const lapS = u - this.straight;
    o.x = x + nx * d; o.z = z + nz * d; o.y = this.elevAt(lapS);
    o.hx = hx; o.hz = hz; o.nx = nx; o.nz = nz; o.k = k; o.slope = this.slopeAt(lapS); o.u = u;
    return o;
  }

  // 走破距離 → ワールド座標
  at(s, d, o) {
    if (this.chute > 0 && s < this.chute) {
      o = this.point(this.joinU, d, o);
      const back = this.chute - s;
      o.x -= o.hx * back; o.z -= o.hz * back; o.k = 0; o.slope = 0;
      return o;
    }
    return this.point(this.u0 + s, d, o);
  }
  uOf(s) { let u = (this.u0 + s) % this.lap; if (u < 0) u += this.lap; return u; }
  // 曲率 (0=直線)
  curvAt(s) {
    if (this.chute > 0 && s < this.chute) return 0;
    const u = this.uOf(s);
    return (u < this.L || (u >= this.half && u < this.half + this.L)) ? 0 : 1 / this.R;
  }
  // 次のコーナーまでの距離 (コーナー内なら0)
  distToCurve(s) {
    if (s < this.chute) return this.chute - s + (this.joinU === 0 ? this.L : this.L);
    const u = this.uOf(s);
    if (u < this.L) return this.L - u;
    if (u < this.half) return 0;
    if (u < this.half + this.L) return this.half + this.L - u;
    return 0;
  }
  // コーナー番号の文字列 (実況用)
  cornerAt(s) {
    if (s < this.chute) return 0;
    const u = this.uOf(s), q = Math.PI * this.R / 2;
    if (u < this.L) return 0;
    if (u < this.L + q) return 1;
    if (u < this.half) return 2;
    if (u < this.half + this.L) return 0;
    if (u < this.half + this.L + q) return 3;
    return 4;
  }
}
