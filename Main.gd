extends Node2D

# ============================================================
# Main.gd
# 戦闘全体の管理役。
#   - biim式レイアウト：戦場を枠で囲い、UIは被せず周囲に配置
#   - data/units.json から味方・敵を生成（無ければコード既定）
#   - data/config.json のプリセットで設定を適用
#   - スペースで一時停止 / 再開（独自フラグ方式）
#   - 戦闘ログ（色分け・名前色分け・フィルタ・バックログ・保存）
#   - HP低下アラート、攻撃/回復のエフェクト＆効果音
# ============================================================

# --- レイアウト ---
const MARGIN: float = 8.0
const PANEL_W: float = 260.0
const LOG_H: float = 210.0
var battle_rect: Rect2  # 戦場の矩形（ユニット配置・後退クランプに使う / 公開）

# 一時停止フラグ。各 Unit はこれを見て動きを止める。
var is_paused: bool = false

# --- 設定（プリセットから適用される） ---
var low_hp_threshold: float = 0.3
var alarm_on: bool = true
var sfx_on: bool = true
var auto_pause_on_alert: bool = false
var max_log_lines: int = 12  # 互換用に残置（バックログ化したため表示制限には未使用）

# --- ログ保存設定（デフォルトOFF） ---
var log_save_enabled: bool = false
var log_save_dir: String = "user://logs"

# ログの色（プリセットから読み込む。category 名 -> Color）
var LOG_COLORS: Dictionary = {
	"attack": Color(0.85, 0.85, 0.85), "heal": Color(0.40, 0.95, 0.55),
	"retreat": Color(0.95, 0.85, 0.35), "death": Color(0.95, 0.45, 0.45),
	"warn": Color(1.00, 0.55, 0.15), "system": Color(0.55, 0.80, 1.00),
}

const MAX_LOG_HISTORY: int = 400

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

# 生存ユニットのキャッシュ（毎フレーム再構築。Unit はここを参照する）
var _alive_by_group: Dictionary = { "ally": [], "enemy": [] }

# エフェクト（{type, from, to, color, t, life}）
var _effects: Array = []

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
var _chk_sfx: CheckBox
var _chk_autopause: CheckBox
var _chk_logsave: CheckBox
var _save_dir_label: Label
var _file_dialog: FileDialog
var _threshold_slider: HSlider
var _maxlines_slider: HSlider
var _color_buttons: Dictionary = {}
var _suppress_ui_signal: bool = false

# 音
var _beep_player: AudioStreamPlayer
var _sfx_attack: AudioStreamPlayer
var _sfx_heal: AudioStreamPlayer


func _ready() -> void:
	add_to_group("main")
	var view: Vector2 = get_viewport_rect().size
	battle_rect = Rect2(
		MARGIN, MARGIN,
		view.x - PANEL_W - MARGIN * 3.0,
		view.y - LOG_H - MARGIN * 3.0)
	_setup_audio()
	_build_ui()
	_apply_preset(GameData.active_preset_name)
	_spawn_units()
	_rebuild_alive_cache()
	queue_redraw()
	log_message("戦闘開始！ スペースキーで一時停止 / 再開", "system", "system")


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_SPACE:
			_toggle_pause()


func _toggle_pause() -> void:
	is_paused = not is_paused
	_pause_label.visible = is_paused
	log_message("―― 一時停止 ――" if is_paused else "―― 再開 ――", "system", "system")


func _process(delta: float) -> void:
	_rebuild_alive_cache()
	_age_effects(delta)
	if _battle_over:
		return
	if _count_alive("enemy") == 0:
		_end_battle("勝利！ 敵を全滅させた")
	elif _count_alive("ally") == 0:
		_end_battle("敗北… 味方が全滅した")


# ============================================================
# 生存ユニットのキャッシュ（get_nodes_in_group の多用を避ける）
# ============================================================
func _rebuild_alive_cache() -> void:
	_alive_by_group["ally"] = get_tree().get_nodes_in_group("ally")
	_alive_by_group["enemy"] = get_tree().get_nodes_in_group("enemy")


