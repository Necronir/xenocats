class_name DodgeArena
extends Control

## DodgeArena: Мини-игра уворота в боксе в стиле Undertale (ADR-001 Section 2.4)
## Аватар имеет 3 независимых сегментных коллайдера:
##   Верхний -> Arms (Руки)
##   Центральный -> Body (Корпус)
##   Нижний -> Legs (Ноги)

signal part_hit(slot: PartData.PartSlot, raw_damage: int)
signal dodge_finished(total_hits: int)

const BOX_W: float = 176.0
const BOX_H: float = 112.0
const BASE_AVATAR_SPEED: float = 96.0

var _active: bool = false
var _time_left: float = 0.0
var _total_duration: float = 3.5
var _spawn_timer: float = 0.0
var _pattern_id: StringName = &"saw_sweep"
var _defender_title: String = ""
var _base_damage: int = 12
var _speed_multiplier: float = 1.0
var _invuln_timer: float = 0.0
var _total_hits: int = 0

var _box_origin: Vector2 = Vector2.ZERO
var _avatar_root: Node2D = null
var _bullets_root: Node2D = null
var _status_label: Label = null
var _legend_label: Label = null
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()

# Набор активных снарядов: Array[Dictionary] -> {node: Area2D, vel: Vector2}
var _bullets: Array[Dictionary] = []

var _tex_top: Texture2D = null
var _tex_mid: Texture2D = null
var _tex_bot: Texture2D = null
var _tex_saw: Texture2D = null
var _tex_laser: Texture2D = null
var _tex_acid: Texture2D = null
var _tex_press: Texture2D = null

func _ready() -> void:
	_rng.randomize()
	custom_minimum_size = Vector2(220, 156)
	size = Vector2(220, 156)
	visible = false

	_tex_top = load("res://assets/sprites/ui/dodge_top.png") as Texture2D
	_tex_mid = load("res://assets/sprites/ui/dodge_mid.png") as Texture2D
	_tex_bot = load("res://assets/sprites/ui/dodge_bot.png") as Texture2D
	_tex_saw = load("res://assets/sprites/ui/bullet_saw.png") as Texture2D
	_tex_laser = load("res://assets/sprites/ui/bullet_laser.png") as Texture2D
	_tex_acid = load("res://assets/sprites/ui/bullet_acid.png") as Texture2D
	_tex_press = load("res://assets/sprites/ui/bullet_press.png") as Texture2D

	_box_origin = Vector2((size.x - BOX_W) * 0.5, 22.0)

	_status_label = Label.new()
	_status_label.position = Vector2(0, 2)
	_status_label.size = Vector2(size.x, 18)
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status_label.add_theme_font_size_override("font_size", 9)
	_status_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.35))
	add_child(_status_label)

	_legend_label = Label.new()
	_legend_label.position = Vector2(0, _box_origin.y + BOX_H + 3.0)
	_legend_label.size = Vector2(size.x, 18)
	_legend_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_legend_label.add_theme_font_size_override("font_size", 8)
	_legend_label.text = "[WASD/Стрелки] Верх:РУКИ | Центр:КОРПУС | Низ:НОГИ"
	_legend_label.add_theme_color_override("font_color", Color(0.78, 0.88, 0.98))
	add_child(_legend_label)

	_bullets_root = Node2D.new()
	add_child(_bullets_root)

	_build_segmented_avatar()

func _build_segmented_avatar() -> void:
	_avatar_root = Node2D.new()
	add_child(_avatar_root)

	# 1. Верхний коллайдер -> ARMS (Руки)
	var top_area: Area2D = _create_segment_area(Vector2(0, -7), Vector2(16, 6), _tex_top, PartData.PartSlot.ARMS)
	_avatar_root.add_child(top_area)

	# 2. Центральный коллайдер -> BODY (Корпус)
	var mid_area: Area2D = _create_segment_area(Vector2(0, 0), Vector2(18, 8), _tex_mid, PartData.PartSlot.BODY)
	_avatar_root.add_child(mid_area)

	# 3. Нижний коллайдер -> LEGS (Ноги)
	var bot_area: Area2D = _create_segment_area(Vector2(0, 7), Vector2(14, 6), _tex_bot, PartData.PartSlot.LEGS)
	_avatar_root.add_child(bot_area)

func _create_segment_area(offset: Vector2, box_size: Vector2, tex: Texture2D, slot: PartData.PartSlot) -> Area2D:
	var area: Area2D = Area2D.new()
	area.position = offset
	area.collision_layer = 2
	area.collision_mask = 4

	var spr: Sprite2D = Sprite2D.new()
	spr.texture = tex
	area.add_child(spr)

	var col: CollisionShape2D = CollisionShape2D.new()
	var rect: RectangleShape2D = RectangleShape2D.new()
	rect.size = box_size
	col.shape = rect
	area.add_child(col)

	area.area_entered.connect(func(bullet_area: Area2D) -> void:
		_on_segment_hit(slot, bullet_area)
	)
	return area

