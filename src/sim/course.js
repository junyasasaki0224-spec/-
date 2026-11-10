// コース定義(単位: m)。x 軸 = ホームストレッチ方向(スタンドから見て右が +x)、+z = スタンド側。
// 競艇と同じ左回り: ホーム(+x 方向) → 1マーク → バック(-x 方向) → 2マーク。

export const PI = Math.PI;
export const clamp = (v, a, b) => (v < a ? a : v > b ? b : v);
export const lerp = (a, b, t) => a + (b - a) * t;
export const sm = (t) => { t = clamp(t, 0, 1); return t * t * (3 - 2 * t); };
export const wrapAngle = (a) => { while (a > PI) a -= 2 * PI; while (a < -PI) a += 2 * PI; return a; };

export const M1 = { x: 150, z: 8 };    // 1マーク(スタンド側に 8m 振ってある)
export const M2 = { x: -150, z: 0 };   // 2マーク
export const BOUNDS = { minX: -262, maxX: 252, minZ: -78, maxZ: 58 }; // 消波装置の内側
export const POLE = { x: 0, z: 4, r: 0.6 };   // センターポール
export const BUOY_R = 0.8;
export const START_X = 0;
export const ARC_S = 60;      // ターン区間に割り当てる進行度
export const LAP_S = 720;     // 1周ぶんの進行度
export const LAPS = 3;

// 2つのターンマークを結ぶ線の z
export function zc(x) {
  const t = clamp((x - M2.x) / (M1.x - M2.x), 0, 1);
  return M2.z + (M1.z - M2.z) * t;
}

// 0: ホーム, 1: 1マーク旋回域, 2: バック, 3: 2マーク旋回域
export function region(x, z) {
  if (x > M1.x) return 1;
  if (x < M2.x) return 3;
  return z >= zc(x) ? 0 : 2;
}

// 区間内の進行度 s (0..720)。x=-150 のホーム側を 0 とする
export function sOf(x, z, reg) {
  switch (reg) {
    case 0: return x + 150;
    case 1: return 300 + ARC_S * clamp(Math.atan2(x - M1.x, z - M1.z), 0, PI) / PI;
    case 2: return 360 + (150 - x);
    default: return 660 + ARC_S * clamp(Math.atan2(-(x - M2.x), -(z - M2.z)), 0, PI) / PI;
  }
}

// マーク線(またはマーク)からの横方向距離
export function lateral(x, z, reg) {
  switch (reg) {
    case 0: return z - zc(x);
    case 1: return Math.hypot(x - M1.x, z - M1.z);
    case 2: return zc(x) - z;
    default: return Math.hypot(x - M2.x, z - M2.z);
  }
}

// ターン中の旋回半径プロファイル: 進入 e → 頂点 a (角度 aA) → 立ち上がり x
export function rProf(al, e, a, x, aA) {
  return al < aA ? lerp(e, a, sm(al / aA)) : lerp(a, x, sm((al - aA) / (PI - aA)));
}

export function arcPoint(mark, al, r, out) {
  if (mark === 1) { out.x = M1.x + r * Math.sin(al); out.z = M1.z + r * Math.cos(al); }
  else { out.x = M2.x - r * Math.sin(al); out.z = M2.z - r * Math.cos(al); }
  return out;
}
