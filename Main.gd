extends Node2D

# ============================================================
# Main.gd
# 戦闘全体の管理役。
#   - 味方4体・敵3体を生成して配置する
#   - スペースキーで一時停止 / 再開（独自フラグ方式）
#   - 戦闘ログ（色分け・フィルタ付き）を表示する
#   - HP低下アラート（警告表示・ビープ音・自動一時停止）
#   - 全滅したら勝敗を表示する
# ============================================================

# 一時停止フラグ。各 Unit はこれを見て動きを止める。
var is_paused: bool = false

# --- HP低下アラート設定 ---
var low_hp_threshold: float = 0.3   # この割合を下回ると警告
var alarm_on: bool = true           # ビープ音を鳴らすか
var auto_pause_on_alert: bool = false  # 警告時に自動で一時停止するか

# ------------------------------------------------------------
# ★ログの色設定★ ここを書き換えれば色を自由に変えられます
# ------------------------------------------------------------
var LOG_COLORS: Dictionary = {
	"attack":  Color(0.85, 0.85, 0.85),  # 攻撃 = 薄いグレー
	"heal":    Color(0.40, 0.95, 0.55),  # 回復 = 緑
	"retreat": Color(0.95, 0.85, 0.35),  # 後退 = 黄
	"death":   Color(0.95, 0.45, 0.45),  # 撃破 = 赤
	"warn":    Color(1.00, 0.55, 0.15),  # 警告 = オレンジ
	"system":  Color(0.55, 0.80, 1.00),  # システム = 水色
}

const MAX_LOG_LINES: int = 12
const MAX_LOG_HISTORY: int = 300

# ログ1件 = { "text": String, "category": String, "faction": String }
var _log_entries: Array = []

# --- フィルタ状態 ---
var _show_faction: Dictionary = { "ally": true, "enemy": true, "system": true }
var _show_category: Dictionary = {
	"attack": true, "heal": true, "retreat": true, "death": true, "system": true,
}
var _filter_target: String = ""  # 空 = 全員

var _battle_over: bool = false

# UI
var _units_node: Node2D
var _log_label: RichTextLabel
var _pause_label: Label
var _alert_label: Label
var _result_label: Label
var _target_option: OptionButton

# 音
var _beep_player: AudioStreamPlayer


func _ready() -> void:
	add_to_group("main")
	_setup_audio()
	_build_ui()
	_spawn_units()
	log_message("戦闘開始！ スペースキーで一時停止 / 再開", "system", "system")


# スペースキーで一時停止トグル
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_SPACE:
			_toggle_pause()


func _toggle_pause() -> void:
	is_paused = not is_paused
	_pause_label.visible = is_paused
	log_message("―― 一時停止 ――" if is_paused else "―― 再開 ――", "system", "system")


func _process(_delta: float) -> void:
	if _battle_over:
		return
	var allies: int = _count_alive("ally")
	var enemies: int = _count_alive("enemy")
	if enemies == 0:
		_end_battle("勝利！ 敵を全滅させた")
	elif allies == 0:
		_end_battle("敗北… 味方が全滅した")


func _count_alive(group_name: String) -> int:
	var n: int = 0
	for u in get_tree().get_nodes_in_group(group_name):
		if u.is_alive():
			n += 1
	return n


func _end_battle(text: String) -> void:
	_battle_over = true
	_result_label.text = text
	_result_label.visible = true
	log_message("=== %s ===" % text, "system", "system")


# ============================================================
# HP低下アラート（Unit.take_damage から呼ばれる）
# ============================================================
func on_low_hp(unit: Unit) -> void:
	var pct: int = int(round(low_hp_threshold * 100.0))
	log_message("⚠ %s のHPが%d%%を下回った" % [unit.unit_name, pct], "warn", unit.team_name())
	_flash_alert(unit.unit_name)
	if alarm_on:
		_play_beep()
	if auto_pause_on_alert and not is_paused:
		_toggle_pause()


func _flash_alert(unit_name: String) -> void:
	_alert_label.text = "⚠ %s HP低下！" % unit_name
	_alert_label.modulate.a = 1.0
	_alert_label.visible = true
	var tw: Tween = create_tween()
	tw.tween_property(_alert_label, "modulate:a", 0.0, 1.8)
	tw.tween_callback(func() -> void: _alert_label.visible = false)


func _play_beep() -> void:
	if _beep_player:
		_beep_player.play()


# ============================================================
# 戦闘ログ
# ============================================================
# category: attack / heal / retreat / death / warn / system
# faction : ally / enemy / system
func log_message(text: String, category: String = "system", faction: String = "system") -> void:
	_log_entries.append({ "text": text, "category": category, "faction": faction })
	if _log_entries.size() > MAX_LOG_HISTORY:
		_log_entries.pop_front()
	_refresh_log()


func _refresh_log() -> void:
	if _log_label == null:
		return
	var lines: Array[String] = []
	for e in _log_entries:
		if not _passes_filter(e):
			continue
		var col: Color = LOG_COLORS.get(e["category"], Color.WHITE)
		lines.append("[color=#%s]%s[/color]" % [col.to_html(false), e["text"]])
	if lines.size() > MAX_LOG_LINES:
		lines = lines.slice(lines.size() - MAX_LOG_LINES)
	_log_label.text = "\n".join(lines)


