class_name QTEController
extends Control

## QTEController: Тайминг-шкала атаки в стиле Paper Mario (ADR-001 Section 1 & 2.4)

signal qte_completed(multiplier: float, label_text: String, bonus_sync: int)

var _active: bool = false
var _cursor_pos: float = 0.0
var _cursor_dir: float = 1.0
var _speed: float = 1.55
var _elapsed: float = 0.0
var _resolved: bool = false

var _title_label: Label = null
var _hint_label: Label = null
var _bar_area: Control = null
var _strike_btn: Button = null

const PERFECT_MIN: float = 0.72
const PERFECT_MAX: float = 0.84
const GOOD_MIN: float = 0.54
const GOOD_MAX: float = 0.92

func _ready() -> void:
	custom_minimum_size = Vector2(280, 92)
	size = Vector2(280, 92)
	visible = false

	var panel: PanelContainer = PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = Color(0.07, 0.09, 0.14, 0.96)
	style.border_color = Color(0.3, 0.85, 1.0, 1.0)
	style.set_border_width_all(2)
	style.set_corner_radius_all(4)
	panel.add_theme_stylebox_override("panel", style)
	add_child(panel)

	var vbox: VBoxContainer = VBoxContainer.new()
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	panel.add_child(vbox)

	_title_label = Label.new()
	_title_label.text = "ТАЙМИНГ АТАКИ (QTE)"
	_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title_label.add_theme_font_size_override("font_size", 11)
	_title_label.add_theme_color_override("font_color", Color(0.95, 0.9, 0.4))
	vbox.add_child(_title_label)

	_bar_area = Control.new()
	_bar_area.custom_minimum_size = Vector2(240, 24)
	_bar_area.draw.connect(_on_bar_draw)
	vbox.add_child(_bar_area)

	var bottom_row: HBoxContainer = HBoxContainer.new()
	bottom_row.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_child(bottom_row)

	_hint_label = Label.new()
	_hint_label.text = "Нажмите [ПРОБЕЛ] или кнопку в жёлто-бирюзовой зоне!"
	_hint_label.add_theme_font_size_override("font_size", 9)
	bottom_row.add_child(_hint_label)

	_strike_btn = Button.new()
	_strike_btn.text = "УДАР!"
	_strike_btn.add_theme_font_size_override("font_size", 10)
	_strike_btn.pressed.connect(trigger_strike)
	bottom_row.add_child(_strike_btn)

func start_qte(skill_name: String, speed_scale: float = 1.0) -> void:
	_title_label.text = "QTE: " + skill_name
	_cursor_pos = 0.0
	_cursor_dir = 1.0
	_speed = 1.45 * speed_scale
	_elapsed = 0.0
	_resolved = false
	_active = true
	visible = true
	_bar_area.queue_redraw()

func _process(delta: float) -> void:
	if not _active or _resolved:
		return
	_elapsed += delta
	_cursor_pos += _cursor_dir * _speed * delta
	if _cursor_pos >= 1.0:
		_cursor_pos = 1.0
		_cursor_dir = -1.0
	elif _cursor_pos <= 0.0:
		_cursor_pos = 0.0
		_cursor_dir = 1.0
	_bar_area.queue_redraw()

	if _elapsed >= 3.2:
		trigger_strike()

func _input(event: InputEvent) -> void:
	if not _active or _resolved:
		return
	if event is InputEventKey:
		var k: InputEventKey = event as InputEventKey
		if k.pressed and not k.echo and (k.keycode == KEY_SPACE or k.keycode == KEY_ENTER or k.keycode == KEY_Z):
			get_viewport().set_input_as_handled()
			trigger_strike()

func trigger_strike() -> void:
	if not _active or _resolved:
		return
	_resolved = true
	_active = false

	var mult: float = 0.8
	var label_str: String = "СЛАБО (x0.8)"
	var bonus_sync: int = 0

	if _cursor_pos >= PERFECT_MIN and _cursor_pos <= PERFECT_MAX:
		mult = 1.5
		label_str = "КРИТ-СИНХРО! (x1.5)"
		bonus_sync = 12
		AudioManager.play_sfx("qte_perfect")
	elif _cursor_pos >= GOOD_MIN and _cursor_pos <= GOOD_MAX:
		mult = 1.15
		label_str = "ТОЧНО! (x1.15)"
		bonus_sync = 5
		AudioManager.play_sfx("qte_good")
	else:
		AudioManager.play_sfx("qte_miss")

	_title_label.text = label_str
	_bar_area.queue_redraw()

	await get_tree().create_timer(0.32).timeout
	visible = false
	qte_completed.emit(mult, label_str, bonus_sync)

func _on_bar_draw() -> void:
	var w: float = _bar_area.size.x
	var h: float = _bar_area.size.y
	if w <= 10.0:
		w = 240.0
		h = 24.0
	# Фон полосы
	_bar_area.draw_rect(Rect2(8, 4, w - 16, h - 8), Color(0.16, 0.18, 0.24, 1.0), true)
	var track_w: float = w - 16.0
	# Зона GOOD
	_bar_area.draw_rect(
		Rect2(8.0 + track_w * GOOD_MIN, 4, track_w * (GOOD_MAX - GOOD_MIN), h - 8),
		Color(0.85, 0.65, 0.15, 0.85),
		true
	)
	# Зона PERFECT (Крит)
	_bar_area.draw_rect(
		Rect2(8.0 + track_w * PERFECT_MIN, 4, track_w * (PERFECT_MAX - PERFECT_MIN), h - 8),
		Color(0.2, 0.95, 0.95, 1.0),
		true
	)
	# Рамка
	_bar_area.draw_rect(Rect2(8, 4, track_w, h - 8), Color(0.75, 0.8, 0.9, 1.0), false, 1.0)
	# Бегунок
	var cx: float = 8.0 + track_w * _cursor_pos
	_bar_area.draw_rect(Rect2(cx - 2.0, 1.0, 4.0, h - 2.0), Color(1.0, 1.0, 1.0, 1.0), true)

