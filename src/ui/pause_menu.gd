class_name PauseMenu
extends CanvasLayer

## PauseMenu: Глобальное меню паузы (Esc) для Боя и Карты с настройками, справочником и переигровкой боя (Issue #12)

var allowed: bool = false
var mode: StringName = &""
var current_scene_ref: Node = null
var is_open: bool = false

var _backdrop: ColorRect = null
var _main_panel: PanelContainer = null
var _settings_panel: SettingsPanel = null
var _tutorials_panel: PanelContainer = null
var _tutorials_list_box: VBoxContainer = null

var _resume_btn: Button = null
var _settings_btn: Button = null
var _tutorials_btn: Button = null
var _retry_battle_btn: Button = null
var _hub_btn: Button = null

func _ready() -> void:
	layer = 50
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	_ensure_input_actions()
	_build_ui()

func _ensure_input_actions() -> void:
	if not InputMap.has_action(&"pause"):
		InputMap.add_action(&"pause")
		var ev_esc: InputEventKey = InputEventKey.new()
		ev_esc.keycode = KEY_ESCAPE
		InputMap.action_add_event(&"pause", ev_esc)
		var ev_joy: InputEventJoypadButton = InputEventJoypadButton.new()
		ev_joy.button_index = JOY_BUTTON_START
		InputMap.action_add_event(&"pause", ev_joy)

	if not InputMap.has_action(&"toggle_fullscreen"):
		InputMap.add_action(&"toggle_fullscreen")
		var ev_f11: InputEventKey = InputEventKey.new()
		ev_f11.keycode = KEY_F11
		InputMap.action_add_event(&"toggle_fullscreen", ev_f11)

func _build_ui() -> void:
	_backdrop = ColorRect.new()
	_backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	_backdrop.color = Color(0.0, 0.0, 0.0, 0.65)
	add_child(_backdrop)

	var st: StyleBoxFlat = StyleBoxFlat.new()
	st.bg_color = Color(0.06, 0.08, 0.14, 0.98)
	st.border_color = Color(0.35, 0.85, 1.0, 1.0)
	st.set_border_width_all(2)
	st.set_corner_radius_all(4)
	st.set_content_margin_all(12)

	# 1. Главная панель паузы
	_main_panel = PanelContainer.new()
	_main_panel.position = Vector2(170, 62)
	_main_panel.size = Vector2(300, 236)
	_main_panel.add_theme_stylebox_override("panel", st)
	add_child(_main_panel)

	var vbox: VBoxContainer = VBoxContainer.new()
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 8)
	_main_panel.add_child(vbox)

	var title_lbl: Label = Label.new()
	title_lbl.text = "⏸ ПАУЗА // ЧАСТОТА БРЕМЕН-4"
	title_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_lbl.add_theme_font_size_override("font_size", 12)
	title_lbl.add_theme_color_override("font_color", Color(1.0, 0.88, 0.35))
	vbox.add_child(title_lbl)

	_resume_btn = _make_menu_button("ПРОДОЛЖИТЬ [ESC]", Color(0.4, 1.0, 0.6), func() -> void:
		AudioManager.play_sfx("ui_click")
		close()
	)
	vbox.add_child(_resume_btn)

	_settings_btn = _make_menu_button("⚙ НАСТРОЙКИ ЗВУКА И ЭКРАНА", Color(0.4, 0.95, 1.0), func() -> void:
		AudioManager.play_sfx("ui_click")
		_main_panel.visible = false
		_settings_panel.open_panel()
	)
	vbox.add_child(_settings_btn)

	_tutorials_btn = _make_menu_button("📖 СПРАВОЧНИК ОБУЧЕНИЯ", Color(0.95, 0.88, 0.45), func() -> void:
		AudioManager.play_sfx("ui_click")
		_open_tutorials_subpanel()
	)
	vbox.add_child(_tutorials_btn)

	_retry_battle_btn = _make_menu_button("↻ ПЕРЕИГРАТЬ БОЙ С НАЧАЛА", Color(1.0, 0.78, 0.35), retry_current_battle)
	vbox.add_child(_retry_battle_btn)

	_hub_btn = _make_menu_button("⌂ В ЛАГЕРЬ БРОДЯГ (ХАБ)", Color(1.0, 0.55, 0.55), return_to_hub)
	vbox.add_child(_hub_btn)

	# 2. Вложенная панель настроек
	_settings_panel = SettingsPanel.new()
	_settings_panel.visible = false
	_settings_panel.closed.connect(func() -> void:
		_main_panel.visible = true
		if _settings_btn != null:
			_settings_btn.grab_focus()
	)
	add_child(_settings_panel)

	# 3. Вложенная панель справочника обучения
	_tutorials_panel = PanelContainer.new()
	_tutorials_panel.position = Vector2(140, 56)
	_tutorials_panel.size = Vector2(360, 248)
	_tutorials_panel.visible = false
	_tutorials_panel.add_theme_stylebox_override("panel", st)
	add_child(_tutorials_panel)

	var tut_vbox: VBoxContainer = VBoxContainer.new()
	tut_vbox.add_theme_constant_override("separation", 6)
	_tutorials_panel.add_child(tut_vbox)

	var tut_title: Label = Label.new()
	tut_title.text = "📖 СПРАВОЧНИК МЕХАНИК БРЕМЕН-4"
	tut_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tut_title.add_theme_font_size_override("font_size", 11)
	tut_title.add_theme_color_override("font_color", Color(1.0, 0.88, 0.35))
	tut_vbox.add_child(tut_title)

	_tutorials_list_box = VBoxContainer.new()
	_tutorials_list_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_tutorials_list_box.add_theme_constant_override("separation", 5)
	tut_vbox.add_child(_tutorials_list_box)

	var tut_back_btn: Button = _make_menu_button("<- НАЗАД В МЕНЮ ПАУЗЫ", Color(0.4, 0.95, 1.0), func() -> void:
		AudioManager.play_sfx("ui_click")
		_close_tutorials_subpanel()
	)
	tut_vbox.add_child(tut_back_btn)

