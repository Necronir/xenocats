class_name DodgeArena
extends Control

## DodgeArena: Мини-игра уворота в боксе в стиле Undertale (ADR-001 Section 2.4 & 2.5)
## Аватар имеет 3 независимых сегментных коллайдера:
##   Верхний -> Arms (Руки)
##   Центральный -> Body (Корпус)
##   Нижний -> Legs (Ноги)
## Поддерживает телеграфирование траекторий (Telegraphing) и модульные волны снарядов (Issue #10).

signal part_hit(slot: PartData.PartSlot, raw_damage: int)
signal dodge_finished(total_hits: int)
signal wave_started(wave_index: int, wave_count: int, pattern_id: StringName)

const BOX_W: float = 176.0
const BOX_H: float = 112.0
const BASE_AVATAR_SPEED: float = 96.0

var _active: bool = false
var _time_left: float = 0.0
var _total_duration: float = 3.5
var _spawn_timer: float = 0.0
var _pattern_id: StringName = &"saw_sweep"
var _pattern_sequence: Array[StringName] = []
var _current_wave_index: int = 0
var _wave_duration: float = 3.5
var _wave_time_left: float = 3.5

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

# Набор активных снарядов: Array[Dictionary]
var _bullets: Array[Dictionary] = []

# Предупреждающие маркеры (Telegraphing): Array[Dictionary]
var _telegraphs: Array[Dictionary] = []

var _tex_top: Texture2D = null
var _tex_mid: Texture2D = null
var _tex_bot: Texture2D = null
var _tex_saw: Texture2D = null
var _tex_laser: Texture2D = null
var _tex_acid: Texture2D = null
var _tex_press: Texture2D = null
var _tex_hammer: Texture2D = null
var _tex_shard: Texture2D = null
var _tex_orb: Texture2D = null
var _tex_satellite_bomb: Texture2D = null
var _tex_pulse: Texture2D = null

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
	_tex_hammer = load("res://assets/sprites/ui/bullet_hammer.png") as Texture2D
	_tex_shard = load("res://assets/sprites/ui/bullet_shard.png") as Texture2D
	_tex_orb = load("res://assets/sprites/ui/bullet_orb.png") as Texture2D
	_tex_satellite_bomb = load("res://assets/sprites/ui/bullet_satellite_bomb.png") as Texture2D
	_tex_pulse = load("res://assets/sprites/ui/bullet_pulse.png") as Texture2D

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

## Запуск фазы уворота. Поддерживает StringName, String, или Array волн (Issue #10)
func start_dodge(
	defender_name: String,
	pattern_data: Variant,
	base_damage: int,
	speed_mult: float,
	duration: float = 3.5
) -> void:
	_clear_bullets()
	_base_damage = base_damage
	_speed_multiplier = speed_mult
	_total_duration = maxf(0.5, duration)
	_time_left = _total_duration
	_invuln_timer = 0.0
	_total_hits = 0

	_parse_pattern_sequence(pattern_data)
	_current_wave_index = 0
	_pattern_id = _pattern_sequence[0]
	_wave_duration = _total_duration / float(maxi(1, _pattern_sequence.size()))
	_wave_time_left = _wave_duration
	_spawn_timer = 0.08

	_avatar_root.position = _box_origin + Vector2(BOX_W * 0.5, BOX_H * 0.5)
	_avatar_root.modulate = Color(1, 1, 1, 1)

	var leg_warn: String = " [-40% СКОР]" if _speed_multiplier < 0.9 else ""
	_defender_title = "ЗАЩИТА: " + defender_name + leg_warn
	_update_status_text()
	_active = true
	visible = true
	queue_redraw()

