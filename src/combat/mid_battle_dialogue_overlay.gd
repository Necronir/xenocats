class_name MidBattleDialogueOverlay
extends CanvasLayer

## MidBattleDialogueOverlay: Модальное окно внутрибоевого диалога Dialogic 2 (ADR-002, Issue #32)
## Бесшовно ставит бой на паузу, отображает ветвящийся диалог с выбором и возобновляет бой после завершения.

signal dialogue_started(timeline_path: String)
signal choice_selected(choice_index: int, choice_label: String, is_boomer: bool)
signal dialogue_completed(timeline_path: String)

var timeline_path: String = ""
var _lines: Array[Dictionary] = []
var _choices: Array[Dictionary] = []
var _line_cursor: int = 0
var _previous_paused: bool = false
var _closing: bool = false

var _panel: PanelContainer = null
var _header_label: Label = null
var _portrait_rect: TextureRect = null
var _speaker_label: Label = null
var _dialogue_text: RichTextLabel = null
var _choices_box: VBoxContainer = null
var _continue_btn: Button = null

const SPEAKER_NAMES: Dictionary = {
	"felix": "FELIX (Бродячий Кот-Музыкант)",
	"hound": "H.O.U.N.D. (Загнанный Пёс-Барабанщик)",
	"mule": "M.U.L.E. (Мельничный Осёл-Басист)",
	"cock": "C.O.C.K. (Голосистый Петух-Солист)"
}

func _ready() -> void:
	layer = 58
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_to_group(&"modal_overlay")

	_build_ui()
	if timeline_path != "":
		_parse_dtl_timeline(timeline_path)
		_render_dialogue_state()

func setup_timeline(path: String) -> void:
	timeline_path = path
	_previous_paused = get_tree().paused
	get_tree().paused = true
	dialogue_started.emit(timeline_path)

	if is_inside_tree():
		_parse_dtl_timeline(timeline_path)
		_render_dialogue_state()

func _build_ui() -> void:
	# Полупрозрачный задник для фокусировки на диалоге
	var backdrop: ColorRect = ColorRect.new()
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	backdrop.color = Color(0.02, 0.03, 0.06, 0.75)
	add_child(backdrop)

	var panel_st: StyleBoxFlat = StyleBoxFlat.new()
	panel_st.bg_color = Color(0.07, 0.09, 0.16, 0.98)
	panel_st.border_color = Color(0.95, 0.82, 0.35, 1.0) # Золотисто-неоновая рамка слияния
	panel_st.set_border_width_all(2)
	panel_st.set_corner_radius_all(6)
	panel_st.set_content_margin_all(8)

	_panel = PanelContainer.new()
	_panel.position = Vector2(30, 165)
	_panel.size = Vector2(580, 185)
	_panel.add_theme_stylebox_override("panel", panel_st)
	add_child(_panel)

	var root_vbox: VBoxContainer = VBoxContainer.new()
	root_vbox.add_theme_constant_override("separation", 6)
	_panel.add_child(root_vbox)

	_header_label = Label.new()
	_header_label.text = "⚡ БОЕВОЕ СЛИЯНИЕ // ДИАЛОГ В РАЗГАРЕ БИТВЫ"
	_header_label.add_theme_font_size_override("font_size", 9)
	_header_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.4))
	root_vbox.add_child(_header_label)

	var content_hbox: HBoxContainer = HBoxContainer.new()
	content_hbox.add_theme_constant_override("separation", 10)
	root_vbox.add_child(content_hbox)

	# Портрет персонажа с эмоцией
	_portrait_rect = TextureRect.new()
	_portrait_rect.custom_minimum_size = Vector2(56, 56)
	_portrait_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_portrait_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_portrait_rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	content_hbox.add_child(_portrait_rect)

	var text_vbox: VBoxContainer = VBoxContainer.new()
	text_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content_hbox.add_child(text_vbox)

	_speaker_label = Label.new()
	_speaker_label.add_theme_font_size_override("font_size", 10)
	_speaker_label.add_theme_color_override("font_color", Color(0.4, 0.95, 1.0))
	text_vbox.add_child(_speaker_label)

	_dialogue_text = RichTextLabel.new()
	_dialogue_text.custom_minimum_size = Vector2(480, 52)
	_dialogue_text.bbcode_enabled = true
	_dialogue_text.add_theme_font_size_override("normal_font_size", 9)
	text_vbox.add_child(_dialogue_text)

	_choices_box = VBoxContainer.new()
	_choices_box.add_theme_constant_override("separation", 4)
	root_vbox.add_child(_choices_box)

	_continue_btn = Button.new()
	_continue_btn.text = "ПРОДОЛЖИТЬ БОЙ ->"
	_continue_btn.visible = false
	_continue_btn.add_theme_font_size_override("font_size", 9)
	_continue_btn.pressed.connect(_on_continue_pressed)
	root_vbox.add_child(_continue_btn)

