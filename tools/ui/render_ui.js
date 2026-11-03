// 画面の写し(tests/client_sim.luau が書き出す JSON)を、ブラウザで絵にする。Studio を開かずに見た目を確かめる用。
//   UI_SNAPSHOTS=build/ui lune run tests/client_sim.luau
//   node tools/ui/render_ui.js build/ui build/ui_png
// Roblox の並べ方(UIListLayout / UIGridLayout / UIPadding / AnchorPoint / TextScaled など)を HTML で近似する。
// 3D(魚・顔写真)は置き換えの絵。文字の大きさ・重なり・はみ出しを見るためのもの。
const fs = require("fs");
const path = require("path");
const { chromium } = require("playwright");

const [inDir, outDir] = process.argv.slice(2);
if (!inDir || !outDir) {
	console.error("usage: node tools/ui/render_ui.js <snapshots dir> <out dir>");
	process.exit(1);
}

const RENDER = String.raw`
const GUI = new Set(["Frame","TextLabel","TextButton","ImageLabel","ImageButton","ScrollingFrame","ViewportFrame"]);
const DEF_SIZE = { TextLabel: {xs:0,xo:200,ys:0,yo:50}, TextButton: {xs:0,xo:200,ys:0,yo:50} };
const DEF_BG = { r: 163/255, g: 162/255, b: 165/255 };
const WEIGHT = { GothamBlack: 900, GothamBold: 700, GothamMedium: 500 };
const rgba = (c, a) => "rgba(" + Math.round(c.r*255) + "," + Math.round(c.g*255) + "," + Math.round(c.b*255) + "," + a + ")";
const mul = (a, b) => ({ r: a.r*b.r, g: a.g*b.g, b: a.b*b.b });
// 0% を含む calc は、高さが決まっていない親の中では auto 扱いになるので、px だけの時は px で書く
const ud = (u, axis) => {
	const sc = axis === "x" ? u.xs : u.ys, of = axis === "x" ? u.xo : u.yo;
	return sc ? "calc(" + (sc*100) + "% + " + of + "px)" : of + "px";
};
const udim = (u) => u ? (u.s ? "calc(" + (u.s*100) + "% + " + u.o + "px)" : u.o + "px") : "0px";

function build(node, parent, mode) {
	const p = node.p, cls = node.c;
	if (cls === "ScreenGui") { for (const k of node.k || []) build(k, parent, null); return; }
	if (!GUI.has(cls) || p.Visible === false) return;
	const kids = Array.isArray(node.k) ? node.k : []; // 空の表は {} で書き出される
	const one = (c) => kids.find((k) => k.c === c);
	const list = one("UIListLayout"), grid = one("UIGridLayout"), pad = one("UIPadding"), corner = one("UICorner");
	const grad = one("UIGradient"), tsc = one("UITextSizeConstraint"), sc = one("UISizeConstraint"), scale = one("UIScale");
	const strokes = kids.filter((k) => k.c === "UIStroke");
	const isText = cls === "TextLabel" || cls === "TextButton";

	const el = document.createElement("div");
	el.className = "n";
	const size = p.Size || DEF_SIZE[cls] || { xs: 0, xo: 100, ys: 0, yo: 100 };
	const auto = p.AutomaticSize && p.AutomaticSize.name;
	if (mode === "grid") {
		el.style.position = "relative"; el.style.width = "100%"; el.style.height = "100%";
	} else {
		el.style.width = ud(size, "x");
		if (auto === "Y" || auto === "XY") el.style.minHeight = ud(size, "y"); else el.style.height = ud(size, "y");
		if (mode === "list") {
			el.style.position = "relative"; el.style.flex = "none";
		} else {
			const pos = p.Position || { xs: 0, xo: 0, ys: 0, yo: 0 };
			const ap = p.AnchorPoint || { x: 0, y: 0 };
			el.style.left = ud(pos, "x"); el.style.top = ud(pos, "y");
			el.style.translate = (-ap.x*100) + "% " + (-ap.y*100) + "%";
		}
	}
	if (p.LayoutOrder !== undefined) el.style.order = Math.max(-1e6, Math.min(1e6, Math.round(p.LayoutOrder)));
	el.style.zIndex = p.ZIndex ?? 1;
	if (scale && scale.p.Scale !== undefined && scale.p.Scale !== 1) el.style.scale = scale.p.Scale;
	if (sc && sc.p.MaxSize) { el.style.maxWidth = sc.p.MaxSize.x + "px"; el.style.maxHeight = sc.p.MaxSize.y + "px"; }
	if (cls === "ScrollingFrame" || p.ClipsDescendants) el.style.overflow = "hidden";

	// 背景(UIGradient は色をかけ合わせる)
	const bt = p.BackgroundTransparency ?? 0;
	if (bt < 1) {
		const bg = p.BackgroundColor3 || DEF_BG;
		if (grad && grad.p.Color) {
			const a = 1 - bt, rot = (grad.p.Rotation ?? 0) + 90;
			el.style.background = "linear-gradient(" + rot + "deg," + rgba(mul(bg, grad.p.Color.c0), a) + "," + rgba(mul(bg, grad.p.Color.c1), a) + ")";
		} else el.style.background = rgba(bg, 1 - bt);
	}
	if (corner) {
		const r = corner.p.CornerRadius || { s: 0, o: 8 };
		el.style.borderRadius = r.s >= 0.5 ? "9999px" : r.s > 0 ? (r.s*100) + "%" : r.o + "px";
	}
	const shadows = [], textShadows = [];
	for (const s of strokes) {
		const c = s.p.Color || { r: 0, g: 0, b: 0 }, a = 1 - (s.p.Transparency ?? 0), th = s.p.Thickness ?? 1;
		const border = (s.p.ApplyStrokeMode && s.p.ApplyStrokeMode.name === "Border") || !isText;
		if (border) shadows.push("0 0 0 " + th + "px " + rgba(c, a));
		else for (const [dx, dy] of [[-1,-1],[1,-1],[-1,1],[1,1],[0,-1],[0,1],[-1,0],[1,0]]) textShadows.push((dx*th) + "px " + (dy*th) + "px 0 " + rgba(c, a));
	}
	if (shadows.length) el.style.boxShadow = shadows.join(",");

	const insets = pad ? [udim(pad.p.PaddingTop), udim(pad.p.PaddingRight), udim(pad.p.PaddingBottom), udim(pad.p.PaddingLeft)] : ["0px","0px","0px","0px"];

	// 置き換えの絵(顔写真・魚)
	if (cls === "ImageLabel" && typeof p.Image === "string" && p.Image.startsWith("rbxthumb")) {
		const ph = document.createElement("div");
		ph.className = "ph"; ph.textContent = "👤";
		ph.style.opacity = 1 - (p.ImageTransparency ?? 0);
		el.appendChild(ph);
	}
	if (cls === "ViewportFrame") {
		const model = kids.find((k) => k.c === "Model");
		if (model && (p.ImageTransparency ?? 0) < 1) {
			const ph = document.createElement("div");
			ph.className = "fish"; ph.innerHTML = "<span>🐟</span><small>" + model.p.Name + "</small>";
			el.appendChild(ph);
		}
	}

	// 文字
	if (isText && typeof p.Text === "string" && p.Text !== "") {
		const box = document.createElement("div");
		box.className = "t";
		[box.style.top, box.style.right, box.style.bottom, box.style.left] = insets;
		const xa = (p.TextXAlignment && p.TextXAlignment.name) || "Center";
		const ya = (p.TextYAlignment && p.TextYAlignment.name) || "Center";
		box.style.justifyContent = xa === "Left" ? "flex-start" : xa === "Right" ? "flex-end" : "center";
		box.style.alignItems = ya === "Top" ? "flex-start" : ya === "Bottom" ? "flex-end" : "center";
		const span = document.createElement("span");
		span.textContent = p.Text;
		span.style.textAlign = xa === "Left" ? "left" : xa === "Right" ? "right" : "center";
		span.style.color = rgba(p.TextColor3 || { r: 0, g: 0, b: 0 }, 1 - (p.TextTransparency ?? 0));
		span.style.fontWeight = WEIGHT[p.Font && p.Font.name] || 400;
		span.style.whiteSpace = p.TextWrapped || p.TextScaled ? "normal" : "nowrap";
		if (textShadows.length) span.style.textShadow = textShadows.join(",");
		span.dataset.max = tsc ? tsc.p.MaxTextSize : p.TextScaled ? 100 : p.TextSize || 14;
		span.dataset.min = tsc ? tsc.p.MinTextSize ?? 1 : 1;
		span.dataset.scaled = p.TextScaled ? "1" : "";
		box.appendChild(span);
		el.appendChild(box);
	}

	// 子の入れ物(UIPadding の内側)
	const content = document.createElement("div");
	content.className = "c";
	if (auto === "Y" || auto === "XY") {
		content.style.position = "relative";
		content.style.padding = insets.join(" ");
	} else {
		[content.style.top, content.style.right, content.style.bottom, content.style.left] = insets;
	}
	let childMode = null;
	if (list) {
		childMode = "list";
		const horiz = list.p.FillDirection && list.p.FillDirection.name === "Horizontal";
		content.style.display = "flex";
		content.style.flexDirection = horiz ? "row" : "column";
		content.style.gap = udim(list.p.Padding);
		const ha = list.p.HorizontalAlignment && list.p.HorizontalAlignment.name;
		const va = list.p.VerticalAlignment && list.p.VerticalAlignment.name;
		const map = (v) => (v === "Center" ? "center" : v === "Right" || v === "Bottom" ? "flex-end" : "flex-start");
		if (horiz) { content.style.justifyContent = map(ha); content.style.alignItems = map(va); }
		else { content.style.alignItems = map(ha); content.style.justifyContent = map(va); }
	} else if (grid) {
		childMode = "grid";
		const cs = grid.p.CellSize || { xs: 0, xo: 100, ys: 0, yo: 100 }, cp = grid.p.CellPadding || { xo: 5, yo: 5 };
		content.style.display = "grid";
		content.style.gridTemplateColumns = "repeat(auto-fill, " + ud(cs, "x") + ")";
		content.style.gridAutoRows = cs.ys ? ud(cs, "y") : cs.yo + "px";
		content.style.gap = cp.yo + "px " + cp.xo + "px";
	}
	el.appendChild(content);
	parent.appendChild(el);
	for (const k of kids) build(k, content, childMode);
}

// TextScaled: 枠に収まる一番大きい文字(MaxTextSize まで)
function fit() {
	for (const span of document.querySelectorAll(".t span")) {
		const box = span.parentElement;
		let size = Number(span.dataset.max);
		const min = Number(span.dataset.min) || 1;
		span.style.fontSize = size + "px";
		if (!span.dataset.scaled) continue;
		while (size > min && (span.scrollWidth > box.clientWidth + 0.5 || span.offsetHeight > box.clientHeight + 0.5)) {
			size -= 1;
			span.style.fontSize = size + "px";
		}
	}
}
build(DATA, document.getElementById("root"), null);
fit();
`;

