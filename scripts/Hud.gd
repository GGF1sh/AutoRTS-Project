class_name Hud
extends Node

# ============================================================
# Hud.gd
# biim式レイアウトのUI一式（戦闘ログ欄・右の設定パネル・中央ラベル）を
# 構築・所有する。ログの蓄積／フィルタ／色分け／保存もここが担当。
# 戦闘設定そのもの（しきい値・音など）は Main が保持し、Hud は操作を
# _main のメソッドへ委譲する。
# ============================================================

var _main: Node  # 司令塔への参照（設定変更の委譲先）

# ログの色（category 名 -> Color）。プリセットで上書きされる。
var colors: Dictionary = {
	"attack": Color(0.85, 0.85, 0.85), "heal": Color(0.40, 0.95, 0.55),
	"retreat": Color(0.95, 0.85, 0.35), "death": Color(0.95, 0.45, 0.45),
	"warn": Color(1.00, 0.55, 0.15), "system": Color(0.55, 0.80, 1.00),
}

const MAX_LOG_HISTORY: int = 400
var _entries: Array = []                 # { text, category, faction }
var _name_colors: Dictionary = {}        # ユニット名 -> #RRGGBB
var _show_faction: Dictionary = { "ally": true, "enemy": true, "system": true }
var _show_category: Dictionary = { "attack": true, "heal": true, "retreat": true, "death": true, "system": true }
var _filter_target: String = ""
var _suppress: bool = false              # プリセット同期中はシグナルを無視

# widget 参照
var _log_label: RichTextLabel
var _pause_label: Label
var _alert_label: Label
var _result_label: Label
var _target_option: OptionButton
var _preset_option: OptionButton
var _preset_name_edit: LineEdit
var _chk_alarm: CheckBox
var _chk_sfx: CheckBox
var _chk_autopause: CheckBox
var _chk_logsave: CheckBox
var _save_dir_label: Label
var _file_dialog: FileDialog
var _threshold_slider: HSlider
var _color_buttons: Dictionary = {}


func build(main: Node, b_rect: Rect2, view: Vector2) -> void:
	_main = main
	var layer: CanvasLayer = CanvasLayer.new()
	add_child(layer)

	# 下：戦闘ログ欄
	var log_bg: ColorRect = ColorRect.new()
	log_bg.color = Color(0.0, 0.0, 0.0, 0.55)
	log_bg.position = Vector2(Main.MARGIN, view.y - Main.LOG_H - Main.MARGIN)
	log_bg.size = Vector2(view.x - Main.MARGIN * 2.0, Main.LOG_H)
	log_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(log_bg)

	_log_label = RichTextLabel.new()
	_log_label.bbcode_enabled = true
	_log_label.scroll_following = true
	_log_label.position = Vector2(Main.MARGIN + 8.0, view.y - Main.LOG_H - Main.MARGIN + 6.0)
	_log_label.size = Vector2(view.x - Main.MARGIN * 2.0 - 16.0, Main.LOG_H - 12.0)
	_log_label.add_theme_font_size_override("normal_font_size", 15)
	layer.add_child(_log_label)

	_build_panel(layer, b_rect, view)

	_pause_label = _overlay_label(28, Color(1.0, 0.85, 0.2))
	_pause_label.text = "● PAUSED （スペースで再開）"
	_pause_label.position = Vector2(b_rect.position.x, b_rect.position.y + 10.0)
	_pause_label.size = Vector2(b_rect.size.x, 40.0)
	_pause_label.visible = false
	layer.add_child(_pause_label)

	_alert_label = _overlay_label(30, Color(1.0, 0.4, 0.2))
	_alert_label.position = Vector2(b_rect.position.x, b_rect.position.y + 52.0)
	_alert_label.size = Vector2(b_rect.size.x, 40.0)
	_alert_label.visible = false
	layer.add_child(_alert_label)

	_result_label = _overlay_label(48, Color(1.0, 1.0, 1.0))
	_result_label.position = b_rect.position
	_result_label.size = b_rect.size
	_result_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_result_label.visible = false
	layer.add_child(_result_label)


# ---------------- ログ ----------------
func log_message(text: String, category: String = "system", faction: String = "system") -> void:
	_entries.append({ "text": text, "category": category, "faction": faction })
	if _entries.size() > MAX_LOG_HISTORY:
		_entries.pop_front()
	refresh()


func register_name(uname: String, hex: String) -> void:
	_name_colors[uname] = hex


func refresh() -> void:
	if _log_label == null:
		return
	var lines: Array[String] = []
	for e in _entries:
		if not _passes_filter(e):
			continue
		var base_hex: String = colors.get(e["category"], Color.WHITE).to_html(false)
		lines.append("[color=#%s]%s[/color]" % [base_hex, _colorize_names(e["text"])])
	_log_label.text = "\n".join(lines)


func _colorize_names(text: String) -> String:
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
	return _show_category.get(key, true)