func _passes_filter(entry: Dictionary) -> bool:
	# 対象キャラ抜粋
	if _filter_target != "" and not entry["text"].contains(_filter_target):
		return false
	# 陣営フィルタ
	if not _show_faction.get(entry["faction"], true):
		return false
	# 種類フィルタ（warn は「システム」に含めて扱う）
	var key: String = entry["category"]
	if key == "warn":
		key = "system"
	if not _show_category.get(key, true):
		return false
	return true


# ============================================================
# 音（外部ファイル不要。短いビープをコードで合成）
# ============================================================
func _setup_audio() -> void:
	_beep_player = AudioStreamPlayer.new()
	_beep_player.stream = _make_beep(880.0, 0.18, 0.5)
	add_child(_beep_player)


func _make_beep(freq: float, secs: float, volume: float) -> AudioStreamWAV:
	var rate: int = 22050
	var count: int = int(rate * secs)
	var data: PackedByteArray = PackedByteArray()
	data.resize(count * 2)  # 16bit モノラル
	for i in count:
		var t: float = float(i) / float(rate)
		var env: float = 1.0 - (float(i) / float(count))  # だんだん小さく
		var s: float = sin(TAU * freq * t) * volume * env
		var v: int = int(clamp(s, -1.0, 1.0) * 32767.0)
		data.encode_s16(i * 2, v)
	var wav: AudioStreamWAV = AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = rate
	wav.stereo = false
	wav.data = data
	return wav


# ============================================================
# ユニット生成
# ============================================================
func _spawn_units() -> void:
	_units_node = Node2D.new()
	_units_node.name = "Units"
	add_child(_units_node)

	var view: Vector2 = get_viewport_rect().size

	# --- 味方4体（丸） ---
	var allies: Array = [
		{
			"name": "タロウ(前衛)", "role": "Frontline",
			"max_hp": 160, "attack": 14, "move_speed": 70.0,
			"attack_range": 48.0, "attack_cooldown": 0.9,
			"radius": 18.0, "color": Color(0.30, 0.55, 1.00),
		},
		{
			"name": "レン(射撃)", "role": "Shooter",
			"max_hp": 90, "attack": 18, "move_speed": 65.0,
			"attack_range": 230.0, "attack_cooldown": 1.1,
			"radius": 15.0, "color": Color(0.30, 0.85, 0.90),
		},
		{
			"name": "ミナ(衛生)", "role": "Medic",
			"max_hp": 110, "attack": 8, "heal_power": 16, "move_speed": 75.0,
			"attack_range": 90.0, "attack_cooldown": 1.3,
			"radius": 15.0, "color": Color(0.30, 0.90, 0.50),
		},
		{
			"name": "アキラ(支援)", "role": "Support",
			"max_hp": 110, "attack": 12, "move_speed": 70.0,
			"attack_range": 150.0, "attack_cooldown": 1.0,
			"radius": 15.0, "color": Color(0.95, 0.85, 0.30),
		},
	]

	# --- 敵3体（四角） ---
	var enemies: Array = [
		{
			"name": "Raider", "role": "Raider",
			"max_hp": 120, "attack": 12, "move_speed": 70.0,
			"attack_range": 48.0, "attack_cooldown": 1.0,
			"radius": 16.0, "color": Color(0.90, 0.35, 0.30),
		},
		{
			"name": "EnemyShooter", "role": "Shooter",
			"max_hp": 80, "attack": 16, "move_speed": 60.0,
			"attack_range": 210.0, "attack_cooldown": 1.2,
			"radius": 15.0, "color": Color(0.90, 0.50, 0.30),
		},
		{
			"name": "Brute", "role": "Brute",
			"max_hp": 220, "attack": 20, "move_speed": 40.0,
			"attack_range": 50.0, "attack_cooldown": 1.6,
			"radius": 22.0, "color": Color(0.70, 0.25, 0.35),
		},
	]

	_place_team(allies, Unit.Team.ALLY, view.x * 0.20, view)
	_place_team(enemies, Unit.Team.ENEMY, view.x * 0.80, view)


# 1チームを縦に並べて配置する
func _place_team(list: Array, team: int, x: float, view: Vector2) -> void:
	var n: int = list.size()
	var top: float = view.y * 0.18
	var bottom: float = view.y * 0.62  # 画面下のログ欄に重ならない高さ
	for i in n:
		var data: Dictionary = list[i]
		data["team"] = team

		var u: Unit = Unit.new()
		u.setup(data)
		u.battle = self

		var y: float
		if n > 1:
			y = top + (bottom - top) * float(i) / float(n - 1)
		else:
			y = (top + bottom) * 0.5
		u.position = Vector2(x, y)

		_units_node.add_child(u)

		# フィルタの「対象キャラ」候補に追加
		if _target_option:
			_target_option.add_item(u.unit_name)


