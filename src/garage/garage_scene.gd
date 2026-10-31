class_name GarageScene
extends Control

## GarageScene: Экран сборки/замены и ремонта 3 деталей кошачьих мехов (ADR-001 Section 2.3 & 3)

var _payload: Dictionary = {}
var _selected_cat_idx: int = 0

var _scrap_label: Label = null
var _banner_label: Label = null
var _repair_all_btn: Button = null
var _exit_btn: Button = null
var _cat_tabs_box: HBoxContainer = null
var _cat_details_box: VBoxContainer = null
var _inventory_box: VBoxContainer = null
var _preview_body: Sprite2D = null
var _preview_arms: Sprite2D = null
var _preview_legs: Sprite2D = null
var _preview_arms_joint: Marker2D = null
var _preview_legs_joint: Marker2D = null

func setup_garage(payload: Dictionary) -> void:
	_payload = payload

func _ready() -> void:
	DataCatalog.ensure_loaded()
	if SaveManager.party.is_empty():
		SaveManager.start_new_run()

	# Если зашли через ноду Мастерской на карте — бесплатный полевой подремонт 25% HP всем деталям
	if bool(_payload.get("free_tuneup", false)):
		for cat: CatMechInstance in SaveManager.party:
			for slot: PartData.PartSlot in [PartData.PartSlot.BODY, PartData.PartSlot.ARMS, PartData.PartSlot.LEGS]:
				var p: PartInstance = cat.get_part(slot)
				if p != null:
					p.repair(maxi(8, int(float(p.get_max_hp()) * 0.25)))
		SaveManager.save_run()

	_build_ui()
	_refresh_view()

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		_on_exit_pressed()