func get_alive_units(group_name: String) -> Array:
	return _alive_by_group.get(group_name, [])


func _count_alive(group_name: String) -> int:
	var n: int = 0
	for u in get_alive_units(group_name):
		if u.is_alive():
			n += 1
	return n


func _end_battle(text: String) -> void:
	_battle_over = true
	_result_label.text = text
	_result_label.visible = true
	log_message("=== %s ===" % text, "system", "system")
	if log_save_enabled:
		_save_log()


# ============================================================
# 描画（戦場の枠＋エフェクト。子のユニットはこの上に描画される）
# ============================================================
func _draw() -> void:
	draw_rect(battle_rect, Color(0.13, 0.15, 0.18), true)
	draw_rect(battle_rect, Color(0.35, 0.40, 0.50), false, 2.0)
	for fx in _effects:
		var a: float = clamp(fx["t"] / fx["life"], 0.0, 1.0)
		if fx["type"] == "line":
			var c: Color = fx["color"]
			c.a = a
			draw_line(fx["from"], fx["to"], c, 2.0)
			draw_circle(fx["to"], 3.0 + 4.0 * a, c)
		elif fx["type"] == "heal":
			var hc: Color = Color(0.40, 1.0, 0.55, a)
			var r: float = 10.0 + (1.0 - a) * 16.0
			draw_arc(fx["from"], r, 0.0, TAU, 24, hc, 2.0)


# Unit から呼ばれるエフェクト登録
func add_attack_fx(from: Vector2, to: Vector2, color: Color) -> void:
	_effects.append({ "type": "line", "from": from, "to": to, "color": color, "t": 0.18, "life": 0.18 })
	queue_redraw()


func add_heal_fx(pos: Vector2, _color: Color) -> void:
	_effects.append({ "type": "heal", "from": pos, "to": pos, "color": Color.GREEN, "t": 0.35, "life": 0.35 })
	queue_redraw()


func _age_effects(delta: float) -> void:
	if _effects.is_empty():
		return
	for fx in _effects:
		fx["t"] -= delta
	var i: int = _effects.size() - 1
	while i >= 0:
		if _effects[i]["t"] <= 0.0:
			_effects.remove_at(i)
		i -= 1
	queue_redraw()


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
	sfx_on = bool(p.get("sfx_on", true))
	auto_pause_on_alert = bool(p.get("auto_pause_on_alert", false))
	max_log_lines = int(p.get("max_log_lines", 12))
	log_save_enabled = bool(p.get("log_save_enabled", false))
	log_save_dir = str(p.get("log_save_dir", "user://logs"))

	var colors: Dictionary = p.get("log_colors", {})
	for key in colors.keys():
		if colors[key] is String:
			LOG_COLORS[key] = Color.html(colors[key])

	_suppress_ui_signal = true
	if _chk_alarm:
		_chk_alarm.set_pressed_no_signal(alarm_on)
	if _chk_sfx:
		_chk_sfx.set_pressed_no_signal(sfx_on)
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
		"sfx_on": sfx_on,
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
		_beep_player.play()
	if auto_pause_on_alert and not is_paused:
		_toggle_pause()


func _flash_alert(unit_name: String) -> void:
	_alert_label.text = "⚠ %s HP低下！" % unit_name
	_alert_label.modulate.a = 1.0
	_alert_label.visible = true
	var tw: Tween = create_tween()
	tw.tween_property(_alert_label, "modulate:a", 0.0, 1.8)
	tw.tween_callback(func() -> void: _alert_label.visible = false)


func play_attack_sfx() -> void:
	if sfx_on and _sfx_attack:
		_sfx_attack.play()


func play_heal_sfx() -> void:
	if sfx_on and _sfx_heal:
		_sfx_heal.play()


# ============================================================
# 戦闘ログ（バックログ：全履歴をスクロールで遡れる）
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
	_log_label.text = "\n".join(lines)