func save_log(dir: String, roster_lines: Array) -> String:
	DirAccess.make_dir_recursive_absolute(dir)
	var stamp: String = Time.get_datetime_string_from_system().replace(":", "-").replace("T", "_")
	var path: String = "%s/battle_%s.txt" % [dir, stamp]
	var f: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return ""
	f.store_line("=== 戦闘ログ ===")
	f.store_line("日時: %s" % Time.get_datetime_string_from_system())
	f.store_line("")
	f.store_line("--- 参加ユニット ---")
	for line in roster_lines:
		f.store_line(line)
	f.store_line("")
	f.store_line("--- 戦闘の流れ ---")
	for e in _entries:
		f.store_line(e["text"])
	return ProjectSettings.globalize_path(path)


# ---------------- 中央ラベル ----------------
func set_pause_visible(b: bool) -> void:
	_pause_label.visible = b


func flash_alert(uname: String) -> void:
	_alert_label.text = "⚠ %s HP低下！" % uname
	_alert_label.modulate.a = 1.0
	_alert_label.visible = true
	var tw: Tween = create_tween()
	tw.tween_property(_alert_label, "modulate:a", 0.0, 1.8)
	tw.tween_callback(func() -> void: _alert_label.visible = false)


func show_result(text: String) -> void:
	_result_label.text = text
	_result_label.visible = true


func add_target_item(uname: String) -> void:
	if _target_option:
		_target_option.add_item(uname)


# ---------------- 設定の反映（Main から） ----------------
func set_colors(new_colors: Dictionary) -> void:
	for k in new_colors.keys():
		colors[k] = new_colors[k]
	_suppress = true
	for k in _color_buttons.keys():
		if colors.has(k):
			_color_buttons[k].color = colors[k]
	_suppress = false


func colors_hex() -> Dictionary:
	var out: Dictionary = {}
	for k in colors.keys():
		out[k] = "#" + colors[k].to_html(false)
	return out


func sync_settings(threshold_pct: float, alarm: bool, sfx: bool, autopause: bool, logsave: bool, dir: String) -> void:
	_suppress = true
	if _threshold_slider:
		_threshold_slider.value = threshold_pct
	if _chk_alarm:
		_chk_alarm.set_pressed_no_signal(alarm)
	if _chk_sfx:
		_chk_sfx.set_pressed_no_signal(sfx)
	if _chk_autopause:
		_chk_autopause.set_pressed_no_signal(autopause)
	if _chk_logsave:
		_chk_logsave.set_pressed_no_signal(logsave)
	if _save_dir_label:
		_save_dir_label.text = dir
	_suppress = false


func set_dir_label(dir: String) -> void:
	if _save_dir_label:
		_save_dir_label.text = dir


func repopulate_presets(select_name: String) -> void:
	if _preset_option == null:
		return
	_preset_option.clear()
	for n in GameData.get_preset_names():
		_preset_option.add_item(n)
	_select_preset(select_name)


func preset_name_text() -> String:
	return _preset_name_edit.text.strip_edges()


func select_preset(target: String) -> void:
	_select_preset(target)


func _select_preset(target: String) -> void:
	for i in _preset_option.item_count:
		if _preset_option.get_item_text(i) == target:
			_preset_option.select(i)
			return


# ============================================================
# 右の設定パネル構築
# ============================================================
func _build_panel(layer: CanvasLayer, b_rect: Rect2, view: Vector2) -> void:
	var panel: PanelContainer = PanelContainer.new()
	panel.position = Vector2(view.x - Main.PANEL_W - Main.MARGIN, Main.MARGIN)
	panel.size = Vector2(Main.PANEL_W, b_rect.size.y)
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

	# プリセット
	box.add_child(_header("― 設定プリセット ―"))
	_preset_option = OptionButton.new()
	_preset_option.focus_mode = Control.FOCUS_NONE
	for n in GameData.get_preset_names():
		_preset_option.add_item(n)
	_preset_option.item_selected.connect(_on_preset_selected)
	box.add_child(_preset_option)
	_select_preset(GameData.active_preset_name)
	box.add_child(_button("▶ 次のプリセットへ", _on_cycle))
	_preset_name_edit = LineEdit.new()
	_preset_name_edit.placeholder_text = "プリセット名"
	box.add_child(_preset_name_edit)
	box.add_child(_button("現在の設定を保存", _on_save_preset))

	# 設定
	box.add_child(_header("― 設定 ―"))
	_threshold_slider = _slider(5.0, 90.0, 5.0, 30.0, _on_threshold)
	box.add_child(_labeled("HP警告%", _threshold_slider))
	_chk_autopause = _check("HP低下で一時停止", false, _on_autopause)
	box.add_child(_chk_autopause)
	_chk_alarm = _check("アラーム音", true, _on_alarm)
	box.add_child(_chk_alarm)
	_chk_sfx = _check("効果音", true, _on_sfx)
	box.add_child(_chk_sfx)

	# ログの色
	box.add_child(_header("― ログの色 ―"))
	box.add_child(_color_row("攻撃", "attack"))
	box.add_child(_color_row("回復", "heal"))
	box.add_child(_color_row("後退", "retreat"))
	box.add_child(_color_row("撃破", "death"))
	box.add_child(_color_row("警告", "warn"))
	box.add_child(_color_row("システム", "system"))

	# ログ表示フィルタ
	box.add_child(_header("― ログ表示 ―"))
	box.add_child(_check("味方", true, _on_faction.bind("ally")))
	box.add_child(_check("敵", true, _on_faction.bind("enemy")))
	box.add_child(_check("システム", true, _on_faction.bind("system")))
	box.add_child(_header("― 種類 ―"))
	box.add_child(_check("攻撃", true, _on_category.bind("attack")))
	box.add_child(_check("回復", true, _on_category.bind("heal")))
	box.add_child(_check("後退", true, _on_category.bind("retreat")))
	box.add_child(_check("撃破", true, _on_category.bind("death")))
	box.add_child(_header("― 対象キャラ ―"))
	_target_option = OptionButton.new()
	_target_option.focus_mode = Control.FOCUS_NONE
	_target_option.add_item("全員")
	_target_option.item_selected.connect(_on_target)
	box.add_child(_target_option)

	# ログ保存
	box.add_child(_header("― ログ保存 ―"))
	_chk_logsave = _check("終了時に自動保存", false, _on_logsave)
	box.add_child(_chk_logsave)
	_save_dir_label = Label.new()
	_save_dir_label.text = "user://logs"
	_save_dir_label.add_theme_font_size_override("font_size", 11)
	_save_dir_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_save_dir_label)
	box.add_child(_button("保存先を選ぶ", _on_choose_dir))
	box.add_child(_button("今すぐ手動保存", _on_manual_save))

	_file_dialog = FileDialog.new()
	_file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_DIR
	_file_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_file_dialog.title = "ログ保存先フォルダを選択"
	_file_dialog.dir_selected.connect(_on_dir_selected)
	add_child(_file_dialog)


