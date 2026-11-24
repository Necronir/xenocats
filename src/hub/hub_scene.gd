class_name HubScene
extends Control

## HubScene: «Лагерь Бродяг» — Мета-прогрессия на месте крушения шаттла Bremen-04 (ADR-001 Section 2.3 & 2.8)

var _dev_menu_bar: DevMenuBar = null
var _res_label: Label = null
var _shuttle_box: VBoxContainer = null
var _perks_box: VBoxContainer = null
var _tapes_box: VBoxContainer = null
var _new_run_btn: Button = null
var _continue_run_btn: Button = null
var _ng_cycle_btn: Button = null
var _selected_ng_cycle: int = 0
var _settings_btn: Button = null
var _settings_backdrop: ColorRect = null
var _settings_panel: SettingsPanel = null

const SHUTTLE_MODULES: Array[Dictionary] = [
	{
		"key": "hull_reinforce",
		"title": "Кузница корпусов",
		"desc": "+12 HP ко всем Корпусам за ур."
	},
	{
		"key": "scrap_recycler",
		"title": "Магнитный сепаратор",
		"desc": "+35 стартового Лома в забеге за ур."
	},
	{
		"key": "harmonic_battery",
		"title": "Резонатор «Бремен»",
		"desc": "+12% стартовой Гармонии за ур."
	}
]

const CAT_PERKS: Array[Dictionary] = [
	{
		"id": "FELIX_SPEED",
		"title": "FELIX: Форсаж лап (+3 Иниц.)",
		"cost": 1
	},
	{
		"id": "MULE_CORE_HP",
		"title": "M.U.L.E.: Титановый каркас (+15 HP)",
		"cost": 1
	},
	{
		"id": "HOUND_ARMOR",
		"title": "H.O.U.N.D.: Бронепластины (+1 Броня)",
		"cost": 1
	},
	{
		"id": "COCK_SPEED",
		"title": "C.O.C.K.: Частотный буст (+3 Иниц.)",
		"cost": 1
	}
]

func _ready() -> void:
	DataCatalog.ensure_loaded()
	if SaveManager.highest_ng_cycle > 0 and SaveManager.get_story_phase() == StoryProgressionData.StoryPhase.COMPLETED:
		_selected_ng_cycle = SaveManager.highest_ng_cycle
	elif SaveManager.ng_cycle > 0:
		_selected_ng_cycle = clampi(SaveManager.ng_cycle, 0, SaveManager.highest_ng_cycle)
	AudioManager.play_tape(SaveManager.equipped_tape_id)
	_build_ui()
	_refresh_hub()

