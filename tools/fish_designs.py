# 妖怪魚50種のデザイン仕様 → Config/Fish/*.luau を生成する(デザインを一覧で管理するための道具)
# 使い方: python3 tools/fish_designs.py   (ゲームのデータを書き換える)
# 見た目の項目: c1 体 / c2 模様 / c3 差し色 / pattern / deco / eyes / mouth / body {幅,高さ,長さ} / tails / size
import json, re, sys, os

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

# 名前(ja / en)はカタカナのあだ名。もとの魚と妖怪は kindJa / kindEn(種類)に書く。
# 魚は実際に住んでいる場所の釣り場に置く(鱏・河豚・鮟鱇・鮫・鯱・鯨は海、鮎・山女魚・岩魚・鮭・大山椒魚は川、
# 鮒・泥鰌・目高・タナゴは沼、公魚・姫鱒・蝶鮫は湖)。どの釣り場にも、その場所らしい強い魚(伝説・神話・秘伝)を置く。
# 河童の親分(川)と雨蛙魚(沼)は魚ではない妖怪で、丸い体に河豚の形を借りている。

# ---- 沼(23種) ----
# 泥の底の止まった水: 鮒・鯉・鯰・泥鰌・目高・タナゴ・鰻・鯊。強い魚は大鯰(鵺)・九尾の鯉・蛟(水の龍)・雷魚のような蛇体(八岐)
SWAMP = [
    dict(id="doro_funa", ja="ドロブー", en="Doroboo", kindJa="泥鮒", kindEn="Mud Crucian", element="earth", rarity="common", time="any", weather="any", kg=[0.3, 1.5], shape="koi",
         c1="#6E5B3E", c2="#B9A57A", c3="#8C7A4E", pattern="belly", eyes="dot", mouth="frown", body=[1.05, 0.95, 1], deco=[],
         jaDesc="沼の底の泥をすすって生きる。妖気はほとんどない。", enDesc="Lives on swamp mud. Barely any yokai energy."),
    dict(id="ashi_medaka", ja="ピーメダ", en="Peemeda", kindJa="葦目高", kindEn="Reed Medaka", element="water", rarity="common", time="day", weather="any", kg=[0.1, 0.5], shape="koi",
         c1="#A8B86A", c2="#5E7A3A", c3="#E6DFA0", pattern="stripes", eyes="cute", mouth="small", body=[0.8, 0.85, 1.1], size=0.75, deco=[],
         jaDesc="葦の影に群れる小さな魚。風の音で歌う。", enDesc="Tiny schooling fish that sing with the reeds."),
    dict(id="ko_namazu", ja="ネムナマ", en="Nemunama", kindJa="小鯰", kindEn="Little Catfish", element="earth", rarity="common", time="any", weather="any", kg=[0.4, 2], shape="catfish",
         c1="#5A5148", c2="#8A7B66", c3="#A39276", pattern="belly", eyes="sleepy", mouth="wide", body=[1.1, 0.9, 0.95], deco=["whiskers"],
         jaDesc="地震を起こすには小さすぎる鯰。", enDesc="Too small to cause an earthquake. For now."),
    dict(id="hotaru_dojo", ja="ホタルン", en="Hotarun", kindJa="蛍泥鰌", kindEn="Firefly Loach", element="fire", rarity="common", time="night", weather="any", kg=[0.1, 0.6], shape="eel",
         c1="#3B3324", c2="#D7FF6B", c3="#9BBF3A", pattern="spots", eyes="dot", mouth="smile", size=0.75, deco=["glow"],
         jaDesc="夜になると背中の点が光る。", enDesc="The dots on its back glow at night."),
    dict(id="ame_gaeru", ja="ケロアメ", en="Keroame", kindJa="雨蛙魚", kindEn="Rainfrog Fish", element="water", rarity="common", time="any", weather="rain", kg=[0.2, 1], shape="puffer",
         c1="#5FB343", c2="#F2E58C", c3="#2F7A36", pattern="belly", eyes="cute", mouth="smile", body=[1.05, 0.85, 1], size=0.85, deco=["smooth"],
         jaDesc="雨の日だけ水面に上がってきて鳴く。", enDesc="Surfaces to croak only on rainy days."),
    dict(id="hasu_koi", ja="ハスコ", en="Hasuko", kindJa="蓮鯉", kindEn="Lotus Koi", element="water", rarity="common", time="day", weather="sunny", kg=[0.8, 3], shape="koi",
         c1="#F4F1EA", c2="#E2483D", c3="#F5A3B5", pattern="patches", eyes="normal", mouth="small", deco=["lotus"],
         jaDesc="蓮の葉の下で昼寝をする鯉。", enDesc="Naps beneath lotus leaves on sunny days."),
    dict(id="kappa_haze", ja="カッパゼ", en="Kappaze", kindJa="河童鯊", kindEn="Kappa Goby", element="water", rarity="common", time="any", weather="any", kg=[0.2, 0.9], shape="catfish",
         c1="#6E9E4A", c2="#C9D88A", c3="#3F6B2E", pattern="spots", eyes="cute", mouth="geta", body=[0.95, 0.95, 0.85], size=0.8, deco=[],
         jaDesc="河童の子分。きゅうりで釣れるという噂。", enDesc="A kappa's sidekick. Rumored to love cucumbers."),
    dict(id="kappa_koi", ja="カパコイ", en="Kapakoi", kindJa="河童鯉", kindEn="Kappa Koi", element="water", rarity="uncommon", time="day", weather="any", kg=[1, 3.5], shape="koi",
         c1="#3F8F5A", c2="#D9C35A", c3="#7A5A2E", pattern="belly", eyes="normal", mouth="beak", deco=["crown"],
         jaDesc="頭の皿の水がこぼれると力が抜ける。", enDesc="Loses all strength if the water in its head-dish spills."),
    dict(id="hitotsume_namazu", ja="ギョロナマ", en="Gyoronama", kindJa="一つ目鯰", kindEn="One-Eyed Catfish", element="spirit", rarity="uncommon", time="night", weather="any", kg=[1, 4], shape="catfish",
         c1="#4A3F66", c2="#8C7FB5", c3="#B9A8E8", pattern="belly", eyes="big", mouth="tongue", deco=["whiskers"],
         jaDesc="大きな一つ目で夜の沼を見張る。", enDesc="Watches the night swamp with one huge eye."),
    dict(id="nure_unagi", ja="ヌレオナ", en="Nureona", kindJa="濡れ鰻", kindEn="Nure Eel", element="water", rarity="uncommon", time="any", weather="rain", kg=[0.6, 2.5], shape="eel",
         c1="#2E5552", c2="#86B3AE", c3="#1C2626", pattern="stripes", eyes="sleepy", mouth="small", tails=2, deco=["hair"],
         jaDesc="雨の夜道で人を呼び止める声がする。", enDesc="Calls out to travelers on rainy roads."),
    dict(id="sunakake_dojo", ja="ザザドジョ", en="Zazadojo", kindJa="砂かけ泥鰌", kindEn="Sand-Flinger Loach", element="earth", rarity="uncommon", time="day", weather="sunny", kg=[0.2, 1], shape="eel",
         c1="#C9A86A", c2="#7E6233", c3="#E8D2A0", pattern="spots", eyes="angry", mouth="frown", size=0.85, deco=["whiskers", "hat"],
         jaDesc="釣り人の目に砂をかけて逃げる。", enDesc="Flings sand in anglers' eyes to escape."),
    dict(id="yomeiri_tanago", ja="コンタナ", en="Kontana", kindJa="嫁入りタナゴ", kindEn="Fox-Wedding Bitterling", element="spirit", rarity="uncommon", time="any", weather="any", kg=[0.05, 0.3], shape="koi",
         c1="#C8D8E8", c2="#E86AA8", c3="#FFD34D", pattern="gradient", eyes="cute", mouth="small", body=[1.0, 1.15, 0.85], size=0.75, deco=["ears", "kanzashi"],
         jaDesc="恋の季節には虹色に染まるタナゴ。狐の嫁入りのお供をするという。", enDesc="A bitterling that turns rainbow-colored in love season. It is said to escort fox weddings."),
    dict(id="raijin_namazu", ja="ライドドン", en="Raidodon", kindJa="雷神鯰", kindEn="Raijin Catfish", element="thunder", rarity="rare", time="any", weather="thunder", kg=[2, 8], shape="catfish",
         c1="#2D3D7A", c2="#FFD84A", c3="#FFF2A8", pattern="stripes", eyes="angry", mouth="fangs", deco=["drums", "horns", "whiskers", "glow"],
         jaDesc="雷が鳴ると太鼓のように腹を鳴らす。", enDesc="Drums its belly whenever thunder rolls."),
    dict(id="nekomata_koi", ja="ニャマタ", en="Nyamata", kindJa="猫又鯉", kindEn="Nekomata Koi", element="spirit", rarity="rare", time="night", weather="any", kg=[1, 4.5], shape="koi",
         c1="#26242A", c2="#F2F2F2", c3="#F2B84B", pattern="patches", eyes="cat", mouth="smile", tails=2, deco=["ears", "bell"],
         jaDesc="尾が二つに分かれた鯉。猫のように鳴く。", enDesc="A koi with a forked tail. It meows."),
    dict(id="nopperabo", ja="ノッペラン", en="Nopperan", kindJa="のっぺら魚", kindEn="Faceless Fish", element="spirit", rarity="rare", time="any", weather="any", kg=[0.8, 3], shape="koi",
         c1="#E9E1EE", c2="#FFFFFF", c3="#B7A9C9", pattern="belly", eyes="none", mouth="none", deco=["hat"],
         jaDesc="顔がない。どちらが前かもわからない。", enDesc="No face. Nobody knows which end is the front."),
    dict(id="oni_unagi", ja="カナボウナ", en="Kanabouna", kindJa="鬼鰻", kindEn="Oni Eel", element="fire", rarity="epic", time="any", weather="any", kg=[2, 9], shape="eel",
         c1="#B8322C", c2="#2A1A1A", c3="#F2C14E", pattern="stripes", eyes="angry", mouth="fangs", body=[1.15, 1.1, 1], deco=["horns"],
         jaDesc="金棒のように硬い体で網を破る。", enDesc="Its club-hard body tears through nets."),
    dict(id="tsuchinoko_fugu", ja="ツチノコロ", en="Tsuchinokoro", kindJa="槌の子泥鰌", kindEn="Tsuchinoko Loach", element="earth", rarity="epic", time="day", weather="sunny", kg=[1.5, 6], shape="eel",
         c1="#8A7A4A", c2="#5A4A2A", c3="#D8C27A", pattern="stripes", eyes="cute", mouth="tongue", body=[1.45, 1.3, 0.75], deco=["coin"],
         jaDesc="幻の生き物。見つけたら懸賞金ものだ。", enDesc="A legendary cryptid. There's a bounty on it."),
    dict(id="rokurokubi_unagi", ja="ロクロニョロ", en="Rokuronyoro", kindJa="ろくろ首鰻", kindEn="Rokurokubi Eel", element="spirit", rarity="epic", time="night", weather="any", kg=[1, 7], shape="eel",
         c1="#EADBCB", c2="#B03A5A", c3="#2B1B2E", pattern="belly", eyes="sleepy", mouth="smile", body=[0.9, 0.9, 1.35], deco=["hair", "kanzashi"],
         jaDesc="夜になると首がどこまでも伸びる。", enDesc="At night, its neck stretches forever."),
    dict(id="kodama_koi", ja="コダマロン", en="Kodamaron", kindJa="木霊鯉", kindEn="Kodama Koi", element="earth", rarity="epic", time="morning", weather="any", kg=[1, 5], shape="koi",
         c1="#D6EBC4", c2="#6FAF4A", c3="#A7D98A", pattern="spots", eyes="dot", mouth="o", body=[1, 1.1, 0.9], deco=["glow", "leaf"],
         jaDesc="朝の森の声が水に宿ったもの。", enDesc="The voice of the morning forest, given scales."),
    dict(id="nue_namazu", ja="ヌエマズ", en="Nuemazu", kindJa="鵺鯰", kindEn="Nue Catfish", element="thunder", rarity="legendary", time="night", weather="any", kg=[5, 20], shape="catfish",
         c1="#4A3220", c2="#D9A441", c3="#5E8C4A", pattern="stripes", eyes="angry", mouth="fangs", tails=2, deco=["horns", "ears", "whiskers", "flame"],
         jaDesc="猿の顔、狸の胴、蛇の尾。正体は誰も知らない。", enDesc="Monkey face, tanuki body, snake tail. True form unknown."),
    dict(id="kyubi_koi", ja="タマモ", en="Tamamo", kindJa="九尾鯉", kindEn="Nine-Tailed Koi", element="fire", rarity="legendary", time="any", weather="any", kg=[3, 15], shape="koi",
         c1="#FFDC8A", c2="#FF8F3D", c3="#FFF0B8", pattern="belly", eyes="sleepy", mouth="smile", tails=9, deco=["ears", "flame"],
         jaDesc="九本の尾びれを持つ、千年生きた鯉。", enDesc="A thousand-year-old koi with nine tails."),
    dict(id="numa_mizuchi", ja="ヌマズチ", en="Numazuchi", kindJa="沼の蛟", kindEn="Swamp Mizuchi", element="thunder", rarity="mythic", time="any", weather="any", kg=[15, 60], shape="eel",
         c1="#1F7A63", c2="#FFD34D", c3="#FFE9A3", pattern="spots", eyes="angry", mouth="fangs", deco=["antlers", "whiskers", "mane", "orb", "glow"],
         jaDesc="龍になりそこねた沼の主の子。", enDesc="Child of the swamp lord, one step from becoming a dragon."),
    dict(id="yamata_chochin", ja="ヤツアカリ", en="Yatsuakari", kindJa="八岐提灯", kindEn="Yamata Lantern", element="fire", rarity="secret", time="night", weather="rain", kg=[30, 120], shape="eel",
         c1="#3A0F24", c2="#FF3D6E", c3="#FFC94D", pattern="stripes", eyes="angry", mouth="grin", body=[1.3, 1.25, 0.9], deco=["lantern", "third_eye", "horns", "flame"],
         jaDesc="雨の夜にだけ、八つの灯りが沼の底でともる。", enDesc="Only on rainy nights do eight lights glow beneath the swamp."),
]

