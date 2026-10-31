class_name HubScene
extends Control

## HubScene: «Лагерь Бродяг» — Мета-прогрессия на месте крушения шаттла Bremen-04 (ADR-001 Section 2.3 & 2.8)

var _res_label: Label = null
var _shuttle_box: VBoxContainer = null
var _perks_box: VBoxContainer = null
var _tapes_box: VBoxContainer = null
var _continue_run_btn: Button = null

const SHUTTLE_MODULES: Array[Dictionary] = [
	{
		"key": "hull_reinforce",
		"title": "Кузница корпусов",
		"desc": "+12 HP ко всем Корпусам за ур.",
		"cost": 40
	},
	{
		"key": "scrap_recycler",
		"title": "Магнитный сепаратор",
		"desc": "+35 стартового Лома в забеге за ур.",
		"cost": 35
	},
	{
		"key": "harmonic_battery",
		"title": "Резонатор «Бремен»",
		"desc": "+25% стартовой Гармонии за ур.",
		"cost": 45
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

	# Верхняя панель
	var top_panel: PanelContainer = PanelContainer.new()
	top_panel.position = Vector2(8, 6)
	top_panel.size = Vector2(624, 38)
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

	# Три колонки мета-прогрессии
	var cols: HBoxContainer = HBoxContainer.new()
	cols.position = Vector2(8, 48)
	cols.size = Vector2(624, 250)
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
	bot_hbox.add_theme_constant_override("separation", 12)
	bot_panel.add_child(bot_hbox)

	var new_run_btn: Button = Button.new()
	new_run_btn.custom_minimum_size = Vector2(260, 34)
	new_run_btn.text = "★ НОВЫЙ ЗАБЕГ К ВЫШКЕ БРЕМЕН-4 ★"
	new_run_btn.add_theme_font_size_override("font_size", 11)
	new_run_btn.add_theme_color_override("font_color", Color(0.4, 1.0, 0.55))
	new_run_btn.pressed.connect(func() -> void:
		AudioManager.play_sfx("ui_click")
		SaveManager.start_new_run()
		EventBus.request_scene_change.emit(&"EVENT", {
			"timeline": "res://data/dialogues/story_intro_crash.dtl",
			"next_scene": &"MAP",
			"next_payload": {},
			"title": "КРУШЕНИЕ BREMEN-04 // ПРОБУЖДЕНИЕ",
			"continue_text": "ОТПРАВИТЬСЯ К ВЫШКЕ ->"
		})
	)
	bot_hbox.add_child(new_run_btn)

	_continue_run_btn = Button.new()
	_continue_run_btn.custom_minimum_size = Vector2(260, 34)
	_continue_run_btn.add_theme_font_size_override("font_size", 10)
	_continue_run_btn.pressed.connect(func() -> void:
		AudioManager.play_sfx("ui_click")
		EventBus.request_scene_change.emit(&"MAP", {})
	)
	bot_hbox.add_child(_continue_run_btn)

func _refresh_hub() -> void:
	_res_label.text = (
		"Титановый сплав: " + str(SaveManager.titanium_scrap)
		+ " | Ядра ИИ (Cores): " + str(SaveManager.ai_cores)
	)

	# 1. Модули шаттла
	for ch: Node in _shuttle_box.get_children():
		ch.queue_free()
	var h1: Label = Label.new()
	h1.text = "МОДУЛИ ШАТТЛА (Титановый лом):"
	h1.add_theme_font_size_override("font_size", 9)
	h1.add_theme_color_override("font_color", Color(0.95, 0.85, 0.35))
	_shuttle_box.add_child(h1)

	for mod: Dictionary in SHUTTLE_MODULES:
		var mkey: String = String(mod["key"])
		var lvl: int = int(SaveManager.shuttle_upgrades.get(mkey, 0))
		var cost: int = int(mod["cost"])
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
		m_btn.pressed.connect(func() -> void:
			if SaveManager.upgrade_shuttle_module(mkey, cost):
				AudioManager.play_sfx("heal")
				_refresh_hub()
		)
		_shuttle_box.add_child(m_btn)

	# 2. Перки котов за AI Cores
	for ch2: Node in _perks_box.get_children():
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
			p_btn.text = "✓ " + String(pk["title"]) + " [ОТКРЫТО]"
			p_btn.disabled = true
		else:
			p_btn.text = String(pk["title"]) + " (" + str(pcost) + " Ядро)"
			p_btn.disabled = SaveManager.ai_cores < pcost
		p_btn.pressed.connect(func() -> void:
			if SaveManager.unlock_perk(pid, pcost):
				AudioManager.play_sfx("qte_perfect")
				_refresh_hub()
		)
		_perks_box.add_child(p_btn)

	# 3. Аварийные кассеты (Music Tapes)
	for ch3: Node in _tapes_box.get_children():
		ch3.queue_free()
	var h3: Label = Label.new()
	h3.text = "АВАРИЙНЫЕ КАССЕТЫ (Ауры):"
	h3.add_theme_font_size_override("font_size", 9)
	h3.add_theme_color_override("font_color", Color(0.9, 0.6, 1.0))
	_tapes_box.add_child(h3)

	for tape: MusicTapeData in DataCatalog.get_all_tapes():
		var is_eq: bool = (SaveManager.equipped_tape_id == tape.tape_id)
		var t_lbl: Label = Label.new()
		t_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		t_lbl.add_theme_font_size_override("font_size", 8)
		t_lbl.text = tape.tape_name + "\n" + tape.description
		_tapes_box.add_child(t_lbl)

		var t_btn: Button = Button.new()
		t_btn.add_theme_font_size_override("font_size", 8)
		t_btn.text = "♪ ИГРАЕТ СЕЙЧАС ♪" if is_eq else "Вставить кассету"
		t_btn.disabled = is_eq
		t_btn.pressed.connect(func() -> void:
			SaveManager.equipped_tape_id = tape.tape_id
			SaveManager.save_meta()
			AudioManager.play_tape(tape.tape_id)
			_refresh_hub()
		)
		_tapes_box.add_child(t_btn)

	# 4. Кнопка продолжения забега
	if SaveManager.has_active_run:
		_continue_run_btn.visible = true
		_continue_run_btn.text = (
			"ПРОДОЛЖИТЬ ЗАБЕГ (Сектор " + str(SaveManager.current_sector)
			+ ", Этаж " + str(maxi(1, SaveManager.current_floor)) + ")"
		)
	else:
		_continue_run_btn.visible = false