func _build_ui() -> void:
	var bg: TextureRect = TextureRect.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.stretch_mode = TextureRect.STRETCH_SCALE
	bg.modulate = Color(0.5, 0.55, 0.65, 1.0)
	if ResourceLoader.exists("res://assets/sprites/backgrounds/bg_hub.png"):
		bg.texture = load("res://assets/sprites/backgrounds/bg_hub.png") as Texture2D
	add_child(bg)

	var st: StyleBoxFlat = StyleBoxFlat.new()
	st.bg_color = Color(0.06, 0.08, 0.13, 0.94)
	st.border_color = Color(0.3, 0.75, 0.95, 1.0)
	st.set_border_width_all(1)
	st.set_content_margin_all(5)

	# Верхняя панель
	var top_panel: PanelContainer = PanelContainer.new()
	top_panel.position = Vector2(8, 6)
	top_panel.size = Vector2(624, 34)
	top_panel.clip_contents = true
	top_panel.add_theme_stylebox_override("panel", st)
	add_child(top_panel)

	var top_hbox: HBoxContainer = HBoxContainer.new()
	top_hbox.add_theme_constant_override("separation", 8)
	top_panel.add_child(top_hbox)

	_banner_label = Label.new()
	_banner_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_banner_label.clip_text = true
	_banner_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_banner_label.add_theme_font_size_override("font_size", 11)
	_banner_label.text = "ГАРАЖ-МАСТЕРСКАЯ"
	_banner_label.add_theme_color_override("font_color", Color(0.4, 0.95, 1.0))
	top_hbox.add_child(_banner_label)

	_scrap_label = Label.new()
	_scrap_label.add_theme_font_size_override("font_size", 10)
	_scrap_label.add_theme_color_override("font_color", Color(0.95, 0.85, 0.3))
	top_hbox.add_child(_scrap_label)

	_repair_all_btn = Button.new()
	_repair_all_btn.text = "Починить всех (35 Лома)"
	_repair_all_btn.add_theme_font_size_override("font_size", 9)
	_repair_all_btn.pressed.connect(_on_repair_all_pressed)
	top_hbox.add_child(_repair_all_btn)

	_exit_btn = Button.new()
	_exit_btn.text = "← ВЫХОД НА КАРТУ"
	_exit_btn.add_theme_font_size_override("font_size", 10)
	_exit_btn.add_theme_color_override("font_color", Color(1.0, 0.9, 0.35))
	_exit_btn.tooltip_text = "Вернуться на карту (Esc)"
	_exit_btn.pressed.connect(_on_exit_pressed)
	top_hbox.add_child(_exit_btn)

	# Кнопки переключения между 4 котами
	var tabs_panel: PanelContainer = PanelContainer.new()
	tabs_panel.position = Vector2(8, 44)
	tabs_panel.size = Vector2(624, 32)
	tabs_panel.add_theme_stylebox_override("panel", st)
	add_child(tabs_panel)

	_cat_tabs_box = HBoxContainer.new()
	_cat_tabs_box.add_theme_constant_override("separation", 6)
	tabs_panel.add_child(_cat_tabs_box)

	for i: int in range(SaveManager.party.size()):
		var cat: CatMechInstance = SaveManager.party[i]
		var tab_btn: Button = Button.new()
		tab_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tab_btn.text = cat.display_name + " (" + cat.role_title + ")"
		tab_btn.add_theme_font_size_override("font_size", 9)
		tab_btn.pressed.connect(func() -> void:
			AudioManager.play_sfx("ui_click")
			_selected_cat_idx = i
			_refresh_view()
		)
		_cat_tabs_box.add_child(tab_btn)

	# Левая панель: 3 установленных слота (Body, Arms, Legs) + превью меха
	var left_panel: PanelContainer = PanelContainer.new()
	left_panel.position = Vector2(8, 80)
	left_panel.size = Vector2(368, 272)
	left_panel.add_theme_stylebox_override("panel", st)
	add_child(left_panel)

	var left_hbox: HBoxContainer = HBoxContainer.new()
	left_hbox.add_theme_constant_override("separation", 8)
	left_panel.add_child(left_hbox)

	# Визуальный стенд кота
	var preview_ctrl: Control = Control.new()
	preview_ctrl.custom_minimum_size = Vector2(96, 250)
	left_hbox.add_child(preview_ctrl)

	var rig_root: Node2D = Node2D.new()
	rig_root.position = Vector2(48, 120)
	rig_root.scale = Vector2(1.8, 1.8)
	preview_ctrl.add_child(rig_root)

	_preview_body = Sprite2D.new()
	_preview_body.name = "BodySprite"
	_preview_body.position = Vector2(0, -4)
	rig_root.add_child(_preview_body)

	_preview_legs_joint = Marker2D.new()
	_preview_legs_joint.name = "LegsJoint"
	_preview_legs_joint.position = Vector2(0, 16)
	_preview_body.add_child(_preview_legs_joint)

	_preview_legs = Sprite2D.new()
	_preview_legs.name = "LegsSprite"
	_preview_legs.show_behind_parent = true
	_preview_legs_joint.add_child(_preview_legs)

	_preview_arms_joint = Marker2D.new()
	_preview_arms_joint.name = "ArmsJoint"
	_preview_arms_joint.position = Vector2(2, 2)
	_preview_body.add_child(_preview_arms_joint)

	_preview_arms = Sprite2D.new()
	_preview_arms.name = "ArmsSprite"
	_preview_arms_joint.add_child(_preview_arms)

	_cat_details_box = VBoxContainer.new()
	_cat_details_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_cat_details_box.add_theme_constant_override("separation", 6)
	left_hbox.add_child(_cat_details_box)

	# Правая панель: Склад запасных деталей
	var right_panel: PanelContainer = PanelContainer.new()
	right_panel.position = Vector2(382, 80)
	right_panel.size = Vector2(250, 272)
	right_panel.add_theme_stylebox_override("panel", st)
	add_child(right_panel)

	var right_scroll: ScrollContainer = ScrollContainer.new()
	right_scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	right_panel.add_child(right_scroll)

	_inventory_box = VBoxContainer.new()
	_inventory_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_inventory_box.add_theme_constant_override("separation", 4)
	right_scroll.add_child(_inventory_box)

