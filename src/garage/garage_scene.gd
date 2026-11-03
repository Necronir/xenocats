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
var _right_scroll: ScrollContainer = null
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
	AudioManager.sync_music_to_party(SaveManager.party)
	_refresh_view()
	if _repair_all_btn != null and not _repair_all_btn.disabled:
		_repair_all_btn.grab_focus()
	elif _exit_btn != null:
		_exit_btn.grab_focus()

func _unhandled_input(event: InputEvent) -> void:
	# Нажатие B на геймпаде или ESC - выход
	var is_b_pressed: bool = (
		event is InputEventJoypadButton
		and (event as InputEventJoypadButton).pressed
		and (event as InputEventJoypadButton).button_index == JOY_BUTTON_B
	)
	if event.is_action_pressed("ui_cancel") or is_b_pressed:
		_on_exit_pressed()
		get_viewport().set_input_as_handled()
		return

	# Переключение котов бамперами LB / RB (L1 / R1)
	if event is InputEventJoypadButton and (event as InputEventJoypadButton).pressed:
		var jb: int = (event as InputEventJoypadButton).button_index
		if jb == JOY_BUTTON_LEFT_SHOULDER:
			_change_cat_tab(-1)
			get_viewport().set_input_as_handled()
			return
		elif jb == JOY_BUTTON_RIGHT_SHOULDER:
			_change_cat_tab(1)
			get_viewport().set_input_as_handled()
			return

	# Прокрутка склада правым аналоговым стиком
	if event is InputEventJoypadMotion:
		var jm: InputEventJoypadMotion = event as InputEventJoypadMotion
		if jm.axis == JOY_AXIS_RIGHT_Y and abs(jm.axis_value) > 0.2:
			if _right_scroll != null:
				_right_scroll.scroll_vertical += int(jm.axis_value * 16.0)
				get_viewport().set_input_as_handled()
				return

	# Автоматический возврат фокуса при потере
	if get_viewport().gui_get_focus_owner() == null:
		if event.is_action(&"pause"):
			return
		if event is InputEventJoypadButton:
			var jb_btn: int = (event as InputEventJoypadButton).button_index
			if jb_btn in [JOY_BUTTON_START, JOY_BUTTON_BACK, JOY_BUTTON_GUIDE]:
				return
		var is_joy_btn: bool = (event is InputEventJoypadButton and (event as InputEventJoypadButton).pressed)
		var is_joy_stick: bool = (event is InputEventJoypadMotion and abs((event as InputEventJoypadMotion).axis_value) > 0.35)
		var is_ui_nav: bool = (
			event.is_action_pressed(&"ui_up")
			or event.is_action_pressed(&"ui_down")
			or event.is_action_pressed(&"ui_left")
			or event.is_action_pressed(&"ui_right")
			or event.is_action_pressed(&"ui_accept")
		)
		if is_joy_btn or is_joy_stick or is_ui_nav:
			_reclaim_garage_focus()
			get_viewport().set_input_as_handled()
			return

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
	_style_garage_button(_repair_all_btn, &"default")
	_repair_all_btn.pressed.connect(_on_repair_all_pressed)
	top_hbox.add_child(_repair_all_btn)

	_exit_btn = Button.new()
	_exit_btn.text = "← ВЫХОД НА КАРТУ"
	_exit_btn.add_theme_font_size_override("font_size", 10)
	_exit_btn.add_theme_color_override("font_color", Color(1.0, 0.9, 0.35))
	_exit_btn.tooltip_text = "Вернуться на карту (Esc / B)"
	_style_garage_button(_exit_btn, &"default")
	_exit_btn.pressed.connect(_on_exit_pressed)
	top_hbox.add_child(_exit_btn)

	var pause_btn: Button = Button.new()
	pause_btn.text = "|| МЕНЮ"
	pause_btn.custom_minimum_size = Vector2(56, 20)
	pause_btn.add_theme_font_size_override("font_size", 9)
	_style_garage_button(pause_btn, &"default")
	pause_btn.pressed.connect(func() -> void:
		AudioManager.play_sfx("ui_click")
		EventBus.pause_requested.emit()

	)
	top_hbox.add_child(pause_btn)

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
		_style_garage_button(tab_btn, &"default")
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

	_right_scroll = ScrollContainer.new()
	_right_scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	right_panel.add_child(_right_scroll)

	_inventory_box = VBoxContainer.new()
	_inventory_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_inventory_box.add_theme_constant_override("separation", 4)
	_right_scroll.add_child(_inventory_box)

	var hint_lbl: Label = Label.new()
	hint_lbl.position = Vector2(8, 342)
	hint_lbl.size = Vector2(624, 16)
	var is_touch_g: bool = (SaveManager.settings != null and SaveManager.settings.touch_controls_enabled)
	hint_lbl.text = "[LB/RB] Выбор героя  |  [D-Pad] Навигация  |  [A] Установить/Починить  |  [R-Стик] Прокрутка  |  [B] Назад" + ("  |  [Тач]" if is_touch_g else "")
	hint_lbl.add_theme_font_size_override("font_size", 7)
	hint_lbl.add_theme_color_override("font_color", Color(0.45, 0.75, 0.9, 0.85))
	add_child(hint_lbl)

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
	title.text = cat.display_name + " [" + cat.instrument_name + "] | Инициатива: " + str(cat.get_initiative_score())
	title.add_theme_font_size_override("font_size", 11)
	title.add_theme_color_override("font_color", Color(0.95, 0.88, 0.35))
	_cat_details_box.add_child(title)

	# Индикатор нагрузки и лимита мощности Front Mission (ADR-001 / Issue #8)
	var total_w: int = cat.get_total_weight()
	var cap_w: int = cat.get_power_capacity()
	var is_ow: bool = cat.is_overweight()
	var ow_val: int = cat.get_overweight()

	var weight_box: VBoxContainer = VBoxContainer.new()
	weight_box.name = "WeightIndicatorBox"
	weight_box.add_theme_constant_override("separation", 2)
	_cat_details_box.add_child(weight_box)

	var weight_hbox: HBoxContainer = HBoxContainer.new()
	weight_hbox.add_theme_constant_override("separation", 6)
	weight_box.add_child(weight_hbox)

	var w_lbl: Label = Label.new()
	w_lbl.name = "WeightSummaryLabel"
	w_lbl.add_theme_font_size_override("font_size", 9)
	if is_ow:
		w_lbl.text = "Вес: " + str(total_w) + " / " + str(cap_w) + " т [ПЕРЕГРУЗ +" + str(ow_val) + " т!]"
		w_lbl.add_theme_color_override("font_color", Color(1.0, 0.35, 0.35))
	elif cap_w > 0 and total_w >= int(float(cap_w) * 0.85):
		w_lbl.text = "Вес: " + str(total_w) + " / " + str(cap_w) + " т [ПРЕДЕЛ]"
		w_lbl.add_theme_color_override("font_color", Color(0.95, 0.85, 0.3))
	else:
		w_lbl.text = "Вес: " + str(total_w) + " / " + str(cap_w) + " т [НОРМА]"
		w_lbl.add_theme_color_override("font_color", Color(0.4, 0.95, 0.65))
	weight_hbox.add_child(w_lbl)

	var w_bar: ProgressBar = ProgressBar.new()
	w_bar.name = "WeightProgressBar"
	w_bar.custom_minimum_size = Vector2(90, 8)
	w_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	w_bar.show_percentage = false
	var safe_cap_w: int = maxi(1, cap_w)
	var safe_max: int = maxi(safe_cap_w, total_w)
	w_bar.max_value = float(safe_max)
	w_bar.value = float(clampi(total_w, 0, safe_max))

	var bar_fill: StyleBoxFlat = StyleBoxFlat.new()
	bar_fill.set_corner_radius_all(2)
	if is_ow:
		bar_fill.bg_color = Color(0.95, 0.25, 0.25)
	elif cap_w > 0 and total_w >= int(float(cap_w) * 0.85):
		bar_fill.bg_color = Color(0.95, 0.8, 0.2)
	else:
		bar_fill.bg_color = Color(0.3, 0.85, 0.45)
	w_bar.add_theme_stylebox_override("fill", bar_fill)

	var bar_bg: StyleBoxFlat = StyleBoxFlat.new()
	bar_bg.bg_color = Color(0.12, 0.14, 0.18, 0.9)
	bar_bg.set_corner_radius_all(2)
	w_bar.add_theme_stylebox_override("background", bar_bg)
	weight_hbox.add_child(w_bar)

	if is_ow:
		var penalty_pct: int = int(round((1.0 - cat.get_overweight_penalty_multiplier()) * 100.0))
		var warn_lbl: Label = Label.new()
		warn_lbl.name = "OverweightWarningLabel"
		warn_lbl.add_theme_font_size_override("font_size", 8)
		warn_lbl.add_theme_color_override("font_color", Color(1.0, 0.45, 0.3))
		warn_lbl.text = "⚠ Внимание: Штраф -" + str(penalty_pct) + "% к скорости и инициативе в бою!"
		weight_box.add_child(warn_lbl)

	var repair_buttons: Array[Button] = []
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
			+ (" | Вес: " + str(part.get_weight()) + " т" if part != null else "")
			+ (" | Мощн: " + str(part.get_power_output()) + " т" if (slot == PartData.PartSlot.BODY and part != null) else "")
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
		_style_garage_button(rep_btn, &"default")
		rep_btn.pressed.connect(func() -> void:
			if SaveManager.run_scrap >= 12:
				SaveManager.add_run_scrap(-12)
				part.repair_full()
				AudioManager.play_sfx("heal")
				SaveManager.save_run()
				_refresh_view()
		)
		slot_card.add_child(rep_btn)
		repair_buttons.append(rep_btn)

	# Перестраиваем склад запчастей
	for child2: Node in _inventory_box.get_children():
		child2.queue_free()

	var inv_buttons: Array[Button] = []
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
		var item_entry: Variant = SaveManager.spare_parts_inventory[inv_idx]
		var pid: String = ""
		var saved_hp: int = -1
		if item_entry is Dictionary:
			pid = String((item_entry as Dictionary).get("part_id", ""))
			saved_hp = int((item_entry as Dictionary).get("current_hp", -1))
		else:
			pid = String(item_entry)

		var pdata: PartData = DataCatalog.get_part(pid)
		if pdata == null:
			continue
		var display_hp: int = pdata.max_hp if saved_hp < 0 else clampi(saved_hp, 0, pdata.max_hp)

		var item_box: VBoxContainer = VBoxContainer.new()
		_inventory_box.add_child(item_box)

		var ilbl: Label = Label.new()
		ilbl.add_theme_font_size_override("font_size", 8)
		var hp_str: String = "HP: " + str(display_hp) + "/" + str(pdata.max_hp)
		ilbl.text = (
			"[" + PartData.slot_to_russian(pdata.slot) + "] " + pdata.part_name
			+ "\n" + hp_str + " | Бр:" + str(pdata.armor) + " | Скор:" + str(pdata.base_speed)
			+ " | Вес:" + str(pdata.weight) + " т"
			+ (" | Мощн:" + str(pdata.power_output) + " т" if pdata.slot == PartData.PartSlot.BODY else "")
		)
		if display_hp <= 0:
			ilbl.add_theme_color_override("font_color", Color(1.0, 0.4, 0.4))
		item_box.add_child(ilbl)

		var eq_btn: Button = Button.new()
		var cur_total: int = cat.get_total_weight()
		var old_part: PartInstance = cat.get_part(pdata.slot)
		var old_w: int = old_part.get_weight() if old_part != null else 0
		var proj_w: int = (cur_total - old_w) + pdata.weight
		var proj_cap: int = pdata.power_output if pdata.slot == PartData.PartSlot.BODY else cat.get_power_capacity()
		var will_overweight: bool = proj_cap > 0 and proj_w > proj_cap
		var ow_diff: int = maxi(0, proj_w - proj_cap) if proj_cap > 0 else 0

		var strict_limit: bool = SaveManager.settings != null and SaveManager.settings.strict_weight_limit
		if will_overweight and strict_limit:
			eq_btn.text = "⛔ Превышен вес (" + str(proj_w) + "/" + str(proj_cap) + " т)"
			eq_btn.disabled = true
			eq_btn.add_theme_color_override("font_color", Color(0.95, 0.4, 0.4))
		elif will_overweight:
			eq_btn.text = "⚠ Установить (" + str(proj_w) + "/" + str(proj_cap) + " т: +" + str(ow_diff) + " т)"
			eq_btn.add_theme_color_override("font_color", Color(1.0, 0.75, 0.25))
		else:
			eq_btn.text = "Установить на " + cat.display_name + " (" + str(proj_w) + "/" + str(proj_cap) + " т)"
		eq_btn.add_theme_font_size_override("font_size", 8)
		_style_garage_button(eq_btn, &"equip")
		eq_btn.focus_entered.connect(func() -> void:
			if _right_scroll != null:
				_right_scroll.ensure_control_visible(eq_btn)
		)
		eq_btn.pressed.connect(func() -> void:
			_equip_inventory_part(inv_idx, pdata, display_hp)
		)
		item_box.add_child(eq_btn)
		inv_buttons.append(eq_btn)

	_link_button_focus_neighbors(inv_buttons)
	if not inv_buttons.is_empty():
		for ibtn: Button in inv_buttons:
			if not repair_buttons.is_empty():
				ibtn.focus_neighbor_left = ibtn.get_path_to(repair_buttons[0])
		for rbtn: Button in repair_buttons:
			rbtn.focus_neighbor_right = rbtn.get_path_to(inv_buttons[0])

