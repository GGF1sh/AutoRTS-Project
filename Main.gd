extends Node2D

# ============================================================
# Main.gd
# 戦闘全体の管理役。
#   - data/units.json から味方・敵を生成（無ければコード既定）
#   - data/config.json のプリセットで設定を適用（ゲーム内で切替・保存）
#   - スペースキーで一時停止 / 再開（独自フラグ方式）
#   - 戦闘ログ（色分け・フィルタ・保存）
#   - HP低下アラート（警告表示・ビープ音・自動一時停止）
#   - 全滅で勝敗表示
# ============================================================

# 一時停止フラグ。各 Unit はこれを見て動きを止める。
var is_paused: bool = false

# --- 設定（プリセットから適用される） ---
var low_hp_threshold: float = 0.3
var alarm_on: bool = true
var auto_pause_on_alert: bool = false
var max_log_lines: int = 12

# --- ログ保存設定（デフォルトOFF） ---
var log_save_enabled: bool = false      # 戦闘終了時の自動保存
var log_save_dir: String = "user://logs"  # 保存先（フォルダ選択で変更可）

# ログの色（プリセットから読み込む。category 名 -> Color）
var LOG_COLORS: Dictionary = {
	"attack": Color(0.85, 0.85, 0.85), "heal": Color(0.40, 0.95, 0.55),
	"retreat": Color(0.95, 0.85, 0.35), "death": Color(0.95, 0.45, 0.45),
	"warn": Color(1.00, 0.55, 0.15), "system": Color(0.55, 0.80, 1.00),
}

const MAX_LOG_HISTORY: int = 300

# ログ1件 = { "text": String, "category": String, "faction": String }
var _log_entries: Array = []

# ユニット名 -> 色(#RRGGBB)。ログ中の名前を色分けするのに使う。
var _name_colors: Dictionary = {}

# --- フィルタ状態 ---
var _show_faction: Dictionary = { "ally": true, "enemy": true, "system": true }
var _show_category: Dictionary = {
	"attack": true, "heal": true, "retreat": true, "death": true, "system": true,
}
var _filter_target: String = ""

var _battle_over: bool = false

# UI
var _units_node: Node2D
var _log_label: RichTextLabel
var _pause_label: Label
var _alert_label: Label
var _result_label: Label
var _target_option: OptionButton
var _preset_option: OptionButton
var _preset_name_edit: LineEdit
var _chk_alarm: CheckBox
var _chk_autopause: CheckBox
var _chk_logsave: CheckBox
var _save_dir_label: Label
var _file_dialog: FileDialog
var _threshold_slider: HSlider
var _maxlines_slider: HSlider
var _color_buttons: Dictionary = {}     # category -> ColorPickerButton
var _suppress_ui_signal: bool = false   # プリセット適用中はUIのシグナルを無視

# 音
var _beep_player: AudioStreamPlayer


func _ready() -> void:
	add_to_group("main")
	_setup_audio()
	_build_ui()
	_apply_preset(GameData.active_preset_name)
	_spawn_units()
	log_message("戦闘開始！ スペースキーで一時停止 / 再開", "system", "system")


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
	if log_save_enabled:  # 自動保存はONのときだけ
		_save_log()


# ============================================================
# プリセット
# ============================================================
func _apply_preset(preset_name: String) -> void:
	if not GameData.presets.has(preset_name):
		return
	GameData.active_preset_name = preset_name
	var p: Dictionary = GameData.get_preset(preset_name)

	low_hp_threshold = float(p.get("low_hp_threshold", 0.3))
	alarm_on = bool(p.get("alarm_on", true))
	auto_pause_on_alert = bool(p.get("auto_pause_on_alert", false))
	max_log_lines = int(p.get("max_log_lines", 12))
	log_save_enabled = bool(p.get("log_save_enabled", false))
	log_save_dir = str(p.get("log_save_dir", "user://logs"))

	var colors: Dictionary = p.get("log_colors", {})
	for key in colors.keys():
		if colors[key] is String:
			LOG_COLORS[key] = Color.html(colors[key])

	# UIに反映（シグナルを出さずに状態だけ合わせる）
	_suppress_ui_signal = true
	if _chk_alarm:
		_chk_alarm.set_pressed_no_signal(alarm_on)
	if _chk_autopause:
		_chk_autopause.set_pressed_no_signal(auto_pause_on_alert)
	if _threshold_slider:
		_threshold_slider.value = low_hp_threshold * 100.0
	if _maxlines_slider:
		_maxlines_slider.value = float(max_log_lines)
	if _chk_logsave:
		_chk_logsave.set_pressed_no_signal(log_save_enabled)
	if _save_dir_label:
		_save_dir_label.text = log_save_dir
	for k in _color_buttons.keys():
		if LOG_COLORS.has(k):
			_color_buttons[k].color = LOG_COLORS[k]
	_suppress_ui_signal = false

	_refresh_log()
	log_message("プリセット「%s」を適用" % preset_name, "system", "system")


