# Roblox のデータ削除依頼への対応

Roblox から削除依頼を受けた場合の運用手順です。公開担当者が Creator Dashboard で設定・確認してください。この文書を追加しただけでは、Roblox 側の設定や実際の削除は完了しません。

## 自動削除の設定

1. [Roblox の公式手順](https://create.roblox.com/docs/cloud-services/data-stores/right-to-be-forgotten)を開き、対象のゲームの Creator Dashboard → Configurations → Data stores manager → RTBF Deletion で削除テンプレートを作成します。画面や権限要件が変わっていないか、公開前に公式手順を再確認してください。
2. 次の各保存先について、Standard は「Standard Key」、Ordered は「Ordered Key」を選んで作成します。キーのパターンは **`{UserId}`**、スコープは **`global`** です。大文字小文字もそのまま入力してください。各プレイヤーの Roblox ユーザー ID を文字列にしたキーに、成績や順位の数値を保存しています。

| 保存先 | 種類 | 内容 |
| --- | --- | --- |
| `MinatoStats_v1` | Standard | 成績、レート、保存済みレースの情報 |
| `MinatoRating_v1` | Ordered | レート順位 |
| `MinatoWins_v1` | Ordered | １着数順位 |
| `MinatoBestTimeMs_v1` | Ordered | ベストタイム順位 |

3. Studio の API アクセスを有効にして試験したことがあり、試験用の記録も残っている場合は、上の４つに加えて `MinatoStats_studio_v1`、`MinatoRating_studio_v1`、`MinatoWins_studio_v1`、`MinatoBestTimeMs_studio_v1` にも同じ種類・キー・スコープで設定します。実際に使った保存先の名前を `PlayerStats.lua` と Dashboard で照合してください。
4. 作成した全テンプレートを保存・公開し、Dashboard で反映を確認します。以後 Roblox の削除依頼は公式の仕組みで処理されます。対象、処理状況、失敗時の対応は公開担当者が公式画面と通知で確認してください。

## 依頼を受けたとき

- Roblox の正式な通知・手順に従い、対象 ID と削除処理の状態を確認します。ユーザー名や ID を公開の作業ログに記載しないでください。自動削除の設定前に受けた依頼が自動処理されるとは限らないため、個別に確認してください。
- Roblox の保存先以外に対象者の情報を保管している場合は、その保管先も含めて削除します。バックアップや外部の記録の確認も公開担当者の責任です。部屋の合言葉に関する一時情報は期限付きですが、依頼時には有効な部屋情報も確認してください。
- 成績の保存やランキングの再送が動作中だと、削除後に記録が再作成される可能性があります。個別に削除する場合は、対象者を含む稼働中のサーバーと保存の再試行が終わっていることを確認し、必要に応じて稼働を止めてから実施し、再開後も４種類すべてを確認してください。
- 通常の `RemoveAsync` は過去の保存バージョンを直ちに完全消去しないため、これだけで永久削除済みと判断しないでください。手作業が必要な場合は、[Roblox のバージョン管理の公式手順](https://create.roblox.com/docs/cloud-services/data-stores/versioning-listing-and-caching)と最新の削除依頼手順に従い、過去バージョンを含めて処理・確認してください。
- 作業完了の報告には、実施日、対象の保存先、処理結果を記載し、本人を特定できる情報は必要最小限の安全な場所だけで管理します。

## フレンド部屋の一時情報

`MinatoRooms_v1`（Studio 試験時は `MinatoRooms_studio_v1`）は、部屋を作った人の ID と、移動途中の人の ID を期限付きで保持します。標準の DataStore の削除テンプレートとは別です。部屋は作成から２時間で使えなくなり、最後の更新から２時間以内に記録も自動消去されます（作成から最大約４時間）。一時記録の確認・削除の必要性と期限は Roblox の依頼内容に従ってください。

すぐに確認・削除する必要がある場合、公開担当者はまず対象者の新たな部屋作成・参加や保存の再試行を止め、[MemoryStore の公式手順](https://create.roblox.com/docs/cloud-services/memory-stores/hash-map)に従って両方の該当マップを `ListItemsAsync` で全ページ確認します。各項目の `owner` が対象 ID の部屋は、他の参加者にも影響することを考慮して終了し、対応するキーを `RemoveAsync` で削除します。`tickets` の文字列キーが対象 ID の項目は、`UpdateAsync` で対象のチケットだけを取り除きます。削除対象を取り違えないよう変更直前にも ID と値を確認し、通信失敗は再試行して全ページを再確認してください。合言葉・内部移動先・ユーザー ID を公開ログへ出力しないでください。削除操作や本番の停止は、この手順書の作成時には実施していません。
