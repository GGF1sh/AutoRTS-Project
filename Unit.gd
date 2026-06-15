class_name Unit
extends Node2D

# ============================================================
# Unit.gd
# 味方・敵で共通の「1体のユニット」。
#
# Phase 6 から「ガンビット」で動く：
#   gambits = [ {条件, 行動}, {条件, 行動}, ... ]
#   毎フレーム上から評価し、最初に成立した1件だけ実行する。
#   これにより Medic は回復、Shooter は後退…とロールごとに動きが変わる。
# ============================================================

# 陣営。ALLY = 味方（丸）, ENEMY = 敵（四角）
enum Team { ALLY, ENEMY }

# --- ステータス（setup() で上書きされる） ---
var unit_name: String = "Unit"
var team: int = Team.ALLY
var role: String = "Frontline"
var max_hp: int = 100
var hp: int = 100
var attack_power: int = 10
var defense: int = 0
var heal_power: int = 0           # 回復量（Medic用。0なら回復役ではない）
var move_speed: float = 80.0      # 1秒あたりの移動ピクセル数
var attack_range: float = 48.0    # 攻撃／回復できる距離
var attack_cooldown: float = 1.0  # 攻撃・回復の間隔（秒）
var radius: float = 16.0          # 見た目の半径
var base_color: Color = Color.WHITE

# --- ガンビット（ロールごとに setup() で設定） ---
var gambits: Array = []

# --- 内部状態 ---
var _cooldown_timer: float = 0.0  # 0 以下なら攻撃／回復可能
var _dead: bool = false
var _last_action: String = ""     # 直前の行動ラベル（ログの重複防止）
var battle: Node = null           # Main への参照（ログ出力・一時停止判定に使う）


# 辞書からステータスを設定する。Main 側から呼ぶ。
func setup(data: Dictionary) -> void:
	unit_name = data.get("name", unit_name)
	team = data.get("team", team)
	role = data.get("role", role)
	max_hp = data.get("max_hp", max_hp)
	hp = max_hp
	attack_power = data.get("attack", attack_power)
	defense = data.get("defense", defense)
	heal_power = data.get("heal_power", heal_power)
	move_speed = data.get("move_speed", move_speed)
	attack_range = data.get("attack_range", attack_range)
	attack_cooldown = data.get("attack_cooldown", attack_cooldown)
	radius = data.get("radius", radius)
	base_color = data.get("color", base_color)

	# ガンビットは明示指定があればそれを、なければロール既定を使う
	gambits = data.get("gambits", _default_gambits(role))

	add_to_group("units")
	add_to_group("ally" if team == Team.ALLY else "enemy")


func is_alive() -> bool:
	return not _dead and hp > 0


func _process(delta: float) -> void:
	# 参照が無い／一時停止中／死亡中は何もしない（独自フラグ方式）
	if battle == null or battle.is_paused or not is_alive():
		return

	if _cooldown_timer > 0.0:
		_cooldown_timer -= delta

	_run_gambits(delta)


# ============================================================
# ガンビット評価：上から見て最初に成立した行動だけ実行
# ============================================================
func _run_gambits(delta: float) -> void:
	for rule in gambits:
		if _check_condition(rule):
			_run_action(rule, delta)
			return
	_set_action("待機")  # どの条件も成立しなければ待機


func _check_condition(rule: Dictionary) -> bool:
	var param: float = rule.get("param", 0.0)
	match rule.get("cond", ""):
		"self_hp_below":
			return float(hp) / float(max_hp) < param
		"ally_hp_below":
			return _find_wounded_ally(param) != null
		"enemy_in_range":
			var e: Unit = _find_nearest_enemy()
			return e != null and global_position.distance_to(e.global_position) <= attack_range
		"enemy_too_close":
			var e2: Unit = _find_nearest_enemy()
			return e2 != null and global_position.distance_to(e2.global_position) < param
		"nearest_enemy_exists":
			return _find_nearest_enemy() != null
		_:
			return false


