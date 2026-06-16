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
var _low_hp_warned: bool = false  # HP低下アラートを既に出したか
var _narration_cd: float = 0.0    # 行動ナレーションlog のクールダウン（連投防止）
const NARRATION_INTERVAL: float = 3.0
var battle: Node = null           # Main への参照（ログ出力・一時停止判定に使う）


# 陣営名（ログのフィルタ用）
func team_name() -> String:
	return "ally" if team == Team.ALLY else "enemy"


# 辞書からステータスを設定する。Main 側から呼ぶ。
func setup(data: Dictionary) -> void:
	unit_name = data.get("name", unit_name)
	team = int(data.get("team", team))
	role = data.get("role", role)
	max_hp = int(data.get("max_hp", max_hp))
	hp = max_hp
	attack_power = int(data.get("attack", attack_power))
	defense = int(data.get("defense", defense))
	heal_power = int(data.get("heal_power", heal_power))
	move_speed = float(data.get("move_speed", move_speed))
	attack_range = float(data.get("attack_range", attack_range))
	attack_cooldown = float(data.get("attack_cooldown", attack_cooldown))
	radius = float(data.get("radius", radius))

	# 色は Color でも "#RRGGBB" 文字列でも受け付ける
	var col: Variant = data.get("color", base_color)
	if col is String:
		base_color = Color.html(col)
	elif col is Color:
		base_color = col

	# ガンビットは明示指定があればそれを、なければロール既定を使う
	var g: Variant = data.get("gambits", [])
	if g is Array and not g.is_empty():
		gambits = g
	else:
		gambits = _default_gambits(role)

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
	if _narration_cd > 0.0:
		_narration_cd -= delta

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
		"backline_threatened":
			return _find_threatened_backline(param) != null
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
		"focus_fire":
			_act_attack(_focus_or_nearest(), delta)
		"protect_ally":
			_act_protect_ally(rule.get("param", 150.0), delta)
		"retreat":
			_act_retreat(delta)
		"retreat_to_safe":
			_act_retreat_to_safe(rule.get("factor", 1.3), delta)
		"flee_to_healer":
			_act_flee_to_healer(rule.get("factor", 1.3), delta)
		"heal_self":
			_act_heal_self()
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


# チームの集中ターゲットを優先（無ければ最寄り敵）。味方で同じ敵を集中攻撃。
func _focus_or_nearest() -> Unit:
	if battle and battle.has_method("get_focus_target"):
		var f: Unit = battle.get_focus_target(team)
		if f != null:
			return f
	return _find_nearest_enemy()


# 脅威にさらされた後衛の味方と敵の「間」へ回り込んで守る。
# 守る相手が居なければ通常攻撃にフォールバック。脅威が射程内なら迎撃する。
func _act_protect_ally(param: float, delta: float) -> void:
	var ally: Unit = _find_threatened_backline(param)
	if ally == null:
		_act_attack(_find_nearest_enemy(), delta)
		return
	var threat: Unit = _nearest_enemy_to(ally.global_position)
	if threat == null:
		_act_attack(_find_nearest_enemy(), delta)
		return
	# 脅威が自分の射程内に居れば迎撃（盾として殴り返す）
	if global_position.distance_to(threat.global_position) <= attack_range:
		_set_action("護衛(迎撃)")
		_try_attack(threat)
		return
	# 守る味方の「敵側」に立ち、間に割り込む
	var dir: Vector2 = (threat.global_position - ally.global_position).normalized()
	var guard_pos: Vector2 = ally.global_position + dir * (radius * 2.0 + 16.0)
	_set_action("護衛")
	var mv: Vector2 = guard_pos - global_position
	if mv.length() > 2.0:
		global_position += mv.normalized() * move_speed * delta
	_clamp_to_battlefield()


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
	_clamp_to_battlefield()


# 安全距離まで下がったら止まる「際限のある後退」。
# safe = 生存している敵の最大射程 × factor（近接だけなら近め、遠距離が居れば遠くまで）
func _act_retreat_to_safe(factor: float, delta: float) -> void:
	var e: Unit = _find_nearest_enemy()
	if e == null:
		_set_action("待機")
		return
	# 最寄りの脅威の射程 × factor まで下がる。最低 150px は確保（トリガー距離より広く）。
	var safe: float = max(150.0, e.attack_range * factor)
	var d: float = global_position.distance_to(e.global_position)
	if d >= safe:
		_set_action("待機(警戒)")  # 十分離れた → その場で警戒
	else:
		_set_action("後退")
		var dir: Vector2 = (global_position - e.global_position).normalized()
		global_position += dir * move_speed * delta
		_clamp_to_battlefield()