func _refresh_view() -> void:
	_scrap_label.text = "Лом: " + str(SaveManager.run_scrap)
	if SaveManager.party.is_empty():
		return
	_selected_cat_idx = clampi(_selected_cat_idx, 0, SaveManager.party.size() - 1)
	var cat: CatMechInstance = SaveManager.party[_selected_cat_idx]

	if _repair_all_btn != null:
		var any_damaged: bool = false
		for c: CatMechInstance in SaveManager.party:
			for s: PartData.PartSlot in [PartData.PartSlot.BODY, PartData.PartSlot.ARMS, PartData.PartSlot.LEGS]:
				var part_inst: PartInstance = c.get_part(s)
				if part_inst != null and part_inst.current_hp < part_inst.get_max_hp():
					any_damaged = true
					break
			if any_damaged:
				break
		if not any_damaged:
			_repair_all_btn.text = "Все мехи целы"
			_repair_all_btn.disabled = true
		else:
			_repair_all_btn.text = "Починить всех (35 Лома)"
			_repair_all_btn.disabled = SaveManager.run_scrap < 35

	if _exit_btn != null:
		var target: StringName = _get_exit_target_scene()
		if target == &"MAP":
			_exit_btn.text = "← ВЫХОД НА КАРТУ"
		elif target == &"HUB":
			_exit_btn.text = "← ВЫХОД В ХАБ"
		else:
			_exit_btn.text = "← ВЫХОД"

	if _cat_tabs_box != null:
		for i: int in range(_cat_tabs_box.get_child_count()):
			var tab_btn: Button = _cat_tabs_box.get_child(i) as Button
			if tab_btn != null:
				if i == _selected_cat_idx:
					tab_btn.add_theme_color_override("font_color", Color(0.4, 1.0, 0.6))
				else:
					tab_btn.remove_theme_color_override("font_color")

	# Обновляем превью спрайтов и позиции сочленений Marker2D (Issue #11)
	if cat.body_part != null and cat.body_part.data != null:
		if _preview_arms_joint != null:
			_preview_arms_joint.position = cat.body_part.data.arms_joint_offset
		if _preview_legs_joint != null:
			_preview_legs_joint.position = cat.body_part.data.legs_joint_offset
		if ResourceLoader.exists(cat.body_part.data.texture_path):
			_preview_body.texture = load(cat.body_part.data.texture_path) as Texture2D
	if cat.arms_part != null and cat.arms_part.data != null and ResourceLoader.exists(cat.arms_part.data.texture_path):
		_preview_arms.texture = load(cat.arms_part.data.texture_path) as Texture2D
	if cat.legs_part != null and cat.legs_part.data != null and ResourceLoader.exists(cat.legs_part.data.texture_path):
		_preview_legs.texture = load(cat.legs_part.data.texture_path) as Texture2D

	for child: Node in _cat_details_box.get_children():
		child.queue_free()

	var title: Label = Label.new()
	title.text = cat.display_name + " | Инициатива: " + str(cat.get_initiative_score())
	title.add_theme_font_size_override("font_size", 11)
	title.add_theme_color_override("font_color", Color(0.95, 0.88, 0.35))
	_cat_details_box.add_child(title)

	for slot: PartData.PartSlot in [PartData.PartSlot.BODY, PartData.PartSlot.ARMS, PartData.PartSlot.LEGS]:
		var part: PartInstance = cat.get_part(slot)
		var slot_card: VBoxContainer = VBoxContainer.new()
		slot_card.add_theme_constant_override("separation", 1)
		_cat_details_box.add_child(slot_card)

		var s_lbl: Label = Label.new()
		s_lbl.add_theme_font_size_override("font_size", 9)
		var slot_ru: String = PartData.slot_to_russian(slot)
		var p_name: String = part.data.part_name if (part != null and part.data != null) else "Пусто"
		s_lbl.text = (
			"[" + slot_ru + "] " + p_name
			+ " | HP: " + str(part.current_hp) + "/" + str(part.get_max_hp())
			+ " | Бр: " + str(part.get_armor())
		)
		s_lbl.add_theme_color_override("font_color", Color(0.45, 0.95, 0.65) if not part.is_broken() else Color(1.0, 0.4, 0.4))
		slot_card.add_child(s_lbl)

		var sk_names: PackedStringArray = PackedStringArray()
		if part != null and part.data != null:
			for sk: SkillData in part.data.skills:
				if sk != null:
					sk_names.append(sk.skill_name)
		var sk_lbl: Label = Label.new()
		sk_lbl.add_theme_font_size_override("font_size", 8)
		sk_lbl.text = "Навыки: " + (", ".join(sk_names) if not sk_names.is_empty() else "Пассивный узел")
		slot_card.add_child(sk_lbl)

		var rep_btn: Button = Button.new()
		var missing_hp: int = part.get_max_hp() - part.current_hp
		rep_btn.text = (
			"Починить " + slot_ru + " (+100% HP за 12 Лома)"
			if missing_hp > 0
			else (slot_ru + " в идеальном состоянии")
		)
		rep_btn.disabled = missing_hp <= 0 or SaveManager.run_scrap < 12
		rep_btn.add_theme_font_size_override("font_size", 8)
		rep_btn.pressed.connect(func() -> void:
			if SaveManager.run_scrap >= 12:
				SaveManager.add_run_scrap(-12)
				part.repair_full()
				AudioManager.play_sfx("heal")
				SaveManager.save_run()
				_refresh_view()
		)
		slot_card.add_child(rep_btn)

	# Перестраиваем склад запчастей
	for child2: Node in _inventory_box.get_children():
		child2.queue_free()

	var inv_title: Label = Label.new()
	inv_title.text = "СКЛАД ЗАПЧАСТЕЙ (" + str(SaveManager.spare_parts_inventory.size()) + "):"
	inv_title.add_theme_font_size_override("font_size", 10)
	inv_title.add_theme_color_override("font_color", Color(0.4, 0.95, 1.0))
	_inventory_box.add_child(inv_title)

	if SaveManager.spare_parts_inventory.is_empty():
		var empty_l: Label = Label.new()
		empty_l.text = "Нет свободных модулей.\nВыбивайте редкие детали в боях с Элитками и Боссами!"
		empty_l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		empty_l.add_theme_font_size_override("font_size", 9)
		_inventory_box.add_child(empty_l)
		return

	for inv_idx: int in range(SaveManager.spare_parts_inventory.size()):
		var pid: String = SaveManager.spare_parts_inventory[inv_idx]
		var pdata: PartData = DataCatalog.get_part(pid)
		if pdata == null:
			continue

		var item_box: VBoxContainer = VBoxContainer.new()
		_inventory_box.add_child(item_box)

		var ilbl: Label = Label.new()
		ilbl.add_theme_font_size_override("font_size", 8)
		ilbl.text = (
			"[" + PartData.slot_to_russian(pdata.slot) + "] " + pdata.part_name
			+ "\nHP:" + str(pdata.max_hp) + " Бр:" + str(pdata.armor) + " Скор:" + str(pdata.base_speed)
		)
		item_box.add_child(ilbl)

		var eq_btn: Button = Button.new()
		eq_btn.text = "Установить на " + cat.display_name
		eq_btn.add_theme_font_size_override("font_size", 8)
		eq_btn.pressed.connect(func() -> void:
			_equip_inventory_part(inv_idx, pdata)
		)
		item_box.add_child(eq_btn)

