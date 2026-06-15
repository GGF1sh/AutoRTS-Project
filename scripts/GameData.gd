extends Node

# ============================================================
# GameData.gd（オートロード / シングルトン）
# data/*.json を起動時に読み込み、全シーンから参照できるようにする。
# ファイルが無い・壊れている場合も落ちないよう、コード側の既定値へ
# フォールバックする（ゲームは必ず起動する）。
# ============================================================

const UNITS_PATH: String = "res://data/units.json"
const GAMBITS_PATH: String = "res://data/gambits.json"
const CONFIG_PATH: String = "res://data/config.json"
const USER_PRESETS_PATH: String = "user://user_presets.json"

var units: Dictionary = {}      # { "allies": [...], "enemies": [...] }
var gambits: Dictionary = {}    # { role: [ {cond, action, param}, ... ] }
var config: Dictionary = {}     # config.json をそのまま
var presets: Dictionary = {}    # 組込み＋ユーザーのプリセットを統合
var active_preset_name: String = "標準"

# プリセットの既定値。JSON のプリセットはこの上にマージされる。
const DEFAULT_PRESET: Dictionary = {
	"low_hp_threshold": 0.3,
	"alarm_on": true,
	"sfx_on": true,
	"auto_pause_on_alert": false,
	"max_log_lines": 12,
	"log_save_enabled": false,
	"log_save_dir": "user://logs",
	"log_colors": {
		"attack": "#d9d9d9", "heal": "#66f28c", "retreat": "#f2d959",
		"death": "#f27373", "warn": "#ff8c26", "system": "#8cccff",
	},
}


func _ready() -> void:
	var u: Variant = _load_json(UNITS_PATH)
	units = u if u is Dictionary else {}

	var g: Variant = _load_json(GAMBITS_PATH)
	gambits = g if g is Dictionary else {}

	var c: Variant = _load_json(CONFIG_PATH)
	config = c if c is Dictionary else {}

	_build_presets()


# JSONを読み込む。失敗したら null を返す（呼び出し側でフォールバック）。
func _load_json(path: String) -> Variant:
	if not FileAccess.file_exists(path):
		push_warning("[GameData] JSONが見つかりません: %s" % path)
		return null
	var f: FileAccess = FileAccess.open(path, FileAccess.READ)
	if f == null:
		push_warning("[GameData] JSONを開けません: %s" % path)
		return null
	var text: String = f.get_as_text()
	var parsed: Variant = JSON.parse_string(text)
	if parsed == null:
		push_error("[GameData] JSON解析失敗: %s" % path)
	return parsed


func _build_presets() -> void:
	presets = {}

	# 組込みプリセット（config.json）
	var builtin: Dictionary = config.get("presets", {})
	for key in builtin.keys():
		presets[key] = _merge_preset(builtin[key])

	# 1つも無ければ既定を入れる
	if presets.is_empty():
		presets["標準"] = DEFAULT_PRESET.duplicate(true)

	# ユーザーのカスタムプリセット（user://）
	var user: Variant = _load_json(USER_PRESETS_PATH)
	if user is Dictionary:
		for key in user.keys():
			presets[key] = _merge_preset(user[key])

	# 初期適用するプリセット名
	active_preset_name = config.get("active_preset", presets.keys()[0])
	if not presets.has(active_preset_name):
		active_preset_name = presets.keys()[0]


# 部分的なプリセットを既定の上にマージして完全な辞書にする
func _merge_preset(p: Variant) -> Dictionary:
	var out: Dictionary = DEFAULT_PRESET.duplicate(true)
	if p is Dictionary:
		for key in p.keys():
			out[key] = p[key]
	return out


# ---------------- 参照用 API ----------------

func get_allies() -> Array:
	var a: Variant = units.get("allies", [])
	if a is Array and not a.is_empty():
		return a
	return _builtin_allies()


func get_enemies() -> Array:
	var e: Variant = units.get("enemies", [])
	if e is Array and not e.is_empty():
		return e
	return _builtin_enemies()


