class_name Main
extends Node2D

# ============================================================
# Main.gd — 司令塔（薄いコーディネーター）
# 戦闘管理（配置・一時停止・勝敗・生存キャッシュ）と、各部品
# （Hud / Fx / AudioBank / GameData）の接続だけを担当する。
# UI・エフェクト・音・データの中身は各ファイルに分離。
# Unit からは battle.* の各メソッドを呼ぶ（インターフェース不変）。
# ============================================================

# レイアウト定数（Hud から Main.MARGIN 等で参照）
const MARGIN: float = 8.0
const PANEL_W: float = 260.0
const LOG_H: float = 210.0

var battle_rect: Rect2  # 戦場の矩形（配置・後退クランプに使う / 公開）
var is_paused: bool = false

# 設定（プリセットから適用。Unit が battle.low_hp_threshold 等を参照）
var low_hp_threshold: float = 0.3
var alarm_on: bool = true
var sfx_on: bool = true
var auto_pause_on_alert: bool = false
var log_save_enabled: bool = false
var log_save_dir: String = "user://logs"

var _battle_over: bool = false
var _alive_by_group: Dictionary = { "ally": [], "enemy": [] }
# チームの集中攻撃ターゲット（team(int) -> Unit）。focus_fire が参照する。
var _focus_target: Dictionary = {}

var _units_node: Node2D
var _hud: Hud
var _fx: Fx
var _audio: AudioBank


func _ready() -> void:
	add_to_group("main")
	var view: Vector2 = get_viewport_rect().size
	battle_rect = Rect2(MARGIN, MARGIN, view.x - PANEL_W - MARGIN * 3.0, view.y - LOG_H - MARGIN * 3.0)

	_audio = AudioBank.new()
	add_child(_audio)
	_hud = Hud.new()
	add_child(_hud)
	_hud.build(self, battle_rect, view)

	apply_preset(GameData.active_preset_name)
	_spawn_units()

	_fx = Fx.new()  # ユニットの後に追加 → ユニットの上に描画
	add_child(_fx)

	_rebuild_alive_cache()
	queue_redraw()
	log_message("戦闘開始！ Space=一時停止/再開  R=再戦", "system", "system")


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_SPACE:
			_toggle_pause()
		elif event.keycode == KEY_R:
			get_tree().reload_current_scene()  # 再戦（観察用に即リセット）


func _toggle_pause() -> void:
	is_paused = not is_paused
	_hud.set_pause_visible(is_paused)
	log_message("―― 一時停止 ――" if is_paused else "―― 再開 ――", "system", "system")


func _process(_delta: float) -> void:
	_rebuild_alive_cache()
	if _battle_over:
		return
	if _count_alive("enemy") == 0:
		_end_battle("勝利！ 敵を全滅させた")
	elif _count_alive("ally") == 0:
		_end_battle("敗北… 味方が全滅した")


func _draw() -> void:
	draw_rect(battle_rect, Color(0.13, 0.15, 0.18), true)
	draw_rect(battle_rect, Color(0.35, 0.40, 0.50), false, 2.0)


# ============================================================
# 生存キャッシュ（Unit から参照）
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
	_hud.show_result("%s\n（R キーで再戦）" % text)
	log_message("=== %s ===" % text, "system", "system")
	if log_save_enabled:
		save_log_now()


# ============================================================
# Unit から呼ばれる橋渡し
# ============================================================
func log_message(text: String, category: String = "system", faction: String = "system") -> void:
	_hud.log_message(text, category, faction)


func on_low_hp(unit: Unit) -> void:
	var pct: int = int(round(low_hp_threshold * 100.0))
	log_message("⚠ %s のHPが%d%%を下回った" % [unit.unit_name, pct], "warn", unit.team_name())
	_hud.flash_alert(unit.unit_name)
	if alarm_on:
		_audio.play_alert()
	if auto_pause_on_alert and not is_paused:
		_toggle_pause()


func play_attack_sfx() -> void:
	if sfx_on:
		_audio.play_attack()


func play_heal_sfx() -> void:
	if sfx_on:
		_audio.play_heal()


func add_attack_fx(from: Vector2, to: Vector2, color: Color, kind: String = "beam") -> void:
	if _fx:
		_fx.add_attack(from, to, color, kind)


func add_heal_fx(pos: Vector2, _color: Color = Color.GREEN) -> void:
	if _fx:
		_fx.add_heal(pos)


# チーム連携：攻撃が起きたら、その陣営の「集中ターゲット」を更新する。
func report_attack(attacker_team: int, target: Unit) -> void:
	if target != null and target.is_alive():
		_focus_target[attacker_team] = target


