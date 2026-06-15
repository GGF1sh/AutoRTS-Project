# Gemini 発言ログ

**役割**: Godot公式ドキュメント調査・実装方式の比較・技術的裏取り（Godot 4.6前提、3系の情報と混ぜない）

新しい発言を下に追記する。出典は Google Drive `GameCreate/docs` の各文書。

| 日付 | 対象Ver/フェーズ | 意見・成果物 | このプロジェクトへの反映 |
|---|---|---|---|
| 2026-06-15 11:23 | Phase 1 | **Godot_Tech_Proposal 作成**。推奨シーン構成を提示: Main(Node2D) / BattleField(Node2D) / UI_Layer(CanvasLayer) / Unit(Area2D: Sprite or ColorRect + CollisionShape2D)。 | 一部採用。Main+UI(CanvasLayer)構成は採用。Unitは当面クリック判定不要なので Area2D ではなく Node2D + `_draw()` で実装（Phase 1の簡素化）。 |
| 2026-06-15 11:23 | Phase 1（一時停止） | **一時停止の2方式を比較**。①独自フラグ方式（`is_paused` 変数）②Godot標準（`get_tree().paused`）。初心者には①を推奨（②はProcessMode設定ミスでUIごと止まる事故が多い）。 | ✅ **採用**。Main.is_paused 方式を採用。各Unitが `_process` 先頭で判定。 |
| 2026-06-15 11:23 | Phase 8 | **JSON連携のコツ**を提示。`FileAccess.open` + `JSON.parse_string` で読み込み、ルールは文字列で持ち `match` 文で分岐するのがベストプラクティス。 | ✅ v0.8.0 で採用。GameData.gd が FileAccess+JSON.parse_string で読み込み、Unit.gd の条件/行動は match 文で分岐。 |
| 2026-06-15 11:23 | Phase 1 | **Claudeへのパス**を明記:「丸と四角を描画して互いに近づく処理だけをまず書く」。 | ✅ 採用。Phase 1 の実装スコープの根拠。 |
