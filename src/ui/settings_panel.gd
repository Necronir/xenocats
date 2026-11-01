class_name SettingsPanel
extends PanelContainer

## SettingsPanel: Переиспользуемая панель настроек звука, экрана и обучения (Issue #12)

signal closed()

var _master_slider: HSlider = null
var _master_val_label: Label = null
var _sfx_slider: HSlider = null
var _sfx_val_label: Label = null
var _music_slider: HSlider = null
var _music_val_label: Label = null
var _fullscreen_check: CheckButton = null
var _tutorials_check: CheckButton = null
var _reset_tutorials_btn: Button = null
var _reset_progress_btn: Button = null
var _reset_progress_armed: bool = false
var _close_btn: Button = null
var _status_hint_label: Label = null

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	custom_minimum_size = Vector2(360, 260)
	size = Vector2(360, 260)
	position = Vector2((640.0 - 360.0) * 0.5, (360.0 - 260.0) * 0.5)

	var st: StyleBoxFlat = StyleBoxFlat.new()
	st.bg_color = Color(0.06, 0.08, 0.14, 0.98)
	st.border_color = Color(0.35, 0.85, 1.0, 1.0)
	st.set_border_width_all(2)
	st.set_corner_radius_all(4)
	st.set_content_margin_all(10)
	add_theme_stylebox_override("panel", st)

	var vbox: VBoxContainer = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	add_child(vbox)

	var title_lbl: Label = Label.new()
	title_lbl.text = "⚙ НАСТРОЙКИ СИСТЕМЫ (БРЕМЕН-4)"
	title_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_lbl.add_theme_font_size_override("font_size", 11)
	title_lbl.add_theme_color_override("font_color", Color(1.0, 0.88, 0.35))
	vbox.add_child(title_lbl)

	# 1. Master Volume
	var master_row: Dictionary = _build_slider_row("Общая громкость:", AudioManager.BUS_MASTER, false)
	_master_slider = master_row["slider"] as HSlider
	_master_val_label = master_row["val_label"] as Label
	vbox.add_child(master_row["container"] as Control)

	# 2. SFX Volume
	var sfx_row: Dictionary = _build_slider_row("Звуки (SFX):", AudioManager.BUS_SFX, true)
	_sfx_slider = sfx_row["slider"] as HSlider
	_sfx_val_label = sfx_row["val_label"] as Label
	vbox.add_child(sfx_row["container"] as Control)

	# 3. Music / Tapes Volume
	var music_row: Dictionary = _build_slider_row("Музыка / Кассеты:", AudioManager.BUS_MUSIC, false)
	_music_slider = music_row["slider"] as HSlider
	_music_val_label = music_row["val_label"] as Label
	vbox.add_child(music_row["container"] as Control)

	# 4. Fullscreen CheckButton
	_fullscreen_check = CheckButton.new()
	_fullscreen_check.text = "Полноэкранный режим (F11)"
	_fullscreen_check.add_theme_font_size_override("font_size", 9)
	_fullscreen_check.toggled.connect(func(pressed: bool) -> void:
		AudioManager.play_sfx("ui_click")
		if SaveManager.settings != null:
			SaveManager.settings.set_fullscreen(pressed)
			SaveManager.settings.save_to_disk(SaveManager.SETTINGS_PATH)
	)
	vbox.add_child(_fullscreen_check)

	# 5. Tutorials CheckButton + Reset Button
	var tut_row: HBoxContainer = HBoxContainer.new()
	tut_row.add_theme_constant_override("separation", 6)
	vbox.add_child(tut_row)

	_tutorials_check = CheckButton.new()
	_tutorials_check.text = "Подсказки обучения"
	_tutorials_check.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_tutorials_check.add_theme_font_size_override("font_size", 9)
	_tutorials_check.toggled.connect(func(pressed: bool) -> void:
		AudioManager.play_sfx("ui_click")
		if SaveManager.settings != null:
			SaveManager.settings.tutorials_enabled = pressed
			SaveManager.settings.save_to_disk(SaveManager.SETTINGS_PATH)
	)
	tut_row.add_child(_tutorials_check)

	_reset_tutorials_btn = Button.new()
	_reset_tutorials_btn.text = "Сбросить подсказки"
	_reset_tutorials_btn.add_theme_font_size_override("font_size", 8)
	_reset_tutorials_btn.pressed.connect(func() -> void:
		AudioManager.play_sfx("ui_click")
		if SaveManager.settings != null:
			SaveManager.settings.reset_tutorials()
			SaveManager.settings.save_to_disk(SaveManager.SETTINGS_PATH)
		refresh_from_settings()
		if _status_hint_label != null:
			_status_hint_label.text = "✓ Все подсказки обучения сброшены!"
	)
	tut_row.add_child(_reset_tutorials_btn)

	_reset_progress_btn = Button.new()
	_reset_progress_btn.text = "⚠ СБРОСИТЬ ВЕСЬ ПРОГРЕСС (NEW GAME)"
	_reset_progress_btn.add_theme_font_size_override("font_size", 9)
	_reset_progress_btn.add_theme_color_override("font_color", Color(1.0, 0.45, 0.45))
	_reset_progress_btn.pressed.connect(func() -> void:
		if not _reset_progress_armed:
			_reset_progress_armed = true
			AudioManager.play_sfx("ui_click")
			_reset_progress_btn.text = "ПОДТВЕРДИТЬ СБРОС (УДАЛИТЬ ВСЕ СЕЙВЫ!)"
			if _status_hint_label != null:
				_status_hint_label.text = "Нажмите повторно для полной очистки сейвов и меты!"
				_status_hint_label.add_theme_color_override("font_color", Color(1.0, 0.35, 0.35))
		else:
			_reset_progress_armed = false
			AudioManager.play_sfx("part_break")
			SaveManager.hard_reset_all_progress()
			if _status_hint_label != null:
				_status_hint_label.text = "✓ Прогресс полностью сброшен! Запущен чистый профиль."
				_status_hint_label.add_theme_color_override("font_color", Color(0.4, 1.0, 0.6))
			close_panel()
			EventBus.request_scene_change.emit(&"HUB", {})
	)
	vbox.add_child(_reset_progress_btn)

	_status_hint_label = Label.new()
	_status_hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status_hint_label.add_theme_font_size_override("font_size", 8)
	_status_hint_label.add_theme_color_override("font_color", Color(0.55, 0.95, 0.65))
	_status_hint_label.text = ""
	vbox.add_child(_status_hint_label)

	# 6. Close Button
	_close_btn = Button.new()
	_close_btn.text = "НАЗАД / СОХРАНИТЬ"
	_close_btn.add_theme_font_size_override("font_size", 10)
	_close_btn.add_theme_color_override("font_color", Color(0.4, 0.95, 1.0))
	_close_btn.pressed.connect(func() -> void:
		AudioManager.play_sfx("ui_click")
		close_panel()
	)
	vbox.add_child(_close_btn)

	refresh_from_settings()