func _on_preset_selected(index: int) -> void:
	_apply_preset(_preset_option.get_item_text(index))


# 1ボタンで次のプリセットへ巡回
func _cycle_preset() -> void:
	var names: Array = GameData.get_preset_names()
	if names.is_empty():
		return
	var i: int = names.find(GameData.active_preset_name)
	var next_name: String = names[(i + 1) % names.size()]
	_select_preset_in_dropdown(next_name)
	_apply_preset(next_name)


func _save_current_as_preset() -> void:
	var preset_name: String = _preset_name_edit.text.strip_edges()
	if preset_name == "":
		preset_name = "カスタム"
	var preset: Dictionary = {
		"low_hp_threshold": low_hp_threshold,
		"alarm_on": alarm_on,
		"auto_pause_on_alert": auto_pause_on_alert,
		"max_log_lines": max_log_lines,
		"log_save_enabled": log_save_enabled,
		"log_save_dir": log_save_dir,
		"log_colors": _colors_to_hex(),
	}
	if GameData.save_user_preset(preset_name, preset):
		_repopulate_preset_dropdown(preset_name)
		log_message("プリセット「%s」を保存しました" % preset_name, "system", "system")
	else:
		log_message("プリセットの保存に失敗しました", "warn", "system")


func _colors_to_hex() -> Dictionary:
	var out: Dictionary = {}
	for key in LOG_COLORS.keys():
		out[key] = "#" + LOG_COLORS[key].to_html(false)
	return out


func _repopulate_preset_dropdown(select_name: String) -> void:
	if _preset_option == null:
		return
	_preset_option.clear()
	for n in GameData.get_preset_names():
		_preset_option.add_item(n)
	_select_preset_in_dropdown(select_name)


func _select_preset_in_dropdown(target_name: String) -> void:
	for i in _preset_option.item_count:
		if _preset_option.get_item_text(i) == target_name:
			_preset_option.select(i)
			return


# ============================================================
# HP低下アラート
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
		var base_hex: String = LOG_COLORS.get(e["category"], Color.WHITE).to_html(false)
		var body: String = _colorize_names(e["text"], base_hex)
		lines.append("[color=#%s]%s[/color]" % [base_hex, body])
	if lines.size() > max_log_lines:
		lines = lines.slice(lines.size() - max_log_lines)
	_log_label.text = "\n".join(lines)


# ログ本文中のユニット名を、そのキャラの色に染める。
# 外側の [color=base] の中で名前部分だけ別色にし、閉じると base に戻る。
func _colorize_names(text: String, base_hex: String) -> String:
	var s: String = text
	for uname in _name_colors.keys():
		if uname in s:
			s = s.replace(uname, "[color=#%s]%s[/color]" % [_name_colors[uname], uname])
	return s


func _passes_filter(entry: Dictionary) -> bool:
	if _filter_target != "" and not entry["text"].contains(_filter_target):
		return false
	if not _show_faction.get(entry["faction"], true):
		return false
	var key: String = entry["category"]
	if key == "warn":
		key = "system"
	if not _show_category.get(key, true):
		return false
	return true


