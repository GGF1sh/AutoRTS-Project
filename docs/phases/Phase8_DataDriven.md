# Phase 8 実装記録 — v0.8.0（データ駆動化＋設定プリセット＋ログ保存）

- **バージョン**: v0.8.0
- **日付**: 2026-06-15
- **担当**: Claude（実装担当）
- **状態**: 実装完了（実機確認待ち）
- **備考**: 土台一括構築。ユーザー不在のため確認ステップを省略しまとめて実装。

## 目的

コードを触らず、JSONを編集するだけで〈ユニット・ガンビット・設定〉を変えられる土台を作る。さらに設定プリセット、戦闘ログ保存を追加。

## 追加・変更したファイル

| ファイル | 内容 |
|---|---|
| `data/units.json` | 敵味方ユニットのテンプレート（allies / enemies） |
| `data/gambits.json` | ロールごとのガンビット（条件→行動） |
| `data/config.json` | 設定プリセット（標準/アラート厳しめ/静音/ログ多め/暗色ログ） |
| `GameData.gd`（autoload） | JSON読み込み・フォールバック・プリセット統合・保存API |
| `project.godot` | `[autoload] GameData` を登録 |
| `Main.gd` | JSONからユニット生成、プリセット適用UI、ログ保存を追加 |
| `Unit.gd` | color を文字列(#RRGGBB)でも受理、gambits をデータから受け取る |

## 設計のポイント

### フォールバック前提（絶対に起動する）
- JSONが無い/壊れていても `GameData` は警告を出して空を返し、`Main` がコード内の `_fallback_allies()` / `_fallback_enemies()` を使う。
- ガンビットがJSONに無ければ `Unit._default_gambits()` を使う。
- 設定は `GameData.DEFAULT_PRESET` の上にJSONをマージするので欠損キーも安全。

### 設定プリセット
- 組込みプリセットは `config.json`。カスタムは `user://user_presets.json` に保存（永続）。
- ゲーム内・右上パネルで: プルダウン選択 / 「▶ 次のプリセットへ」巡回 / 名前を付けて「現在の設定を保存」。
- **他人の設定の採用**: JSONファイルなので、`user://user_presets.json` や `config.json` を配布・差し替えれば共有可能。

### 戦闘ログ保存
- 右上「戦闘ログを保存」ボタン＋戦闘終了時に自動保存。
- 保存先 `user://logs/battle_<日時>.txt`。〈参加ユニットの設定＋戦闘の流れ〉を書き出す。
- 用途: AIに渡して小説化（→ `docs/ideas/USER_IDEAS.md` の1番）。

## 編集方法（ユーザー向けメモ）

- **キャラを増やす/調整する**: `data/units.json` の allies / enemies に要素を足す・数値を変える。`color` は `#RRGGBB`。
- **AIの賢さを変える**: `data/gambits.json` のロール配列を編集（条件→行動を上から評価）。
- **設定の初期値**: `data/config.json` の `active_preset` と各プリセット。

## 既知の制約 / 次への申し送り

- ユニットの配置は今もコード（左右に縦並べ）。配置のJSON化は将来。
- セリフ・画像・性格・エフェクトは未実装（`docs/ideas/USER_IDEAS.md` に設計メモ）。
- MP は未実装。
- ゲーム内の色ピッカー等の設定UIは無し（プリセット/JSON編集で対応）。

## 関連

- 将来アイデアの一覧 → [../ideas/USER_IDEAS.md](../ideas/USER_IDEAS.md)