func start_dodge(
	defender_name: String,
	pattern_id: StringName,
	base_damage: int,
	speed_mult: float,
	duration: float = 3.5
) -> void:
	_clear_bullets()
	_pattern_id = pattern_id
	_base_damage = base_damage
	_speed_multiplier = speed_mult
	_total_duration = maxf(0.5, duration)
	_time_left = _total_duration
	_spawn_timer = 0.1
	_invuln_timer = 0.0
	_total_hits = 0

	_avatar_root.position = _box_origin + Vector2(BOX_W * 0.5, BOX_H * 0.5)
	_avatar_root.modulate = Color(1, 1, 1, 1)

	var leg_warn: String = " [-40% СКОР]" if _speed_multiplier < 0.9 else ""
	_defender_title = "ЗАЩИТА: " + defender_name + leg_warn
	_update_status_text()
	_active = true
	visible = true
	queue_redraw()

func force_finish() -> void:
	if not _active:
		return
	_active = false
	_clear_bullets()
	visible = false
	dodge_finished.emit(_total_hits)

func _update_status_text() -> void:
	_status_label.text = _defender_title + " (" + String.num(maxf(0.0, _time_left), 1) + "с)"

func _process(delta: float) -> void:
	if not _active:
		return

	# Сначала проверяем таймер завершения фазы уворота!
	_time_left -= delta
	if _time_left <= 0.0:
		force_finish()
		return

	_update_status_text()
	queue_redraw()

	if _invuln_timer > 0.0:
		_invuln_timer -= delta
		_avatar_root.modulate.a = 0.45 if int(_invuln_timer * 20.0) % 2 == 0 else 1.0
	else:
		_avatar_root.modulate.a = 1.0

	# Управление аватаром (WASD / Стрелки)
	var dir: Vector2 = Vector2.ZERO
	if Input.is_key_pressed(KEY_LEFT) or Input.is_key_pressed(KEY_A):
		dir.x -= 1.0
	if Input.is_key_pressed(KEY_RIGHT) or Input.is_key_pressed(KEY_D):
		dir.x += 1.0
	if Input.is_key_pressed(KEY_UP) or Input.is_key_pressed(KEY_W):
		dir.y -= 1.0
	if Input.is_key_pressed(KEY_DOWN) or Input.is_key_pressed(KEY_S):
		dir.y += 1.0

	if dir.length_squared() > 0.0:
		dir = dir.normalized()
		var move_spd: float = BASE_AVATAR_SPEED * _speed_multiplier
		_avatar_root.position += dir * move_spd * delta

	# Ограничение внутри бокса
	_avatar_root.position.x = clampf(
		_avatar_root.position.x,
		_box_origin.x + 11.0,
		_box_origin.x + BOX_W - 11.0
	)
	_avatar_root.position.y = clampf(
		_avatar_root.position.y,
		_box_origin.y + 12.0,
		_box_origin.y + BOX_H - 12.0
	)

	# Спавн снарядов по паттерну
	_spawn_timer -= delta
	if _spawn_timer <= 0.0:
		_spawn_pattern_wave()

	# Движение снарядов (безопасная проверка is_instance_valid ДО приведения типов!)
	for i: int in range(_bullets.size() - 1, -1, -1):
		var b_entry: Dictionary = _bullets[i]
		var raw_node: Variant = b_entry.get("node", null)
		if raw_node == null or not is_instance_valid(raw_node):
			_bullets.remove_at(i)
			continue
		var b_node: Area2D = raw_node as Area2D
		if b_node == null or b_node.is_queued_for_deletion():
			_bullets.remove_at(i)
			continue
		var b_vel: Vector2 = b_entry["vel"] as Vector2
		b_node.position += b_vel * delta
		var p: Vector2 = b_node.position
		if (
			p.x < _box_origin.x - 24.0
			or p.x > _box_origin.x + BOX_W + 24.0
			or p.y < _box_origin.y - 24.0
			or p.y > _box_origin.y + BOX_H + 24.0
		):
			b_node.queue_free()
			_bullets.remove_at(i)