const PAGE = (data) => `<!doctype html><html><head><meta charset="utf-8"><style>
html,body{margin:0;width:1280px;height:720px;overflow:hidden;font-family:"IPAGothic","Noto Color Emoji",sans-serif}
#world{position:absolute;inset:0;background:linear-gradient(180deg,#86b9cf 0%,#b9d9c9 52%,#4f7f69 53%,#2f5747 100%)}
#world:after{content:"(ゲームの景色)";position:absolute;left:50%;top:60%;translate:-50% 0;color:rgba(255,255,255,.35);font-size:28px}
#root{position:absolute;inset:0}
.n{position:absolute;box-sizing:border-box}
.c{position:absolute}
.t{position:absolute;display:flex;overflow:visible;line-height:1.08;pointer-events:none}
.t span{display:block;max-width:100%;overflow-wrap:anywhere}
.ph{position:absolute;inset:0;border-radius:9999px;background:radial-gradient(circle at 50% 35%,#c9c3e6,#6d6890);display:flex;align-items:center;justify-content:center;font-size:60%;overflow:hidden}
.fish{position:absolute;inset:8%;border-radius:40%;background:radial-gradient(circle,rgba(255,255,255,.22),rgba(255,255,255,0) 70%);display:flex;flex-direction:column;align-items:center;justify-content:center;color:rgba(255,255,255,.75)}
.fish span{font-size:64px;line-height:1}.fish small{font-size:12px;margin-top:4px}
</style></head><body><div id="world"></div><div id="root"></div><script>(() => {const DATA=${data};${RENDER}})();</script></body></html>`;

(async () => {
	fs.mkdirSync(outDir, { recursive: true });
	const browser = await chromium.launch();
	const page = await browser.newPage({ viewport: { width: 1280, height: 720 } });
	page.on("pageerror", (e) => console.error("page error:", e.message));
	const files = fs.readdirSync(inDir).filter((f) => f.endsWith(".json")).sort();
	for (const f of files) {
		const data = fs.readFileSync(path.join(inDir, f), "utf8");
		await page.setContent(PAGE(data), { waitUntil: "load" });
		const out = path.join(outDir, f.replace(/\.json$/, ".png"));
		await page.screenshot({ path: out });
		console.log(out);
	}
	await browser.close();
})();