func _parse_pattern_sequence(pattern_data: Variant) -> void:
	_pattern_sequence.clear()
	if pattern_data is Array:
		for item: Variant in pattern_data:
			var s_item: String = str(item).strip_edges()
			if not s_item.is_empty():
				_pattern_sequence.append(StringName(s_item))
	elif pattern_data is StringName or pattern_data is String:
		var s: String = str(pattern_data).strip_edges()
		if s.contains(",") or s.contains(";"):
			var sep: String = ";" if s.contains(";") else ","
			var parts: PackedStringArray = s.split(sep)
			for p_part: String in parts:
				var clean: String = p_part.strip_edges()
				if not clean.is_empty():
					_pattern_sequence.append(StringName(clean))
		elif s == "boss_press":
			_pattern_sequence = [&"boss_press_hammers", &"press_crush"]
		elif s == "boss_atamansha":
			_pattern_sequence = [&"boss_atamansha_crane", &"boss_atamansha_rotating"]
		elif s == "boss_satellite":
			_pattern_sequence = [&"boss_satellite_orbital", &"boss_satellite_homing", &"boss_satellite_interference"]
		else:
			_pattern_sequence = [StringName(s)]

	if _pattern_sequence.is_empty():
		_pattern_sequence = [&"saw_sweep"]

func force_finish() -> void:
	if not _active:
		return
	_active = false
	_clear_bullets()
	visible = false
	dodge_finished.emit(_total_hits)

func _update_status_text() -> void:
	var wave_info: String = ""
	if _pattern_sequence.size() > 1:
		wave_info = " [ВОЛНА " + str(_current_wave_index + 1) + "/" + str(_pattern_sequence.size()) + "]"
	_status_label.text = _defender_title + wave_info + " (" + String.num(maxf(0.0, _time_left), 1) + "с)"

