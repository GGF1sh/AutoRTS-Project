class_name Fx
extends Node2D

# ============================================================
# Fx.gd
# 攻撃・回復のエフェクトを描画する層。Main の子（ユニットより後ろに
# 追加）として置き、ユニットの上に重ねて描く。座標はワールド座標。
# ============================================================

# エフェクト1件 = { type, from, to, color, t, life }
var _effects: Array = []


func add_attack(from: Vector2, to: Vector2, color: Color, kind: String = "beam") -> void:
	var ty: String = "slash" if kind == "slash" else "line"
	_effects.append({ "type": ty, "from": from, "to": to, "color": color, "t": 0.18, "life": 0.18 })
	queue_redraw()


func add_heal(pos: Vector2) -> void:
	_effects.append({ "type": "heal", "from": pos, "to": pos, "color": Color.GREEN, "t": 0.45, "life": 0.45 })
	queue_redraw()


func _process(delta: float) -> void:
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


func _draw() -> void:
	for fx in _effects:
		var a: float = clamp(fx["t"] / fx["life"], 0.0, 1.0)
		match fx["type"]:
			"line":  # 遠距離：ビーム＋着弾
				var c: Color = fx["color"]
				c.a = a
				draw_line(fx["from"], fx["to"], c, 2.0)
				draw_circle(fx["to"], 3.0 + 4.0 * a, c)
			"slash":  # 近距離：斜めに走るスラッシュ
				_draw_slash(fx["to"], a)
			"heal":  # 回復：うにょうにょと立ち上る線
				_draw_heal_squiggle(fx["from"], a)


func _draw_slash(center: Vector2, a: float) -> void:
	var p: float = 1.0 - a
	var axis: Vector2 = Vector2(0.7071, -0.7071)
	var perp: Vector2 = Vector2(axis.y, -axis.x)
	var c: Vector2 = center + axis * lerp(-18.0, 18.0, p)
	var half: float = 16.0
	draw_line(c - perp * half, c + perp * half, Color(1.0, 1.0, 1.0, a), 3.0)


func _draw_heal_squiggle(base: Vector2, a: float) -> void:
	var phase: float = (1.0 - a) * 6.0
	var pts: PackedVector2Array = PackedVector2Array()
	for k in 13:
		var yy: float = base.y - float(k) * 4.0
		var xx: float = base.x + sin(float(k) * 0.9 + phase) * 7.0
		pts.append(Vector2(xx, yy))
	if pts.size() >= 2:
		draw_polyline(pts, Color(0.40, 1.0, 0.55, a), 2.0)