func _equip_inventory_part(inv_index: int, new_pdata: PartData, saved_hp: int = -1) -> void:
	var cat: CatMechInstance = SaveManager.party[_selected_cat_idx]
	var initial_hp: int = new_pdata.max_hp if saved_hp < 0 else saved_hp
	var new_inst: PartInstance = PartInstance.new(new_pdata, initial_hp)
	# Применяем бонусы меты, перков и кассеты к новой детали:
	SaveManager.apply_meta_and_tape_bonuses_to_part(new_inst, cat.cat_id)
	new_inst.current_hp = clampi(initial_hp, 0, new_inst.get_max_hp())

	var old_inst: PartInstance = cat.set_part(new_pdata.slot, new_inst)

	SaveManager.spare_parts_inventory.remove_at(inv_index)
	if old_inst != null and old_inst.data != null:
		# Сохраняем на склад с РЕАЛЬНЫМ HP детали (устраняем бесплатный ремонт)
		SaveManager.spare_parts_inventory.append({
			"part_id": String(old_inst.data.part_id),
			"current_hp": old_inst.current_hp
		})

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



func _change_cat_tab(delta: int) -> void:
	if SaveManager.party.is_empty():
		return
	var p_size: int = SaveManager.party.size()
	_selected_cat_idx = (_selected_cat_idx + delta + p_size) % p_size
	AudioManager.play_sfx("ui_click")
	_refresh_view()

