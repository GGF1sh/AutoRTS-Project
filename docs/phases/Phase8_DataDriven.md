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
- 設計の相談事項 → [../ideas/DESIGN_QUESTIONS.md](../ideas/DESIGN_QUESTIONS.md)

---

# v0.8.1 追記 — ログ色分け・ゲーム内CONFIG UI・ログ保存設定

- **日付**: 2026-06-15 / **担当**: Claude

## 追加内容（ユーザー要望）

1. **ログ内のキャラ名を色分け**: ダメージ等が白系の行でも、ユニット名はそのキャラ色で表示（`_name_colors` 登録 → `_colorize_names()` で BBCode の入れ子色）。
2. **ログ保存をデフォルトOFF＋ON/OFF＋保存先選択**:
   - `log_save_enabled`（既定 false）。ONのときだけ戦闘終了時に自動保存。
   - 「今すぐ手動保存」ボタンは常時可。
   - 「保存先を選ぶ」で `FileDialog`(OPEN_DIR) からフォルダ指定 → `log_save_dir`。
3. **ゲーム内CONFIG UI**: 右上パネルを `ScrollContainer` 化し、設定をその場で編集:
   - HP警告%・ログ行数の `HSlider`
   - HP低下で一時停止 / アラーム音の `CheckBox`
   - ログ6種の色を `ColorPickerButton` で変更
   - 編集した設定は「現在の設定を保存」で名前付きプリセット化（user://）。
   - プリセット切替時はスライダー/チェック/カラーピッカーも `_suppress_ui_signal` ガード付きで追従。

## 保留（→ DESIGN_QUESTIONS.md）

- セミオート指揮（ホールド/索敵攻撃/ムーブアタック）とガンビット切替
- 信頼度（俺屍）/ ゲージ発動＆バフ（ブルアカ）
- ステージクリア成長 vs ローグライト