func _process(delta: float) -> void:
	if not _active:
		return

	# Таймер общего завершения фазы уворота
	_time_left -= delta
	if _time_left <= 0.0:
		force_finish()
		return

	# Прогрессия модульных волн (Multi-Wave Sequencer)
	if _pattern_sequence.size() > 1:
		_wave_time_left -= delta
		if _wave_time_left <= 0.0 and _current_wave_index + 1 < _pattern_sequence.size():
			_current_wave_index += 1
			_pattern_id = _pattern_sequence[_current_wave_index]
			_wave_time_left = _wave_duration
			_spawn_timer = 0.05
			wave_started.emit(_current_wave_index, _pattern_sequence.size(), _pattern_id)
			AudioManager.play_sfx("ui_click")

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

	# Обработка активных маркеров телеграфа (Telegraphing)
	for i: int in range(_telegraphs.size() - 1, -1, -1):
		var tg: Dictionary = _telegraphs[i]
		var t_rem: float = float(tg.get("time_left", 0.0)) - delta
		tg["time_left"] = t_rem
		if t_rem <= 0.0:
			_telegraphs.remove_at(i)
			var cb: Variant = tg.get("on_trigger", null)
			if cb is Callable and cb.is_valid():
				cb.call()

	# Спавн снарядов по паттерну
	_spawn_timer -= delta
	if _spawn_timer <= 0.0:
		_spawn_pattern_wave()

	# Движение снарядов с поддержкой продвинутых паттернов (линейный, молот, осколки, наведение, орбита, волны)
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

		var b_type: StringName = b_entry.get("type", &"linear")
		var b_vel: Vector2 = b_entry.get("vel", Vector2.ZERO)

		match b_type:
			&"hammer":
				# Молот Трёхголового Пресса: если ещё взведён, слегка вибрирует у потолка
				if bool(b_entry.get("primed", false)):
					var base_hx: float = float(b_entry.get("hx", b_node.position.x))
					b_node.position.x = base_hx + _rng.randf_range(-1.2, 1.2)
				else:
					b_node.position += b_vel * delta
					var floor_y: float = float(b_entry.get("floor_y", _box_origin.y + BOX_H - 8.0))
					if b_node.position.y >= floor_y:
						# Удар о пол: порождает осколки по нижней зоне (Legs)
						_create_bullet(Vector2(b_node.position.x, floor_y - 2.0), Vector2(-130.0, 0.0), _tex_shard, Vector2(10, 6), &"shard")
						_create_bullet(Vector2(b_node.position.x, floor_y - 2.0), Vector2(130.0, 0.0), _tex_shard, Vector2(10, 6), &"shard")
						AudioManager.play_sfx("hit")
						b_node.queue_free()
						_bullets.remove_at(i)
						continue

			&"shard":
				# Осколки от удара молота: летят по полу, вращаясь
				b_node.position += b_vel * delta
				b_node.rotation += (12.0 if b_vel.x > 0.0 else -12.0) * delta

			&"homing":
				# Самонаводящиеся радио-сферы Спящего Спутника
				var spd: float = float(b_entry.get("homing_speed", 62.0))
				var turn_rate: float = float(b_entry.get("turn_rate", 2.2))
				var desired_dir: Vector2 = (_avatar_root.position - b_node.position).normalized()
				var cur_dir: Vector2 = b_vel.normalized()
				if cur_dir.length_squared() < 0.01:
					cur_dir = desired_dir
				var new_dir: Vector2 = cur_dir.slerp(desired_dir, clampf(turn_rate * delta, 0.0, 1.0)).normalized()
				b_vel = new_dir * spd
				b_entry["vel"] = b_vel
				b_node.position += b_vel * delta
				b_node.rotation += 3.5 * delta

			&"orbit":
				# Вращающиеся лазерные лучи Атаманши
				var pivot: Vector2 = b_entry.get("pivot", _box_origin + Vector2(BOX_W * 0.5, BOX_H * 0.5))
				var ang: float = float(b_entry.get("angle", 0.0)) + float(b_entry.get("ang_spd", 2.2)) * delta
				var rad: float = float(b_entry.get("radius", 14.0)) + float(b_entry.get("expand_spd", 35.0)) * delta
				b_entry["angle"] = ang
				b_entry["radius"] = rad
				b_node.position = pivot + Vector2(cos(ang), sin(ang)) * rad
				b_node.rotation = ang + PI * 0.5

			&"wave":
				# Фазовые помехи (синусоидальные волны радиочастот)
				var w_time: float = float(b_entry.get("w_time", 0.0)) + delta
				b_entry["w_time"] = w_time
				var base_x: float = float(b_entry.get("base_x", b_node.position.x)) + b_vel.x * delta
				b_entry["base_x"] = base_x
				var base_y: float = float(b_entry.get("base_y", b_node.position.y))
				var freq: float = float(b_entry.get("freq", 7.0))
				var amp: float = float(b_entry.get("amp", 16.0))
				b_node.position = Vector2(base_x, base_y + sin(w_time * freq) * amp)

			_:
				# Обычные линейные пули
				if bool(b_entry.get("primed", false)):
					# Ожидание триггера телеграфа
					pass
				else:
					b_node.position += b_vel * delta

		var p: Vector2 = b_node.position
		if (
			p.x < _box_origin.x - 30.0
			or p.x > _box_origin.x + BOX_W + 30.0
			or p.y < _box_origin.y - 30.0
			or p.y > _box_origin.y + BOX_H + 30.0
		):
			b_node.queue_free()
			_bullets.remove_at(i)

## Создание предупреждающих маркеров (Telegraphing)
func add_telegraph_rect(rect: Rect2, duration: float, on_trigger: Callable, color: Color = Color(1.0, 0.22, 0.22)) -> Dictionary:
	var tg: Dictionary = {
		"type": &"rect",
		"rect": rect,
		"time_left": duration,
		"duration": duration,
		"color": color,
		"on_trigger": on_trigger
	}
	_telegraphs.append(tg)
	queue_redraw()
	return tg

func add_telegraph_line(p1: Vector2, p2: Vector2, duration: float, on_trigger: Callable, width: float = 2.0, color: Color = Color(1.0, 0.22, 0.22)) -> Dictionary:
	var tg: Dictionary = {
		"type": &"line",
		"p1": p1,
		"p2": p2,
		"width": width,
		"time_left": duration,
		"duration": duration,
		"color": color,
		"on_trigger": on_trigger
	}
	_telegraphs.append(tg)
	queue_redraw()
	return tg