func _equip_inventory_part(inv_index: int, new_pdata: PartData) -> void:
	var cat: CatMechInstance = SaveManager.party[_selected_cat_idx]
	var new_inst: PartInstance = PartInstance.new(new_pdata)
	var old_inst: PartInstance = cat.set_part(new_pdata.slot, new_inst)

	SaveManager.spare_parts_inventory.remove_at(inv_index)
	if old_inst != null and old_inst.data != null:
		SaveManager.spare_parts_inventory.append(String(old_inst.data.part_id))

	AudioManager.play_sfx("heal")
	SaveManager.save_run()
	_refresh_view()

func _on_repair_all_pressed() -> void:
	if SaveManager.run_scrap < 35:
		return
	var any_repaired: bool = false
	for cat: CatMechInstance in SaveManager.party:
		for slot: PartData.PartSlot in [PartData.PartSlot.BODY, PartData.PartSlot.ARMS, PartData.PartSlot.LEGS]:
			var p: PartInstance = cat.get_part(slot)
			if p != null and p.current_hp < p.get_max_hp():
				p.repair_full()
				any_repaired = true
	if not any_repaired:
		return
	SaveManager.add_run_scrap(-35)
	AudioManager.play_sfx("heal")
	SaveManager.save_run()
	_refresh_view()

func _on_exit_pressed() -> void:
	AudioManager.play_sfx("ui_click")
	SaveManager.save_run()
	var target_scene: StringName = _get_exit_target_scene()
	EventBus.request_scene_change.emit(target_scene, {})

func _get_exit_target_scene() -> StringName:
	if _payload.has("return_scene"):
		return StringName(_payload["return_scene"])
	if SaveManager.has_active_run:
		return &"MAP"
	return &"HUB"

