--!strict
-- オンライン機能の調整値(人数・対戦・ボス戦・なかま)。
local Online = {
	-- 1サーバーの最大人数。Studio の ゲーム設定 → 場所 → 最大プレイヤー数 も同じ値にする
	-- (村の釣り小屋の数もこの値。人が多いほど重くなるので、10人で止める)
	MaxPlayers = 10,

	-- 対戦(相棒3匹どうし)
	ChallengeSeconds = 20, -- 申し込みの返事を待つ時間
	ChallengeCooldown = 8, -- 同じ相手へ申し込み直せるまで(しつこい申し込みを防ぐ)
	TurnSeconds = 25, -- 1ターンで行動を選べる時間。過ぎたらコンピューターが代わりに選ぶ
	FirstTurnSeconds = 35, -- 最初のターンは少し長め(相手のチームを見る時間)
	MaxMissedTurns = 3, -- 続けてこの回数選ばなかったら降参あつかい(放置対策)
	QueueGhostAfter = 10, -- ランダム対戦: このサーバーに相手がいなければ、この秒数でほかのサーバーの釣り人のチームと
	QueueGiveUpAfter = 60, -- それでも見つからなければ探すのをやめる
	PowerWindow = 0.35, -- 強さ(能力値の合計)の差がこの割合までの相手と組む
	RatingStart = 1000,
	RatingK = 32,
	DailyWinCoins = 1500, -- ランダム対戦の1日の最初の勝利のごほうび(申し込み対戦では出ない)
	GhostStore = "YokaiPvpTeams_v1", -- ほかのサーバーの釣り人のチームの置き場所(MemoryStore)
	GhostTtlSeconds = 2 * 24 * 3600,
	GhostWriteEverySeconds = 300,

	-- ボス戦(協力)
	RaidPartyMax = 4,
	RaidRoomsMax = 2, -- 1サーバーで同時に開ける部屋の数
	RaidLobbySeconds = 40, -- 部屋を作ってから自動で始まるまで(ホストは途中で始められる)
	RaidSeconds = 240, -- 制限時間

	-- なかま
	Stamps = { "hello", "nice", "caught", "thanks", "nushi", "battle", "help", "bye" }, -- 定型のスタンプだけ(自由な文字は使わない)
}

return Online