func _build_slider_row(label_text: String, bus_name: StringName, play_preview_on_drag_end: bool) -> Dictionary:
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)

	var lbl: Label = Label.new()
	lbl.text = label_text
	lbl.custom_minimum_size = Vector2(128, 0)
	lbl.add_theme_font_size_override("font_size", 9)
	row.add_child(lbl)

	var slider: HSlider = HSlider.new()
	slider.min_value = 0.0
	slider.max_value = 1.0
	slider.step = 0.05
	slider.value = 1.0
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.custom_minimum_size = Vector2(140, 16)
	row.add_child(slider)

	var val_lbl: Label = Label.new()
	val_lbl.custom_minimum_size = Vector2(40, 0)
	val_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	val_lbl.add_theme_font_size_override("font_size", 9)
	val_lbl.add_theme_color_override("font_color", Color(0.4, 0.95, 1.0))
	val_lbl.text = "100%"
	row.add_child(val_lbl)

	slider.value_changed.connect(func(new_val: float) -> void:
		val_lbl.text = str(int(round(new_val * 100.0))) + "%"
		if SaveManager.settings != null:
			SaveManager.settings.set_bus_linear(bus_name, new_val)
	)
	if play_preview_on_drag_end:
		slider.drag_ended.connect(func(value_changed_flag: bool) -> void:
			if value_changed_flag:
				AudioManager.play_sfx("ui_click")
		)

	return {
		"container": row,
		"slider": slider,
		"val_label": val_lbl
	}

func refresh_from_settings() -> void:
	var s: GameSettings = SaveManager.settings
	if s == null:
		return
	if _master_slider != null:
		_master_slider.set_value_no_signal(s.master_volume)
		_master_val_label.text = str(int(round(s.master_volume * 100.0))) + "%"
	if _sfx_slider != null:
		_sfx_slider.set_value_no_signal(s.sfx_volume)
		_sfx_val_label.text = str(int(round(s.sfx_volume * 100.0))) + "%"
	if _music_slider != null:
		_music_slider.set_value_no_signal(s.music_volume)
		_music_val_label.text = str(int(round(s.music_volume * 100.0))) + "%"
	if _fullscreen_check != null:
		_fullscreen_check.set_pressed_no_signal(s.fullscreen)
	if _tutorials_check != null:
		_tutorials_check.set_pressed_no_signal(s.tutorials_enabled)
	if _status_hint_label != null:
		_status_hint_label.text = ""

func open_panel() -> void:
	_reset_progress_armed = false
	if _reset_progress_btn != null:
		_reset_progress_btn.text = "⚠ СБРОСИТЬ ВЕСЬ ПРОГРЕСС (NEW GAME)"
	refresh_from_settings()
	visible = true
	if _close_btn != null:
		_close_btn.grab_focus()

func close_panel() -> void:
	if SaveManager.settings != null:
		SaveManager.settings.save_to_disk(SaveManager.SETTINGS_PATH)
	visible = false
	closed.emit()