func _unhandled_input(event: InputEvent) -> void:
	if _closing:
		return
	if (
		event.is_action_pressed("ui_accept")
		or (event is InputEventKey and event.pressed and not event.echo and (event.keycode == KEY_SPACE or event.keycode == KEY_ENTER or event.keycode == KEY_KP_ENTER))
		or (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT)
	):
		if advance():
			get_viewport().set_input_as_handled()

func advance() -> bool:
	if _continue_btn != null and _continue_btn.visible:
		_on_continue_pressed()
		return true
	elif _choices_box != null and _choices_box.get_child_count() == 1:
		var btn: Button = _choices_box.get_child(0) as Button
		if btn != null and btn.visible:
			btn.emit_signal("pressed")
			return true
	return false

func _parse_dtl_timeline(path: String) -> void:
	_lines.clear()
	_choices.clear()
	_line_cursor = 0

	var full_path: String = path
	if not FileAccess.file_exists(full_path):
		if not full_path.begins_with("res://"):
			full_path = "res://data/dialogues/" + full_path
		if not full_path.ends_with(".dtl"):
			full_path += ".dtl"

	if not FileAccess.file_exists(full_path):
		_lines.append({
			"char": "hound",
			"mood": "battle",
			"text": "Стыковка завершена! Робокотопёс готов к бою!",
			"sfx": "pyramid_siren"
		})
		return

	var file: FileAccess = FileAccess.open(full_path, FileAccess.READ)
	var raw_lines: PackedStringArray = file.get_as_text().split("\n")
	file.close()

	var current_choice: Dictionary = {}
	var current_sfx: String = ""

	for raw: String in raw_lines:
		var line: String = raw.strip_edges()
		if line == "" or line.begins_with("#"):
			continue

		if line.begins_with("[image"):
			continue
		elif line.begins_with("[sound") or line.begins_with("[audio") or line.begins_with("[sfx"):
			var q1: int = line.find("\"")
			var q2: int = line.rfind("\"")
			if q1 != -1 and q2 > q1:
				current_sfx = line.substr(q1 + 1, q2 - q1 - 1)
		elif line.begins_with("- "):
			var choice_dict: Dictionary = {
				"label": line.substr(2).strip_edges(),
				"signal": "",
				"branch_lines": []
			}
			_choices.append(choice_dict)
			current_choice = choice_dict
		elif line.begins_with("[signal"):
			var sq1: int = line.find("\"")
			var sq2: int = line.rfind("\"")
			if sq1 != -1 and sq2 > sq1 and not current_choice.is_empty():
				current_choice["signal"] = line.substr(sq1 + 1, sq2 - sq1 - 1)
		elif not line.begins_with("[") and line.find(":") != -1:
			var colon_idx: int = line.find(":")
			var head: String = line.substr(0, colon_idx).strip_edges()
			var body: String = line.substr(colon_idx + 1).strip_edges()
			var char_id: String = "felix"
			var mood: String = "normal"
			var p_open: int = head.find("(")
			var p_close: int = head.find(")")
			if p_open != -1 and p_close > p_open:
				char_id = head.substr(0, p_open).strip_edges().to_lower()
				mood = head.substr(p_open + 1, p_close - p_open - 1).strip_edges().to_lower()
			else:
				char_id = head.to_lower()

			var parsed_line: Dictionary = {
				"char": char_id,
				"mood": mood,
				"text": body,
				"sfx": current_sfx
			}
			current_sfx = ""

			# Если строка реплики находится под выбором (с отступом табуляции или пробелов)
			if not _choices.is_empty() and (raw.begins_with("\t") or raw.begins_with("  ")):
				var bl: Array = current_choice.get("branch_lines", []) as Array
				bl.append(parsed_line)
				current_choice["branch_lines"] = bl
			else:
				_lines.append(parsed_line)