func _build_ui() -> void:
	var bg: TextureRect = TextureRect.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.stretch_mode = TextureRect.STRETCH_SCALE
	if ResourceLoader.exists("res://assets/sprites/backgrounds/bg_hub.png"):
		bg.texture = load("res://assets/sprites/backgrounds/bg_hub.png") as Texture2D
	add_child(bg)

	var st: StyleBoxFlat = StyleBoxFlat.new()
	st.bg_color = Color(0.06, 0.08, 0.13, 0.93)
	st.border_color = Color(0.9, 0.65, 0.25, 0.95)
	st.set_border_width_all(1)
	st.set_corner_radius_all(3)
	st.set_content_margin_all(5)

	# Верхнее меню разработчика (Fast Track к боссу уровня, Issue #16)
	_dev_menu_bar = DevMenuBar.new()
	add_child(_dev_menu_bar)

	# Верхняя панель
	var top_panel: PanelContainer = PanelContainer.new()
	top_panel.position = Vector2(8, 30)
	top_panel.size = Vector2(624, 30)
	top_panel.add_theme_stylebox_override("panel", st)
	add_child(top_panel)

	var top_hbox: HBoxContainer = HBoxContainer.new()
	top_hbox.add_theme_constant_override("separation", 10)
	top_panel.add_child(top_hbox)

	var title_lbl: Label = Label.new()
	title_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_lbl.text = "ЛАГЕРЬ БРОДЯГ (ХАБ) — Аварийная частота: Бремен-4"
	title_lbl.add_theme_font_size_override("font_size", 11)
	title_lbl.add_theme_color_override("font_color", Color(1.0, 0.85, 0.35))
	top_hbox.add_child(title_lbl)

	_res_label = Label.new()
	_res_label.add_theme_font_size_override("font_size", 10)
	_res_label.add_theme_color_override("font_color", Color(0.4, 0.95, 1.0))
	top_hbox.add_child(_res_label)

	_settings_btn = Button.new()
	_settings_btn.text = "⚙ НАСТРОЙКИ"
	_settings_btn.add_theme_font_size_override("font_size", 9)
	_style_hub_button(_settings_btn, Color(0.95, 0.9, 0.5))
	_settings_btn.pressed.connect(func() -> void:
		AudioManager.play_sfx("ui_click")
		if _settings_backdrop != null:
			_settings_backdrop.visible = true
		if _settings_panel != null:
			_settings_panel.open_panel()
	)
	top_hbox.add_child(_settings_btn)

	# Три колонки мета-прогрессии
	var cols: HBoxContainer = HBoxContainer.new()
	cols.position = Vector2(8, 63)
	cols.size = Vector2(624, 237)
	cols.add_theme_constant_override("separation", 6)
	add_child(cols)

	# Колонка 1: Ремонт модулей шаттла (Titanium Scrap)
	var col1_panel: PanelContainer = PanelContainer.new()
	col1_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col1_panel.add_theme_stylebox_override("panel", st)
	cols.add_child(col1_panel)
	_shuttle_box = VBoxContainer.new()
	_shuttle_box.add_theme_constant_override("separation", 5)
	col1_panel.add_child(_shuttle_box)

	# Колонка 2: Перки котов за AI Cores
	var col2_panel: PanelContainer = PanelContainer.new()
	col2_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col2_panel.add_theme_stylebox_override("panel", st)
	cols.add_child(col2_panel)
	_perks_box = VBoxContainer.new()
	_perks_box.add_theme_constant_override("separation", 5)
	col2_panel.add_child(_perks_box)

	# Колонка 3: Аварийные кассеты (Music Tapes)
	var col3_panel: PanelContainer = PanelContainer.new()
	col3_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col3_panel.add_theme_stylebox_override("panel", st)
	cols.add_child(col3_panel)
	_tapes_box = VBoxContainer.new()
	_tapes_box.add_theme_constant_override("separation", 5)
	col3_panel.add_child(_tapes_box)

	# Нижняя панель старта забега
	var bot_panel: PanelContainer = PanelContainer.new()
	bot_panel.position = Vector2(8, 304)
	bot_panel.size = Vector2(624, 50)
	bot_panel.add_theme_stylebox_override("panel", st)
	add_child(bot_panel)

	var bot_hbox: HBoxContainer = HBoxContainer.new()
	bot_hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	bot_hbox.add_theme_constant_override("separation", 8)
	bot_panel.add_child(bot_hbox)

	_ng_cycle_btn = Button.new()
	_ng_cycle_btn.custom_minimum_size = Vector2(165, 34)
	_ng_cycle_btn.add_theme_font_size_override("font_size", 9)
	_ng_cycle_btn.visible = false
	_style_hub_button(_ng_cycle_btn, Color(1.0, 0.85, 0.35))
	_ng_cycle_btn.pressed.connect(func() -> void:
		AudioManager.play_sfx("ui_click")
		if SaveManager.highest_ng_cycle > 0:
			_selected_ng_cycle = (_selected_ng_cycle + 1) % (SaveManager.highest_ng_cycle + 1)
		_refresh_hub()
		if _ng_cycle_btn != null and _ng_cycle_btn.visible:
			_ng_cycle_btn.grab_focus()
	)
	bot_hbox.add_child(_ng_cycle_btn)

	_new_run_btn = Button.new()
	var new_run_btn: Button = _new_run_btn
	new_run_btn.custom_minimum_size = Vector2(260, 34)
	new_run_btn.text = "★ НОВЫЙ ЗАБЕГ К ВЫШКЕ БРЕМЕН-4 ★"
	new_run_btn.add_theme_font_size_override("font_size", 10)
	_style_hub_button(new_run_btn, Color(0.4, 1.0, 0.55))
	new_run_btn.pressed.connect(func() -> void:
		AudioManager.play_sfx("ui_click")
		SaveManager.start_new_run()
		if _selected_ng_cycle > 0 and SaveManager.highest_ng_cycle > 0:
			SaveManager.ng_cycle = clampi(_selected_ng_cycle, 0, SaveManager.highest_ng_cycle)
			SaveManager.save_run()

		var is_cycle_0: bool = SaveManager.story_progression != null and SaveManager.story_progression.current_phase == StoryProgressionData.StoryPhase.CYCLE_0_SOLO_CAT

		if is_cycle_0:
			var cat_dtl_payload: Dictionary = {
				"timeline": "res://data/dialogues/story_intro_cat.dtl",
				"next_scene": &"MAP",
				"next_payload": {},
				"title": "ПРОЛОГ: ИЗГНАНИЕ КОТА (ЧАСТЬ 1)",
				"continue_text": "В ПУТЬ К ВЫШКЕ БРЕМЕН-4 ->"
			}
			var cat_video_payload: Dictionary = {
				"video_path": "res://assets/videos/1-1-start.ogv",
				"title": "ПРОЛОГ: ПОБЕГ ФЕЛИКСА",
				"story_stage": 1,
				"next_scene": &"EVENT",
				"next_payload": cat_dtl_payload
			}
			var cat_img: String = "res://assets/photos/1-1-cat-start.jpg"
			if ResourceLoader.exists(cat_img):
				EventBus.request_scene_change.emit(&"VIDEO", {
					"image_path": cat_img,
					"title": "ПРОЛОГ: ИЗГНАНИЕ КОТА ФЕЛИКСА",
					"story_stage": 1,
					"next_scene": &"VIDEO",
					"next_payload": cat_video_payload
				})
			elif ResourceLoader.exists("res://assets/videos/1-1-start.ogv"):
				EventBus.request_scene_change.emit(&"VIDEO", cat_video_payload)
			elif ResourceLoader.exists("res://assets/videos/1-cat.ogv"):
				EventBus.request_scene_change.emit(&"VIDEO", {
					"video_path": "res://assets/videos/1-cat.ogv",
					"title": "FELIX — СЕРВИСНЫЙ ЮНИТ-МУЗЫКАНТ",
					"next_scene": &"EVENT",
					"next_payload": cat_dtl_payload
				})
			else:
				EventBus.request_scene_change.emit(&"EVENT", cat_dtl_payload)
		else:
			EventBus.request_scene_change.emit(&"MAP", {})
	)
	bot_hbox.add_child(new_run_btn)

	_continue_run_btn = Button.new()
	_continue_run_btn.custom_minimum_size = Vector2(260, 34)
	_continue_run_btn.add_theme_font_size_override("font_size", 10)
	_style_hub_button(_continue_run_btn, Color(0.45, 0.95, 1.0))
	_continue_run_btn.pressed.connect(func() -> void:
		AudioManager.play_sfx("ui_click")
		if not SaveManager.pending_battle.is_empty():
			EventBus.request_scene_change.emit(&"BATTLE", SaveManager.pending_battle.duplicate(true))
		else:
			EventBus.request_scene_change.emit(&"MAP", {})
	)
	bot_hbox.add_child(_continue_run_btn)

	# Оверлей настроек поверх Хаба (без паузы)
	_settings_backdrop = ColorRect.new()
	_settings_backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	_settings_backdrop.color = Color(0.0, 0.0, 0.0, 0.65)
	_settings_backdrop.visible = false
	add_child(_settings_backdrop)

	_settings_panel = SettingsPanel.new()
	_settings_panel.visible = false
	_settings_panel.closed.connect(func() -> void:
		if _settings_backdrop != null:
			_settings_backdrop.visible = false
		_refresh_hub()
		if _settings_btn != null and _settings_btn.is_inside_tree():
			_settings_btn.grab_focus()
	)
	add_child(_settings_panel)

