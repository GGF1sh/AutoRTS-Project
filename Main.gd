extends Node2D

# ============================================================
# Main.gd
# 戦闘全体の管理役。
#   - 味方4体・敵3体を生成して配置する
#   - スペースキーで一時停止 / 再開（独自フラグ方式）
#   - 画面下に戦闘ログを表示する
#   - 全滅したら勝敗を表示する
# ============================================================

# 一時停止フラグ。各 Unit はこれを見て動きを止める。
var is_paused: bool = false

const MAX_LOG_LINES: int = 8
var _log_lines: Array[String] = []
var _battle_over: bool = false

# UI（_build_ui で生成）
var _units_node: Node2D
var _log_label: RichTextLabel
var _pause_label: Label
var _result_label: Label


func _ready() -> void:
	add_to_group("main")
	_build_ui()
	_spawn_units()
	log_message("戦闘開始！ スペースキーで一時停止 / 再開")


# スペースキーで一時停止トグル
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_SPACE:
			_toggle_pause()


func _toggle_pause() -> void:
	is_paused = not is_paused
	_pause_label.visible = is_paused
	log_message("―― 一時停止 ――" if is_paused else "―― 再開 ――")


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
	log_message("=== %s ===" % text)


# ============================================================
# 戦闘ログ（最新 MAX_LOG_LINES 行を画面下に表示）
# ============================================================
func log_message(text: String) -> void:
	_log_lines.append(text)
	if _log_lines.size() > MAX_LOG_LINES:
		_log_lines.pop_front()
	if _log_label:
		_log_label.text = "\n".join(_log_lines)


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


# ============================================================
# UI（コードで生成。シーンを手で組まなくても動く）
# ============================================================
func _build_ui() -> void:
	var layer: CanvasLayer = CanvasLayer.new()
	add_child(layer)

	# 戦闘ログの背景（画面下）
	var log_bg: ColorRect = ColorRect.new()
	log_bg.color = Color(0.0, 0.0, 0.0, 0.6)
	log_bg.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	log_bg.offset_top = -170.0
	log_bg.offset_bottom = 0.0
	log_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(log_bg)

	# 戦闘ログ本体
	_log_label = RichTextLabel.new()
	_log_label.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_log_label.offset_top = -160.0
	_log_label.offset_bottom = -8.0
	_log_label.offset_left = 12.0
	_log_label.offset_right = -12.0
	_log_label.scroll_following = true
	_log_label.add_theme_font_size_override("normal_font_size", 16)
	layer.add_child(_log_label)

	# 「PAUSED」表示（一時停止中だけ表示）
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

	# 勝敗の結果表示（最後だけ表示）
	_result_label = Label.new()
	_result_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	_result_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_result_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_result_label.add_theme_font_size_override("font_size", 48)
	_result_label.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0))
	_result_label.visible = false
	layer.add_child(_result_label)