func _render_dialogue_state() -> void:
	for child: Node in _choices_box.get_children():
		child.queue_free()

	if _line_cursor < _lines.size():
		var item: Dictionary = _lines[_line_cursor]
		var cid: String = String(item["char"])
		var mood: String = String(item["mood"])
		var sfx: String = String(item.get("sfx", ""))

		if sfx != "":
			AudioManager.play_sfx(sfx)

		var p_path: String = "res://assets/sprites/portraits/" + cid + "_" + mood + ".png"
		if ResourceLoader.exists(p_path):
			_portrait_rect.texture = load(p_path) as Texture2D
		elif ResourceLoader.exists("res://assets/sprites/portraits/" + cid + "_normal.png"):
			_portrait_rect.texture = load("res://assets/sprites/portraits/" + cid + "_normal.png") as Texture2D

		_speaker_label.text = String(SPEAKER_NAMES.get(cid, cid.to_upper())) + " [" + mood.to_upper() + "]"
		_dialogue_text.text = String(item["text"])

		# Если есть следующие реплики в текущем блоке
		if _line_cursor < _lines.size() - 1:
			var next_btn: Button = Button.new()
			next_btn.text = "Далее (" + str(_line_cursor + 1) + "/" + str(_lines.size()) + ") ->"
			next_btn.add_theme_font_size_override("font_size", 9)
			next_btn.pressed.connect(func() -> void:
				AudioManager.play_sfx("ui_click")
				_line_cursor += 1
				_render_dialogue_state()
			)
			_choices_box.add_child(next_btn)
			return

	# Реплики текущего списка прочитаны: если есть развилки, отображаем кнопки выбора
	if not _choices.is_empty():
		for idx: int in range(_choices.size()):
			var ch: Dictionary = _choices[idx]
			var btn: Button = Button.new()
			btn.name = "ChoiceButton_" + str(idx)
			btn.text = "▸ " + String(ch["label"])
			btn.add_theme_font_size_override("font_size", 9)
			var choice_idx: int = idx
			btn.pressed.connect(func() -> void:
				select_choice(choice_idx)
			)
			_choices_box.add_child(btn)
		return

	# Нет развилок либо ветка уже пройдена — кнопка продолжения боя
	_continue_btn.visible = true

func select_choice(index: int) -> void:
	if index < 0 or index >= _choices.size():
		return
	var ch: Dictionary = _choices[index]
	var label: String = String(ch.get("label", ""))
	var sig_arg: String = String(ch.get("signal", ""))

	var is_boomer: bool = (sig_arg == "boomer_true" or label.find("Yes") != -1 or label.find("Да") != -1)
	SaveManager.set_player_is_boomer(is_boomer)

	if sig_arg != "":
		EventBus.dialogic_event_triggered.emit(sig_arg, 1)

	choice_selected.emit(index, label, is_boomer)
	AudioManager.play_sfx("ui_click")

	# Переходим к ветке диалога выбранного варианта
	var branch_lines: Array = ch.get("branch_lines", []) as Array
	if not branch_lines.is_empty():
		_lines.clear()
		for b: Variant in branch_lines:
			_lines.append(b as Dictionary)
		_line_cursor = 0
		_choices.clear()
		_render_dialogue_state()
	else:
		_choices.clear()
		close_dialogue()

func _on_continue_pressed() -> void:
	AudioManager.play_sfx("ui_click")
	close_dialogue()

func close_dialogue() -> void:
	if _closing:
		return
	_closing = true
	get_tree().paused = _previous_paused
	dialogue_completed.emit(timeline_path)
	queue_free()

# --- Вспомогательные методы для автотестов ---

func is_showing_choices() -> bool:
	return not _choices.is_empty() and (_line_cursor >= _lines.size() - 1 or _lines.is_empty())

func get_choices() -> Array[Dictionary]:
	return _choices.duplicate()

func get_current_line() -> Dictionary:
	if _line_cursor < _lines.size():
		return _lines[_line_cursor]
	return {}

func get_current_speaker() -> String:
	var l: Dictionary = get_current_line()
	return String(l.get("char", ""))

func get_current_mood() -> String:
	var l: Dictionary = get_current_line()
	return String(l.get("mood", ""))