# ---------------- widget ハンドラ ----------------
func _on_preset_selected(index: int) -> void:
	_main.apply_preset(_preset_option.get_item_text(index))


func _on_cycle() -> void:
	_main.cycle_preset()


func _on_save_preset() -> void:
	_main.save_current_preset()


func _on_threshold(v: float) -> void:
	if not _suppress:
		_main.set_threshold(v)


func _on_alarm(b: bool) -> void:
	if not _suppress:
		_main.set_alarm(b)


func _on_sfx(b: bool) -> void:
	if not _suppress:
		_main.set_sfx(b)


func _on_autopause(b: bool) -> void:
	if not _suppress:
		_main.set_autopause(b)


func _on_logsave(b: bool) -> void:
	if not _suppress:
		_main.set_logsave(b)


func _on_logcolor(color: Color, key: String) -> void:
	if _suppress:
		return
	colors[key] = color
	refresh()


func _on_faction(pressed: bool, key: String) -> void:
	_show_faction[key] = pressed
	refresh()


func _on_category(pressed: bool, key: String) -> void:
	_show_category[key] = pressed
	refresh()


func _on_target(index: int) -> void:
	_filter_target = "" if index == 0 else _target_option.get_item_text(index)
	refresh()


func _on_choose_dir() -> void:
	_file_dialog.popup_centered(Vector2i(760, 520))


func _on_dir_selected(dir: String) -> void:
	_main.set_log_dir(dir)


func _on_manual_save() -> void:
	_main.save_log_now()


# ---------------- widget 生成ヘルパー ----------------
func _overlay_label(font_size: int, color: Color) -> Label:
	var l: Label = Label.new()
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _header(text: String) -> Label:
	var l: Label = Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 13)
	l.add_theme_color_override("font_color", Color(0.7, 0.85, 1.0))
	return l


func _check(text: String, pressed: bool, callback: Callable) -> CheckBox:
	var c: CheckBox = CheckBox.new()
	c.text = text
	c.button_pressed = pressed
	c.focus_mode = Control.FOCUS_NONE
	c.add_theme_font_size_override("font_size", 14)
	c.toggled.connect(callback)
	return c


func _button(text: String, callback: Callable) -> Button:
	var b: Button = Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", 14)
	b.pressed.connect(callback)
	return b


func _slider(minv: float, maxv: float, step: float, value: float, callback: Callable) -> HSlider:
	var sl: HSlider = HSlider.new()
	sl.min_value = minv
	sl.max_value = maxv
	sl.step = step
	sl.value = value
	sl.focus_mode = Control.FOCUS_NONE
	sl.custom_minimum_size = Vector2(90, 0)
	sl.value_changed.connect(callback)
	return sl


func _labeled(label_text: String, control: Control) -> HBoxContainer:
	var row: HBoxContainer = HBoxContainer.new()
	var l: Label = Label.new()
	l.text = label_text
	l.custom_minimum_size = Vector2(86, 0)
	l.add_theme_font_size_override("font_size", 13)
	row.add_child(l)
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(control)
	return row


func _color_row(label_text: String, key: String) -> HBoxContainer:
	var cpb: ColorPickerButton = ColorPickerButton.new()
	cpb.color = colors.get(key, Color.WHITE)
	cpb.focus_mode = Control.FOCUS_NONE
	cpb.custom_minimum_size = Vector2(60, 24)
	cpb.color_changed.connect(_on_logcolor.bind(key))
	_color_buttons[key] = cpb
	return _labeled(label_text, cpb)