func _reclaim_garage_focus() -> void:
	if not is_inside_tree():
		return
	if _inventory_box != null:
		for child: Node in _inventory_box.get_children():
			if child is VBoxContainer:
				for sub: Node in child.get_children():
					if sub is Button and not (sub as Button).disabled:
						(sub as Button).grab_focus()
						return
	if _cat_details_box != null:
		for child2: Node in _cat_details_box.get_children():
			if child2 is VBoxContainer:
				for sub2: Node in child2.get_children():
					if sub2 is Button and not (sub2 as Button).disabled:
						(sub2 as Button).grab_focus()
						return
	if _repair_all_btn != null and not _repair_all_btn.disabled:
		_repair_all_btn.grab_focus()
		return
	if _exit_btn != null:
		_exit_btn.grab_focus()

func _link_button_focus_neighbors(buttons: Array[Button]) -> void:
	if buttons.is_empty():
		return
	if buttons.size() == 1:
		var b0: Button = buttons[0]
		b0.focus_neighbor_top = b0.get_path()
		b0.focus_neighbor_bottom = b0.get_path()
		return
	for i: int in range(buttons.size()):
		var cur: Button = buttons[i]
		var prev: Button = buttons[(i - 1 + buttons.size()) % buttons.size()]
		var nxt: Button = buttons[(i + 1) % buttons.size()]
		cur.focus_neighbor_top = cur.get_path_to(prev)
		cur.focus_neighbor_bottom = cur.get_path_to(nxt)