func add_telegraph_circle(center: Vector2, radius: float, duration: float, on_trigger: Callable, color: Color = Color(1.0, 0.22, 0.22)) -> Dictionary:
	var tg: Dictionary = {
		"type": &"circle",
		"center": center,
		"radius": radius,
		"time_left": duration,
		"duration": duration,
		"color": color,
		"on_trigger": on_trigger
	}
	_telegraphs.append(tg)
	queue_redraw()
	return tg

func _spawn_pattern_wave() -> void:
	if String(_pattern_id).contains("+"):
		var sub_patterns: PackedStringArray = String(_pattern_id).split("+")
		for sub: String in sub_patterns:
			var sp_id: StringName = StringName(sub.strip_edges())
			_spawn_single_pattern(sp_id)
	else:
		_spawn_single_pattern(_pattern_id)

func _spawn_single_pattern(pattern_name: StringName) -> void:
	match pattern_name:
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

		# === Уникальные паттерны боссов и элиток (Issue #10) ===

		&"boss_press_hammers", &"boss_press":
			# Трёхголовый пресс: вертикальные молоты с предупреждающими линиями телеграфа + осколки по зоне Legs
			_spawn_timer = 0.52
			var hx: float = _box_origin.x + _rng.randf_range(20.0, BOX_W - 20.0)
			var col_rect: Rect2 = Rect2(hx - 12.0, _box_origin.y, 24.0, BOX_H)
			var floor_y: float = _box_origin.y + BOX_H - 8.0

			var hammer_node: Area2D = _create_bullet(
				Vector2(hx, _box_origin.y - 10.0),
				Vector2.ZERO,
				_tex_hammer,
				Vector2(20.0, 16.0),
				&"hammer",
				{"floor_y": floor_y, "primed": true, "slam_vel": Vector2(0.0, 240.0), "hx": hx}
			)

			add_telegraph_rect(col_rect, 0.42, func() -> void:
				if is_instance_valid(hammer_node):
					for b_entry: Dictionary in _bullets:
						if b_entry.get("node") == hammer_node:
							b_entry["primed"] = false
							b_entry["vel"] = b_entry.get("slam_vel", Vector2(0.0, 240.0))
							break
			)

		&"boss_atamansha_crane":
			# Атаманша (Кран-Шагатель): сканирующий лазерный прицел турели крана
			_spawn_timer = 0.55
			var turret_pos: Vector2 = _box_origin + Vector2(BOX_W * 0.5, 0.0)
			var target_pos: Vector2 = _avatar_root.position
			var aim_dir: Vector2 = (target_pos - turret_pos).normalized()
			var end_pos: Vector2 = turret_pos + aim_dir * 250.0

			# Ведущий снаряд сразу создаётся для мгновенного наличия пули
			var b_lead: Area2D = _create_bullet(
				turret_pos,
				aim_dir * 45.0,
				_tex_laser,
				Vector2(14.0, 5.0),
				&"linear"
			)

			add_telegraph_line(turret_pos, end_pos, 0.40, func() -> void:
				# Залп из 2 концентрированных лучей по маркеру
				_create_bullet(turret_pos, aim_dir * 185.0, _tex_laser, Vector2(16.0, 5.0), &"linear")
				_create_bullet(turret_pos - aim_dir * 14.0, aim_dir * 185.0, _tex_laser, Vector2(16.0, 5.0), &"linear")
			)

		&"boss_atamansha_rotating":
			# Атаманша: вращающиеся расширяющиеся лазерные лучи
			_spawn_timer = 0.70
			var pivot: Vector2 = _box_origin + Vector2(BOX_W * 0.5, BOX_H * 0.5)
			var base_ang: float = _rng.randf_range(0.0, TAU)
			for k: int in 3:
				var ang: float = base_ang + k * (TAU / 3.0)
				_create_bullet(
					pivot,
					Vector2.ZERO,
					_tex_laser,
					Vector2(14.0, 5.0),
					&"orbit",
					{"pivot": pivot, "angle": ang, "radius": 14.0, "ang_spd": 2.2, "expand_spd": 35.0}
				)

		&"boss_atamansha":
			# Композитный паттерн Атаманши: чередование турели и вращающихся лучей
			if _rng.randf() < 0.55:
				_spawn_single_pattern(&"boss_atamansha_crane")
			else:
				_spawn_single_pattern(&"boss_atamansha_rotating")

		&"boss_satellite_orbital":
			# Спящий Спутник: орбитальная бомбардировка с прицельным ретикулом
			_spawn_timer = 0.50
			var bx: float = clampf(_avatar_root.position.x + _rng.randf_range(-14.0, 14.0), _box_origin.x + 16.0, _box_origin.x + BOX_W - 16.0)
			var reticle_center: Vector2 = Vector2(bx, _avatar_root.position.y)

			var bomb_node: Area2D = _create_bullet(
				Vector2(bx, _box_origin.y - 12.0),
				Vector2.ZERO,
				_tex_satellite_bomb,
				Vector2(12.0, 18.0),
				&"linear",
				{"primed": true, "strike_vel": Vector2(0.0, 260.0)}
			)

			add_telegraph_circle(reticle_center, 15.0, 0.44, func() -> void:
				if is_instance_valid(bomb_node):
					for b_entry: Dictionary in _bullets:
						if b_entry.get("node") == bomb_node:
							b_entry["primed"] = false
							b_entry["vel"] = b_entry.get("strike_vel", Vector2(0.0, 260.0))
							break
			)

		&"boss_satellite_homing":
			# Спящий Спутник: самонаводящиеся радио-сферы
			_spawn_timer = 0.75
			var from_left: bool = _rng.randf() < 0.5
			var sx: float = (_box_origin.x - 6.0) if from_left else (_box_origin.x + BOX_W + 6.0)
			var sy: float = _box_origin.y + _rng.randf_range(16.0, BOX_H - 16.0)
			var init_vel: Vector2 = Vector2(55.0 if from_left else -55.0, 0.0)
			_create_bullet(
				Vector2(sx, sy),
				init_vel,
				_tex_orb,
				Vector2(12.0, 12.0),
				&"homing",
				{"homing_speed": 62.0, "turn_rate": 2.2}
			)

		&"boss_satellite_interference":
			# Спящий Спутник: фазовые радиочастотные помехи (синусоидальные волны)
			_spawn_timer = 0.45
			var from_left: bool = _rng.randf() < 0.5
			var sx: float = (_box_origin.x - 8.0) if from_left else (_box_origin.x + BOX_W + 8.0)
			var sy: float = _box_origin.y + _rng.randf_range(20.0, BOX_H - 20.0)
			var vx: float = 85.0 if from_left else -85.0
			_create_bullet(
				Vector2(sx, sy),
				Vector2(vx, 0.0),
				_tex_pulse,
				Vector2(16.0, 8.0),
				&"wave",
				{"base_x": sx, "base_y": sy, "freq": 7.0, "amp": 16.0, "w_time": 0.0}
			)

		&"boss_satellite":
			# Композитный паттерн Спутника: орбитальные бомбы, сферы и фазовые волны
			var roll: float = _rng.randf()
			if roll < 0.45:
				_spawn_single_pattern(&"boss_satellite_orbital")
			elif roll < 0.75:
				_spawn_single_pattern(&"boss_satellite_homing")
			else:
				_spawn_single_pattern(&"boss_satellite_interference")

		_:
			# saw_sweep: пилы справа/слева преимущественно по низу и центру
			_spawn_timer = 0.38
			var side_left: bool = _rng.randf() < 0.45
			var sx: float = (_box_origin.x - 8.0) if side_left else (_box_origin.x + BOX_W + 8.0)
			var sy: float = _box_origin.y + _rng.randf_range(14.0, BOX_H - 10.0)
			var vx: float = 96.0 if side_left else -96.0
			_create_bullet(Vector2(sx, sy), Vector2(vx, _rng.randf_range(-18.0, 18.0)), _tex_saw, Vector2(10, 10))