# 自陣営の集中ターゲット（生存していれば返す。focus_fire 用）
func get_focus_target(my_team: int) -> Unit:
	var t: Unit = _focus_target.get(my_team, null)
	if t != null and t.is_alive():
		return t
	return null


# ============================================================
# プリセット / 設定（Hud から委譲される）
# ============================================================
func apply_preset(preset_name: String) -> void:
	if not GameData.presets.has(preset_name):
		return
	GameData.active_preset_name = preset_name
	var p: Dictionary = GameData.get_preset(preset_name)
	low_hp_threshold = float(p.get("low_hp_threshold", 0.3))
	alarm_on = bool(p.get("alarm_on", true))
	sfx_on = bool(p.get("sfx_on", true))
	auto_pause_on_alert = bool(p.get("auto_pause_on_alert", false))
	log_save_enabled = bool(p.get("log_save_enabled", false))
	log_save_dir = str(p.get("log_save_dir", "user://logs"))

	var col_dict: Dictionary = {}
	var lc: Dictionary = p.get("log_colors", {})
	for k in lc.keys():
		if lc[k] is String:
			col_dict[k] = Color.html(lc[k])
	_hud.set_colors(col_dict)
	_hud.sync_settings(low_hp_threshold * 100.0, alarm_on, sfx_on, auto_pause_on_alert, log_save_enabled, log_save_dir)
	_hud.refresh()
	log_message("プリセット「%s」を適用" % preset_name, "system", "system")


func cycle_preset() -> void:
	var names: Array = GameData.get_preset_names()
	if names.is_empty():
		return
	var i: int = names.find(GameData.active_preset_name)
	var nx: String = names[(i + 1) % names.size()]
	_hud.select_preset(nx)
	apply_preset(nx)


func save_current_preset() -> void:
	var preset_name: String = _hud.preset_name_text()
	if preset_name == "":
		preset_name = "カスタム"
	var preset: Dictionary = {
		"low_hp_threshold": low_hp_threshold,
		"alarm_on": alarm_on,
		"sfx_on": sfx_on,
		"auto_pause_on_alert": auto_pause_on_alert,
		"log_save_enabled": log_save_enabled,
		"log_save_dir": log_save_dir,
		"log_colors": _hud.colors_hex(),
	}
	if GameData.save_user_preset(preset_name, preset):
		_hud.repopulate_presets(preset_name)
		log_message("プリセット「%s」を保存しました" % preset_name, "system", "system")
	else:
		log_message("プリセットの保存に失敗しました", "warn", "system")


func set_threshold(v: float) -> void:
	low_hp_threshold = v / 100.0


func set_alarm(b: bool) -> void:
	alarm_on = b


func set_sfx(b: bool) -> void:
	sfx_on = b


func set_autopause(b: bool) -> void:
	auto_pause_on_alert = b


func set_logsave(b: bool) -> void:
	log_save_enabled = b


func set_log_dir(dir: String) -> void:
	log_save_dir = dir
	_hud.set_dir_label(dir)
	log_message("ログ保存先: %s" % dir, "system", "system")


func save_log_now() -> void:
	var path: String = _hud.save_log(log_save_dir, _build_roster())
	if path != "":
		log_message("ログを保存: %s" % path, "system", "system")
	else:
		log_message("ログ保存に失敗しました", "warn", "system")


func _build_roster() -> Array:
	var lines: Array = []
	for u in get_tree().get_nodes_in_group("units"):
		lines.append("[%s] %s / role=%s / HP%d ATK%d DEF%d HEAL%d / 速度%d 射程%d 間隔%.1f" % [
			u.team_name(), u.unit_name, u.role,
			u.max_hp, u.attack_power, u.defense, u.heal_power,
			int(u.move_speed), int(u.attack_range), u.attack_cooldown,
		])
	return lines


# ============================================================
# ユニット生成（データは GameData が供給）
# ============================================================
func _spawn_units() -> void:
	_units_node = Node2D.new()
	_units_node.name = "Units"
	add_child(_units_node)

	var ax: float = battle_rect.position.x + battle_rect.size.x * 0.20
	var ex: float = battle_rect.position.x + battle_rect.size.x * 0.80
	_place_team(GameData.get_allies(), Unit.Team.ALLY, ax)
	_place_team(GameData.get_enemies(), Unit.Team.ENEMY, ex)


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

		var y: float = (top + bottom) * 0.5
		if n > 1:
			y = top + (bottom - top) * float(i) / float(n - 1)
		u.position = Vector2(x, y)

		_units_node.add_child(u)
		_hud.register_name(u.unit_name, u.base_color.to_html(false))
		_hud.add_target_item(u.unit_name)
