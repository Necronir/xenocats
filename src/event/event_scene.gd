class_name EventScene
extends Control

## EventScene: Нарративные события и интеграция Dialogic 2 (.dtl таймлайны + портреты эмоций + EventBus)
## (ADR-001 Section 2.7)

var _payload: Dictionary = {}
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()

var _portrait_rect: TextureRect = null
var _speaker_label: Label = null
var _dialogue_text: RichTextLabel = null
var _choices_box: VBoxContainer = null
var _outcome_label: Label = null
var _continue_btn: Button = null

var _lines: Array[Dictionary] = []
var _choices: Array[Dictionary] = []
var _line_cursor: int = 0

const TIMELINE_FILES: Array[String] = [
	"res://data/dialogues/event_scrap_container.dtl",
	"res://data/dialogues/event_pirate_frequency.dtl",
	"res://data/dialogues/event_overloaded_core.dtl"
]

const SPEAKER_NAMES: Dictionary = {
	"felix": "FELIX (Кот-Лидер)",
	"mule": "M.U.L.E. (Тяжёлый Погрузчик)",
	"hound": "H.O.U.N.D. (Патрульный Брузер)",
	"cock": "C.O.C.K. (РЭБ-Связист)",
	"atamansha": "АТАМАНША (ИИ Фабрики)",
	"press": "ТРЁХГОЛОВЫЙ ПРЕСС (Утилизатор Свалки)",
	"satellite": "СПЯЩИЙ СПУТНИК (Автономный Ретранслятор)"
}

func setup_event(payload: Dictionary) -> void:
	_payload = payload

func _ready() -> void:
	_rng.randomize()
	DataCatalog.ensure_loaded()

	# Если глобальный синглтон Dialogic 2 активен в дереве, подписываемся на его signal_event
	var dialogic_node: Node = get_node_or_null("/root/Dialogic")
	if dialogic_node != null and dialogic_node.has_signal("signal_event"):
		dialogic_node.connect("signal_event", _on_dialogic_signal_event)

	EventBus.dialogic_event_triggered.connect(_on_eventbus_dialogic_reward)

	_build_ui()
	var tl_path: String = String(_payload.get("timeline", ""))
	if tl_path == "" or not FileAccess.file_exists(tl_path):
		tl_path = TIMELINE_FILES[_rng.randi_range(0, TIMELINE_FILES.size() - 1)]
	_parse_dtl_timeline(tl_path)
	_render_dialogue_state()

func _build_ui() -> void:
	var bg: TextureRect = TextureRect.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.stretch_mode = TextureRect.STRETCH_SCALE
	bg.modulate = Color(0.45, 0.5, 0.65, 1.0)
	var sec: int = clampi(SaveManager.current_sector, 1, 3)
	var bg_path: String = "res://assets/sprites/backgrounds/bg_sector" + str(sec) + ".png"
	if ResourceLoader.exists(bg_path):
		bg.texture = load(bg_path) as Texture2D
	add_child(bg)

	var st: StyleBoxFlat = StyleBoxFlat.new()
	st.bg_color = Color(0.06, 0.08, 0.14, 0.95)
	st.border_color = Color(0.55, 0.35, 0.9, 1.0)
	st.set_border_width_all(2)
	st.set_corner_radius_all(4)
	st.set_content_margin_all(8)

	var main_panel: PanelContainer = PanelContainer.new()
	main_panel.position = Vector2(24, 18)
	main_panel.size = Vector2(592, 324)
	main_panel.add_theme_stylebox_override("panel", st)
	add_child(main_panel)

	var root_vbox: VBoxContainer = VBoxContainer.new()
	root_vbox.add_theme_constant_override("separation", 8)
	main_panel.add_child(root_vbox)

	var top_title: Label = Label.new()
	top_title.text = String(_payload.get("title", "РАДИОПЕРЕХВАТ / СОБЫТИЕ СЕКТОРА (Dialogic 2 DTL)"))
	top_title.add_theme_font_size_override("font_size", 11)
	top_title.add_theme_color_override("font_color", Color(0.8, 0.6, 1.0))
	root_vbox.add_child(top_title)

	# Портрет говорящего кота + Диалоговое окно
	var speaker_hbox: HBoxContainer = HBoxContainer.new()
	speaker_hbox.add_theme_constant_override("separation", 10)
	root_vbox.add_child(speaker_hbox)

	_portrait_rect = TextureRect.new()
	_portrait_rect.custom_minimum_size = Vector2(72, 72)
	_portrait_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	speaker_hbox.add_child(_portrait_rect)

	var text_vbox: VBoxContainer = VBoxContainer.new()
	text_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	speaker_hbox.add_child(text_vbox)

	_speaker_label = Label.new()
	_speaker_label.add_theme_font_size_override("font_size", 11)
	_speaker_label.add_theme_color_override("font_color", Color(0.4, 0.95, 1.0))
	text_vbox.add_child(_speaker_label)

	_dialogue_text = RichTextLabel.new()
	_dialogue_text.custom_minimum_size = Vector2(460, 88)
	_dialogue_text.bbcode_enabled = true
	_dialogue_text.add_theme_font_size_override("normal_font_size", 10)
	text_vbox.add_child(_dialogue_text)

	# Кнопка пролистывания реплик / Список выборов
	_choices_box = VBoxContainer.new()
	_choices_box.add_theme_constant_override("separation", 5)
	root_vbox.add_child(_choices_box)

	_outcome_label = Label.new()
	_outcome_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_outcome_label.add_theme_font_size_override("font_size", 10)
	_outcome_label.add_theme_color_override("font_color", Color(0.45, 1.0, 0.6))
	root_vbox.add_child(_outcome_label)

	_continue_btn = Button.new()
	_continue_btn.text = String(_payload.get("continue_text", "ВЕРНУТЬСЯ НА КАРТУ ->"))
	_continue_btn.visible = false
	_continue_btn.add_theme_font_size_override("font_size", 10)
	_continue_btn.pressed.connect(_on_continue_pressed)
	root_vbox.add_child(_continue_btn)

