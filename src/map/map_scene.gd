class_name MapScene
extends Control

## MapScene: Отображение и навигация по 15-этажному DAG-графу забега (ADR-001 Section 2.6)

var _dev_menu_bar: DevMenuBar = null
var _fast_boss_btn: Button = null
var _graph_canvas: Control = null
var _scroll: ScrollContainer = null
var _header_label: Label = null
var _status_label: Label = null
var _node_positions: Dictionary = {}
var _scroll_tween: Tween = null
var _selectable_buttons: Array[Button] = []
var _top_bar_buttons: Array[Button] = []

const FLOOR_SPACING_X: float = 92.0
const MAP_LEFT_PAD: float = 48.0
const MAP_TOP_PAD: float = 34.0
const MAP_HEIGHT_SPAN: float = 152.0

const SECTOR_NAMES: Dictionary = {
	1: "СЕКТОР 1: Тракт у Старой Мельницы (Отряд: Кот и Пёс)",
	2: "СЕКТОР 2: Притон Разбойников (Отряд: Кот, Пёс и Осёл)",
	3: "СЕКТОР 3: Вершина Бремен-4 (Квартет в сборе!)"
}

func _ready() -> void:
	if not SaveManager.has_active_run:
		SaveManager.start_new_run()
	if SaveManager.map_graph.is_empty():
		var phase_val: int = int(SaveManager.story_progression.current_phase) if SaveManager.story_progression != null else -1
		SaveManager.map_graph = MapGenerator.generate_sector_dag(SaveManager.run_seed, SaveManager.current_sector, -1, phase_val)
		SaveManager.save_run()

	_build_ui()
	_populate_map_nodes()
	AudioManager.sync_music_to_party(SaveManager.party)

	await get_tree().process_frame
	if is_inside_tree():
		center_on_selectable_path(false)

func _process(delta: float) -> void:
	# Плавная непрерывная прокрутка карты правым аналоговым стиком
	var right_stick_x: float = Input.get_joy_axis(0, JOY_AXIS_RIGHT_X)
	if absf(right_stick_x) > 0.18:
		_kill_scroll_tween()
		var speed: float = 720.0
		_scroll_horizontal_by(right_stick_x * speed * delta)

func _unhandled_input(event: InputEvent) -> void:
	# Прокрутка правым аналоговым стиком (событийная обработка)
	if event is InputEventJoypadMotion:
		var jm: InputEventJoypadMotion = event as InputEventJoypadMotion
		if jm.axis == JOY_AXIS_RIGHT_X and absf(jm.axis_value) > 0.18:
			_kill_scroll_tween()
			_scroll_horizontal_by(jm.axis_value * 28.0)
			get_viewport().set_input_as_handled()
			return

	# Бамперы LB / RB для быстрой постраничной прокрутки карты влево / вправо
	if event is InputEventJoypadButton and event.is_pressed():
		var jb: int = (event as InputEventJoypadButton).button_index
		if jb == JOY_BUTTON_RIGHT_SHOULDER:
			_kill_scroll_tween()
			_scroll_horizontal_by(FLOOR_SPACING_X * 2.5)
			get_viewport().set_input_as_handled()
			return
		elif jb == JOY_BUTTON_LEFT_SHOULDER:
			_kill_scroll_tween()
			_scroll_horizontal_by(-FLOOR_SPACING_X * 2.5)
			get_viewport().set_input_as_handled()
			return
		elif jb == JOY_BUTTON_Y or jb == JOY_BUTTON_RIGHT_STICK:
			center_on_selectable_path(true)
			_reclaim_map_focus()
			get_viewport().set_input_as_handled()
			return

	# Стрелки D-Pad Влево / Вправо при фокусе на ноде карты для ручной прокрутки
	var focus_owner: Control = get_viewport().gui_get_focus_owner()
	var is_on_map_node: bool = (focus_owner is Button and _selectable_buttons.has(focus_owner as Button))
	if is_on_map_node:
		if event.is_action_pressed(&"ui_right"):
			_kill_scroll_tween()
			_scroll_horizontal_by(FLOOR_SPACING_X * 1.5)
			get_viewport().set_input_as_handled()
			return
		elif event.is_action_pressed(&"ui_left"):
			_kill_scroll_tween()
			_scroll_horizontal_by(-FLOOR_SPACING_X * 1.5)
			get_viewport().set_input_as_handled()
			return

	# Автоматический возврат фокуса при потере
	if focus_owner == null:
		var is_joy_btn: bool = (event is InputEventJoypadButton and (event as InputEventJoypadButton).pressed)
		var is_joy_stick: bool = (event is InputEventJoypadMotion and absf((event as InputEventJoypadMotion).axis_value) > 0.35)
		var is_ui_nav: bool = (
			event.is_action_pressed(&"ui_up")
			or event.is_action_pressed(&"ui_down")
			or event.is_action_pressed(&"ui_left")
			or event.is_action_pressed(&"ui_right")
			or event.is_action_pressed(&"ui_accept")
		)
		if is_joy_btn or is_joy_stick or is_ui_nav:
			_reclaim_map_focus()
			get_viewport().set_input_as_handled()
			return