# ---- ぬしの湖(18種) ----
# 大きな淡水の湖: 鯉・鮒・金魚・鯰・鰻・公魚・姫鱒・白魚・蝶鮫(チョウザメ)。強い魚は黒い大鯉(八咫烏)・鳳凰の鯉・龍神・月読の鯉
LAKE = [
    dict(id="koban_funa", ja="チャリブナ", en="Charibuna", kindJa="小判鮒", kindEn="Koban Crucian", element="earth", rarity="common", time="any", weather="any", kg=[0.4, 1.6], shape="koi",
         c1="#A08A4E", c2="#D9C27A", c3="#7A6630", pattern="belly", eyes="dot", mouth="smile", body=[1.15, 1, 0.85], deco=["coin"],
         jaDesc="額に小判の模様。釣れると少し得した気分になる。", enDesc="A coin mark on its forehead. Catching one feels lucky."),
    dict(id="furin_kingyo", ja="リンキン", en="Rinkin", kindJa="風鈴金魚", kindEn="Wind-Chime Goldfish", element="water", rarity="common", time="day", weather="sunny", kg=[0.1, 0.6], shape="koi",
         c1="#E8452E", c2="#FFFFFF", c3="#FFB3A1", pattern="patches", eyes="cute", mouth="o", body=[1.1, 1.15, 0.8], tails=3, size=0.8, deco=["bell"],
         jaDesc="夏の晴れた日、風鈴の音に誘われて泳ぎ出る。", enDesc="On sunny summer days it swims out to the sound of wind chimes."),
    dict(id="dango_unagi", ja="モッチウナ", en="Mocchiuna", kindJa="団子鰻", kindEn="Dango Eel", element="earth", rarity="common", time="day", weather="any", kg=[0.3, 1.2], shape="eel",
         c1="#F3E7D3", c2="#F59AB5", c3="#8CC47A", pattern="dango", eyes="cute", mouth="smile", size=0.85, deco=["blush"],
         jaDesc="花見の季節に現れる、三色の鰻。甘い香りがする。", enDesc="A three-colored eel of cherry-blossom season. Smells sweet."),
    dict(id="kiri_shirauo", ja="スケシラ", en="Sukeshira", kindJa="霧白魚", kindEn="Mist Whitebait", element="spirit", rarity="common", time="any", weather="fog", kg=[0.1, 0.4], shape="eel",
         c1="#E3ECF0", c2="#9FC6D6", c3="#9FE3F0", pattern="gradient", eyes="dot", mouth="small", body=[0.8, 0.8, 1.05], size=0.7, deco=[],
         jaDesc="霧の湖で、体が透けて見えなくなる。", enDesc="In the lake fog its body turns see-through."),
    dict(id="yukimi_wakasagi", ja="ユキサギ", en="Yukisagi", kindJa="雪見公魚", kindEn="Snow-Viewing Smelt", element="water", rarity="common", time="morning", weather="any", kg=[0.02, 0.1], shape="koi",
         c1="#D8E4EC", c2="#8AA8C0", c3="#F2F6FA", pattern="belly", eyes="dot", mouth="o", body=[0.75, 0.8, 1.15], size=0.65, deco=[],
         jaDesc="冬の朝、湖の氷に穴をあけると群れで集まってくる。", enDesc="On winter mornings, drill a hole in the lake ice and they gather in schools."),
    dict(id="akaname_namazu", ja="ペロナマ", en="Peronama", kindJa="垢嘗鯰", kindEn="Akaname Catfish", element="spirit", rarity="uncommon", time="night", weather="any", kg=[0.8, 3], shape="catfish",
         c1="#C8483B", c2="#F08A6E", c3="#5A1E1A", pattern="belly", eyes="cute", mouth="tongue", deco=["whiskers"],
         jaDesc="風呂場の垢をなめて回る鯰。長い舌が自慢。", enDesc="It licks bathhouse grime clean. Proud of its long tongue."),
    dict(id="zashiki_koi", ja="ワラッコ", en="Warakko", kindJa="座敷童鯉", kindEn="Zashiki-Warashi Koi", element="spirit", rarity="uncommon", time="any", weather="any", kg=[0.5, 2], shape="koi",
         c1="#F6E3D3", c2="#D94F4F", c3="#2B2430", pattern="belly", eyes="cute", mouth="smile", deco=["okappa", "blush"],
         jaDesc="おかっぱ頭の鯉。見た者の家には福が来るという。", enDesc="A bob-haired koi. The home of whoever sees it is blessed."),
    dict(id="tsukimi_himemasu", ja="ツキマス", en="Tsukimasu", kindJa="月見姫鱒", kindEn="Moon-Viewing Kokanee", element="water", rarity="uncommon", time="night", weather="any", kg=[0.3, 1.5], shape="koi",
         c1="#C84A3A", c2="#E8E0D0", c3="#6A9A5A", pattern="gradient", eyes="sleepy", mouth="small", body=[0.9, 0.95, 1.1], deco=["blush"],
         jaDesc="月の夜、湖の深いところから浮かんでくる姫鱒。赤い婚姻色が美しい。", enDesc="On moonlit nights this kokanee rises from the lake depths, beautiful in red breeding colors."),
    dict(id="kasha_namazu", ja="ヒグルマズ", en="Higurumazu", kindJa="火車鯰", kindEn="Kasha Catfish", element="fire", rarity="rare", time="night", weather="any", kg=[2, 7], shape="catfish",
         c1="#2A2230", c2="#FF7A2E", c3="#FFB547", pattern="saddle", eyes="cat", mouth="fangs", deco=["fire_wheel", "ears"],
         jaDesc="炎の車を引く猫の妖怪が、鯰に化けたもの。", enDesc="A cat demon that pulls a burning cart, now a catfish."),
    dict(id="komainu_koi", ja="ガウコマ", en="Gaukoma", kindJa="狛犬鯉", kindEn="Komainu Koi", element="earth", rarity="rare", time="any", weather="any", kg=[1.5, 5], shape="koi",
         c1="#4FA59A", c2="#E8C65A", c3="#2E6B64", pattern="patches", eyes="angry", mouth="fangs", body=[1.05, 1.05, 0.95], deco=["crest", "bell"],
         jaDesc="神社を守る狛犬の鯉。本当は二匹いるはず。", enDesc="A shrine-guardian koi. There should be a pair..."),
    dict(id="nurari_unagi", ja="ヌラリン", en="Nurarin", kindJa="ぬらりひょん鰻", kindEn="Nurarihyon Eel", element="spirit", rarity="rare", time="night", weather="any", kg=[1, 5], shape="eel",
         c1="#D9C2A7", c2="#5B4A7A", c3="#2B2440", pattern="belly", eyes="sleepy", mouth="smile", deco=["bighead", "beard"],
         jaDesc="いつの間にか家に上がり込んでいる、妖怪の総大将。", enDesc="The supreme yokai boss who slips into homes unnoticed."),
    dict(id="gasha_unagi", ja="ガシャボーン", en="Gashabone", kindJa="がしゃどくろ鰻", kindEn="Gashadokuro Eel", element="spirit", rarity="epic", time="night", weather="any", kg=[3, 15], shape="eel",
         c1="#EDE6D6", c2="#3A3530", c3="#FF3D3D", pattern="ribs", eyes="glow", mouth="grin", body=[1.1, 1.05, 1.1], deco=[],
         jaDesc="夜に骨の鳴る音がしたら、それはもう近い。", enDesc="If you hear rattling bones at night, it's already close."),
    dict(id="kingyo_hime", ja="ヒメキン", en="Himekin", kindJa="金魚姫", kindEn="Goldfish Princess", element="water", rarity="epic", time="day", weather="any", kg=[0.8, 3], shape="koi",
         c1="#FF6B4A", c2="#FFE0D6", c3="#FFD34D", pattern="patches", eyes="cute", mouth="smile", body=[1.15, 1.2, 0.85], tails=4, deco=["kanzashi", "frills", "blush"],
         jaDesc="城の池から逃げ出した、金魚のお姫さま。", enDesc="A goldfish princess who escaped the castle pond."),
    dict(id="yoroi_chouzame", ja="ヨロチョウ", en="Yorocho", kindJa="鎧蝶鮫", kindEn="Armored Sturgeon", element="earth", rarity="epic", time="any", weather="any", kg=[20.0, 80.0], shape="sturgeon",
         c1="#6A6E5A", c2="#D8D2B8", c3="#3A3E30", pattern="belly", eyes="sleepy", mouth="wide", deco=["whiskers"],
         jaDesc="千年を生きる湖の古代魚。鎧のような鱗で、どんな網も破ってしまう。", enDesc="An ancient fish of the lake that lives a thousand years. Its armor-like scales tear through any net."),
    dict(id="yatagarasu_ei", ja="ヤタクロ", en="Yatakuro", kindJa="八咫烏鯉", kindEn="Yatagarasu Carp", element="fire", rarity="legendary", time="any", weather="any", kg=[6, 20], shape="koi",
         c1="#1A1A22", c2="#3A3A48", c3="#FFB547", pattern="belly", eyes="normal", mouth="beak", body=[1.1, 1.1, 1.15], deco=["sun_disc", "crest"],
         jaDesc="湖の底に住む大きな黒い鯉。太陽の使いで、道に迷った者を正しい方へ導く。", enDesc="A huge black carp of the lake floor. Messenger of the sun, it guides the lost the right way."),
    dict(id="houou_koi", ja="ヒイロ", en="Hiiro", kindJa="鳳凰鯉", kindEn="Phoenix Koi", element="fire", rarity="legendary", time="morning", weather="any", kg=[4, 14], shape="koi",
         c1="#E8483B", c2="#FFC94D", c3="#3FB7A8", pattern="gradient", eyes="sleepy", mouth="small", deco=["plumes", "crest", "flame"],
         jaDesc="朝日とともに舞い上がる、不死の鯉。", enDesc="An undying koi that rises with the morning sun."),
    dict(id="ryujin", ja="タツガミ", en="Tatsugami", kindJa="龍神", kindEn="Ryujin", element="water", rarity="mythic", time="any", weather="any", kg=[40, 120], shape="eel",
         c1="#E8F1F2", c2="#7FC8D8", c3="#FFD34D", pattern="spots", eyes="angry", mouth="fangs", size=1.1, deco=["antlers", "mane", "whiskers", "orb", "shimenawa"],
         jaDesc="湖の底の宮に住む龍の神。ぬしの湖の本当の主。", enDesc="The dragon god of the lake-bottom palace. The lake's true lord."),
    dict(id="tsukuyomi_koi", ja="ツクヨ", en="Tsukuyo", kindJa="月読鯉", kindEn="Tsukuyomi Koi", element="spirit", rarity="secret", time="night", weather="fog", kg=[20, 80], shape="koi",
         c1="#2B3A6B", c2="#C9D6FF", c3="#F4F1C8", pattern="gradient", eyes="glow", mouth="small", tails=3, deco=["moon", "frills", "kanzashi"],
         jaDesc="霧の夜、湖に映った月から生まれるという鯉。", enDesc="Said to be born from the moon's reflection on foggy nights."),
]