func _run_action(rule: Dictionary, delta: float) -> void:
	match rule.get("action", ""):
		"attack_nearest":
			_act_attack(_find_nearest_enemy(), delta)
		"attack_weakest":
			_act_attack(_find_weakest_enemy(), delta)
		"retreat":
			_act_retreat(delta)
		"move_to_nearest_enemy":
			_act_move_to(_find_nearest_enemy(), delta)
		"heal_lowest_hp_ally":
			_act_heal(rule.get("param", 0.7), delta)
		_:
			_set_action("待機")


# ============================================================
# 行動の実体
# ============================================================
func _act_attack(target: Unit, delta: float) -> void:
	if target == null:
		_set_action("待機")
		return
	var dist: float = global_position.distance_to(target.global_position)
	if dist <= attack_range:
		_set_action("攻撃")
		_try_attack(target)
	else:
		_set_action("接近")
		_move_toward(target, delta)


func _act_move_to(target: Unit, delta: float) -> void:
	if target == null:
		_set_action("待機")
		return
	_set_action("接近")
	_move_toward(target, delta)


func _act_retreat(delta: float) -> void:
	var e: Unit = _find_nearest_enemy()
	if e == null:
		_set_action("待機")
		return
	_set_action("後退")
	var dir: Vector2 = (global_position - e.global_position).normalized()
	global_position += dir * move_speed * delta
	_clamp_to_screen()


func _act_heal(threshold: float, delta: float) -> void:
	var ally: Unit = _find_wounded_ally(threshold)
	if ally == null:
		_set_action("待機")
		return
	var dist: float = global_position.distance_to(ally.global_position)
	if dist <= attack_range:
		_set_action("回復")
		if _cooldown_timer <= 0.0:
			_cooldown_timer = attack_cooldown
			ally.receive_heal(heal_power, self)
	else:
		_set_action("接近(回復)")
		_move_toward(ally, delta)


# ============================================================
# 探索ヘルパー
# ============================================================
func _enemy_group() -> String:
	return "enemy" if team == Team.ALLY else "ally"


func _ally_group() -> String:
	return "ally" if team == Team.ALLY else "enemy"


# 最も近い「生きている敵」
func _find_nearest_enemy() -> Unit:
	var nearest: Unit = null
	var best: float = INF
	for u in get_tree().get_nodes_in_group(_enemy_group()):
		if not u.is_alive():
			continue
		var d: float = global_position.distance_to(u.global_position)
		if d < best:
			best = d
			nearest = u
	return nearest


# HPが最も少ない「生きている敵」（Support の集中攻撃用）
func _find_weakest_enemy() -> Unit:
	var weakest: Unit = null
	var lowest: int = 999999
	for u in get_tree().get_nodes_in_group(_enemy_group()):
		if not u.is_alive():
			continue
		if u.hp < lowest:
			lowest = u.hp
			weakest = u
	return weakest


# HP割合が threshold 未満で最も弱った味方（自分以外）。Medic の回復対象用。
func _find_wounded_ally(threshold: float) -> Unit:
	var target: Unit = null
	var lowest_ratio: float = threshold
	for u in get_tree().get_nodes_in_group(_ally_group()):
		if u == self or not u.is_alive():
			continue
		var ratio: float = float(u.hp) / float(u.max_hp)
		if ratio < lowest_ratio:
			lowest_ratio = ratio
			target = u
	return target


# ============================================================
# 移動・攻撃・回復・被弾
# ============================================================
func _move_toward(target: Unit, delta: float) -> void:
	var dir: Vector2 = (target.global_position - global_position).normalized()
	global_position += dir * move_speed * delta


func _try_attack(target: Unit) -> void:
	if _cooldown_timer > 0.0:
		return
	_cooldown_timer = attack_cooldown
	var damage: int = max(1, attack_power - target.defense)
	target.take_damage(damage, self)


func take_damage(amount: int, source: Unit) -> void:
	if _dead:
		return
	hp -= amount
	if battle:
		battle.log_message("%s が %s に %d ダメージ" % [source.unit_name, unit_name, amount])
	if hp <= 0:
		hp = 0
		_die()
	queue_redraw()