func _refresh_hub() -> void:
	var ng_str: String = (" | ЦИКЛ NG+: " + str(SaveManager.ng_cycle)) if SaveManager.ng_cycle > 0 else ""
	_res_label.text = (
		"Титановый сплав: " + str(SaveManager.titanium_scrap)
		+ " | Ядра ИИ (Cores): " + str(SaveManager.ai_cores)
		+ " | Эвакуаций: " + str(SaveManager.successful_evacuations)
		+ ng_str
	)

	var col1_btns: Array[Button] = []
	var col2_btns: Array[Button] = []
	var col3_btns: Array[Button] = []

	# 1. Модули шаттла
	for ch: Node in _shuttle_box.get_children():
		_shuttle_box.remove_child(ch)
		ch.queue_free()
	var h1: Label = Label.new()
	h1.text = "МОДУЛИ ШАТТЛА (Титановый лом):"
	h1.add_theme_font_size_override("font_size", 9)
	h1.add_theme_color_override("font_color", Color(0.95, 0.85, 0.35))
	_shuttle_box.add_child(h1)

	for mod: Dictionary in SHUTTLE_MODULES:
		var mkey: String = String(mod["key"])
		var lvl: int = int(SaveManager.shuttle_upgrades.get(mkey, 0))
		var cost: int = SaveManager.get_shuttle_upgrade_cost(mkey)
		var m_lbl: Label = Label.new()
		m_lbl.text = String(mod["title"]) + " [Ур." + str(lvl) + "/3]\n" + String(mod["desc"])
		m_lbl.add_theme_font_size_override("font_size", 8)
		_shuttle_box.add_child(m_lbl)

		var m_btn: Button = Button.new()
		m_btn.add_theme_font_size_override("font_size", 8)
		if lvl >= 3:
			m_btn.text = "МАКС. УРОВЕНЬ"
			m_btn.disabled = true
		else:
			m_btn.text = "Улучшить (" + str(cost) + " Сплава)"
			m_btn.disabled = SaveManager.titanium_scrap < cost
		_style_hub_button(m_btn, Color(0.95, 0.88, 0.45))
		m_btn.pressed.connect(func() -> void:
			if SaveManager.upgrade_shuttle_module(mkey, cost):
				AudioManager.play_sfx("heal")
				_refresh_hub()
		)
		_shuttle_box.add_child(m_btn)
		if not m_btn.disabled:
			col1_btns.append(m_btn)

	# 2. Перки котов за AI Cores
	for ch2: Node in _perks_box.get_children():
		_perks_box.remove_child(ch2)
		ch2.queue_free()
	var h2: Label = Label.new()
	h2.text = "НЕЙРО-ПЕРКИ КОТОВ (AI Cores):"
	h2.add_theme_font_size_override("font_size", 9)
	h2.add_theme_color_override("font_color", Color(0.4, 0.95, 1.0))
	_perks_box.add_child(h2)

	for pk: Dictionary in CAT_PERKS:
		var pid: String = String(pk["id"])
		var pcost: int = int(pk["cost"])
		var unlocked: bool = SaveManager.has_perk(pid)
		var p_btn: Button = Button.new()
		p_btn.add_theme_font_size_override("font_size", 8)
		if unlocked:
			p_btn.text = "★ " + String(pk["title"]) + " [ОТКРЫТО]"
			p_btn.disabled = true
		else:
			p_btn.text = String(pk["title"]) + " (" + str(pcost) + " Ядро)"
			p_btn.disabled = SaveManager.ai_cores < pcost
		_style_hub_button(p_btn, Color(0.45, 0.95, 1.0))
		p_btn.pressed.connect(func() -> void:
			if SaveManager.unlock_perk(pid, pcost):
				AudioManager.play_sfx("qte_perfect")
				_refresh_hub()
		)
		_perks_box.add_child(p_btn)
		if not p_btn.disabled:
			col2_btns.append(p_btn)

	# 3. Аварийные кассеты (Music Tapes)
	for ch3: Node in _tapes_box.get_children():
		_tapes_box.remove_child(ch3)
		ch3.queue_free()
	var h3: Label = Label.new()
	h3.text = "АВАРИЙНЫЕ КАССЕТЫ (Ауры):"
	h3.add_theme_font_size_override("font_size", 9)
	h3.add_theme_color_override("font_color", Color(0.9, 0.6, 1.0))
	_tapes_box.add_child(h3)

	for tape: MusicTapeData in DataCatalog.get_all_tapes():
		var is_unlocked: bool = SaveManager.unlocked_tapes.has(String(tape.tape_id))
		var is_eq: bool = (SaveManager.equipped_tape_id == tape.tape_id)
		var t_lbl: Label = Label.new()
		t_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		t_lbl.add_theme_font_size_override("font_size", 8)
		if is_unlocked:
			t_lbl.text = tape.tape_name + "\n" + tape.description
		else:
			t_lbl.text = "[!] " + tape.tape_name + "\n[ТРЕБУЕТСЯ ПОБЕДА В ЭПИЛОГЕ]"
		_tapes_box.add_child(t_lbl)

		var t_btn: Button = Button.new()
		t_btn.add_theme_font_size_override("font_size", 8)
		if not is_unlocked:
			t_btn.text = "Заблокировано"
			t_btn.disabled = true
		elif is_eq:
			t_btn.text = "★ ИГРАЕТ СЕЙЧАС ★"
			t_btn.disabled = true
		else:
			t_btn.text = "Вставить кассету"
			t_btn.disabled = false
		_style_hub_button(t_btn, Color(0.9, 0.7, 1.0))
		t_btn.pressed.connect(func() -> void:
			SaveManager.equip_tape(tape.tape_id)
			AudioManager.play_tape(tape.tape_id)
			_refresh_hub()
		)
		_tapes_box.add_child(t_btn)
		if not t_btn.disabled:
			col3_btns.append(t_btn)

	# 4. Переключатель New Game+ и кнопки старта / продолжения забега
	if _ng_cycle_btn != null:
		if SaveManager.highest_ng_cycle > 0:
			_selected_ng_cycle = clampi(_selected_ng_cycle, 0, SaveManager.highest_ng_cycle)
			_ng_cycle_btn.visible = true
			if _selected_ng_cycle <= 0:
				_ng_cycle_btn.text = "СЛОЖНОСТЬ: ОБЫЧНАЯ"
			else:
				_ng_cycle_btn.text = "★ ЦИКЛ: NG+ " + str(_selected_ng_cycle) + " ★"
		else:
			_selected_ng_cycle = 0
			_ng_cycle_btn.visible = false

	if SaveManager.has_active_run:
		_continue_run_btn.visible = true
		var prefix_txt: String = (
			"ВЕРНУТЬСЯ В БОЙ"
			if not SaveManager.pending_battle.is_empty()
			else "ПРОДОЛЖИТЬ ЗАБЕГ"
		)
		_continue_run_btn.text = (
			prefix_txt + " (Сектор " + str(SaveManager.current_sector)
			+ ", Этаж " + str(maxi(1, SaveManager.current_floor)) + ")"
		)
	else:
		_continue_run_btn.visible = false

	var compact_bot: bool = (_ng_cycle_btn != null and _ng_cycle_btn.visible and _continue_run_btn != null and _continue_run_btn.visible)
	if _new_run_btn != null:
		_new_run_btn.custom_minimum_size.x = 205.0 if compact_bot else 260.0
	if _continue_run_btn != null:
		_continue_run_btn.custom_minimum_size.x = 205.0 if compact_bot else 260.0

	_wire_hub_focus_grid([col1_btns, col2_btns, col3_btns])

	if _continue_run_btn != null and _continue_run_btn.visible:
		_continue_run_btn.grab_focus()
	elif _new_run_btn != null and _new_run_btn.visible:
		_new_run_btn.grab_focus()