# ログ＋参加ユニット設定を user://logs/ にテキスト保存（AIに食わせる素材用）
func _save_log() -> void:
	var dir: String = log_save_dir
	DirAccess.make_dir_recursive_absolute(dir)
	var stamp: String = Time.get_datetime_string_from_system().replace(":", "-").replace("T", "_")
	var path: String = "%s/battle_%s.txt" % [dir, stamp]
	var f: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		log_message("ログ保存に失敗しました", "warn", "system")
		return

	f.store_line("=== 戦闘ログ ===")
	f.store_line("日時: %s" % Time.get_datetime_string_from_system())
	f.store_line("")
	f.store_line("--- 参加ユニット ---")
	for u in get_tree().get_nodes_in_group("units"):
		f.store_line("[%s] %s / role=%s / HP%d ATK%d DEF%d HEAL%d / 速度%d 射程%d 間隔%.1f" % [
			u.team_name(), u.unit_name, u.role,
			u.max_hp, u.attack_power, u.defense, u.heal_power,
			int(u.move_speed), int(u.attack_range), u.attack_cooldown,
		])
	f.store_line("")
	f.store_line("--- 戦闘の流れ ---")
	for e in _log_entries:
		f.store_line(e["text"])

	var full: String = ProjectSettings.globalize_path(path)
	log_message("ログを保存: %s" % full, "system", "system")


# ============================================================
# 音
# ============================================================
func _setup_audio() -> void:
	_beep_player = AudioStreamPlayer.new()
	_beep_player.stream = _make_beep(880.0, 0.18, 0.5)
	add_child(_beep_player)


func _make_beep(freq: float, secs: float, volume: float) -> AudioStreamWAV:
	var rate: int = 22050
	var count: int = int(rate * secs)
	var data: PackedByteArray = PackedByteArray()
	data.resize(count * 2)
	for i in count:
		var t: float = float(i) / float(rate)
		var env: float = 1.0 - (float(i) / float(count))
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
# ユニット生成（JSON優先、無ければコード既定）
# ============================================================
func _spawn_units() -> void:
	_units_node = Node2D.new()
	_units_node.name = "Units"
	add_child(_units_node)

	var view: Vector2 = get_viewport_rect().size

	var allies: Array = GameData.get_allies()
	if allies.is_empty():
		allies = _fallback_allies()
	var enemies: Array = GameData.get_enemies()
	if enemies.is_empty():
		enemies = _fallback_enemies()

	_place_team(allies, Unit.Team.ALLY, view.x * 0.20, view)
	_place_team(enemies, Unit.Team.ENEMY, view.x * 0.80, view)


func _place_team(list: Array, team: int, x: float, view: Vector2) -> void:
	var n: int = list.size()
	var top: float = view.y * 0.18
	var bottom: float = view.y * 0.62
	for i in n:
		# JSONの辞書を壊さないよう複製してから team / gambits を足す
		var data: Dictionary = (list[i] as Dictionary).duplicate(true)
		data["team"] = team
		if not data.has("gambits"):
			var gl: Array = GameData.get_gambits(data.get("role", ""))
			if not gl.is_empty():
				data["gambits"] = gl

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

		# ログ用に「名前 -> 色」を登録
		_name_colors[u.unit_name] = u.base_color.to_html(false)

		if _target_option:
			_target_option.add_item(u.unit_name)


# JSONが読めない時のための最低限のフォールバック
func _fallback_allies() -> Array:
	return [
		{ "name": "タロウ(前衛)", "role": "Frontline", "max_hp": 160, "attack": 14,
			"move_speed": 70.0, "attack_range": 48.0, "attack_cooldown": 0.9,
			"radius": 18.0, "color": Color(0.30, 0.55, 1.00) },
		{ "name": "レン(射撃)", "role": "Shooter", "max_hp": 90, "attack": 18,
			"move_speed": 65.0, "attack_range": 230.0, "attack_cooldown": 1.1,
			"radius": 15.0, "color": Color(0.30, 0.85, 0.90) },
		{ "name": "ミナ(衛生)", "role": "Medic", "max_hp": 110, "attack": 8, "heal_power": 16,
			"move_speed": 75.0, "attack_range": 90.0, "attack_cooldown": 1.3,
			"radius": 15.0, "color": Color(0.30, 0.90, 0.50) },
		{ "name": "アキラ(支援)", "role": "Support", "max_hp": 110, "attack": 12,
			"move_speed": 70.0, "attack_range": 150.0, "attack_cooldown": 1.0,
			"radius": 15.0, "color": Color(0.95, 0.85, 0.30) },
	]