func receive_heal(amount: int, source: Unit) -> void:
	if _dead or amount <= 0:
		return
	var before: int = hp
	hp = min(max_hp, hp + amount)
	if battle and hp > before:
		battle.log_message("✚ %s が %s を %d 回復" % [source.unit_name, unit_name, hp - before])
	queue_redraw()


func _die() -> void:
	_dead = true
	remove_from_group("ally")
	remove_from_group("enemy")
	if battle:
		battle.log_message("☠ %s は倒れた" % unit_name)
	queue_redraw()


# 画面外に逃げすぎないよう位置を制限する（後退用）
func _clamp_to_screen() -> void:
	var view: Vector2 = get_viewport_rect().size
	var m: float = radius + 4.0
	global_position.x = clamp(global_position.x, m, view.x - m)
	# 画面下のログ欄(約170px)に重ならないようにする
	global_position.y = clamp(global_position.y, m, view.y - 180.0)


# 行動が変わった時だけ、目立つ判断をログに出す
func _set_action(label: String) -> void:
	if label == _last_action:
		return
	_last_action = label
	if battle == null:
		return
	match label:
		"後退":
			battle.log_message("← %s は危険を察知して後退する" % unit_name)
		"回復", "接近(回復)":
			battle.log_message("%s は負傷した味方を助けに向かう" % unit_name)


# ============================================================
# ロール別の既定ガンビット
# ============================================================
func _default_gambits(r: String) -> Array:
	match r:
		"Shooter":  # 近づかれたら後退して距離を取る（カイト）
			return [
				{ "cond": "self_hp_below", "param": 0.3, "action": "retreat" },
				{ "cond": "enemy_too_close", "param": 120.0, "action": "retreat" },
				{ "cond": "enemy_in_range", "action": "attack_nearest" },
				{ "cond": "nearest_enemy_exists", "action": "move_to_nearest_enemy" },
			]
		"Medic":  # 味方を回復。自分が危なければ逃げる
			return [
				{ "cond": "self_hp_below", "param": 0.25, "action": "retreat" },
				{ "cond": "ally_hp_below", "param": 0.7, "action": "heal_lowest_hp_ally" },
				{ "cond": "enemy_in_range", "action": "attack_nearest" },
				{ "cond": "nearest_enemy_exists", "action": "move_to_nearest_enemy" },
			]
		"Support":  # 弱った敵を集中攻撃。危なければ後退
			return [
				{ "cond": "self_hp_below", "param": 0.3, "action": "retreat" },
				{ "cond": "enemy_in_range", "action": "attack_weakest" },
				{ "cond": "nearest_enemy_exists", "action": "move_to_nearest_enemy" },
			]
		_:  # Frontline / Raider / Brute など：接近して殴る
			return [
				{ "cond": "enemy_in_range", "action": "attack_nearest" },
				{ "cond": "nearest_enemy_exists", "action": "move_to_nearest_enemy" },
			]


# ============================================================
# 描画：味方＝丸、敵＝四角。上に名前とHPバー。
# ============================================================
func _draw() -> void:
	if _dead:
		return

	if team == Team.ALLY:
		draw_circle(Vector2.ZERO, radius, base_color)
	else:
		draw_rect(Rect2(-radius, -radius, radius * 2.0, radius * 2.0), base_color)

	# HPバー
	var bar_w: float = radius * 2.0
	var bar_y: float = -radius - 12.0
	var ratio: float = float(hp) / float(max_hp)
	draw_rect(Rect2(-radius, bar_y, bar_w, 5.0), Color(0.15, 0.15, 0.15))
	draw_rect(Rect2(-radius, bar_y, bar_w * ratio, 5.0), Color(0.25, 0.9, 0.35))

	# 名前
	var font: Font = ThemeDB.fallback_font
	draw_string(font, Vector2(-radius, radius + 16.0), unit_name,
		HORIZONTAL_ALIGNMENT_LEFT, bar_w + 40.0, 14)