func _colorize_names(text: String, _base_hex: String) -> String:
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
	log_message("ログを保存: %s" % ProjectSettings.globalize_path(path), "system", "system")


# ============================================================
# 音（外部ファイル不要。コードで波形合成）
# ============================================================
func _setup_audio() -> void:
	_beep_player = AudioStreamPlayer.new()
	_beep_player.stream = _make_beep(880.0, 0.18, 0.5)
	add_child(_beep_player)

	_sfx_attack = AudioStreamPlayer.new()
	_sfx_attack.stream = _make_beep(190.0, 0.06, 0.25)
	add_child(_sfx_attack)

	_sfx_heal = AudioStreamPlayer.new()
	_sfx_heal.stream = _make_beep(620.0, 0.14, 0.30)
	add_child(_sfx_heal)


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

	var allies: Array = GameData.get_allies()
	if allies.is_empty():
		allies = _fallback_allies()
	var enemies: Array = GameData.get_enemies()
	if enemies.is_empty():
		enemies = _fallback_enemies()

	var ax: float = battle_rect.position.x + battle_rect.size.x * 0.20
	var ex: float = battle_rect.position.x + battle_rect.size.x * 0.80
	_place_team(allies, Unit.Team.ALLY, ax)
	_place_team(enemies, Unit.Team.ENEMY, ex)


func _place_team(list: Array, team: int, x: float) -> void:
	var n: int = list.size()
	var top: float = battle_rect.position.y + 40.0
	var bottom: float = battle_rect.position.y + battle_rect.size.y - 40.0
	for i in n:
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
		_name_colors[u.unit_name] = u.base_color.to_html(false)
		if _target_option:
			_target_option.add_item(u.unit_name)


func _fallback_allies() -> Array:
	return [
		{ "name": "タロウ(前衛)", "role": "Frontline", "max_hp": 170, "attack": 14, "defense": 2,
			"move_speed": 72.0, "attack_range": 48.0, "attack_cooldown": 0.9,
			"radius": 18.0, "color": Color(0.30, 0.55, 1.00) },
		{ "name": "レン(射撃)", "role": "Shooter", "max_hp": 90, "attack": 18,
			"move_speed": 66.0, "attack_range": 240.0, "attack_cooldown": 1.0,
			"radius": 15.0, "color": Color(0.30, 0.85, 0.90) },
		{ "name": "ミナ(衛生)", "role": "Medic", "max_hp": 110, "attack": 8, "heal_power": 18,
			"move_speed": 78.0, "attack_range": 95.0, "attack_cooldown": 1.2,
			"radius": 15.0, "color": Color(0.30, 0.90, 0.50) },
		{ "name": "アキラ(支援)", "role": "Support", "max_hp": 110, "attack": 13,
			"move_speed": 72.0, "attack_range": 160.0, "attack_cooldown": 1.0,
			"radius": 15.0, "color": Color(0.95, 0.85, 0.30) },
	]


func _fallback_enemies() -> Array:
	return [
		{ "name": "レイダー", "role": "Raider", "max_hp": 120, "attack": 12,
			"move_speed": 72.0, "attack_range": 48.0, "attack_cooldown": 1.0,
			"radius": 16.0, "color": Color(0.90, 0.35, 0.30) },
		{ "name": "スナイパー", "role": "Shooter", "max_hp": 75, "attack": 22,
			"move_speed": 58.0, "attack_range": 260.0, "attack_cooldown": 1.6,
			"radius": 15.0, "color": Color(0.90, 0.50, 0.30) },
		{ "name": "ブルート", "role": "Brute", "max_hp": 240, "attack": 20, "defense": 3,
			"move_speed": 40.0, "attack_range": 52.0, "attack_cooldown": 1.6,
			"radius": 22.0, "color": Color(0.70, 0.25, 0.35) },
	]


