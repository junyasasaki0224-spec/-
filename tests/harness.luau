-- Roblox 形式の require(script.Parent.X) を、ファイルから読み込めるようにする小さな仕組み(Lune 用)。
-- Roblox に依存しない純粋なモジュール(Config / Roll / Pricing / WorldClock / Format / Locale)をテストする。
local fs = require("@lune/fs")
local luau = require("@lune/luau")
local roblox = require("@lune/roblox")

local Harness = {}

local cache = {}

-- フォルダを先に全部読み込んで、Instance のような木構造(ただのテーブル)を作る
-- (Lune のファイル操作はメタメソッド内で呼べないため)
local function scan(path: string, name: string, parent: any): any
	local node: any = { __path = path, Name = name, Parent = parent }
	if fs.isDir(path) then
		node.__dir = true
		for _, entry in fs.readDir(path) do
			local full = path .. "/" .. entry
			local childName = entry:gsub("%.luau$", ""):gsub("%.lua$", "")
			if fs.isDir(full) or entry:match("%.luau?$") then
				if childName ~= "init" then
					node[childName] = scan(full, childName, node)
				else
					node.__init = full
					node.__source = fs.readFile(full)
				end
			end
		end
	else
		node.__source = fs.readFile(path)
	end
	return node
end

local function requireNode(node: any): any
	local key = node.__path
	if cache[key] ~= nil then
		return cache[key]
	end
	local src = node.__source
	if not src then
		error("no source for " .. key)
	end
	local env = setmetatable({
		script = node,
		require = function(n)
			if type(n) == "table" and n.__path then
				return requireNode(n)
			end
			return require(n)
		end,
		Color3 = roblox.Color3,
		Vector3 = roblox.Vector3,
		CFrame = roblox.CFrame,
	}, { __index = _G })
	local fn = luau.load(src, { debugName = node.__init or key, environment = env })
	local result = fn()
	cache[key] = result
	return result
end

-- "src/shared" のようなフォルダを Roblox のフォルダのように扱う
function Harness.root(path: string)
	local parts = string.split(path, "/")
	return scan(path, parts[#parts], nil)
end

Harness.require = requireNode

-- 小さなテストランナー
local passed, failed = 0, 0
function Harness.test(name: string, fn: () -> ())
	local ok, err = pcall(fn)
	if ok then
		passed += 1
		print("  ✓ " .. name)
	else
		failed += 1
		print("  ✗ " .. name .. "\n      " .. tostring(err))
	end
end

function Harness.assertEq(a, b, msg: string?)
	if a ~= b then
		error(("%s: expected %s, got %s"):format(msg or "assertEq", tostring(b), tostring(a)), 2)
	end
end

function Harness.assertNear(a: number, b: number, tol: number, msg: string?)
	if math.abs(a - b) > tol then
		error(("%s: expected %g ± %g, got %g"):format(msg or "assertNear", b, tol, a), 2)
	end
end

function Harness.assert(cond: any, msg: string?)
	if not cond then
		error(msg or "assertion failed", 2)
	end
end

function Harness.summary(): boolean
	print(("\n%d passed, %d failed"):format(passed, failed))
	return failed == 0
end

return Harness