func _build_ui() -> void:
	var bg: TextureRect = TextureRect.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.stretch_mode = TextureRect.STRETCH_SCALE
	bg.modulate = Color(0.55, 0.55, 0.65, 1.0)
	var sec: int = clampi(SaveManager.current_sector, 1, 4)
	var bg_path: String = "res://assets/sprites/backgrounds/bg_sector" + str(sec) + ".png"
	if ResourceLoader.exists(bg_path):
		bg.texture = load(bg_path) as Texture2D
	add_child(bg)

	# Верхнее меню разработчика (Fast Track к боссу уровня, Issue #16)
	_dev_menu_bar = DevMenuBar.new()
	add_child(_dev_menu_bar)

	# Верхняя шапка уровня
	var top_bar: PanelContainer = PanelContainer.new()
	top_bar.position = Vector2(8, 30)
	top_bar.size = Vector2(624, 28)
	top_bar.clip_contents = true
	var st: StyleBoxFlat = StyleBoxFlat.new()
	st.bg_color = Color(0.06, 0.08, 0.13, 0.94)
	st.border_color = Color(0.3, 0.7, 0.95, 1.0)
	st.set_border_width_all(1)
	st.set_content_margin_all(3)
	top_bar.add_theme_stylebox_override("panel", st)
	add_child(top_bar)

	var top_hbox: HBoxContainer = HBoxContainer.new()
	top_hbox.add_theme_constant_override("separation", 6)
	top_bar.add_child(top_hbox)

	_header_label = Label.new()
	_header_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_header_label.clip_text = true
	_header_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_header_label.add_theme_font_size_override("font_size", 10)
	var phase_val: int = int(SaveManager.story_progression.current_phase) if SaveManager.story_progression != null else -1
	var sec_title: String = MapGenerator.get_sector_title(SaveManager.current_sector, phase_val)
	_header_label.text = sec_title + " | Сид: #" + str(SaveManager.run_seed)
	_header_label.add_theme_color_override("font_color", Color(0.4, 0.95, 1.0))
	top_hbox.add_child(_header_label)

	_status_label = Label.new()
	_status_label.add_theme_font_size_override("font_size", 10)
	_status_label.text = "Лом: " + str(SaveManager.run_scrap) + " | Гармония: " + str(SaveManager.sync_gauge) + "%"
	_status_label.add_theme_color_override("font_color", Color(0.95, 0.85, 0.35))
	top_hbox.add_child(_status_label)

	_fast_boss_btn = Button.new()
	_fast_boss_btn.text = "⚔ К БОССУ"
	_fast_boss_btn.add_theme_font_size_override("font_size", 9)
	_fast_boss_btn.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3))
	_fast_boss_btn.pressed.connect(func() -> void:
		AudioManager.play_sfx("ui_click")
		SaveManager.jump_to_boss_battle(-1)
	)
	_style_top_bar_button(_fast_boss_btn)
	top_hbox.add_child(_fast_boss_btn)

	var garage_btn: Button = Button.new()
	garage_btn.text = "ГАРАЖ / ОТРЯД"
	garage_btn.add_theme_font_size_override("font_size", 9)
	garage_btn.pressed.connect(func() -> void:
		AudioManager.play_sfx("ui_click")
		EventBus.request_scene_change.emit(&"GARAGE", {"from_map_button": true})
	)
	_style_top_bar_button(garage_btn)
	top_hbox.add_child(garage_btn)

	var hub_btn: Button = Button.new()
	hub_btn.text = "В ХАБ"
	hub_btn.add_theme_font_size_override("font_size", 9)
	hub_btn.pressed.connect(func() -> void:
		AudioManager.play_sfx("ui_click")
		SaveManager.save_run()
		EventBus.request_scene_change.emit(&"HUB", {})
	)
	_style_top_bar_button(hub_btn)
	top_hbox.add_child(hub_btn)

	var pause_btn: Button = Button.new()
	pause_btn.text = "⏸ МЕНЮ"
	pause_btn.add_theme_font_size_override("font_size", 9)
	pause_btn.pressed.connect(func() -> void:
		AudioManager.play_sfx("ui_click")
		Input.action_press(&"pause")
		Input.action_release(&"pause")
	)
	_style_top_bar_button(pause_btn)
	top_hbox.add_child(pause_btn)

	_top_bar_buttons = [_fast_boss_btn, garage_btn, hub_btn, pause_btn]
	for i: int in range(_top_bar_buttons.size()):
		var left_idx: int = (i - 1 + _top_bar_buttons.size()) % _top_bar_buttons.size()
		var right_idx: int = (i + 1) % _top_bar_buttons.size()
		_top_bar_buttons[i].focus_neighbor_left = _top_bar_buttons[left_idx].get_path()
		_top_bar_buttons[i].focus_neighbor_right = _top_bar_buttons[right_idx].get_path()

	# Горизонтальный скролл графа на 15 этажей
	var map_panel: PanelContainer = PanelContainer.new()
	map_panel.position = Vector2(8, 60)
	map_panel.size = Vector2(624, 250)
	map_panel.add_theme_stylebox_override("panel", st)
	add_child(map_panel)

	_scroll = ScrollContainer.new()
	_scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	map_panel.add_child(_scroll)

	var max_fl: int = 15
	for n_dict: Dictionary in SaveManager.map_graph:
		max_fl = maxi(max_fl, int(n_dict.get("floor", 15)))

	_graph_canvas = Control.new()
	_graph_canvas.custom_minimum_size = Vector2(MAP_LEFT_PAD * 2.0 + FLOOR_SPACING_X * float(max_fl), 224.0)
	_graph_canvas.draw.connect(_on_graph_draw)
	_scroll.add_child(_graph_canvas)

	# Нижняя легенда типов нод и подсказка контроллера
	var legend_panel: PanelContainer = PanelContainer.new()
	legend_panel.position = Vector2(8, 314)
	legend_panel.size = Vector2(624, 40)
	legend_panel.add_theme_stylebox_override("panel", st)
	add_child(legend_panel)

	var leg_vbox: VBoxContainer = VBoxContainer.new()
	leg_vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	leg_vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	leg_vbox.add_theme_constant_override("separation", 2)
	legend_panel.add_child(leg_vbox)

	var leg_lbl: Label = Label.new()
	leg_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	leg_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	leg_lbl.add_theme_font_size_override("font_size", 8)
	leg_lbl.text = (
		"ЛЕГЕНДА: [БОЙ: Мародёры]  |  [ЭЛИТА: Модульный дроид]  |  "
		+ "[ГАРАЖ: Ремонт]  |  [СИГНАЛ: Диалог]  |  [БОСС: " + str(max_fl) + " этаж]"
	)
	leg_vbox.add_child(leg_lbl)

	var hint_lbl: Label = Label.new()
	hint_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	hint_lbl.add_theme_font_size_override("font_size", 8)
	hint_lbl.add_theme_color_override("font_color", Color(1.0, 0.9, 0.4, 0.95))
	hint_lbl.text = "🎮 ГЕЙМПАД: [D-Pad] Выбор пути  •  [A] В путь  •  [Прав. Стик / LB / RB] Прокрутка карты  •  [Y] Центр пути"
	leg_vbox.add_child(hint_lbl)