# ---- 川(21種) ----
# 山あいの清流: 鮎・山女魚・岩魚・鰍・鯊・鯰・鰻・鯉・鮭・大山椒魚。強い魚は幻の伊富魚・水虎・大はんざき・鮭の大助
RIVER = [
    dict(id="azukiarai_haze", ja="ショキハゼ", en="Shokihaze", kindJa="小豆洗い鯊", kindEn="Azuki-Washer Goby", element="earth", rarity="common", time="any", weather="any", kg=[0.1, 0.6], shape="catfish",
         c1="#B89A74", c2="#7A2E2A", c3="#E8D8B8", pattern="spots", eyes="cute", mouth="smile", body=[0.95, 0.9, 0.95], size=0.75, deco=[],
         jaDesc="川辺で「しょきしょき」と、小豆を洗うような音を立てる鯊。", enDesc="A goby that makes a sound like azuki beans being washed by the river."),
    dict(id="seoto_ayu", ja="サラアユ", en="Saraayu", kindJa="瀬音鮎", kindEn="Rapids Ayu", element="water", rarity="common", time="day", weather="any", kg=[0.1, 0.5], shape="koi",
         c1="#8FA66B", c2="#F0E6A0", c3="#F2C94C", pattern="gradient", eyes="normal", mouth="small", body=[0.82, 0.88, 1.15], size=0.8, deco=[],
         jaDesc="瀬の音に合わせて泳ぐ。焼くと西瓜のような香りがする。", enDesc="Swims to the sound of the rapids. Smells like watermelon when grilled."),
    dict(id="koke_iwana", ja="コケナ", en="Kokena", kindJa="苔岩魚", kindEn="Moss Char", element="earth", rarity="common", time="any", weather="any", kg=[0.3, 1.5], shape="koi",
         c1="#4E5E3A", c2="#E8E0B0", c3="#E07A3A", pattern="spots", eyes="sleepy", mouth="frown", body=[0.95, 0.95, 1.1], deco=[],
         jaDesc="岩陰でじっとしているうちに、背中に苔が生えた。", enDesc="Sat so still under a rock that moss grew on its back."),
    dict(id="sasabune_medaka", ja="ササメダ", en="Sasameda", kindJa="笹舟目高", kindEn="Leaf-Boat Medaka", element="water", rarity="common", time="day", weather="sunny", kg=[0.05, 0.3], shape="koi",
         c1="#F2E6C8", c2="#7DBE5A", c3="#4C8C3A", pattern="belly", eyes="cute", mouth="o", body=[0.85, 0.9, 1], size=0.65, deco=["leaf"],
         jaDesc="子どもが流した笹舟に乗って、川を下ってきた。", enDesc="Rode down the river on a bamboo-leaf boat a child set afloat."),
    dict(id="ishinage_kajika", ja="ドボカジ", en="Dobokaji", kindJa="石投げ鰍", kindEn="Stone-Toss Sculpin", element="earth", rarity="common", time="night", weather="any", kg=[0.1, 0.8], shape="catfish",
         c1="#6E6A62", c2="#3E3A34", c3="#C9B48A", pattern="patches", eyes="angry", mouth="wide", body=[1.05, 0.8, 0.9], size=0.8, deco=[],
         jaDesc="夜の川原で、どぼんと石を投げこむ音の正体。", enDesc="The source of that splash, as if someone tossed a stone into the night river."),
    dict(id="yamanba_yamame", ja="ヤマンバメ", en="Yamanbame", kindJa="山姥山女魚", kindEn="Mountain-Hag Yamame", element="earth", rarity="uncommon", time="any", weather="any", kg=[0.3, 1.5], shape="koi",
         c1="#A7A9B8", c2="#4A4E6A", c3="#F2EEE6", pattern="patches", eyes="angry", mouth="grin", body=[0.9, 0.95, 1.1], deco=["hair"],
         jaDesc="山奥の渓流に住む。白い乱れ髪をなびかせ、近づく者をにらむ。", enDesc="Lives in remote mountain streams, glaring at intruders through wild white hair."),
    dict(id="kawaakago_namazu", ja="オギャナマ", en="Ogyanama", kindJa="川赤子鯰", kindEn="River-Baby Catfish", element="spirit", rarity="uncommon", time="night", weather="any", kg=[0.5, 2.5], shape="catfish",
         c1="#F2A7A0", c2="#FFE3DA", c3="#D96B6B", pattern="belly", eyes="cute", mouth="open", body=[0.95, 0.95, 0.9], deco=["blush", "whiskers"],
         jaDesc="夜の川から赤ん坊の泣き声。近づくと、泣いていたのは鯰だった。", enDesc="A baby crying from the night river... it turned out to be a catfish."),
    dict(id="kawauso_haze", ja="オラウソ", en="Orauso", kindJa="川獺鯊", kindEn="River-Otter Goby", element="earth", rarity="uncommon", time="day", weather="any", kg=[0.3, 1.2], shape="catfish",
         c1="#8A5A3A", c2="#E8D2B0", c3="#4A3020", pattern="belly", eyes="cute", mouth="smile", size=0.85, deco=["ears", "hat", "whiskers"],
         jaDesc="笠をかぶって子どもに化けるのが得意。「誰だ」と聞くと「おら」と答える。", enDesc="Loves disguising itself as a child in a straw hat. Ask who it is and it says \"Me.\""),
    dict(id="hashihime_ayu", ja="ヒメアユ", en="Himeayu", kindJa="橋姫鮎", kindEn="Bridge-Princess Ayu", element="spirit", rarity="uncommon", time="night", weather="any", kg=[0.2, 0.8], shape="koi",
         c1="#E8D8E8", c2="#B07AB0", c3="#6A3A6A", pattern="gradient", eyes="sleepy", mouth="small", body=[0.85, 0.9, 1.1], deco=["kanzashi", "hair"],
         jaDesc="古い橋の下に住む。橋の上でほかの川をほめると機嫌が悪くなる。", enDesc="Lives under an old bridge. Praise another river while standing on it and it sulks."),
    dict(id="kitsunebi_ayu", ja="ヒノコン", en="Hinokon", kindJa="狐火鮎", kindEn="Foxfire Ayu", element="fire", rarity="uncommon", time="night", weather="any", kg=[0.3, 1.2], shape="koi",
         c1="#E8893A", c2="#FFE7B8", c3="#7AD8FF", pattern="belly", eyes="sleepy", mouth="smile", size=0.9, deco=["ears", "flame"],
         jaDesc="尾びれに狐火をともして泳ぐ。", enDesc="Swims with a foxfire flame on its tail."),
    dict(id="shirohebi_unagi", ja="シュルリ", en="Shururi", kindJa="白蛇鰻", kindEn="White Serpent Eel", element="water", rarity="rare", time="any", weather="any", kg=[1, 4], shape="eel",
         c1="#F4F2EC", c2="#E8E0D0", c3="#E8485A", pattern="belly", eyes="normal", mouth="tongue", deco=["shimenawa"],
         jaDesc="川の神の使い。見た者にはお金が貯まるという。", enDesc="Messenger of the river god. Whoever sees it will grow rich, they say."),
    dict(id="kawatengu_yamame", ja="ハナタカ", en="Hanataka", kindJa="川天狗山女魚", kindEn="River-Tengu Yamame", element="thunder", rarity="rare", time="any", weather="thunder", kg=[1, 4], shape="koi",
         c1="#C0392B", c2="#F2D0A4", c3="#2B2222", pattern="patches", eyes="angry", mouth="frown", deco=["nose", "crest"],
         jaDesc="雷が鳴ると川へ下りてくる天狗の山女魚。網を破るいたずら者。", enDesc="Comes down to the river when thunder rolls. A tengu prankster that tears nets."),
    dict(id="kawaguma_namazu", ja="クマナマ", en="Kumanama", kindJa="川熊鯰", kindEn="River-Bear Catfish", element="earth", rarity="rare", time="night", weather="any", kg=[3, 10], shape="catfish",
         c1="#4A3626", c2="#7A5A40", c3="#E8D2B0", pattern="belly", eyes="angry", mouth="fangs", body=[1.15, 1.05, 1.05], deco=["ears", "whiskers"],
         jaDesc="毛むくじゃらの腕で、舟から刀を奪っていく川の熊の妖怪。", enDesc="A river-bear yokai that snatches swords from boats with a hairy arm."),
    dict(id="ikada_ei", ja="イカダマズ", en="Ikadamazu", kindJa="筏鯰", kindEn="Raft Catfish", element="earth", rarity="rare", time="any", weather="rain", kg=[2, 8], shape="catfish",
         c1="#A07A4A", c2="#6A4A2A", c3="#E8C27A", pattern="stripes", eyes="dot", mouth="wide", body=[1.4, 0.6, 1.1], deco=["whiskers"],
         jaDesc="雨で増えた川を、筏のふりをして下ってくる。上に乗ると怒る。", enDesc="Drifts down rain-swollen rivers pretending to be a raft. Gets angry if you stand on it."),
    dict(id="kappa_oyabun", ja="ドンカッパ", en="Donkappa", kindJa="河童の親分", kindEn="Kappa Boss", element="water", rarity="epic", time="any", weather="any", kg=[5, 20], shape="puffer",
         c1="#4F9A5A", c2="#E8D88A", c3="#2E5A34", pattern="belly", eyes="angry", mouth="beak", body=[1.15, 1.05, 1.05], deco=["crown", "smooth"],
         jaDesc="川の河童をたばねる親分。頭の皿の水が減ると、急におとなしくなる。", enDesc="Boss of the river kappa. Goes quiet when the water in its head dish runs low."),
    dict(id="kawahime_koi", ja="セセラヒメ", en="Seserahime", kindJa="川姫鯉", kindEn="River-Princess Koi", element="spirit", rarity="epic", time="night", weather="fog", kg=[2, 8], shape="koi",
         c1="#F4F0FA", c2="#9FB8E8", c3="#E86A9A", pattern="gradient", eyes="sleepy", mouth="smile", tails=3, deco=["hair", "frills", "kanzashi"],
         jaDesc="霧の夜の川辺に現れる美しい鯉。見とれていると、精を吸われるという。", enDesc="A beautiful koi of foggy riversides. Stare too long and it drains your spirit."),
    dict(id="toryu_koi", ja="ノボリュウ", en="Noboryu", kindJa="登竜鯉", kindEn="Dragon-Climb Koi", element="thunder", rarity="epic", time="morning", weather="any", kg=[3, 12], shape="koi",
         c1="#FFB547", c2="#E8483B", c3="#FFE9A3", pattern="patches", eyes="angry", mouth="small", body=[1, 1.05, 1.1], deco=["whiskers", "antlers"],
         jaDesc="滝を登りきれば龍になれると信じて、毎朝跳び続ける鯉。", enDesc="Believes it will become a dragon if it climbs the falls, so it leaps every morning."),
    dict(id="maboroshi_itou", ja="シカノミ", en="Shikanomi", kindJa="幻の伊富魚", kindEn="Phantom Huchen", element="water", rarity="legendary", time="any", weather="any", kg=[20, 60], shape="salmon",
         c1="#6A4A3A", c2="#C24A3A", c3="#E8D8B0", pattern="spots", eyes="angry", mouth="fangs", deco=[],
         jaDesc="鹿をも飲みこむという、川の幻の大魚。見た者はほとんどいない。", enDesc="A phantom giant of the river said to swallow deer whole. Few have ever seen it."),
    dict(id="suiko", ja="トラッパ", en="Torappa", kindJa="水虎", kindEn="Suiko", element="thunder", rarity="legendary", time="night", weather="rain", kg=[10, 40], shape="catfish",
         c1="#D98A2B", c2="#2A1A10", c3="#F2E6C8", pattern="stripes", eyes="angry", mouth="fangs", body=[1.2, 1.1, 1.15], deco=["crown", "horns"],
         jaDesc="河童たちの長。虎のような縞と鱗を持ち、雨の夜に川を荒らす。", enDesc="Elder of all kappa. Tiger-striped and scaled, it ravages rivers on rainy nights."),
    dict(id="o_hanzaki", ja="ゴンザキ", en="Gonzaki", kindJa="大はんざき", kindEn="Great Hanzaki", element="earth", rarity="mythic", time="any", weather="any", kg=[50, 200], shape="salamander",
         c1="#5A4A36", c2="#2E261C", c3="#C9B48A", pattern="spots", eyes="dot", mouth="wide", deco=["shimenawa"],
         jaDesc="牛をも丸のみにしたという、川の主の大山椒魚。今は神として祀られている。", enDesc="The river lord, a giant salamander said to have swallowed a cow. Now worshipped as a god."),
    dict(id="sake_no_osuke", ja="オオスケ", en="Osuke", kindJa="鮭の大助", kindEn="Osuke the Salmon King", element="water", rarity="secret", time="night", weather="any", kg=[60, 250], shape="salmon",
         c1="#8A2A2A", c2="#E8C27A", c3="#FFE38A", pattern="gradient", eyes="angry", mouth="fangs", deco=["crest", "flame"],
         jaDesc="年に一度の夜、「鮭の大助、今のぼる」と名乗りながら川を上る鮭の王。", enDesc="Once a year, on one night, the salmon king swims upriver announcing \"Osuke the salmon, coming up!\""),
]