func _on_continue_pressed() -> void:
	AudioManager.play_sfx("ui_click")
	var action: String = String(_payload.get("action_on_complete", ""))
	if action == "advance_sector":
		SaveManager.advance_to_next_sector()
	elif action == "finish_run":
		SaveManager.delete_run_save()
	else:
		SaveManager.save_run()

	var next_sc: StringName = _payload.get("next_scene", &"MAP")
	var next_pl: Dictionary = _payload.get("next_payload", {})
	EventBus.request_scene_change.emit(next_sc, next_pl)

func _parse_dtl_timeline(path: String) -> void:
	_lines.clear()
	_choices.clear()
	_line_cursor = 0

	if not FileAccess.file_exists(path):
		_lines.append({"char": "felix", "mood": "normal", "text": "Пойман слабый сигнал с ретранслятора Бремен-4."})
		_choices.append({"label": "Собрать лом (+30 Лома)", "signal": "safe_scrap"})
		return

	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	var raw_lines: PackedStringArray = file.get_as_text().split("\n")
	file.close()

	var current_choice: Dictionary = {}
	for raw: String in raw_lines:
		var line: String = raw.strip_edges()
		if line == "" or line.begins_with("#"):
			continue
		if line.begins_with("- "):
			current_choice = {"label": line.substr(2).strip_edges(), "signal": "safe_scrap"}
			_choices.append(current_choice)
		elif line.begins_with("[signal"):
			var start_q: int = line.find("\"")
			var end_q: int = line.rfind("\"")
			if start_q != -1 and end_q > start_q and not current_choice.is_empty():
				current_choice["signal"] = line.substr(start_q + 1, end_q - start_q - 1)
		elif line.find(":") != -1:
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
			_lines.append({"char": char_id, "mood": mood, "text": body})

func _render_dialogue_state() -> void:
	for child: Node in _choices_box.get_children():
		child.queue_free()

	if _line_cursor < _lines.size():
		var item: Dictionary = _lines[_line_cursor]
		var cid: String = String(item["char"])
		var mood: String = String(item["mood"])
		var p_path: String = "res://assets/sprites/portraits/" + cid + "_" + mood + ".png"
		if ResourceLoader.exists(p_path):
			_portrait_rect.texture = load(p_path) as Texture2D
		elif ResourceLoader.exists("res://assets/sprites/portraits/" + cid + "_normal.png"):
			_portrait_rect.texture = load("res://assets/sprites/portraits/" + cid + "_normal.png") as Texture2D
		elif ResourceLoader.exists("res://assets/sprites/enemies/boss_" + cid + ".png"):
			_portrait_rect.texture = load("res://assets/sprites/enemies/boss_" + cid + ".png") as Texture2D
		elif ResourceLoader.exists("res://assets/sprites/enemies/" + cid + ".png"):
			_portrait_rect.texture = load("res://assets/sprites/enemies/" + cid + ".png") as Texture2D

		_speaker_label.text = String(SPEAKER_NAMES.get(cid, cid.to_upper())) + " [" + mood.to_upper() + "]"
		_dialogue_text.text = String(item["text"])

		if _line_cursor < _lines.size() - 1:
			var next_btn: Button = Button.new()
			next_btn.text = "Далее (" + str(_line_cursor + 1) + "/" + str(_lines.size()) + ") ->"
			next_btn.add_theme_font_size_override("font_size", 10)
			next_btn.pressed.connect(func() -> void:
				AudioManager.play_sfx("ui_click")
				_line_cursor += 1
				_render_dialogue_state()
			)
			_choices_box.add_child(next_btn)
			return

	# Если в диалоге нет развилок (чисто сюжетная кат-сцена / прелюдия / постлюдия)
	if _choices.is_empty():
		_continue_btn.text = String(_payload.get("continue_text", "ПРОДОЛЖИТЬ ->"))
		_continue_btn.visible = true
		return

	# Отображаем варианты выбора из таймлайна Dialogic 2
	for ch: Dictionary in _choices:
		var c_btn: Button = Button.new()
		c_btn.text = "▸ " + String(ch["label"])
		c_btn.add_theme_font_size_override("font_size", 9)
		var sig_arg: String = String(ch["signal"])
		c_btn.pressed.connect(func() -> void:
			AudioManager.play_sfx("ui_click")
			_on_dialogic_signal_event(sig_arg)
		)
		_choices_box.add_child(c_btn)

