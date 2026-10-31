class_name TutorialToast
extends PanelContainer

## TutorialToast: Ненавязчивое всплывающее уведомление обучения без остановки боя (Issue #12)

signal dismissed()

var _data: TutorialData = null
var _duration: float = 7.0
var _elapsed: float = 0.0
var _title_label: Label = null
var _body_label: Label = null
var _close_btn: Button = null

func setup(data: TutorialData) -> void:
	_data = data
	if data != null and data.toast_duration > 0.5:
		_duration = data.toast_duration

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_INHERIT
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	position = Vector2(336, 174)
	size = Vector2(296, 54)
	custom_minimum_size = Vector2(296, 54)

	var st: StyleBoxFlat = StyleBoxFlat.new()
	st.bg_color = Color(0.08, 0.11, 0.18, 0.95)
	st.border_color = Color(1.0, 0.88, 0.25, 1.0)
	st.set_border_width_all(2)
	st.set_corner_radius_all(4)
	st.set_content_margin_all(5)
	add_theme_stylebox_override("panel", st)

	var hbox: HBoxContainer = HBoxContainer.new()
	hbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hbox.add_theme_constant_override("separation", 4)
	add_child(hbox)

	var vbox: VBoxContainer = VBoxContainer.new()
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_theme_constant_override("separation", 2)
	hbox.add_child(vbox)

	_title_label = Label.new()
	_title_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_title_label.text = _data.title if _data != null else "ПОДСКАЗКА"
	_title_label.add_theme_font_size_override("font_size", 9)
	_title_label.add_theme_color_override("font_color", Color(1.0, 0.9, 0.3))
	vbox.add_child(_title_label)

	_body_label = Label.new()
	_body_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_body_label.text = _data.body if _data != null else ""
	_body_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_body_label.add_theme_font_size_override("font_size", 8)
	_body_label.add_theme_color_override("font_color", Color(0.88, 0.95, 1.0))
	vbox.add_child(_body_label)

	_close_btn = Button.new()
	_close_btn.text = "×"
	_close_btn.custom_minimum_size = Vector2(20, 20)
	_close_btn.add_theme_font_size_override("font_size", 9)
	_close_btn.pressed.connect(func() -> void:
		AudioManager.play_sfx("ui_click")
		dismiss()
	)
	hbox.add_child(_close_btn)

func _process(delta: float) -> void:
	_elapsed += delta
	if _elapsed >= _duration:
		dismiss()

func dismiss() -> void:
	if not is_inside_tree():
		return
	dismissed.emit()
	queue_free()

static func show_if_needed(host: Node, tutorial_id: StringName) -> TutorialToast:
	if host == null or not host.is_inside_tree():
		return null
	var s: GameSettings = SaveManager.settings
	if s == null or not s.is_tutorial_needed(tutorial_id):
		return null
	var data: TutorialData = DataCatalog.get_tutorial(String(tutorial_id))
	if data == null:
		return null
	var toast: TutorialToast = TutorialToast.new()
	toast.setup(data)
	host.add_child(toast)
	s.mark_tutorial_seen(tutorial_id)
	s.save_to_disk(SaveManager.SETTINGS_PATH)
	return toast