func _make_menu_button(text_str: String, font_col: Color, on_press: Callable) -> Button:
	var btn: Button = Button.new()
	btn.text = text_str
	btn.custom_minimum_size = Vector2(240, 28)
	btn.add_theme_font_size_override("font_size", 9)
	btn.add_theme_color_override("font_color", font_col)
	btn.pressed.connect(on_press)
	return btn

func _open_tutorials_subpanel() -> void:
	_main_panel.visible = false
	_tutorials_panel.visible = true
	for ch: Node in _tutorials_list_box.get_children():
		ch.queue_free()
	var tutorials: Array[TutorialData] = DataCatalog.get_all_tutorials()
	for td: TutorialData in tutorials:
		var tid: StringName = td.tutorial_id
		var b: Button = _make_menu_button("• " + td.title, Color(0.9, 0.95, 1.0), func() -> void:
			AudioManager.play_sfx("ui_click")
			TutorialOverlay.show_reference(self, tid)
		)
		_tutorials_list_box.add_child(b)

func _close_tutorials_subpanel() -> void:
	_tutorials_panel.visible = false
	_main_panel.visible = true
	if _tutorials_btn != null:
		_tutorials_btn.grab_focus()

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"toggle_fullscreen"):
		if SaveManager.settings != null:
			SaveManager.settings.set_fullscreen(not SaveManager.settings.fullscreen)
			SaveManager.settings.save_to_disk(SaveManager.SETTINGS_PATH)
			if _settings_panel != null and _settings_panel.visible:
				_settings_panel.refresh_from_settings()
		get_viewport().set_input_as_handled()
		return

	if not event.is_action_pressed(&"pause"):
		return

	# Если открыто модальное окно обучения — не перехватываем Esc под меню паузы
	if not get_tree().get_nodes_in_group(&"modal_overlay").is_empty():
		return

	if is_open:
		AudioManager.play_sfx("ui_click")
		if _settings_panel != null and _settings_panel.visible:
			_settings_panel.close_panel()
		elif _tutorials_panel != null and _tutorials_panel.visible:
			_close_tutorials_subpanel()
		else:
			close()
		get_viewport().set_input_as_handled()
	elif can_open_pause():
		AudioManager.play_sfx("ui_click")
		open()
		get_viewport().set_input_as_handled()

func can_open_pause() -> bool:
	if not allowed:
		return false
	if not get_tree().get_nodes_in_group(&"modal_overlay").is_empty():
		return false
	if current_scene_ref != null and is_instance_valid(current_scene_ref) and current_scene_ref.has_method("can_pause"):
		if not bool(current_scene_ref.call("can_pause")):
			return false
	return true

func toggle() -> void:
	if is_open:
		close()
	else:
		open()

func open() -> bool:
	if not can_open_pause():
		return false
	is_open = true
	visible = true
	_main_panel.visible = true
	_settings_panel.visible = false
	_tutorials_panel.visible = false
	_retry_battle_btn.visible = (mode == &"BATTLE")
	get_tree().paused = true
	AudioManager.set_pause_duck(true)
	if _resume_btn != null:
		_resume_btn.grab_focus()
	return true

func close() -> void:
	is_open = false
	visible = false
	if _settings_panel != null:
		_settings_panel.visible = false
	if _tutorials_panel != null:
		_tutorials_panel.visible = false
	if _main_panel != null:
		_main_panel.visible = true
	AudioManager.set_pause_duck(false)
	if is_inside_tree():
		get_tree().paused = false

func retry_current_battle() -> void:
	AudioManager.play_sfx("ui_click")
	var payload: Dictionary = SaveManager.restore_battle_checkpoint()
	close()
	EventBus.request_scene_change.emit(&"BATTLE", payload)

func return_to_hub() -> void:
	AudioManager.play_sfx("ui_click")
	if mode == &"BATTLE":
		SaveManager.restore_battle_checkpoint()
		SaveManager.save_run()
	close()
	EventBus.request_scene_change.emit(&"HUB", {})