func _create_bullet(
	pos: Vector2,
	vel: Vector2,
	tex: Texture2D,
	hitbox: Vector2,
	b_type: StringName = &"linear",
	custom_props: Dictionary = {}
) -> Area2D:
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
	var entry: Dictionary = {
		"node": b,
		"vel": vel,
		"type": b_type
	}
	for k: Variant in custom_props.keys():
		entry[k] = custom_props[k]
	_bullets.append(entry)
	return b

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
	_telegraphs.clear()

func _draw() -> void:
	# Тёмный фон подложки
	draw_rect(Rect2(0, 0, size.x, size.y), Color(0.04, 0.05, 0.08, 0.94), true)
	draw_rect(Rect2(0, 0, size.x, size.y), Color(0.4, 0.45, 0.55, 1.0), false, 1.0)

	# Бокс арены Undertale-style
	var box_rect: Rect2 = Rect2(_box_origin, Vector2(BOX_W, BOX_H))
	draw_rect(box_rect, Color(0.02, 0.02, 0.04, 1.0), true)

	# Отрисовка активных маркеров предупреждения (Telegraphing)
	for tg: Dictionary in _telegraphs:
		var col: Color = tg.get("color", Color(1.0, 0.22, 0.22))
		var total_t: float = maxf(0.01, float(tg.get("duration", 0.5)))
		var t_left: float = clampf(float(tg.get("time_left", 0.0)), 0.0, total_t)
		var progress: float = 1.0 - (t_left / total_t)
		var pulse: float = sin(progress * PI * 8.0) * 0.5 + 0.5
		var alpha_fill: float = 0.18 + 0.20 * pulse + 0.15 * progress
		var alpha_line: float = 0.65 + 0.35 * pulse

		var tg_type: StringName = tg.get("type", &"rect")
		match tg_type:
			&"rect":
				var r: Rect2 = tg.get("rect", Rect2())
				# Полупрозрачная зона предупреждения
				draw_rect(r, Color(col.r, col.g, col.b, alpha_fill), true)
				draw_rect(r, Color(col.r, col.g, col.b, alpha_line), false, 1.5)
				# Диагональные предупреждающие штрихи
				draw_line(Vector2(r.position.x, r.position.y), Vector2(r.position.x + r.size.x, r.position.y + r.size.y), Color(col.r, col.g, col.b, 0.25 * pulse), 1.0)

			&"line":
				var p1: Vector2 = tg.get("p1", Vector2.ZERO)
				var p2: Vector2 = tg.get("p2", Vector2.ZERO)
				var w: float = float(tg.get("width", 2.0))
				# Ореол луча
				draw_line(p1, p2, Color(col.r, col.g, col.b, alpha_fill * 1.5), w + 4.0)
				# Концентрированный лазерный прицел
				draw_line(p1, p2, Color(1.0, 0.65 + 0.35 * pulse, 0.65 + 0.35 * pulse, alpha_line), w)
				# Точка наведения на цели
				draw_circle(p2, 3.5 + 2.0 * pulse, Color(col.r, col.g, col.b, alpha_line))

			&"circle":
				var center: Vector2 = tg.get("center", Vector2.ZERO)
				var radius: float = float(tg.get("radius", 14.0))
				draw_circle(center, radius, Color(col.r, col.g, col.b, alpha_fill))
				draw_arc(center, radius, 0.0, TAU, 32, Color(col.r, col.g, col.b, alpha_line), 1.5)
				var cross_len: float = radius + 4.0
				draw_line(center - Vector2(cross_len, 0), center + Vector2(cross_len, 0), Color(col.r, col.g, col.b, alpha_line), 1.0)
				draw_line(center - Vector2(0, cross_len), center + Vector2(0, cross_len), Color(col.r, col.g, col.b, alpha_line), 1.0)

	# Белая рамка бокса
	draw_rect(box_rect, Color(0.95, 0.95, 0.98, 1.0), false, 2.0)

	# Полоска оставшегося времени уворота над боксом
	var ratio: float = clampf(_time_left / maxf(0.1, _total_duration), 0.0, 1.0)
	draw_rect(Rect2(_box_origin.x, _box_origin.y - 4.0, BOX_W * ratio, 2.0), Color(0.3, 0.95, 1.0, 1.0), true)