func _on_dialogic_signal_event(argument: Variant) -> void:
	var code: String = String(argument)
	EventBus.dialogic_event_triggered.emit(code, 1)

func _on_eventbus_dialogic_reward(event_code: String, _amount: int) -> void:
	for child: Node in _choices_box.get_children():
		child.queue_free()

	var summary: String = ""
	match event_code:
		"risky_container":
			var c: CatMechInstance = SaveManager.party[0]
			c.apply_part_damage(PartData.PartSlot.ARMS, 15, true)
			SaveManager.add_run_scrap(35)
			SaveManager.spare_parts_inventory.append("titan_arms")
			AudioManager.play_sfx("part_break")
			summary = "Взрыв конденсатора задел манипуляторы FELIX (-15 HP Рукам), но внутри найден [Рельсотрон «Авангард»] и +35 Лома!"
		"safe_scrap":
			SaveManager.add_run_scrap(30)
			SaveManager.add_sync(20)
			AudioManager.play_sfx("heal")
			summary = "Отряд аккуратно собрал ресурсы вокруг контейнера: +30 Лома и +20% Гармонии!"
		"field_recharge":
			for cat: CatMechInstance in SaveManager.party:
				cat.body_part.repair(25)
				cat.arms_part.repair(25)
				cat.legs_part.repair(25)
			AudioManager.play_sfx("heal")
			summary = "Энергия конденсатора направлена на сервоприводы: +25 HP всем деталям 4 котов!"
		"hack_convoy":
			SaveManager.add_run_scrap(45)
			SaveManager.add_meta_rewards(15, 1)
			AudioManager.play_sfx("qte_perfect")
			summary = "C.O.C.K. успешно взломал пеленг конвоя! Получено +45 Лома и +1 Ядро ИИ!"
		"record_harmony":
			SaveManager.add_sync(50)
			AudioManager.play_sfx("pyramid_siren")
			summary = "Записан боевой ритм на аварийную частоту: +50% к шкале Гармонии «Пирамиды Бремена»!"
		"salvage_relay":
			SaveManager.add_run_scrap(30)
			for cat2: CatMechInstance in SaveManager.party:
				cat2.body_part.repair_full()
			AudioManager.play_sfx("heal")
			summary = "Ретранслятор разобран: +30 Лома, все Корпуса отряда полностью отремонтированы!"
		"plasma_dive":
			var mule: CatMechInstance = SaveManager.party[1 if SaveManager.party.size() > 1 else 0]
			mule.apply_part_damage(PartData.PartSlot.BODY, 12, true)
			SaveManager.add_run_scrap(25)
			SaveManager.spare_parts_inventory.append("titan_legs")
			AudioManager.play_sfx("qte_perfect")
			summary = "M.U.L.E. принял тепловой удар (-12 HP Корпусу) и вытащил из шлюза [Турбо-траки «Бастион»] + 25 Лома!"
		"plasma_charge":
			SaveManager.add_sync(40)
			SaveManager.add_run_scrap(20)
			AudioManager.play_sfx("heal")
			summary = "Аккумуляторы заряжены от плазмы: +40% Гармонии и +20 Лома!"
		_:
			SaveManager.add_run_scrap(40)
			AudioManager.play_sfx("heal")
			summary = "Слита охлаждающая жидкость и редкие сплавы: +40 Лома!"

	_outcome_label.text = "ИТОГ СОБЫТИЯ: " + summary
	_continue_btn.text = String(_payload.get("continue_text", "ВЕРНУТЬСЯ НА КАРТУ ->"))
	_continue_btn.visible = true