func _populate_map_nodes() -> void:
	for child: Node in _graph_canvas.get_children():
		child.queue_free()
	_node_positions.clear()
	_selectable_buttons.clear()

	var selectable_ids: Array[int] = _get_selectable_node_ids()

	for node_dict: Dictionary in SaveManager.map_graph:
		var nid: int = int(node_dict["id"])
		var fl: int = int(node_dict["floor"])
		var y_ratio: float = float(node_dict["y_ratio"])
		var ntype: String = String(node_dict["type"])

		var pos: Vector2 = Vector2(
			MAP_LEFT_PAD + float(fl - 1) * FLOOR_SPACING_X,
			MAP_TOP_PAD + y_ratio * MAP_HEIGHT_SPAN
		)
		_node_positions[nid] = pos

		var btn: Button = Button.new()
		btn.position = pos - Vector2(34, 16)
		btn.size = Vector2(68, 32)
		btn.add_theme_font_size_override("font_size", 8)

		var is_done: bool = SaveManager.completed_node_ids.has(nid)
		var is_avail: bool = selectable_ids.has(nid)

		btn.text = str(fl) + ": " + _short_type_label(ntype)
		btn.disabled = not is_avail

		var btn_style: StyleBoxFlat = StyleBoxFlat.new()
		if is_done:
			btn_style.bg_color = Color(0.15, 0.32, 0.22, 0.9)
			btn_style.border_color = Color(0.3, 0.85, 0.45, 1.0)
		elif is_avail:
			btn_style.bg_color = _type_color(ntype)
			btn_style.border_color = Color(1.0, 0.95, 0.4, 1.0)
		else:
			btn_style.bg_color = Color(0.12, 0.14, 0.18, 0.75)
			btn_style.border_color = Color(0.3, 0.34, 0.4, 0.6)
		btn_style.set_border_width_all(2 if is_avail else 1)
		btn_style.set_corner_radius_all(4)
		btn.add_theme_stylebox_override("normal", btn_style)
		btn.add_theme_stylebox_override("hover", btn_style)
		btn.add_theme_stylebox_override("disabled", btn_style)

		if is_avail:
			var focus_sb: StyleBoxFlat = StyleBoxFlat.new()
			focus_sb.bg_color = btn_style.bg_color
			focus_sb.border_color = Color(1.0, 0.95, 0.35, 1.0)
			focus_sb.set_border_width_all(3)
			focus_sb.set_corner_radius_all(4)
			focus_sb.set_expand_margin_all(2)
			btn.add_theme_stylebox_override("focus", focus_sb)

			btn.focus_entered.connect(func() -> void:
				_center_on_x(pos.x, true)
			)
			_selectable_buttons.append(btn)

		btn.pressed.connect(func() -> void:
			_on_node_clicked(node_dict)
		)
		_graph_canvas.add_child(btn)

	_graph_canvas.queue_redraw()

	# Связываем соседей фокуса между доступными нодами (D-Pad Вверх / Вниз)
	if _selectable_buttons.size() > 1:
		for i: int in range(_selectable_buttons.size()):
			var prev_i: int = (i - 1 + _selectable_buttons.size()) % _selectable_buttons.size()
			var next_i: int = (i + 1) % _selectable_buttons.size()
			_selectable_buttons[i].focus_neighbor_top = _selectable_buttons[prev_i].get_path()
			_selectable_buttons[i].focus_neighbor_bottom = _selectable_buttons[next_i].get_path()
	elif _selectable_buttons.size() == 1:
		if is_instance_valid(_fast_boss_btn):
			_selectable_buttons[0].focus_neighbor_top = _fast_boss_btn.get_path()

	# Автоматическое центрование карты по выбираемому пути
	center_on_selectable_path(false)

	if not _selectable_buttons.is_empty():
		for tb_btn: Button in _top_bar_buttons:
			if is_instance_valid(tb_btn):
				tb_btn.focus_neighbor_bottom = _selectable_buttons[0].get_path()
		_selectable_buttons[0].grab_focus()