# 衛生兵のところへ後退する（衛生兵が居なければ安全距離後退にフォールバック）
func _act_flee_to_healer(factor: float, delta: float) -> void:
	var medic: Unit = _find_nearest_healer()
	if medic == null:
		_act_retreat_to_safe(factor, delta)
		return
	var d: float = global_position.distance_to(medic.global_position)
	if d > 48.0:
		_set_action("後退")
		var dir: Vector2 = (medic.global_position - global_position).normalized()
		global_position += dir * move_speed * delta
		_clamp_to_battlefield()
	else:
		_set_action("待機(警戒)")  # 衛生兵のそばで回復を待つ


# 自己回復（衛生兵が自分を治す）
func _act_heal_self() -> void:
	if hp >= max_hp:
		_set_action("待機")
		return
	_set_action("自己回復")
	if _cooldown_timer <= 0.0:
		_cooldown_timer = attack_cooldown
		if battle:
			battle.add_heal_fx(global_position, base_color)
			battle.play_heal_sfx()
		receive_heal(heal_power, self)


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
			if battle:
				battle.add_heal_fx(ally.global_position, base_color)
				battle.play_heal_sfx()
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


# 生存ユニットの取得（Main 側のキャッシュを使う。無ければグループ直引き）
func _units_in(group_name: String) -> Array:
	if battle and battle.has_method("get_alive_units"):
		return battle.get_alive_units(group_name)
	return get_tree().get_nodes_in_group(group_name)


# 最も近い「生きている敵」
func _find_nearest_enemy() -> Unit:
	var nearest: Unit = null
	var best: float = INF
	for u in _units_in(_enemy_group()):
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
	for u in _units_in(_enemy_group()):
		if not u.is_alive():
			continue
		if u.hp < lowest:
			lowest = u.hp
			weakest = u
	return weakest


# 生存している敵の最大攻撃射程（後退の安全距離計算に使う）
func _max_enemy_range() -> float:
	var m: float = 0.0
	for u in _units_in(_enemy_group()):
		if u.is_alive() and u.attack_range > m:
			m = u.attack_range
	return m


# 最も近い「生きている味方の衛生兵（heal_power>0）」。自分は除く。
func _find_nearest_healer() -> Unit:
	var nearest: Unit = null
	var best: float = INF
	for u in _units_in(_ally_group()):
		if u == self or not u.is_alive() or u.heal_power <= 0:
			continue
		var d: float = global_position.distance_to(u.global_position)
		if d < best:
			best = d
			nearest = u
	return nearest


# HP割合が threshold 未満で最も弱った味方（自分以外）。Medic の回復対象用。
func _find_wounded_ally(threshold: float) -> Unit:
	var target: Unit = null
	var lowest_ratio: float = threshold
	for u in _units_in(_ally_group()):
		if u == self or not u.is_alive():
			continue
		var ratio: float = float(u.hp) / float(u.max_hp)
		if ratio < lowest_ratio:
			lowest_ratio = ratio
			target = u
	return target


# 指定座標に最も近い「生きている敵」
func _nearest_enemy_to(pos: Vector2) -> Unit:
	var nearest: Unit = null
	var best: float = INF
	for u in _units_in(_enemy_group()):
		if not u.is_alive():
			continue
		var d: float = pos.distance_to(u.global_position)
		if d < best:
			best = d
			nearest = u
	return nearest


# 後衛ロール判定（射撃・支援・衛生兵、または回復役）
func _is_backline(u: Unit) -> bool:
	return u.heal_power > 0 or u.role == "Shooter" or u.role == "Support" or u.role == "Medic"


# 敵が param px 以内に迫っている後衛の味方のうち、最も脅威が近い1体（自分以外）。
# protect_ally の対象。守る必要が無ければ null。
func _find_threatened_backline(param: float) -> Unit:
	var best: Unit = null
	var best_threat: float = param
	for u in _units_in(_ally_group()):
		if u == self or not u.is_alive() or not _is_backline(u):
			continue
		var e: Unit = _nearest_enemy_to(u.global_position)
		if e == null:
			continue
		var d: float = u.global_position.distance_to(e.global_position)
		if d < best_threat:
			best_threat = d
			best = u
	return best


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
	if battle:
		var kind: String = "slash" if attack_range <= 90.0 else "beam"
		battle.add_attack_fx(global_position, target.global_position, base_color, kind)
		battle.play_attack_sfx()
		battle.report_attack(team, target)  # チームの集中ターゲットを更新
	target.take_damage(damage, self)


func take_damage(amount: int, source: Unit) -> void:
	if _dead:
		return
	hp -= amount
	if battle:
		battle.log_message("%s が %s に %d ダメージ" % [source.unit_name, unit_name, amount],
			"attack", source.team_name())
	if hp <= 0:
		hp = 0
		_die()
	else:
		_check_low_hp()
	queue_redraw()


