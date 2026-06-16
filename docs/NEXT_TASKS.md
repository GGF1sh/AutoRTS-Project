# 次やることリスト（新チャット引き継ぎ用）

最終更新: 2026-06-16 / 現行: **v0.9.5**（protect_ally＝盾役が後衛を守る連携まで実装済み）

新しいチャットを開いたら、まず `docs/VERSION_HISTORY.md` と `docs/ai-log/` を読んで状況把握してから着手すること。

## 直近の状態

- 構成: `scripts/`(Main/Unit/Hud/Fx/AudioBank/GameData) `scenes/Main.tscn` `data/*.json` `docs/`。
- 戦闘: 味方5 vs 敵5、ガンビット自律、後退の安全距離・衛生兵退避・自己回復・戦線復帰、focus_fire（味方集中攻撃）。
- UI: biim式レイアウト、設定パネル（プリセット/色/フィルタ/保存）、ログ色分け＋バックログ。
- 観察: **R=再戦**、Space=一時停止。

## 3AIレビューの合意（優先度つき）

### 最優先：チーム連携をさらに強化（Grok最推奨）
- ✅ `focus_fire`（v0.9.4で実装）
- ✅ `protect_ally`（v0.9.5で実装。盾役Frontlineが狙われた後衛と敵の間へ割り込み、射程内なら迎撃）
- 🔲 `retreat_then_return`（下がった後、安全になったら再接近）※現状は戦線復帰で近い挙動
- 🔲 「前衛が引いたら後衛も下がる」等の連動

### 次点：戦闘ループ／リザルト（ChatGPT最推奨, バックログPhase 9）
- 🔲 戦闘後リザルト画面（撃破数・生存・かかった時間など）
- 🔲 連戦（勝ったら次の敵編成へ）／ステージ選択
- 🔲 観察用シナリオプリセット（1v1, 全近接, 衛生兵入り 等の構成を選べる）

### プレイヤー介入（Grok次点・ChatGPTは後回し推奨）
- 🔲 一時停止中にクリックでユニット選択→「この敵を集中」「ここへ移動」命令
- DESIGN_QUESTIONS Q1: 「隊長命令としての一時的な上書き」が4AIの推し（FF12式）

### 技術・リファクタ
- 🔲 `Hud._refresh_log` を全文再構築→`append_text` で1行追加方式に（Gemini: ログ長大化時のスパイク対策）
- 🔲 `Unit.gd` の分割（条件評価/行動実行/ターゲット探索）（ChatGPT: 次の肥大化対策）
- 🔲 ガンビット定義の `user://` 対応（Gemini/Grok: エクスポート後にユーザー編集を保存可能に）
- メモ: `globalize_path` はWeb非対応（PC前提なので現状OK）

## 別途記録済みの設計論点

- `docs/ideas/DESIGN_QUESTIONS.md` … Q1操作方式 / Q2信頼度・ゲージ / Q3ローグライト / Q4 ZoC・地形
- `docs/ideas/USER_IDEAS.md` … AI小説化 / キャラ画像・性格 / ガンビット連動セリフ / エフェクト音 / ComfyUI

## 作業ルール（変更しないこと）

- main に直接コミット＆push（PR不要）。各Verで docs（VERSION_HISTORY/phases/ai-log）更新。
- Unit の `battle.*` インターフェースは安定させる（Main分割の境界）。
- 実装→ユーザーが実機確認→エラー報告→修正、のループ（Claude側にGodot無し）。