func _get_selectable_node_ids() -> Array[int]:
	var result: Array[int] = []
	if SaveManager.current_node_id < 0 or SaveManager.completed_node_ids.is_empty():
		for n: Dictionary in SaveManager.map_graph:
			if int(n["floor"]) == 1:
				result.append(int(n["id"]))
		return result

	for n2: Dictionary in SaveManager.map_graph:
		if int(n2["id"]) == SaveManager.current_node_id:
			var next_arr: Array = n2["next_ids"] as Array
			for tid: Variant in next_arr:
				result.append(int(tid))
			break
	return result

func _on_graph_draw() -> void:
	for node_dict: Dictionary in SaveManager.map_graph:
		var src_id: int = int(node_dict["id"])
		if not _node_positions.has(src_id):
			continue
		var p1: Vector2 = _node_positions[src_id] as Vector2
		var next_arr: Array = node_dict["next_ids"] as Array
		var is_active_branch: bool = (src_id == SaveManager.current_node_id)
		for tid_v: Variant in next_arr:
			var tid: int = int(tid_v)
			if _node_positions.has(tid):
				var p2: Vector2 = _node_positions[tid] as Vector2
				var col: Color = (
					Color(0.95, 0.85, 0.3, 0.95)
					if is_active_branch
					else Color(0.32, 0.45, 0.62, 0.65)
				)
				_graph_canvas.draw_line(p1, p2, col, 2.0 if is_active_branch else 1.2)