func _wire_hub_focus_grid(columns: Array) -> void:
	var bot_btns: Array[Button] = []
	for b: Button in [_ng_cycle_btn, _new_run_btn, _continue_run_btn]:
		if b != null and b.visible and not b.disabled:
			bot_btns.append(b)

	for bi: int in range(bot_btns.size()):
		var b_cur: Button = bot_btns[bi]
		var b_prev: Button = bot_btns[(bi - 1 + bot_btns.size()) % bot_btns.size()]
		var b_next: Button = bot_btns[(bi + 1) % bot_btns.size()]
		b_cur.focus_neighbor_left = b_cur.get_path_to(b_prev)
		b_cur.focus_neighbor_right = b_cur.get_path_to(b_next)

	var non_empty_cols: Array = []
	for col_v: Variant in columns:
		var col_arr: Array = col_v as Array
		if not col_arr.is_empty():
			non_empty_cols.append(col_arr)

	var primary_bot: Button = _continue_run_btn if (_continue_run_btn != null and _continue_run_btn.visible) else _new_run_btn
	if non_empty_cols.is_empty():
		if _settings_btn != null and primary_bot != null:
			_settings_btn.focus_neighbor_bottom = _settings_btn.get_path_to(primary_bot)
			for b2: Button in bot_btns:
				b2.focus_neighbor_top = b2.get_path_to(_settings_btn)
		return

	var first_col_top: Button = (non_empty_cols[0] as Array)[0] as Button
	if _settings_btn != null and first_col_top != null:
		_settings_btn.focus_neighbor_bottom = _settings_btn.get_path_to(first_col_top)

	for c_idx: int in range(non_empty_cols.size()):
		var col_btns: Array = non_empty_cols[c_idx] as Array
		var left_col: Array = non_empty_cols[(c_idx - 1 + non_empty_cols.size()) % non_empty_cols.size()] as Array
		var right_col: Array = non_empty_cols[(c_idx + 1) % non_empty_cols.size()] as Array
		for r_idx: int in range(col_btns.size()):
			var cur_btn: Button = col_btns[r_idx] as Button
			if r_idx == 0:
				if _settings_btn != null:
					cur_btn.focus_neighbor_top = cur_btn.get_path_to(_settings_btn)
			else:
				var up_btn: Button = col_btns[r_idx - 1] as Button
				cur_btn.focus_neighbor_top = cur_btn.get_path_to(up_btn)

			if r_idx == col_btns.size() - 1:
				if primary_bot != null:
					cur_btn.focus_neighbor_bottom = cur_btn.get_path_to(primary_bot)
			else:
				var dn_btn: Button = col_btns[r_idx + 1] as Button
				cur_btn.focus_neighbor_bottom = cur_btn.get_path_to(dn_btn)

			var l_target: Button = left_col[mini(r_idx, left_col.size() - 1)] as Button
			var r_target: Button = right_col[mini(r_idx, right_col.size() - 1)] as Button
			cur_btn.focus_neighbor_left = cur_btn.get_path_to(l_target)
			cur_btn.focus_neighbor_right = cur_btn.get_path_to(r_target)

	var first_col_bottom: Button = (non_empty_cols[0] as Array)[(non_empty_cols[0] as Array).size() - 1] as Button
	for b3: Button in bot_btns:
		if first_col_bottom != null:
			b3.focus_neighbor_top = b3.get_path_to(first_col_bottom)

