class_name MapScene
extends Control

## MapScene: Отображение и навигация по 15-этажному DAG-графу забега (ADR-001 Section 2.6)

var _graph_canvas: Control = null
var _scroll: ScrollContainer = null
var _header_label: Label = null
var _status_label: Label = null
var _node_positions: Dictionary = {}

const FLOOR_SPACING_X: float = 92.0
const MAP_LEFT_PAD: float = 48.0
const MAP_TOP_PAD: float = 42.0
const MAP_HEIGHT_SPAN: float = 165.0

const SECTOR_NAMES: Dictionary = {
	1: "СЕКТОР 1: Свалка переработки (Scrap Valley)",
	2: "СЕКТОР 2: Трущобы разбойников (Outlaw Hub)",
	3: "СЕКТОР 3: Вертикаль ретранслятора (Bremen Spire)"
}

func _ready() -> void:
	if not SaveManager.has_active_run:
		SaveManager.start_new_run()
	if SaveManager.map_graph.is_empty():
		SaveManager.map_graph = MapGenerator.generate_sector_dag(SaveManager.run_seed, SaveManager.current_sector)
		SaveManager.save_run()

	_build_ui()
	_populate_map_nodes()

func _build_ui() -> void:
	var bg: TextureRect = TextureRect.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.stretch_mode = TextureRect.STRETCH_SCALE
	bg.modulate = Color(0.55, 0.55, 0.65, 1.0)
	var sec: int = clampi(SaveManager.current_sector, 1, 3)
	var bg_path: String = "res://assets/sprites/backgrounds/bg_sector" + str(sec) + ".png"
	if ResourceLoader.exists(bg_path):
		bg.texture = load(bg_path) as Texture2D
	add_child(bg)

	# Верхняя шапка
	var top_bar: PanelContainer = PanelContainer.new()
	top_bar.position = Vector2(8, 6)
	top_bar.size = Vector2(624, 32)
	top_bar.clip_contents = true
	var st: StyleBoxFlat = StyleBoxFlat.new()
	st.bg_color = Color(0.06, 0.08, 0.13, 0.94)
	st.border_color = Color(0.3, 0.7, 0.95, 1.0)
	st.set_border_width_all(1)
	st.set_content_margin_all(4)
	top_bar.add_theme_stylebox_override("panel", st)
	add_child(top_bar)

	var top_hbox: HBoxContainer = HBoxContainer.new()
	top_hbox.add_theme_constant_override("separation", 10)
	top_bar.add_child(top_hbox)

	_header_label = Label.new()
	_header_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_header_label.clip_text = true
	_header_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_header_label.add_theme_font_size_override("font_size", 10)
	var sec_title: String = String(SECTOR_NAMES.get(SaveManager.current_sector, "СЕКТОР 1"))
	_header_label.text = sec_title + " | Сид: #" + str(SaveManager.run_seed)
	_header_label.add_theme_color_override("font_color", Color(0.4, 0.95, 1.0))
	top_hbox.add_child(_header_label)

	_status_label = Label.new()
	_status_label.add_theme_font_size_override("font_size", 10)
	_status_label.text = "Лом: " + str(SaveManager.run_scrap) + " | Гармония: " + str(SaveManager.sync_gauge) + "%"
	_status_label.add_theme_color_override("font_color", Color(0.95, 0.85, 0.35))
	top_hbox.add_child(_status_label)

	var garage_btn: Button = Button.new()
	garage_btn.text = "ГАРАЖ / ОТРЯД"
	garage_btn.add_theme_font_size_override("font_size", 9)
	garage_btn.pressed.connect(func() -> void:
		AudioManager.play_sfx("ui_click")
		EventBus.request_scene_change.emit(&"GARAGE", {"from_map_button": true})
	)
	top_hbox.add_child(garage_btn)

	var hub_btn: Button = Button.new()
	hub_btn.text = "В ХАБ"
	hub_btn.add_theme_font_size_override("font_size", 9)
	hub_btn.pressed.connect(func() -> void:
		AudioManager.play_sfx("ui_click")
		SaveManager.save_run()
		EventBus.request_scene_change.emit(&"HUB", {})
	)
	top_hbox.add_child(hub_btn)

	# Горизонтальный скролл графа на 15 этажей
	var map_panel: PanelContainer = PanelContainer.new()
	map_panel.position = Vector2(8, 42)
	map_panel.size = Vector2(624, 268)
	map_panel.add_theme_stylebox_override("panel", st)
	add_child(map_panel)

	_scroll = ScrollContainer.new()
	_scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	map_panel.add_child(_scroll)

	_graph_canvas = Control.new()
	_graph_canvas.custom_minimum_size = Vector2(MAP_LEFT_PAD * 2.0 + FLOOR_SPACING_X * 15.0, 245.0)
	_graph_canvas.draw.connect(_on_graph_draw)
	_scroll.add_child(_graph_canvas)

	# Нижняя легенда типов нод
	var legend_panel: PanelContainer = PanelContainer.new()
	legend_panel.position = Vector2(8, 314)
	legend_panel.size = Vector2(624, 40)
	legend_panel.add_theme_stylebox_override("panel", st)
	add_child(legend_panel)

	var leg_lbl: Label = Label.new()
	leg_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	leg_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	leg_lbl.add_theme_font_size_override("font_size", 9)
	leg_lbl.text = (
		"ЛЕГЕНДА НОД: [БОЙ: Мародёры]  |  [ЭЛИТА: Модульный дроид + редкая деталь]  |  "
		+ "[МАСТЕРСКАЯ: Ремонт и сборка]  |  [СИГНАЛ: Диалог Dialogic 2]  |  [БОСС СЕКТОРА: 15 этаж]"
	)
	legend_panel.add_child(leg_lbl)

func _populate_map_nodes() -> void:
	for child: Node in _graph_canvas.get_children():
		child.queue_free()
	_node_positions.clear()

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

		btn.pressed.connect(func() -> void:
			_on_node_clicked(node_dict)
		)
		_graph_canvas.add_child(btn)

	_graph_canvas.queue_redraw()

	# Автопрокрутка к текущему этажу
	await get_tree().process_frame
	var target_floor: int = maxi(1, SaveManager.current_floor)
	_scroll.scroll_horizontal = maxi(0, int((target_floor - 2) * FLOOR_SPACING_X))

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
		"COMBAT", "ELITE", "BOSS":
			EventBus.request_scene_change.emit(&"BATTLE", {"node_id": nid, "node_type": ntype})
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