# ---- 海(33種) ----
# 海: 鯛・鰯・飛魚・鰹・鮪・太刀魚・河豚・鮟鱇・鱏・海蛇・鮫・鯱・鯨。強い魚は磯撫で(鮫)・金鯱・赤えい・海坊主・化け鯨・あやかし
SEA = [
    dict(id="ebisu_dai", ja="メデタイ", en="Medetai", kindJa="恵比寿鯛", kindEn="Ebisu Sea Bream", element="water", rarity="common", time="any", weather="any", kg=[0.5, 2.5], shape="koi",
         c1="#E8485A", c2="#FFD0D6", c3="#FFD34D", pattern="belly", eyes="cute", mouth="smile", body=[1.15, 1.15, 0.9], deco=["blush"],
         jaDesc="恵比寿さまが抱えていた鯛。釣れるとその日はいいことがある。", enDesc="The sea bream Ebisu holds. Catch one and your day goes well."),
    dict(id="iwashi_kozo", ja="イワッコ", en="Iwakko", kindJa="鰯小僧", kindEn="Sardine Kid", element="water", rarity="common", time="any", weather="any", kg=[0.05, 0.3], shape="koi",
         c1="#7FA8C8", c2="#E8F0F6", c3="#2E4A6A", pattern="belly", eyes="dot", mouth="o", body=[0.8, 0.85, 1.1], size=0.65, deco=["okappa"],
         jaDesc="群れで泳ぐ小僧。一匹だけ釣れると、ちょっとさびしそう。", enDesc="A kid that swims in schools. Caught alone, it looks a little lonely."),
    dict(id="kaze_tobiuo", ja="トビカゼ", en="Tobikaze", kindJa="風切り飛魚", kindEn="Wind-Cutter Flying Fish", element="thunder", rarity="common", time="day", weather="sunny", kg=[0.2, 0.8], shape="koi",
         c1="#3A6AB8", c2="#E8F4FF", c3="#7CC6FF", pattern="belly", eyes="normal", mouth="small", body=[0.85, 0.85, 1.15], deco=["frills"],
         jaDesc="晴れた日には、波の上を百歩も飛ぶ。", enDesc="On sunny days it glides a hundred paces over the waves."),
    dict(id="hako_fugu", ja="ハコプク", en="Hakopuku", kindJa="箱河豚", kindEn="Box Puffer", element="earth", rarity="common", time="day", weather="any", kg=[0.2, 1], shape="puffer",
         c1="#F2C94C", c2="#2A2A2A", c3="#4A8AC8", pattern="spots", eyes="cute", mouth="o", body=[1.05, 1, 1.1], deco=["smooth"],
         jaDesc="四角い体で、まじめに泳ぐ。箱の中身は誰も知らない。", enDesc="Swims earnestly in its boxy body. No one knows what's inside the box."),
    dict(id="kage_tachiuo", ja="カゲタチ", en="Kagetachi", kindJa="影太刀魚", kindEn="Shadow Cutlassfish", element="spirit", rarity="common", time="night", weather="any", kg=[0.3, 1.5], shape="eel",
         c1="#D8E0E8", c2="#A0B0C0", c3="#3A4A5A", pattern="gradient", eyes="normal", mouth="fangs", body=[0.85, 1, 1.1], deco=[],
         jaDesc="月の夜、刀のように立って泳ぐ。影を斬られると眠くなる。", enDesc="Swims upright like a sword on moonlit nights. If it cuts your shadow, you get sleepy."),
    dict(id="kawara_ei", ja="カタコト", en="Katakoto", kindJa="瓦鱏", kindEn="Roof-Tile Ray", element="earth", rarity="common", time="night", weather="any", kg=[0.8, 2.5], shape="ray",
         c1="#5D6470", c2="#3E434C", c3="#9AA3B0", pattern="stripes", eyes="dot", mouth="none", deco=[],
         jaDesc="海辺の古い寺の瓦がはがれて、夜の海を泳ぎ出した。", enDesc="A roof tile from a seaside temple that slid off and swam into the night sea."),
    dict(id="geta_fugu", ja="カラコロ", en="Karakoro", kindJa="下駄河豚", kindEn="Geta Puffer", element="water", rarity="common", time="any", weather="rain", kg=[0.3, 1.4], shape="puffer",
         c1="#C69C6D", c2="#7A5230", c3="#D7263D", pattern="saddle", eyes="normal", mouth="geta", deco=[],
         jaDesc="雨の日、からんころんと下駄の音を鳴らして泳ぐ。", enDesc="On rainy days it clip-clops like wooden sandals."),
    dict(id="kaminari_katsuo", ja="ビリカツ", en="Birikatsu", kindJa="雷鰹", kindEn="Thunder Bonito", element="thunder", rarity="uncommon", time="any", weather="any", kg=[1, 4], shape="koi",
         c1="#2E4A7A", c2="#E8EEF6", c3="#FFD84A", pattern="stripes", eyes="angry", mouth="small", body=[1, 1, 1.1], deco=[],
         jaDesc="雷のような速さで泳ぎ、止まると息ができない。", enDesc="Swims as fast as lightning, and can't breathe if it stops."),
    dict(id="ningyo", ja="ウミウタ", en="Umiuta", kindJa="人魚", kindEn="Ningyo", element="spirit", rarity="uncommon", time="night", weather="any", kg=[1, 4], shape="koi",
         c1="#F2D8C8", c2="#7AB8C8", c3="#E86A8A", pattern="gradient", eyes="cute", mouth="smile", deco=["hair", "blush"],
         jaDesc="人の顔を持つ魚。その肉を食べると八百年生きるという。", enDesc="A fish with a human face. Eating its flesh is said to grant 800 years of life."),
    dict(id="funayurei_ei", ja="ヒシャクレ", en="Hishakure", kindJa="船幽霊鱏", kindEn="Ship-Ghost Ray", element="spirit", rarity="uncommon", time="any", weather="fog", kg=[1, 4], shape="ray",
         c1="#DCE6EE", c2="#A8B8C8", c3="#5A6A8A", pattern="belly", eyes="glow", mouth="open", deco=["glow"],
         jaDesc="霧の海で「柄杓を貸せ」とささやく。底の抜けた柄杓を渡すとよい。", enDesc="Whispers \"lend me a ladle\" in the sea fog. Hand it one with no bottom."),
    dict(id="umi_osho", ja="ナムナム", en="Namunamu", kindJa="海和尚", kindEn="Sea Monk", element="water", rarity="uncommon", time="any", weather="rain", kg=[2, 6], shape="puffer",
         c1="#6A7A5A", c2="#C8B890", c3="#3A4A2A", pattern="belly", eyes="sleepy", mouth="small", deco=["bighead", "beard", "smooth"],
         jaDesc="坊主頭の海の妖怪。雨の日に網にかかり、涙を流して逃がしてもらう。", enDesc="A bald-headed sea yokai. Caught in nets on rainy days, it weeps until released."),
    dict(id="bake_fugu", ja="ポコプー", en="Pokopoo", kindJa="化け河豚", kindEn="Trickster Puffer", element="spirit", rarity="uncommon", time="any", weather="any", kg=[0.5, 2], shape="puffer",
         c1="#D79A3E", c2="#6B4520", c3="#6FAF4A", pattern="saddle", eyes="cute", mouth="smile", deco=["leaf", "blush", "smooth"],
         jaDesc="狸に化け方を教わった河豚。", enDesc="A puffer that learned shapeshifting from a tanuki."),
    dict(id="tengu_ei", ja="ドヤエイ", en="Doyaei", kindJa="天狗鱏", kindEn="Tengu Ray", element="thunder", rarity="uncommon", time="any", weather="any", kg=[1, 3], shape="ray",
         c1="#C0392B", c2="#F2D0A4", c3="#2B2222", pattern="belly", eyes="angry", mouth="none", deco=["nose", "crest"],
         jaDesc="鼻が高く、いつも得意げに泳ぐ。", enDesc="Long-nosed and always swimming proudly."),
    dict(id="ittan_ei", ja="ヒラリン", en="Hirarin", kindJa="一反木綿鱏", kindEn="Ittan-Momen Ray", element="spirit", rarity="uncommon", time="any", weather="fog", kg=[0.5, 2], shape="ray",
         c1="#F2F0E8", c2="#DCD6C8", c3="#A79F8E", pattern="belly", eyes="dot", mouth="none", deco=["cloth"],
         jaDesc="霧の夜、一反の布のようにひらひらと泳ぐ。", enDesc="On foggy nights it flutters like a long strip of cloth."),
    dict(id="tsurube_fugu", ja="ツルベン", en="Tsuruben", kindJa="釣瓶河豚", kindEn="Tsurube Puffer", element="earth", rarity="uncommon", time="night", weather="any", kg=[1, 3], shape="puffer",
         c1="#8B5A2B", c2="#5C3A1A", c3="#F2D16B", pattern="stripes", eyes="angry", mouth="grin", deco=["crest"],
         jaDesc="夜道の木の上から、どすんと落ちてくる大きな頭。", enDesc="A huge head that drops from trees onto night roads."),
    dict(id="maguro_daimyo", ja="トノマグロ", en="Tonomaguro", kindJa="鮪大名", kindEn="Tuna Daimyo", element="water", rarity="rare", time="any", weather="any", kg=[8, 30], shape="koi",
         c1="#1E2A4A", c2="#C8D0E0", c3="#FFD34D", pattern="belly", eyes="angry", mouth="frown", body=[1.15, 1.15, 1.15], deco=["crest"],
         jaDesc="大海原を大名行列で渡っていく、鮪の殿さま。", enDesc="A tuna lord making its grand procession across the ocean."),
    dict(id="kurage_anko", ja="ポワアンコ", en="Powaanko", kindJa="海月鮟鱇", kindEn="Jellyfish Angler", element="fire", rarity="rare", time="night", weather="any", kg=[2, 8], shape="angler",
         c1="#2A1E3A", c2="#8AE8FF", c3="#E8F8FF", pattern="spots", eyes="glow", mouth="grin", deco=["lantern", "glow"],
         jaDesc="深い海で、海月のような灯りをゆらして獲物を誘う。", enDesc="In the deep sea it sways a jellyfish-like light to lure prey."),
    dict(id="tomokazuki", ja="モウヒトリ", en="Mouhitori", kindJa="共潜き", kindEn="Tomokazuki", element="spirit", rarity="rare", time="any", weather="fog", kg=[2, 6], shape="koi",
         c1="#E8E0D0", c2="#3A3A4A", c3="#8AB8C8", pattern="patches", eyes="dot", mouth="smile", deco=["hair"],
         jaDesc="霧の海に潜ると、もう一人の自分が手招きする。それがこの魚だ。", enDesc="Dive in a foggy sea and a second you beckons. That's this fish."),
    dict(id="shima_umihebi", ja="シマシャー", en="Shimasha", kindJa="縞海蛇", kindEn="Banded Sea Snake", element="earth", rarity="rare", time="any", weather="rain", kg=[1, 5], shape="eel",
         c1="#2A2A3A", c2="#D8E0F0", c3="#4A8AC8", pattern="stripes", eyes="angry", mouth="tongue", deco=[],
         jaDesc="白と黒の縞の海蛇。雨の日に浜へ上がってくる。", enDesc="A black-and-white banded sea snake that comes ashore on rainy days."),
    dict(id="chochin_anko", ja="テラシー", en="Terashee", kindJa="提灯あんこう", kindEn="Lantern Angler", element="fire", rarity="rare", time="night", weather="any", kg=[1.5, 5], shape="angler",
         c1="#35264A", c2="#FF9E3D", c3="#FFCE6B", pattern="spots", eyes="cute", mouth="grin", deco=["lantern"],
         jaDesc="深い海の底から、祭りの提灯のような灯りをぶら下げて上がってきた。", enDesc="Rose from the deep sea dangling a light like a festival lantern."),
    dict(id="karakasa_fugu", ja="ベロカサ", en="Berokasa", kindJa="唐傘河豚", kindEn="Umbrella Puffer", element="spirit", rarity="rare", time="any", weather="rain", kg=[0.8, 3], shape="puffer",
         c1="#D8443C", c2="#F7E9D7", c3="#C79A4B", pattern="stripes", eyes="big", mouth="tongue", deco=["umbrella", "smooth"],
         jaDesc="雨が降ると傘のように広がる。", enDesc="Opens up like an umbrella when it rains."),
    dict(id="yukionna_ei", ja="ツララ", en="Tsurara", kindJa="雪女鱏", kindEn="Yuki-Onna Ray", element="water", rarity="rare", time="any", weather="fog", kg=[1, 4], shape="ray",
         c1="#BFDDF5", c2="#EAF6FF", c3="#1C2A3A", pattern="belly", eyes="sleepy", mouth="small", deco=["hair", "glow"],
         jaDesc="北の冷たい海に住む。触れた水が一瞬で凍る。", enDesc="Lives in cold northern seas. Water freezes the instant it touches it."),
    dict(id="ushioni_ei", ja="ブモエイ", en="Bumoei", kindJa="牛鬼鱏", kindEn="Ushi-Oni Ray", element="earth", rarity="rare", time="any", weather="rain", kg=[3, 9], shape="ray",
         c1="#3B2F2A", c2="#8A2B2B", c3="#E8D7B0", pattern="spots", eyes="angry", mouth="fangs", deco=["horns"],
         jaDesc="雨の日の磯に現れる、牛の頭を持つ鱏。", enDesc="An ox-headed ray that haunts rocky shores on rainy days."),
    dict(id="jinbe_zame", ja="ノホホン", en="Nohohon", kindJa="甚兵衛鮫", kindEn="Jinbe Whale Shark", element="water", rarity="epic", time="any", weather="any", kg=[40, 150], shape="shark",
         c1="#2E4A6A", c2="#E8F0F6", c3="#9FC6D6", pattern="spots", eyes="sleepy", mouth="smile", body=[1.15, 1.05, 1.15], size=1.1, deco=[],
         jaDesc="海でいちばん大きな魚。のんびり屋で、人なつっこい。", enDesc="The biggest fish in the sea. Laid-back and friendly."),
    dict(id="shiranui_ei", ja="ヌイヌイ", en="Nuinui", kindJa="不知火鱏", kindEn="Shiranui Ray", element="fire", rarity="epic", time="night", weather="any", kg=[10, 40], shape="ray",
         c1="#3A1A2A", c2="#FF7A2E", c3="#FFD34D", pattern="spots", eyes="glow", mouth="none", deco=["flame", "glow"],
         jaDesc="夜の海に並んで灯る怪しい火。その正体は、光る鱏の群れだった。", enDesc="Mysterious fires lined up on the night sea... they were glowing rays."),
    dict(id="ryugu_tsukai", ja="オシラセ", en="Oshirase", kindJa="竜宮の使い", kindEn="Oarfish", element="spirit", rarity="epic", time="any", weather="fog", kg=[10, 50], shape="eel",
         c1="#E8ECF2", c2="#9FB0C8", c3="#E8485A", pattern="belly", eyes="normal", mouth="small", body=[0.9, 1.1, 1.3], deco=["mane"],
         jaDesc="竜宮から地上へ知らせを運ぶ使い。赤いたてがみが目印。", enDesc="A messenger carrying news from the Dragon Palace. Known by its red mane."),
    dict(id="fujin_ei", ja="カゼブクロ", en="Kazebukuro", kindJa="風神鱏", kindEn="Fujin Ray", element="thunder", rarity="epic", time="any", weather="any", kg=[4, 12], shape="ray",
         c1="#3E8E5E", c2="#CDE8B0", c3="#F2F0E8", pattern="belly", eyes="angry", mouth="fangs", deco=["wind_bag", "horns"],
         jaDesc="雷神の相棒。背中の風袋で嵐を起こす。", enDesc="Raijin's partner. Its wind bag stirs up storms."),
    dict(id="isonade", ja="ナデザメ", en="Nadezame", kindJa="磯撫で", kindEn="Isonade", element="water", rarity="legendary", time="any", weather="any", kg=[80, 300], shape="shark",
         c1="#3A4A5A", c2="#C8D0D8", c3="#E8F0F6", pattern="belly", eyes="angry", mouth="jaws", size=1.1, deco=["frills"],
         jaDesc="尾びれの針で、船の人をなでるように引きこむ北の海の大鮫。", enDesc="A great shark of the northern seas that snags sailors with the barbs on its tail."),
    dict(id="kin_shachi", ja="キンシャッチ", en="Kinshacchi", kindJa="金鯱", kindEn="Golden Shachihoko", element="water", rarity="legendary", time="day", weather="sunny", kg=[50, 200], shape="orca",
         c1="#E8A92A", c2="#FFF0C0", c3="#FFE38A", pattern="orca", eyes="angry", mouth="fangs", deco=["ears", "crest"],
         jaDesc="城の屋根から海へ帰ってきた金の鯱。火を消す水を吹く。", enDesc="A golden shachihoko returned to the sea from a castle roof. It spouts water that douses fire."),
    dict(id="akaei", ja="ウキシマ", en="Ukishima", kindJa="赤えい", kindEn="Akaei", element="earth", rarity="legendary", time="any", weather="fog", kg=[100, 500], shape="ray",
         c1="#A83A2A", c2="#E8A07A", c3="#F2D8B0", pattern="spots", eyes="sleepy", mouth="none", size=1.25, deco=["leaf"],
         jaDesc="背中に砂がつもり、島とまちがえて船が着いたという巨大な鱏。", enDesc="A ray so huge that sand piled on its back and sailors landed on it, mistaking it for an island."),
    dict(id="umibozu_ei", ja="ウミボン", en="Umibon", kindJa="海坊主鯱", kindEn="Umibozu Orca", element="water", rarity="legendary", time="any", weather="rain", kg=[8, 30], shape="orca",
         c1="#16182A", c2="#C9D2F5", c3="#6E7BD6", pattern="orca", eyes="big", mouth="none", size=1.1, deco=["bighead", "glow"],
         jaDesc="嵐の海に立ち上がる黒い大入道。漁師はその目を見ると逃げ出す。", enDesc="A black giant that rises from stormy seas. Fishermen flee at the sight of its eye."),
    dict(id="bake_kujira", ja="ホネクジ", en="Honekuji", kindJa="化け鯨", kindEn="Bake-Kujira", element="spirit", rarity="mythic", time="any", weather="any", kg=[300, 1500], shape="whale",
         c1="#DCE2E8", c2="#55657A", c3="#8AE8FF", pattern="ribs", eyes="glow", mouth="none", size=1.2, deco=["glow"],
         jaDesc="骨だけになっても海を泳ぎ続ける白い鯨。怪しい鳥と魚を連れている。", enDesc="A white whale that keeps swimming even as bare bones, trailed by eerie birds and fish."),
    dict(id="ayakashi", ja="アヤカシ", en="Ayakashi", kindJa="あやかし", kindEn="Ayakashi", element="spirit", rarity="secret", time="night", weather="fog", kg=[500, 3000], shape="eel",
         c1="#2A1E4A", c2="#6AE8C8", c3="#FFD34D", pattern="gradient", eyes="glow", mouth="fangs", body=[1.15, 1.15, 1.2], size=1.2, deco=["mane", "horns", "glow"],
         jaDesc="船の横を通り過ぎるのに何日もかかるほど長い、海の大妖怪。あやかし釣りの名の由来。", enDesc="A sea yokai so long it takes days to pass a ship. The legend this game is named after."),
]

