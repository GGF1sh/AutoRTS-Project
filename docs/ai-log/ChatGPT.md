# ChatGPT 発言ログ

**役割**: 企画整理・仕様書・設計・タスク分解（ゲームディレクター兼設計相談役）

新しい発言を下に追記する。出典は Google Drive `GameCreate/docs` の各文書。

| 日付 | 対象Ver/フェーズ | 意見・成果物 | このプロジェクトへの反映 |
|---|---|---|---|
| 2026-06-15 | 企画全体（Ver前） | **Project_Brief 作成**。最初から大作を作らず「仲間が賢く動く楽しさ」を最小プロトタイプで検証する方針を提示。Godot 4.6 / GDScript / 2Dトップダウンを推奨。 | ✅ 採用。プロジェクトの基本方針。 |
| 2026-06-15 | Phase 1〜 | **MVP_Spec 作成**。ユニット共通ステータス（hp/attack/defense/move_speed/attack_range/attack_cooldown/role）、味方4ロール（Frontline/Shooter/Medic/Support）、敵3タイプ（Raider/Shooter/Brute）、ガンビット最小仕様（条件→行動を上から評価）を定義。 | ✅ 採用。Unit.gd のステータス設計・ロール構成の元。 |
| 2026-06-15 | 全フェーズ | **Task_Backlog 作成**。Phase 0〜10 に作業を細分化。「1タスク1変更／動いたらコミット／一度に大改造しない」の作業ルールを提示。 | ✅ 採用。フェーズ進行の指針。Phase 1〜5を v0.1.0 でまとめて達成。 |
| 2026-06-15 | Phase 1 | **AI_Workflow_Prompts 作成**。4AIへの役割別プロンプトを定義。Claude=実装担当と明記。最初の実装依頼（味方/敵を丸四角で表示→接近→攻撃→Space一時停止→ログ）を記載。 | ✅ 採用。Claudeへの実装依頼の原型。 |

## メモ

- ChatGPTの初期MVP案は「味方2・敵2」だったが、Project_Brief/最終合意で「味方4・敵3〜5」に拡張された。v0.1.0 は味方4・敵3で実装。