func _fallback_enemies() -> Array:
	return [
		{ "name": "Raider", "role": "Raider", "max_hp": 120, "attack": 12,
			"move_speed": 70.0, "attack_range": 48.0, "attack_cooldown": 1.0,
			"radius": 16.0, "color": Color(0.90, 0.35, 0.30) },
		{ "name": "EnemyShooter", "role": "Shooter", "max_hp": 80, "attack": 16,
			"move_speed": 60.0, "attack_range": 210.0, "attack_cooldown": 1.2,
			"radius": 15.0, "color": Color(0.90, 0.50, 0.30) },
		{ "name": "Brute", "role": "Brute", "max_hp": 220, "attack": 20, "defense": 2,
			"move_speed": 40.0, "attack_range": 50.0, "attack_cooldown": 1.6,
			"radius": 22.0, "color": Color(0.70, 0.25, 0.35) },
	]


# ============================================================
# UI
# ============================================================
func _build_ui() -> void:
	var layer: CanvasLayer = CanvasLayer.new()
	add_child(layer)

	var log_bg: ColorRect = ColorRect.new()
	log_bg.color = Color(0.0, 0.0, 0.0, 0.6)
	log_bg.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	log_bg.offset_top = -210.0
	log_bg.offset_bottom = 0.0
	log_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(log_bg)

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

	_build_control_panel(layer)

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

	_alert_label = Label.new()
	_alert_label.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_alert_label.offset_top = 52.0
	_alert_label.offset_bottom = 92.0
	_alert_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_alert_label.add_theme_font_size_override("font_size", 30)
	_alert_label.add_theme_color_override("font_color", Color(1.0, 0.4, 0.2))
	_alert_label.visible = false
	layer.add_child(_alert_label)

	_result_label = Label.new()
	_result_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	_result_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_result_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_result_label.add_theme_font_size_override("font_size", 48)
	_result_label.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0))
	_result_label.visible = false
	layer.add_child(_result_label)


# 右上の設定パネル（スクロール可能）。ゲーム内CONFIGをここで完結。
func _build_control_panel(layer: CanvasLayer) -> void:
	var panel: PanelContainer = PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	panel.offset_left = -260.0
	panel.offset_right = -8.0
	panel.offset_top = 8.0
	panel.offset_bottom = get_viewport_rect().size.y - 220.0  # ログ欄の上で止める

	var sb: StyleBoxFlat = StyleBoxFlat.new()
	sb.bg_color = Color(0.0, 0.0, 0.0, 0.62)
	sb.set_content_margin_all(8.0)
	panel.add_theme_stylebox_override("panel", sb)
	layer.add_child(panel)

	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel.add_child(scroll)

	var box: VBoxContainer = VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.custom_minimum_size = Vector2(200, 0)
	scroll.add_child(box)

	# --- プリセット ---
	box.add_child(_make_header("― 設定プリセット ―"))
	_preset_option = OptionButton.new()
	_preset_option.focus_mode = Control.FOCUS_NONE
	for n in GameData.get_preset_names():
		_preset_option.add_item(n)
	_preset_option.item_selected.connect(_on_preset_selected)
	box.add_child(_preset_option)
	_select_preset_in_dropdown(GameData.active_preset_name)
	box.add_child(_make_button("▶ 次のプリセットへ", _cycle_preset))

	_preset_name_edit = LineEdit.new()
	_preset_name_edit.placeholder_text = "プリセット名"
	box.add_child(_preset_name_edit)
	box.add_child(_make_button("現在の設定を保存", _save_current_as_preset))

	# --- 設定（スライダー・チェック） ---
	box.add_child(_make_header("― 設定 ―"))
	_threshold_slider = _make_slider(5.0, 90.0, 5.0, low_hp_threshold * 100.0, _on_threshold_changed)
	box.add_child(_labeled_row("HP警告%", _threshold_slider))
	_maxlines_slider = _make_slider(5.0, 30.0, 1.0, float(max_log_lines), _on_maxlines_changed)
	box.add_child(_labeled_row("ログ行数", _maxlines_slider))
	_chk_autopause = _make_check("HP低下で一時停止", false, _on_autopause_toggled)
	box.add_child(_chk_autopause)
	_chk_alarm = _make_check("アラーム音", true, _on_alarm_toggled)
	box.add_child(_chk_alarm)

	# --- ログの色（カラーピッカー） ---
	box.add_child(_make_header("― ログの色 ―"))
	box.add_child(_make_color_row("攻撃", "attack"))
	box.add_child(_make_color_row("回復", "heal"))
	box.add_child(_make_color_row("後退", "retreat"))
	box.add_child(_make_color_row("撃破", "death"))
	box.add_child(_make_color_row("警告", "warn"))
	box.add_child(_make_color_row("システム", "system"))

	# --- ログ表示フィルタ ---
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
	_target_option.add_item("全員")
	_target_option.item_selected.connect(_on_target_selected)
	box.add_child(_target_option)

	# --- ログ保存（デフォルトOFF） ---
	box.add_child(_make_header("― ログ保存 ―"))
	_chk_logsave = _make_check("終了時に自動保存", false, _on_logsave_toggled)
	box.add_child(_chk_logsave)
	_save_dir_label = Label.new()
	_save_dir_label.text = log_save_dir
	_save_dir_label.add_theme_font_size_override("font_size", 11)
	_save_dir_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_save_dir_label)
	box.add_child(_make_button("保存先を選ぶ", _open_dir_dialog))
	box.add_child(_make_button("今すぐ手動保存", _save_log))

	# フォルダ選択ダイアログ
	_file_dialog = FileDialog.new()
	_file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_DIR
	_file_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_file_dialog.title = "ログ保存先フォルダを選択"
	_file_dialog.dir_selected.connect(_on_dir_selected)
	add_child(_file_dialog)


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
	c.focus_mode = Control.FOCUS_NONE
	c.add_theme_font_size_override("font_size", 14)
	c.toggled.connect(callback)
	return c