func _style_hub_button(btn: Button, font_col: Color) -> void:
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
		box.content_margin_left = 5
		box.content_margin_right = 5
		box.content_margin_top = 3
		box.content_margin_bottom = 3

	normal_box.bg_color = Color(0.08, 0.11, 0.18, 0.92)
	normal_box.border_color = Color(0.3, 0.5, 0.7, 0.8)
	normal_box.set_border_width_all(1)

	hover_box.bg_color = Color(0.15, 0.22, 0.34, 0.98)
	hover_box.border_color = Color(0.45, 0.85, 1.0, 1.0)
	hover_box.set_border_width_all(2)

	focus_box.bg_color = Color(0.2, 0.3, 0.48, 1.0)
	focus_box.border_color = Color(1.0, 0.92, 0.35, 1.0)
	focus_box.set_border_width_all(2)
	focus_box.set_expand_margin_all(1)

	pressed_box.bg_color = Color(0.28, 0.44, 0.68, 1.0)
	pressed_box.border_color = Color(1.0, 1.0, 0.85, 1.0)
	pressed_box.set_border_width_all(2)

	disabled_box.bg_color = Color(0.05, 0.07, 0.1, 0.6)
	disabled_box.border_color = Color(0.2, 0.22, 0.28, 0.45)
	disabled_box.set_border_width_all(1)

	btn.add_theme_color_override("font_color", font_col)
	btn.add_theme_color_override("font_focus_color", Color(1.0, 1.0, 0.4))
	btn.add_theme_color_override("font_hover_color", Color(1.0, 1.0, 0.65))
	btn.add_theme_color_override("font_disabled_color", Color(0.45, 0.48, 0.52, 0.7))

	btn.add_theme_stylebox_override("normal", normal_box)
	btn.add_theme_stylebox_override("hover", hover_box)
	btn.add_theme_stylebox_override("focus", focus_box)
	btn.add_theme_stylebox_override("pressed", pressed_box)
	btn.add_theme_stylebox_override("disabled", disabled_box)

func _unhandled_input(event: InputEvent) -> void:
	if _settings_panel != null and _settings_panel.visible:
		return

	var is_joy_pause: bool = (
		event is InputEventJoypadButton
		and event.is_pressed()
		and (event as InputEventJoypadButton).button_index in [JOY_BUTTON_START, JOY_BUTTON_BACK, JOY_BUTTON_GUIDE]
	)
	if event.is_action_pressed(&"pause") or is_joy_pause:
		if _settings_panel != null and not _settings_panel.visible:
			AudioManager.play_sfx("ui_click")
			if _settings_backdrop != null:
				_settings_backdrop.visible = true
			_settings_panel.open_panel()
			get_viewport().set_input_as_handled()
			return

	if get_viewport().gui_get_focus_owner() == null:
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
			if _continue_run_btn != null and _continue_run_btn.visible:
				_continue_run_btn.grab_focus()
			elif _new_run_btn != null and _new_run_btn.visible:
				_new_run_btn.grab_focus()
			get_viewport().set_input_as_handled()
