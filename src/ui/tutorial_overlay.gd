class_name TutorialOverlay
extends CanvasLayer

## TutorialOverlay: Модальное окно контекстного обучения с авто-паузой и опцией отключения (Issue #12)

signal closed()

var _data: TutorialData = null
var _is_reference_mode: bool = false
var _previous_paused: bool = false
var _closing: bool = false

var _title_label: Label = null
var _body_label: Label = null
var _ok_btn: Button = null
var _disable_btn: Button = null

func setup(data: TutorialData, reference_mode: bool = false) -> void:
	_data = data
	_is_reference_mode = reference_mode

func _ready() -> void:
	layer = 60
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_to_group(&"modal_overlay")

	_previous_paused = get_tree().paused
	get_tree().paused = true

	var backdrop: ColorRect = ColorRect.new()
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	backdrop.color = Color(0.0, 0.0, 0.0, 0.72)
	add_child(backdrop)

	var panel: PanelContainer = PanelContainer.new()
	panel.position = Vector2(120, 62)
	panel.size = Vector2(400, 236)
	var st: StyleBoxFlat = StyleBoxFlat.new()
	st.bg_color = Color(0.06, 0.09, 0.15, 0.98)
	st.border_color = Color(0.35, 0.92, 1.0, 1.0)
	st.set_border_width_all(2)
	st.set_corner_radius_all(4)
	st.set_content_margin_all(12)
	panel.add_theme_stylebox_override("panel", st)
	add_child(panel)

	var vbox: VBoxContainer = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	panel.add_child(vbox)

	var badge_lbl: Label = Label.new()
	badge_lbl.text = "📖 ТАКТИЧЕСКАЯ ПАМЯТКА БРЕМЕН-4"
	badge_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	badge_lbl.add_theme_font_size_override("font_size", 8)
	badge_lbl.add_theme_color_override("font_color", Color(0.4, 0.95, 1.0))
	vbox.add_child(badge_lbl)

	_title_label = Label.new()
	_title_label.text = _data.title if _data != null else "ОБУЧЕНИЕ"
	_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_title_label.add_theme_font_size_override("font_size", 11)
	_title_label.add_theme_color_override("font_color", Color(1.0, 0.88, 0.35))
	vbox.add_child(_title_label)

	_body_label = Label.new()
	_body_label.text = _data.body if _data != null else ""
	_body_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_body_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_body_label.add_theme_font_size_override("font_size", 9)
	_body_label.add_theme_color_override("font_color", Color(0.92, 0.95, 1.0))
	vbox.add_child(_body_label)

	var btn_row: HBoxContainer = HBoxContainer.new()
	btn_row.alignment = BoxContainer.ALIGNMENT_CENTER
	btn_row.add_theme_constant_override("separation", 8)
	vbox.add_child(btn_row)

	_ok_btn = Button.new()
	_ok_btn.text = "ПОНЯТНО"
	_ok_btn.custom_minimum_size = Vector2(140, 28)
	_ok_btn.add_theme_font_size_override("font_size", 10)
	_ok_btn.add_theme_color_override("font_color", Color(0.4, 1.0, 0.6))
	_ok_btn.pressed.connect(confirm_and_close)
	btn_row.add_child(_ok_btn)

	_disable_btn = Button.new()
	_disable_btn.text = "Пропустить / Отключить обучение"
	_disable_btn.custom_minimum_size = Vector2(190, 28)
	_disable_btn.add_theme_font_size_override("font_size", 8)
	_disable_btn.add_theme_color_override("font_color", Color(1.0, 0.65, 0.55))
	_disable_btn.visible = not _is_reference_mode
	_disable_btn.pressed.connect(disable_tutorials_and_close)
	btn_row.add_child(_disable_btn)

	_ok_btn.grab_focus()

func confirm_and_close() -> void:
	if _closing:
		return
	AudioManager.play_sfx("ui_click")
	_finish_close()

func disable_tutorials_and_close() -> void:
	if _closing:
		return
	AudioManager.play_sfx("ui_click")
	if SaveManager.settings != null:
		SaveManager.settings.tutorials_enabled = false
		SaveManager.settings.save_to_disk(SaveManager.SETTINGS_PATH)
	_finish_close()

func _finish_close() -> void:
	if _closing:
		return
	_closing = true
	if is_in_group(&"modal_overlay"):
		remove_from_group(&"modal_overlay")
	if is_inside_tree():
		get_tree().paused = _previous_paused
	closed.emit()
	queue_free()

static func show_if_needed(host: Node, tutorial_id: StringName) -> void:
	if host == null or not host.is_inside_tree():
		return
	var s: GameSettings = SaveManager.settings
	if s == null or not s.is_tutorial_needed(tutorial_id):
		return
	var data: TutorialData = DataCatalog.get_tutorial(String(tutorial_id))
	if data == null:
		return
	var overlay: TutorialOverlay = TutorialOverlay.new()
	overlay.setup(data, false)
	host.add_child(overlay)
	await overlay.closed
	s.mark_tutorial_seen(tutorial_id)
	s.save_to_disk(SaveManager.SETTINGS_PATH)

static func show_reference(host: Node, tutorial_id: StringName) -> TutorialOverlay:
	if host == null or not host.is_inside_tree():
		return null
	var data: TutorialData = DataCatalog.get_tutorial(String(tutorial_id))
	if data == null:
		return null
	var overlay: TutorialOverlay = TutorialOverlay.new()
	overlay.setup(data, true)
	host.add_child(overlay)
	return overlay