func _style_garage_button(btn: Button, style_variant: StringName = &"default") -> void:
	if btn == null:
		return
	btn.clip_text = true
	btn.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	btn.focus_mode = Control.FOCUS_ALL

	var normal_box: StyleBoxFlat = StyleBoxFlat.new()
	var hover_box: StyleBoxFlat = StyleBoxFlat.new()
	var focus_box: StyleBoxFlat = StyleBoxFlat.new()
	var pressed_box: StyleBoxFlat = StyleBoxFlat.new()
	var disabled_box: StyleBoxFlat = StyleBoxFlat.new()

	for box: StyleBoxFlat in [normal_box, hover_box, focus_box, pressed_box, disabled_box]:
		box.set_corner_radius_all(3)
		box.content_margin_left = 6
		box.content_margin_right = 6
		box.content_margin_top = 3
		box.content_margin_bottom = 3

	if style_variant == &"equip":
		normal_box.bg_color = Color(0.1, 0.15, 0.22, 0.92)
		normal_box.border_color = Color(0.3, 0.6, 0.85, 0.85)
		normal_box.set_border_width_all(1)

		hover_box.bg_color = Color(0.18, 0.28, 0.42, 0.98)
		hover_box.border_color = Color(0.4, 0.85, 1.0, 1.0)
		hover_box.set_border_width_all(2)

		focus_box.bg_color = Color(0.2, 0.35, 0.55, 1.0)
		focus_box.border_color = Color(0.35, 0.95, 1.0, 1.0)
		focus_box.set_border_width_all(2)
		focus_box.set_expand_margin_all(2)

		pressed_box.bg_color = Color(0.3, 0.5, 0.75, 1.0)
		pressed_box.border_color = Color(1.0, 1.0, 1.0, 1.0)
		pressed_box.set_border_width_all(2)

		btn.add_theme_color_override("font_color", Color(0.88, 0.94, 1.0))
		btn.add_theme_color_override("font_focus_color", Color(1.0, 1.0, 0.35))
		btn.add_theme_color_override("font_hover_color", Color(1.0, 1.0, 0.55))
	else:
		normal_box.bg_color = Color(0.08, 0.11, 0.16, 0.92)
		normal_box.border_color = Color(0.25, 0.45, 0.65, 0.8)
		normal_box.set_border_width_all(1)

		hover_box.bg_color = Color(0.15, 0.22, 0.32, 0.98)
		hover_box.border_color = Color(0.4, 0.8, 1.0, 1.0)
		hover_box.set_border_width_all(2)

		focus_box.bg_color = Color(0.18, 0.3, 0.48, 1.0)
		focus_box.border_color = Color(0.35, 0.95, 1.0, 1.0)
		focus_box.set_border_width_all(2)
		focus_box.set_expand_margin_all(2)

		pressed_box.bg_color = Color(0.25, 0.42, 0.65, 1.0)
		pressed_box.border_color = Color(0.9, 0.95, 1.0, 1.0)
		pressed_box.set_border_width_all(2)

		btn.add_theme_color_override("font_focus_color", Color(1.0, 1.0, 0.35))

	disabled_box.bg_color = Color(0.05, 0.07, 0.1, 0.6)
	disabled_box.border_color = Color(0.2, 0.22, 0.26, 0.4)
	disabled_box.set_border_width_all(1)
	btn.add_theme_color_override("font_disabled_color", Color(0.45, 0.48, 0.52, 0.65))

	btn.add_theme_stylebox_override("normal", normal_box)
	btn.add_theme_stylebox_override("hover", hover_box)
	btn.add_theme_stylebox_override("focus", focus_box)
	btn.add_theme_stylebox_override("pressed", pressed_box)
	btn.add_theme_stylebox_override("disabled", disabled_box)
