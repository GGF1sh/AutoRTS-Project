class_name Unit
extends Node2D

# ============================================================
# Unit.gd
# 味方・敵で共通の「1体のユニット」。
# Phase 1 の行動はシンプル：
#   1. 最も近い敵を探す
#   2. 射程外なら近づく
#   3. 射程内なら攻撃する
# ※ 回復・後退などのロール別AIは Phase 6〜7 で追加予定。
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
var move_speed: float = 80.0      # 1秒あたりの移動ピクセル数
var attack_range: float = 48.0    # この距離以内なら攻撃できる
var attack_cooldown: float = 1.0  # 攻撃の間隔（秒）
var radius: float = 16.0          # 見た目の半径
var base_color: Color = Color.WHITE

# --- 内部状態 ---
var _cooldown_timer: float = 0.0  # 0 以下なら攻撃可能
var _dead: bool = false
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
	move_speed = data.get("move_speed", move_speed)
	attack_range = data.get("attack_range", attack_range)
	attack_cooldown = data.get("attack_cooldown", attack_cooldown)
	radius = data.get("radius", radius)
	base_color = data.get("color", base_color)

	# グループに登録しておくと、敵味方をまとめて探しやすい
	add_to_group("units")
	add_to_group("ally" if team == Team.ALLY else "enemy")


func is_alive() -> bool:
	return not _dead and hp > 0


func _process(delta: float) -> void:
	# 参照が無い／一時停止中／死亡中は何もしない（独自フラグ方式）
	if battle == null or battle.is_paused or not is_alive():
		return

	# 攻撃クールダウンを進める
	if _cooldown_timer > 0.0:
		_cooldown_timer -= delta

	var target: Unit = _find_nearest_enemy()
	if target == null:
		return  # 敵が残っていない

	var dist: float = global_position.distance_to(target.global_position)
	if dist <= attack_range:
		_try_attack(target)
	else:
		_move_toward(target, delta)


# 最も近い「生きている敵」を返す。いなければ null。
func _find_nearest_enemy() -> Unit:
	var enemy_group: String = "enemy" if team == Team.ALLY else "ally"
	var nearest: Unit = null
	var best: float = INF
	for u in get_tree().get_nodes_in_group(enemy_group):
		if not u.is_alive():
			continue
		var d: float = global_position.distance_to(u.global_position)
		if d < best:
			best = d
			nearest = u
	return nearest


func _move_toward(target: Unit, delta: float) -> void:
	var dir: Vector2 = (target.global_position - global_position).normalized()
	global_position += dir * move_speed * delta


func _try_attack(target: Unit) -> void:
	if _cooldown_timer > 0.0:
		return  # まだ攻撃できない
	_cooldown_timer = attack_cooldown
	var damage: int = max(1, attack_power - target.defense)
	target.take_damage(damage, self)


# ダメージを受ける。source は攻撃してきたユニット。
func take_damage(amount: int, source: Unit) -> void:
	if _dead:
		return
	hp -= amount
	if battle:
		battle.log_message("%s が %s に %d ダメージ" % [source.unit_name, unit_name, amount])
	if hp <= 0:
		hp = 0
		_die()
	queue_redraw()  # HPバーを更新


func _die() -> void:
	_dead = true
	# もう狙われないように陣営グループから外す
	remove_from_group("ally")
	remove_from_group("enemy")
	if battle:
		battle.log_message("☠ %s は倒れた" % unit_name)
	queue_redraw()


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