func _on_node_clicked(node_dict: Dictionary) -> void:
	AudioManager.play_sfx("ui_click")
	var nid: int = int(node_dict["id"])
	var fl: int = int(node_dict["floor"])
	var ntype: String = String(node_dict["type"])

	SaveManager.current_node_id = nid
	SaveManager.current_floor = fl
	if not SaveManager.completed_node_ids.has(nid):
		SaveManager.completed_node_ids.append(nid)

	EventBus.node_selected.emit(nid, StringName(ntype))

	match ntype:
		"COMBAT", "ELITE":
			EventBus.request_scene_change.emit(&"BATTLE", {"node_id": nid, "node_type": ntype})
		"BOSS":
			var sec: int = clampi(SaveManager.current_sector, 1, 4)
			var p_val: int = int(SaveManager.story_progression.current_phase) if SaveManager.story_progression != null else -1
			var th: String = MapGenerator.get_sector_theme(sec, p_val)

			var prelude_path: String = "res://data/dialogues/boss_prelude_sector1.dtl"
			var b_title: String = "БОЕВАЯ ТРЕВОГА"
			var b_btn: String = "В БОЙ ->"
			var b_photo: String = ""
			var b_cut_title: String = "БОСС"
			var boss_enemy_id: String = ""

			if p_val == int(StoryProgressionData.StoryPhase.CYCLE_0_SOLO_CAT):
				prelude_path = "res://data/dialogues/boss_prelude_sputnik_solo.dtl"
				b_title = "ПРОЛОГ // БОСС: СПЯЩИЙ СПУТНИК"
				b_btn = "РАЗБУДИТЬ НАДЗИРАТЕЛЯ (В БОЙ) ->"
				b_photo = "res://assets/photos/1-2-sputnik-apperiance.jpg"
				b_cut_title = "БОСС: СПЯЩИЙ СПУТНИК ВЫШКИ БРЕМЕН-4"
				boss_enemy_id = "boss_satellite"
			elif sec == 1:
				prelude_path = "res://data/dialogues/boss_prelude_sector1.dtl"
				b_title = "МЕЛЬНИЦА СВАЛКИ // ХОЗЯИН ОСЛА (ТРЁХГОЛОВЫЙ ПРЕСС)"
				b_btn = "В БОЙ ЗА СПАСЕНИЕ ОСЛА ->"
				b_photo = "res://assets/photos/2-2-press-boss-appirance.jpg"
				b_cut_title = "БОСС 1: ПОЯВЛЕНИЕ ТРЁХГОЛОВОГО ПРЕССА"
				boss_enemy_id = "boss_press"
			elif sec == 2:
				prelude_path = "res://data/dialogues/boss_prelude_sector2.dtl"
				b_title = "ПРИТОН РАЗБОЙНИКОВ // ПЕТУХ И СУП АТАМАНШИ"
				b_btn = "В БОЙ ЗА СПАСЕНИЕ ПЕТУХА ->"
				b_photo = "res://assets/photos/3-1-atamansha-boss-apperiance.jpg"
				b_cut_title = "БОСС 2: ПОЯВЛЕНИЕ АТАМАНШИ РАЗБОЙНИКОВ"
				boss_enemy_id = "boss_atamansha"
			else:
				if p_val >= int(StoryProgressionData.StoryPhase.CYCLE_3_QUARTET) or sec >= 4:
					prelude_path = "res://data/dialogues/boss_prelude_sector3.dtl"
					b_title = "ИЗБА НА ВЕРШИНЕ // ПИРАМИДА БРЕМЕНА В ОКНЕ"
					b_btn = "ВЛОМИТЬСЯ В ОКНО (ФИНАЛЬНЫЙ БОЙ) ->"
					b_photo = "res://assets/photos/6-1-fake-boss-apperiance.jpg"
					b_cut_title = "ФИНАЛЬНЫЙ БОСС: ЗАСЛУЖЕННЫЕ ДЕЯТЕЛИ ЭСТРАДЫ"
					boss_enemy_id = "boss_censor"
				else:
					prelude_path = "res://data/dialogues/boss_prelude_sector3.dtl"
					b_title = "ВЕРШИНА БРЕМЕН-4 // СПУТНИК В ЭФИРЕ"
					b_btn = "В БОЙ ЗА РЕТРАНСЛЯТОР ->"
					b_photo = "res://assets/photos/4-1-sputnik-boss-apperiance.jpg"
					b_cut_title = "БОСС 3: СПЯЩИЙ СПУТНИК ВЫШКИ БРЕМЕН-4"
					boss_enemy_id = "boss_satellite"

			SaveManager.save_run()
			var event_payload: Dictionary = {
				"timeline": prelude_path,
				"next_scene": &"BATTLE",
				"next_payload": {"node_id": nid, "node_type": "BOSS", "boss_id": boss_enemy_id, "biome_theme": th},
				"title": b_title,
				"continue_text": b_btn
			}
			if b_photo != "" and ResourceLoader.exists(b_photo):
				EventBus.request_scene_change.emit(&"VIDEO", {
					"image_path": b_photo,
					"title": b_cut_title,
					"boss_theme": sec,
					"next_scene": &"EVENT",
					"next_payload": event_payload
				})
			else:
				EventBus.request_scene_change.emit(&"EVENT", event_payload)
		"WORKSHOP":
			SaveManager.save_run()
			EventBus.request_scene_change.emit(&"GARAGE", {"node_id": nid, "free_tuneup": true})
		"EVENT":
			SaveManager.save_run()
			EventBus.request_scene_change.emit(&"EVENT", {"node_id": nid})