func receive_heal(amount: int, source: Unit) -> void:
	if _dead or amount <= 0:
		return
	var before: int = hp
	hp = min(max_hp, hp + amount)
	if battle and hp > before:
		battle.log_message("✚ %s が %s を %d 回復" % [source.unit_name, unit_name, hp - before],
			"heal", source.team_name())
	_check_low_hp()  # 回復でしきい値を上回ったら警告フラグを戻す
	queue_redraw()


# HPがしきい値を下回った瞬間だけ Main にアラートを通知する
func _check_low_hp() -> void:
	if battle == null:
		return
	var ratio: float = float(hp) / float(max_hp)
	if ratio < battle.low_hp_threshold:
		if not _low_hp_warned:
			_low_hp_warned = true
			battle.on_low_hp(self)
	else:
		_low_hp_warned = false


func _die() -> void:
	_dead = true
	remove_from_group("ally")
	remove_from_group("enemy")
	if battle:
		battle.log_message("☠ %s は倒れた" % unit_name, "death", team_name())
	queue_redraw()


# 戦場の枠内に位置を制限する（後退用）
func _clamp_to_battlefield() -> void:
	if battle == null:
		return
	var r: Rect2 = battle.battle_rect
	var m: float = radius + 2.0
	global_position.x = clamp(global_position.x, r.position.x + m, r.position.x + r.size.x - m)
	global_position.y = clamp(global_position.y, r.position.y + m, r.position.y + r.size.y - m)


# 行動が変わった時だけ、目立つ判断をログに出す。
# ただし毎フレームの状態フリップでログが溢れないよう、ユニットごとに
# クールダウン（NARRATION_INTERVAL秒）を設けて間引く。
func _set_action(label: String) -> void:
	if label == _last_action:
		return
	_last_action = label
	if battle == null or _narration_cd > 0.0:
		return  # 直近に喋ったばかり → 行動は継続するがログは出さない

	var msg: String = ""
	var cat: String = "retreat"
	match label:
		"後退":
			msg = "← %s は危険を察知して後退する" % unit_name
			cat = "retreat"
		"自己回復":
			msg = "%s は自分を治療する" % unit_name
			cat = "heal"
		"回復", "接近(回復)":
			msg = "%s は負傷した味方を助けに向かう" % unit_name
			cat = "heal"
		"護衛", "護衛(迎撃)":
			msg = "%s は仲間を守るため前に出る" % unit_name
			cat = "retreat"
	if msg != "":
		battle.log_message(msg, cat, team_name())
		_narration_cd = NARRATION_INTERVAL


# ============================================================
# ロール別の既定ガンビット
# ============================================================
func _default_gambits(r: String) -> Array:
	match r:
		"Shooter":  # 近づかれたらカイト。瀕死なら衛生兵へ。射程内は味方と集中攻撃
			return [
				{ "cond": "self_hp_below", "param": 0.3, "action": "flee_to_healer", "factor": 1.3 },
				{ "cond": "enemy_too_close", "param": 130.0, "action": "retreat_to_safe", "factor": 1.2 },
				{ "cond": "enemy_in_range", "action": "focus_fire" },
				{ "cond": "nearest_enemy_exists", "action": "move_to_nearest_enemy" },
			]
		"Medic":  # 危険なら安全圏へ→自己回復→味方回復→復帰
			return [
				{ "cond": "enemy_too_close", "param": 110.0, "action": "retreat_to_safe", "factor": 1.3 },
				{ "cond": "self_hp_below", "param": 0.6, "action": "heal_self" },
				{ "cond": "ally_hp_below", "param": 0.7, "action": "heal_lowest_hp_ally" },
				{ "cond": "enemy_in_range", "action": "attack_nearest" },
				{ "cond": "nearest_enemy_exists", "action": "move_to_nearest_enemy" },
			]
		"Support":  # 味方が狙う敵を集中攻撃（援護）。瀕死なら衛生兵へ
			return [
				{ "cond": "self_hp_below", "param": 0.3, "action": "flee_to_healer" },
				{ "cond": "enemy_in_range", "action": "focus_fire" },
				{ "cond": "nearest_enemy_exists", "action": "move_to_nearest_enemy" },
			]
		"Scout":  # 高速・弱点狙い。瀕死なら安全圏へ
			return [
				{ "cond": "self_hp_below", "param": 0.3, "action": "retreat_to_safe" },
				{ "cond": "enemy_in_range", "action": "attack_weakest" },
				{ "cond": "nearest_enemy_exists", "action": "move_to_nearest_enemy" },
			]
		"Frontline":  # 盾役。後衛が狙われたら割り込んで守る→いなければ普通に殴る
			return [
				{ "cond": "backline_threatened", "param": 150.0, "action": "protect_ally" },
				{ "cond": "enemy_in_range", "action": "attack_nearest" },
				{ "cond": "nearest_enemy_exists", "action": "move_to_nearest_enemy" },
			]
		_:  # Raider / Brute：純アタッカー。退かずHP0まで戦う
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