func _spawn_pattern_wave() -> void:
	match _pattern_id:
		&"acid_rain":
			_spawn_timer = 0.34
			var bx: float = _box_origin.x + _rng.randf_range(12.0, BOX_W - 12.0)
			var by: float = _box_origin.y - 6.0
			_create_bullet(Vector2(bx, by), Vector2(_rng.randf_range(-15.0, 15.0), 82.0), _tex_acid, Vector2(8, 8))
		&"press_crush":
			_spawn_timer = 0.48
			if _rng.randf() < 0.6:
				# Сверху (бьет по Верхнему коллайдеру -> Arms)
				var px: float = _box_origin.x + _rng.randf_range(16.0, BOX_W - 16.0)
				_create_bullet(Vector2(px, _box_origin.y - 8.0), Vector2(0, 92.0), _tex_press, Vector2(20, 10))
			else:
				# Сбоку по низу (бьет по Нижнему коллайдеру -> Legs)
				var py: float = _box_origin.y + BOX_H - _rng.randf_range(12.0, 32.0)
				_create_bullet(Vector2(_box_origin.x + BOX_W + 8.0, py), Vector2(-105.0, 0.0), _tex_saw, Vector2(10, 10))
		&"laser_grid":
			_spawn_timer = 0.40
			var from_left: bool = _rng.randf() < 0.5
			var start_x: float = (_box_origin.x - 8.0) if from_left else (_box_origin.x + BOX_W + 8.0)
			var start_y: float = _box_origin.y + _rng.randf_range(10.0, BOX_H - 10.0)
			var start_pos: Vector2 = Vector2(start_x, start_y)
			var aim_dir: Vector2 = (_avatar_root.position - start_pos).normalized()
			_create_bullet(start_pos, aim_dir * 108.0, _tex_laser, Vector2(12, 5))
		_:
			# saw_sweep: пилы справа/слева преимущественно по низу и центру
			_spawn_timer = 0.38
			var side_left: bool = _rng.randf() < 0.45
			var sx: float = (_box_origin.x - 8.0) if side_left else (_box_origin.x + BOX_W + 8.0)
			var sy: float = _box_origin.y + _rng.randf_range(14.0, BOX_H - 10.0)
			var vx: float = 96.0 if side_left else -96.0
			_create_bullet(Vector2(sx, sy), Vector2(vx, _rng.randf_range(-18.0, 18.0)), _tex_saw, Vector2(10, 10))

func _create_bullet(pos: Vector2, vel: Vector2, tex: Texture2D, hitbox: Vector2) -> void:
	var b: Area2D = Area2D.new()
	b.position = pos
	b.collision_layer = 4
	b.collision_mask = 2

	var spr: Sprite2D = Sprite2D.new()
	spr.texture = tex
	b.add_child(spr)

	var col: CollisionShape2D = CollisionShape2D.new()
	var shape: RectangleShape2D = RectangleShape2D.new()
	shape.size = hitbox
	col.shape = shape
	b.add_child(col)

	_bullets_root.add_child(b)
	_bullets.append({"node": b, "vel": vel})

func _on_segment_hit(slot: PartData.PartSlot, bullet_area: Area2D) -> void:
	if not _active:
		return
	if bullet_area != null and is_instance_valid(bullet_area):
		for i: int in range(_bullets.size() - 1, -1, -1):
			var raw_node: Variant = _bullets[i].get("node", null)
			if raw_node != null and is_instance_valid(raw_node) and raw_node == bullet_area:
				_bullets.remove_at(i)
		bullet_area.set_deferred("monitoring", false)
		bullet_area.set_deferred("monitorable", false)
		bullet_area.queue_free()
	if _invuln_timer > 0.0:
		return
	_invuln_timer = 0.32
	_total_hits += 1
	AudioManager.play_sfx("hit")
	part_hit.emit(slot, _base_damage)

func _clear_bullets() -> void:
	for b_entry: Dictionary in _bullets:
		var raw_node: Variant = b_entry.get("node", null)
		if raw_node != null and is_instance_valid(raw_node):
			var b_node: Area2D = raw_node as Area2D
			if b_node != null:
				b_node.queue_free()
	_bullets.clear()

func _draw() -> void:
	# Тёмный фон подложки
	draw_rect(Rect2(0, 0, size.x, size.y), Color(0.04, 0.05, 0.08, 0.94), true)
	draw_rect(Rect2(0, 0, size.x, size.y), Color(0.4, 0.45, 0.55, 1.0), false, 1.0)
	# Бокс арены Undertale-style
	var box_rect: Rect2 = Rect2(_box_origin, Vector2(BOX_W, BOX_H))
	draw_rect(box_rect, Color(0.02, 0.02, 0.04, 1.0), true)
	draw_rect(box_rect, Color(0.95, 0.95, 0.98, 1.0), false, 2.0)
	# Полоска оставшегося времени уворота над боксом
	var ratio: float = clampf(_time_left / maxf(0.1, _total_duration), 0.0, 1.0)
	draw_rect(Rect2(_box_origin.x, _box_origin.y - 4.0, BOX_W * ratio, 2.0), Color(0.3, 0.95, 1.0, 1.0), true)