func _short_type_label(ntype: String) -> String:
	match ntype:
		"COMBAT":
			return "БОЙ"
		"ELITE":
			return "ЭЛИТА"
		"WORKSHOP":
			return "ГАРАЖ"
		"EVENT":
			return "СИГНАЛ"
		"BOSS":
			return "БОСС"
	return ntype

func _type_color(ntype: String) -> Color:
	match ntype:
		"COMBAT":
			return Color(0.55, 0.18, 0.2, 0.95)
		"ELITE":
			return Color(0.68, 0.42, 0.12, 0.95)
		"WORKSHOP":
			return Color(0.14, 0.42, 0.62, 0.95)
		"EVENT":
			return Color(0.42, 0.2, 0.62, 0.95)
		"BOSS":
			return Color(0.75, 0.1, 0.28, 0.98)
	return Color(0.2, 0.25, 0.35, 0.9)


func _center_on_x(target_x: float, animate: bool = true) -> void:
	if _scroll == null:
		return
	var viewport_w: float = _scroll.size.x if _scroll.size.x > 0.0 else 624.0
	var canvas_w: float = _graph_canvas.custom_minimum_size.x if _graph_canvas != null else 1476.0
	var max_scroll: float = maxf(0.0, canvas_w - viewport_w)
	var desired_scroll: int = int(clampf(target_x - (viewport_w * 0.5), 0.0, max_scroll))

	if animate and is_inside_tree():
		_kill_scroll_tween()
		_scroll_tween = create_tween()
		_scroll_tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		_scroll_tween.tween_property(_scroll, "scroll_horizontal", desired_scroll, 0.25)
	else:
		_kill_scroll_tween()
		_scroll.scroll_horizontal = desired_scroll