# ============================================================
# UI（biim式：戦場の周囲に配置）
# ============================================================
func _build_ui() -> void:
	var view: Vector2 = get_viewport_rect().size
	var layer: CanvasLayer = CanvasLayer.new()
	add_child(layer)

	# 下：戦闘ログ欄
	var log_bg: ColorRect = ColorRect.new()
	log_bg.color = Color(0.0, 0.0, 0.0, 0.55)
	log_bg.position = Vector2(MARGIN, view.y - LOG_H - MARGIN)
	log_bg.size = Vector2(view.x - MARGIN * 2.0, LOG_H)
	log_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(log_bg)

	_log_label = RichTextLabel.new()
	_log_label.bbcode_enabled = true
	_log_label.scroll_following = true
	_log_label.position = Vector2(MARGIN + 8.0, view.y - LOG_H - MARGIN + 6.0)
	_log_label.size = Vector2(view.x - MARGIN * 2.0 - 16.0, LOG_H - 12.0)
	_log_label.add_theme_font_size_override("normal_font_size", 15)
	layer.add_child(_log_label)

	_build_control_panel(layer, view)

	# 戦場の上に重ねる中央ラベル（戦場の幅に合わせる）
	_pause_label = _make_overlay_label(28, Color(1.0, 0.85, 0.2))
	_pause_label.text = "● PAUSED （スペースで再開）"
	_pause_label.position = Vector2(battle_rect.position.x, battle_rect.position.y + 10.0)
	_pause_label.size = Vector2(battle_rect.size.x, 40.0)
	_pause_label.visible = false
	layer.add_child(_pause_label)

	_alert_label = _make_overlay_label(30, Color(1.0, 0.4, 0.2))
	_alert_label.position = Vector2(battle_rect.position.x, battle_rect.position.y + 52.0)
	_alert_label.size = Vector2(battle_rect.size.x, 40.0)
	_alert_label.visible = false
	layer.add_child(_alert_label)

	_result_label = _make_overlay_label(48, Color(1.0, 1.0, 1.0))
	_result_label.position = battle_rect.position
	_result_label.size = battle_rect.size
	_result_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_result_label.visible = false
	layer.add_child(_result_label)


func _make_overlay_label(font_size: int, color: Color) -> Label:
	var l: Label = Label.new()
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


# 右：設定パネル（スクロール可能。ゲーム内CONFIGをここで完結）
func _build_control_panel(layer: CanvasLayer, view: Vector2) -> void:
	var panel: PanelContainer = PanelContainer.new()
	panel.position = Vector2(view.x - PANEL_W - MARGIN, MARGIN)
	panel.size = Vector2(PANEL_W, battle_rect.size.y)

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

	# --- 設定 ---
	box.add_child(_make_header("― 設定 ―"))
	_threshold_slider = _make_slider(5.0, 90.0, 5.0, low_hp_threshold * 100.0, _on_threshold_changed)
	box.add_child(_labeled_row("HP警告%", _threshold_slider))
	_chk_autopause = _make_check("HP低下で一時停止", false, _on_autopause_toggled)
	box.add_child(_chk_autopause)
	_chk_alarm = _make_check("アラーム音", true, _on_alarm_toggled)
	box.add_child(_chk_alarm)
	_chk_sfx = _make_check("効果音", true, _on_sfx_toggled)
	box.add_child(_chk_sfx)

	# --- ログの色 ---
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

	# --- ログ保存 ---
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


# ---------------- ハンドラ ----------------
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


func _on_sfx_toggled(pressed: bool) -> void:
	sfx_on = pressed


func _on_target_selected(index: int) -> void:
	if index == 0:
		_filter_target = ""
	else:
		_filter_target = _target_option.get_item_text(index)
	_refresh_log()


func _on_threshold_changed(v: float) -> void:
	if _suppress_ui_signal:
		return
	low_hp_threshold = v / 100.0


func _on_maxlines_changed(v: float) -> void:
	if _suppress_ui_signal:
		return
	max_log_lines = int(v)


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