# data/units.json が読めない時のための内蔵フォールバック（色は #RRGGBB）
func _builtin_allies() -> Array:
	return [
		{ "name": "タロウ(前衛)", "role": "Frontline", "max_hp": 170, "attack": 14, "defense": 2,
			"move_speed": 72.0, "attack_range": 48.0, "attack_cooldown": 0.9, "radius": 18.0, "color": "#4d8cff" },
		{ "name": "ゴウ(重装)", "role": "Frontline", "max_hp": 240, "attack": 10, "defense": 5,
			"move_speed": 52.0, "attack_range": 50.0, "attack_cooldown": 1.4, "radius": 21.0, "color": "#3f6fd1" },
		{ "name": "レン(射撃)", "role": "Shooter", "max_hp": 90, "attack": 18,
			"move_speed": 66.0, "attack_range": 240.0, "attack_cooldown": 1.0, "radius": 15.0, "color": "#4dd9e6" },
		{ "name": "ミナ(衛生)", "role": "Medic", "max_hp": 110, "attack": 8, "heal_power": 18,
			"move_speed": 78.0, "attack_range": 95.0, "attack_cooldown": 1.2, "radius": 15.0, "color": "#4de680" },
		{ "name": "アキラ(支援)", "role": "Support", "max_hp": 110, "attack": 13,
			"move_speed": 72.0, "attack_range": 160.0, "attack_cooldown": 1.0, "radius": 15.0, "color": "#f2d94d" },
	]


func _builtin_enemies() -> Array:
	return [
		{ "name": "レイダー", "role": "Raider", "max_hp": 120, "attack": 12,
			"move_speed": 72.0, "attack_range": 48.0, "attack_cooldown": 1.0, "radius": 16.0, "color": "#e65a4d" },
		{ "name": "スカウト", "role": "Scout", "max_hp": 70, "attack": 10,
			"move_speed": 110.0, "attack_range": 46.0, "attack_cooldown": 0.7, "radius": 13.0, "color": "#e6a24d" },
		{ "name": "スナイパー", "role": "Shooter", "max_hp": 75, "attack": 22,
			"move_speed": 58.0, "attack_range": 260.0, "attack_cooldown": 1.6, "radius": 15.0, "color": "#e6804d" },
		{ "name": "敵衛生兵", "role": "Medic", "max_hp": 95, "attack": 7, "heal_power": 15,
			"move_speed": 74.0, "attack_range": 90.0, "attack_cooldown": 1.3, "radius": 14.0, "color": "#d46a8c" },
		{ "name": "ブルート", "role": "Brute", "max_hp": 240, "attack": 20, "defense": 3,
			"move_speed": 40.0, "attack_range": 52.0, "attack_cooldown": 1.6, "radius": 22.0, "color": "#b34059" },
	]


func get_gambits(role: String) -> Array:
	var g: Variant = gambits.get(role, [])
	return g if g is Array else []


func get_active_preset() -> Dictionary:
	return presets.get(active_preset_name, DEFAULT_PRESET.duplicate(true))


func get_preset(preset_name: String) -> Dictionary:
	return presets.get(preset_name, DEFAULT_PRESET.duplicate(true))


func get_preset_names() -> Array:
	return presets.keys()


# カスタムプリセットを user:// に保存し、メモリにも反映する
func save_user_preset(preset_name: String, preset: Dictionary) -> bool:
	var existing: Variant = _load_json(USER_PRESETS_PATH)
	var store: Dictionary = existing if existing is Dictionary else {}
	store[preset_name] = preset
	var f: FileAccess = FileAccess.open(USER_PRESETS_PATH, FileAccess.WRITE)
	if f == null:
		push_error("[GameData] プリセット保存に失敗: %s" % USER_PRESETS_PATH)
		return false
	f.store_string(JSON.stringify(store, "\t"))
	presets[preset_name] = _merge_preset(preset)
	return true