func _kill_scroll_tween() -> void:
	if _scroll_tween != null and _scroll_tween.is_valid():
		_scroll_tween.kill()
		_scroll_tween = null

func center_on_selectable_path(animate: bool = false) -> void:
	var selectable_ids: Array[int] = _get_selectable_node_ids()
	if not selectable_ids.is_empty():
		var first_id: int = selectable_ids[0]
		if _node_positions.has(first_id):
			var target_pos: Vector2 = _node_positions[first_id] as Vector2
			var center_x: float = target_pos.x
			if SaveManager.current_node_id >= 0 and _node_positions.has(SaveManager.current_node_id):
				var cur_pos: Vector2 = _node_positions[SaveManager.current_node_id] as Vector2
				center_x = (cur_pos.x + target_pos.x) * 0.5
			_center_on_x(center_x, animate)
			return

	var target_floor: int = maxi(1, SaveManager.current_floor)
	var fallback_x: float = MAP_LEFT_PAD + float(target_floor - 1) * FLOOR_SPACING_X
	_center_on_x(fallback_x, animate)

func _scroll_horizontal_by(delta_x: float) -> void:
	if _scroll == null:
		return
	var viewport_w: float = _scroll.size.x if _scroll.size.x > 0.0 else 624.0
	var canvas_w: float = _graph_canvas.custom_minimum_size.x if _graph_canvas != null else 1476.0
	var max_scroll: float = maxf(0.0, canvas_w - viewport_w)
	_scroll.scroll_horizontal = int(clampf(float(_scroll.scroll_horizontal) + delta_x, 0.0, max_scroll))

func _reclaim_map_focus() -> void:
	for btn: Button in _selectable_buttons:
		if is_instance_valid(btn) and btn.is_inside_tree() and not btn.disabled:
			btn.grab_focus()
			return
	if is_instance_valid(_fast_boss_btn) and _fast_boss_btn.is_inside_tree():
		_fast_boss_btn.grab_focus()

func _style_top_bar_button(btn: Button) -> void:
	var foc_sb: StyleBoxFlat = StyleBoxFlat.new()
	foc_sb.bg_color = Color(0.18, 0.24, 0.35, 0.95)
	foc_sb.border_color = Color(1.0, 0.9, 0.35, 1.0)
	foc_sb.set_border_width_all(2)
	foc_sb.set_corner_radius_all(3)
	foc_sb.set_expand_margin_all(1)
	btn.add_theme_stylebox_override("focus", foc_sb)