func _make_button(text: String, callback: Callable) -> Button:
	var b: Button = Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", 14)
	b.pressed.connect(callback)
	return b


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


func _on_target_selected(index: int) -> void:
	if index == 0:
		_filter_target = ""
	else:
		_filter_target = _target_option.get_item_text(index)
	_refresh_log()


# ---------------- 設定UIのヘルパー ----------------
func _make_slider(minv: float, maxv: float, step: float, value: float, callback: Callable) -> HSlider:
	var sl: HSlider = HSlider.new()
	sl.min_value = minv
	sl.max_value = maxv
	sl.step = step
	sl.value = value
	sl.focus_mode = Control.FOCUS_NONE
	sl.custom_minimum_size = Vector2(90, 0)
	sl.value_changed.connect(callback)
	return sl


func _labeled_row(label_text: String, control: Control) -> HBoxContainer:
	var row: HBoxContainer = HBoxContainer.new()
	var l: Label = Label.new()
	l.text = label_text
	l.custom_minimum_size = Vector2(86, 0)
	l.add_theme_font_size_override("font_size", 13)
	row.add_child(l)
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(control)
	return row


func _make_color_row(label_text: String, key: String) -> HBoxContainer:
	var cpb: ColorPickerButton = ColorPickerButton.new()
	cpb.color = LOG_COLORS.get(key, Color.WHITE)
	cpb.focus_mode = Control.FOCUS_NONE
	cpb.custom_minimum_size = Vector2(60, 24)
	cpb.color_changed.connect(_on_logcolor_changed.bind(key))
	_color_buttons[key] = cpb
	return _labeled_row(label_text, cpb)


# ---------------- 設定UIのハンドラ ----------------
func _on_threshold_changed(v: float) -> void:
	if _suppress_ui_signal:
		return
	low_hp_threshold = v / 100.0


func _on_maxlines_changed(v: float) -> void:
	if _suppress_ui_signal:
		return
	max_log_lines = int(v)
	_refresh_log()


func _on_logcolor_changed(color: Color, key: String) -> void:
	if _suppress_ui_signal:
		return
	LOG_COLORS[key] = color
	_refresh_log()


func _on_logsave_toggled(pressed: bool) -> void:
	log_save_enabled = pressed


func _open_dir_dialog() -> void:
	_file_dialog.popup_centered(Vector2i(760, 520))


func _on_dir_selected(dir: String) -> void:
	log_save_dir = dir
	if _save_dir_label:
		_save_dir_label.text = dir
	log_message("ログ保存先: %s" % dir, "system", "system")