# ============================================================
# UI（コードで生成）
# ============================================================
func _build_ui() -> void:
	var layer: CanvasLayer = CanvasLayer.new()
	add_child(layer)

	# 戦闘ログの背景（画面下）
	var log_bg: ColorRect = ColorRect.new()
	log_bg.color = Color(0.0, 0.0, 0.0, 0.6)
	log_bg.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	log_bg.offset_top = -210.0
	log_bg.offset_bottom = 0.0
	log_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(log_bg)

	# 戦闘ログ本体（色分けのため BBCode を有効化）
	_log_label = RichTextLabel.new()
	_log_label.bbcode_enabled = true
	_log_label.scroll_following = true
	_log_label.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_log_label.offset_top = -200.0
	_log_label.offset_bottom = -8.0
	_log_label.offset_left = 12.0
	_log_label.offset_right = -12.0
	_log_label.add_theme_font_size_override("normal_font_size", 15)
	layer.add_child(_log_label)

	_build_filter_panel(layer)

	# 「PAUSED」表示
	_pause_label = Label.new()
	_pause_label.text = "● PAUSED （スペースで再開）"
	_pause_label.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_pause_label.offset_top = 12.0
	_pause_label.offset_bottom = 50.0
	_pause_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_pause_label.add_theme_font_size_override("font_size", 26)
	_pause_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.2))
	_pause_label.visible = false
	layer.add_child(_pause_label)

	# HP低下アラート表示（一瞬光って消える）
	_alert_label = Label.new()
	_alert_label.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_alert_label.offset_top = 52.0
	_alert_label.offset_bottom = 92.0
	_alert_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_alert_label.add_theme_font_size_override("font_size", 30)
	_alert_label.add_theme_color_override("font_color", Color(1.0, 0.4, 0.2))
	_alert_label.visible = false
	layer.add_child(_alert_label)

	# 勝敗の結果表示
	_result_label = Label.new()
	_result_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	_result_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_result_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_result_label.add_theme_font_size_override("font_size", 48)
	_result_label.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0))
	_result_label.visible = false
	layer.add_child(_result_label)


# 右上のログ表示切替パネル
func _build_filter_panel(layer: CanvasLayer) -> void:
	var panel: PanelContainer = PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	panel.offset_left = -220.0
	panel.offset_right = -8.0
	panel.offset_top = 8.0
	panel.offset_bottom = 430.0

	var sb: StyleBoxFlat = StyleBoxFlat.new()
	sb.bg_color = Color(0.0, 0.0, 0.0, 0.55)
	sb.set_content_margin_all(8.0)
	panel.add_theme_stylebox_override("panel", sb)
	layer.add_child(panel)

	var box: VBoxContainer = VBoxContainer.new()
	panel.add_child(box)

	box.add_child(_make_header("― ログ表示 ―"))
	box.add_child(_make_check("味方", true, _on_faction_toggled.bind("ally")))
	box.add_child(_make_check("敵", true, _on_faction_toggled.bind("enemy")))
	box.add_child(_make_check("システム", true, _on_faction_toggled.bind("system")))

	box.add_child(_make_header("― 種類 ―"))
	box.add_child(_make_check("攻撃", true, _on_category_toggled.bind("attack")))
	box.add_child(_make_check("回復", true, _on_category_toggled.bind("heal")))
	box.add_child(_make_check("後退", true, _on_category_toggled.bind("retreat")))
	box.add_child(_make_check("撃破", true, _on_category_toggled.bind("death")))

	box.add_child(_make_header("― 対象キャラ ―"))
	_target_option = OptionButton.new()
	_target_option.focus_mode = Control.FOCUS_NONE
	_target_option.add_item("全員")  # index 0
	_target_option.item_selected.connect(_on_target_selected)
	box.add_child(_target_option)

	box.add_child(_make_header("― アラート ―"))
	box.add_child(_make_check("HP低下で一時停止", false, _on_autopause_toggled))
	box.add_child(_make_check("アラーム音", true, _on_alarm_toggled))


# CheckBox から呼ばれるハンドラ群（bind で陣営/種類のキーを渡す）
func _on_faction_toggled(pressed: bool, key: String) -> void:
	_show_faction[key] = pressed
	_refresh_log()


func _on_category_toggled(pressed: bool, key: String) -> void:
	_show_category[key] = pressed
	_refresh_log()


func _on_autopause_toggled(pressed: bool) -> void:
	auto_pause_on_alert = pressed


func _on_alarm_toggled(pressed: bool) -> void:
	alarm_on = pressed


func _make_header(text: String) -> Label:
	var l: Label = Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 13)
	l.add_theme_color_override("font_color", Color(0.7, 0.85, 1.0))
	return l


func _make_check(text: String, pressed: bool, callback: Callable) -> CheckBox:
	var c: CheckBox = CheckBox.new()
	c.text = text
	c.button_pressed = pressed
	c.focus_mode = Control.FOCUS_NONE  # スペースキーを奪わせない
	c.add_theme_font_size_override("font_size", 14)
	c.toggled.connect(callback)
	return c


func _on_target_selected(index: int) -> void:
	if index == 0:
		_filter_target = ""
	else:
		_filter_target = _target_option.get_item_text(index)
	_refresh_log()