LOOK_KEYS = ["shape", "c1", "c2", "c3", "pattern", "eyes", "mouth", "body", "tails", "deco", "size"]

def lua_val(v):
    if isinstance(v, str):
        return json.dumps(v, ensure_ascii=False)
    if isinstance(v, bool):
        return "true" if v else "false"
    if isinstance(v, (int, float)):
        return repr(v) if isinstance(v, float) else str(v)
    if isinstance(v, list):
        return "{ " + ", ".join(lua_val(x) for x in v) + " }" if v else "{}"
    raise TypeError(v)

ORDER = ["id", "ja", "en", "kindJa", "kindEn", "element", "rarity", "time", "weather", "kg", "shape", "c1", "c2", "c3", "pattern", "eyes", "mouth", "body", "tails", "deco", "size", "jaDesc", "enDesc"]

def row(f):
    parts = []
    for k in ORDER:
        if k in f and f[k] is not None:
            parts.append(f"{k} = {lua_val(f[k])}")
    return "\t{ " + ", ".join(parts) + " },"

HEADER = """--!strict
-- {title}。1行 = 1匹。tools/fish_designs.py で生成(デザインの意図は docs/FISH_DESIGN.md)。
--   id      : 一意な英数字(保存データのキーになるので、公開後に変更しないこと)
--   ja / en : 名前(カタカナのあだ名と、その読み)
--   kindJa / kindEn : 種類(もとになった魚と妖怪。図鑑と釣果の画面に小さく出る)
--   element : 属性 water(水) / fire(火) / thunder(雷) / earth(土) / spirit(霊)  ※相棒バトル用
--   rarity  : common / uncommon / rare / epic / legendary / mythic / secret
--   time    : any / day / night / morning(朝。昼にも含まれる)
--   weather : any / sunny / rain / fog / thunder
--   kg      : 重さの範囲 {{ 最小, 最大 }}
--   shape   : koi(鯉) / catfish(鯰) / puffer(河豚) / eel(鰻) / angler(提灯) / ray(鱏) / shark(鮫) / orca(鯱) / salmon(鮭) / salamander(山椒魚) / whale(鯨) / sturgeon(蝶鮫)
--   c1, c2, c3 : 色(体, 模様, 差し色)
--   pattern : plain / stripes / spots / belly / patches / saddle / gradient / ribs / dango / orca(鯱の白黒)
--   eyes    : normal / cute / angry / sleepy / big(一つ目) / cat / glow / dot / none
--   mouth   : small / wide / o / smile / frown / open / tongue / fangs / grin / geta / beak / jaws(鮫の歯) / none
--   body    : 体つき {{ 幅, 高さ, 長さ }} の倍率 / tails : 尾の本数 / size : 大きさの微調整(レア度の大きさに掛け算)
--   deco    : 飾り(一覧は Config/init.luau の DECOS)
--   jaDesc / enDesc : 図鑑の説明
-- レア度の格(大きさ・ツヤ・縁取り・金・後光)は FishBuilder が自動で付ける。

local F = {{
{rows}
}}

return F
"""

def main():
    for var, title, name in ((SWAMP, "沼", "Swamp"), (LAKE, "ぬしの湖", "NushiLake"), (RIVER, "川", "River"), (SEA, "海", "Sea")):
        open(os.path.join(ROOT, f"src/shared/Config/Fish/{name}.luau"), "w").write(
            HEADER.format(title=f"{title}の妖怪魚({len(var)}種)", rows="\n".join(row(f) for f in var)))
    print("wrote", len(SWAMP), "+", len(LAKE), "+", len(RIVER), "+", len(SEA))


if __name__ == "__main__":
    main()
