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
	"auto_pause_on_alert": false,
	"max_log_lines": 12,
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
	return a if a is Array else []


func get_enemies() -> Array:
	var e: Variant = units.get("enemies", [])
	return e if e is Array else []


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
