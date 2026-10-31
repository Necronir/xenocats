class_name DevMenuBar
extends PanelContainer

## DevMenuBar: Верхняя панель разработчика (Fast Track) для мгновенного перехода к битве с боссом уровня (Issue #16)

var _title_label: Label = null
var _current_boss_btn: Button = null
var _boss1_btn: Button = null
var _boss2_btn: Button = null
var _boss3_btn: Button = null

func _ready() -> void:
	position = Vector2(8, 4)
	size = Vector2(624, 24)
	clip_contents = true

	var st: StyleBoxFlat = StyleBoxFlat.new()
	st.bg_color = Color(0.12, 0.07, 0.16, 0.95)
	st.border_color = Color(1.0, 0.55, 0.2, 0.95)
	st.set_border_width_all(1)
	st.set_corner_radius_all(3)
	st.set_content_margin_all(2)
	add_theme_stylebox_override("panel", st)

	var hbox: HBoxContainer = HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 6)
	add_child(hbox)

	_title_label = Label.new()
	_title_label.text = "DEV МЕНЮ:"
	_title_label.add_theme_font_size_override("font_size", 9)
	_title_label.add_theme_color_override("font_color", Color(1.0, 0.72, 0.28))
	hbox.add_child(_title_label)

	var sec: int = clampi(SaveManager.current_sector if SaveManager.has_active_run else 1, 1, 3)
	_current_boss_btn = _make_dev_button(
		"⚔ К БОССУ УРОВНЯ (Сектор " + str(sec) + ")",
		Color(1.0, 0.92, 0.35),
		func() -> void:
			_trigger_boss_jump(-1)
	)
	_current_boss_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(_current_boss_btn)

	_boss1_btn = _make_dev_button(
		"БОСС 1: Пресс",
		Color(0.55, 0.95, 1.0),
		func() -> void:
			_trigger_boss_jump(1)
	)
	hbox.add_child(_boss1_btn)

	_boss2_btn = _make_dev_button(
		"БОСС 2: Атаманша",
		Color(0.55, 0.95, 1.0),
		func() -> void:
			_trigger_boss_jump(2)
	)
	hbox.add_child(_boss2_btn)

	_boss3_btn = _make_dev_button(
		"БОСС 3: Спутник",
		Color(1.0, 0.55, 0.65),
		func() -> void:
			_trigger_boss_jump(3)
	)
	hbox.add_child(_boss3_btn)

func refresh_labels() -> void:
	if _current_boss_btn != null:
		var sec: int = clampi(SaveManager.current_sector if SaveManager.has_active_run else 1, 1, 3)
		_current_boss_btn.text = "⚔ К БОССУ УРОВНЯ (Сектор " + str(sec) + ")"

func _make_dev_button(text_str: String, font_col: Color, on_press: Callable) -> Button:
	var btn: Button = Button.new()
	btn.text = text_str
	btn.add_theme_font_size_override("font_size", 8)
	btn.add_theme_color_override("font_color", font_col)
	btn.pressed.connect(on_press)
	return btn

func _trigger_boss_jump(target_sector: int) -> void:
	AudioManager.play_sfx("ui_click")
	SaveManager.jump_to_boss_battle(target_sector)

