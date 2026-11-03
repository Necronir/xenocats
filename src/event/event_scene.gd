class_name EventScene
extends Control

## EventScene: Нарративные события и интеграция Dialogic 2 (.dtl таймлайны + портреты эмоций + EventBus)
## (ADR-001 Section 2.7)

var _payload: Dictionary = {}
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()

var _dev_menu_bar: DevMenuBar = null
var _illustration_panel: PanelContainer = null
var _illustration_rect: TextureRect = null
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
	"res://data/dialogues/event_overloaded_core.dtl",
	"res://data/dialogues/event_pirate_frequency.dtl"
]

const SPEAKER_NAMES: Dictionary = {
	"felix": "FELIX (Бродячий Кот-Музыкант)",
	"hound": "H.O.U.N.D. (Загнанный Пёс-Барабанщик)",
	"mule": "M.U.L.E. (Мельничный Осёл-Басист)",
	"cock": "C.O.C.K. (Голосистый Петух-Солист)",
	"press": "ХОЗЯИН МЕЛЬНИЦЫ (Трёхголовый Пресс)",
	"atamansha": "ХОЗЯЙКА ПРИТОНА (Атаманша)",
	"satellite": "НАДЗИРАТЕЛЬ ИЗБЫ (Спящий Спутник)",
	"outlaw": "ГЛАВАРЬ РАЗБОЙНИКОВ (Мародёр из Избы)",
	"trubadur": "КИБЕР-ТРУБАДУР (Владыка Башни «Бремен-4»)"
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
	if tl_path != "" and not FileAccess.file_exists(tl_path):
		var candidate_name: String = tl_path if tl_path.ends_with(".dtl") else (tl_path + ".dtl")
		if not candidate_name.begins_with("res://"):
			candidate_name = "res://data/dialogues/" + candidate_name
		if FileAccess.file_exists(candidate_name):
			tl_path = candidate_name
	if tl_path == "" or not FileAccess.file_exists(tl_path):
		var sec_idx: int = clampi(SaveManager.current_sector - 1, 0, TIMELINE_FILES.size() - 1)
		tl_path = TIMELINE_FILES[sec_idx]
	_parse_dtl_timeline(tl_path)
	_render_dialogue_state()

func _build_ui() -> void:
	var bg: TextureRect = TextureRect.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.stretch_mode = TextureRect.STRETCH_SCALE
	bg.modulate = Color(0.45, 0.5, 0.65, 1.0)
	var sec: int = clampi(SaveManager.current_sector, 1, 4)
	var bg_path: String = "res://assets/sprites/backgrounds/bg_sector" + str(sec) + ".png"
	if ResourceLoader.exists(bg_path):
		bg.texture = load(bg_path) as Texture2D
	add_child(bg)

	# Верхнее меню разработчика (Fast Track к боссу уровня, Issue #16)
	_dev_menu_bar = DevMenuBar.new()
	add_child(_dev_menu_bar)

	var st: StyleBoxFlat = StyleBoxFlat.new()
	st.bg_color = Color(0.06, 0.08, 0.14, 0.95)
	st.border_color = Color(0.55, 0.35, 0.9, 1.0)
	st.set_border_width_all(2)
	st.set_corner_radius_all(4)
	st.set_content_margin_all(6)

	var main_panel: PanelContainer = PanelContainer.new()
	main_panel.position = Vector2(20, 24)
	main_panel.size = Vector2(600, 328)
	main_panel.add_theme_stylebox_override("panel", st)
	add_child(main_panel)

	var root_vbox: VBoxContainer = VBoxContainer.new()
	root_vbox.add_theme_constant_override("separation", 4)
	main_panel.add_child(root_vbox)

	var top_title: Label = Label.new()
	top_title.text = String(_payload.get("title", "СЮЖЕТНАЯ СЦЕНА // БРЕМЕНСКИЕ МУЗЫКАНТЫ"))
	top_title.add_theme_font_size_override("font_size", 10)
	top_title.add_theme_color_override("font_color", Color(0.95, 0.82, 0.35))
	root_vbox.add_child(top_title)

	# Сюжетная иллюстрация («история в картинках»)
	_illustration_panel = PanelContainer.new()
	_illustration_panel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var pic_st: StyleBoxFlat = StyleBoxFlat.new()
	pic_st.bg_color = Color(0.03, 0.04, 0.08, 0.98)
	pic_st.border_color = Color(0.35, 0.85, 1.0, 0.9)
	pic_st.set_border_width_all(1)
	pic_st.set_content_margin_all(2)
	_illustration_panel.add_theme_stylebox_override("panel", pic_st)
	root_vbox.add_child(_illustration_panel)

	_illustration_rect = TextureRect.new()
	_illustration_rect.custom_minimum_size = Vector2(256, 144)
	_illustration_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_illustration_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_illustration_rect.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	_illustration_panel.add_child(_illustration_rect)

	# Портрет говорящего персонажа + Диалоговое окно
	var speaker_hbox: HBoxContainer = HBoxContainer.new()
	speaker_hbox.add_theme_constant_override("separation", 10)
	root_vbox.add_child(speaker_hbox)

	_portrait_rect = TextureRect.new()
	_portrait_rect.custom_minimum_size = Vector2(60, 60)
	_portrait_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_portrait_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_portrait_rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	speaker_hbox.add_child(_portrait_rect)

	var text_vbox: VBoxContainer = VBoxContainer.new()
	text_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	speaker_hbox.add_child(text_vbox)

	_speaker_label = Label.new()
	_speaker_label.add_theme_font_size_override("font_size", 10)
	_speaker_label.add_theme_color_override("font_color", Color(0.4, 0.95, 1.0))
	text_vbox.add_child(_speaker_label)

	_dialogue_text = RichTextLabel.new()
	_dialogue_text.custom_minimum_size = Vector2(480, 54)
	_dialogue_text.bbcode_enabled = true
	_dialogue_text.add_theme_font_size_override("normal_font_size", 9)
	text_vbox.add_child(_dialogue_text)

	# Кнопка пролистывания реплик / Список выборов
	_choices_box = VBoxContainer.new()
	_choices_box.add_theme_constant_override("separation", 3)
	root_vbox.add_child(_choices_box)

	_outcome_label = Label.new()
	_outcome_label.visible = false
	_outcome_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_outcome_label.add_theme_font_size_override("font_size", 9)
	_outcome_label.add_theme_color_override("font_color", Color(0.45, 1.0, 0.6))
	root_vbox.add_child(_outcome_label)

	_continue_btn = Button.new()
	_continue_btn.text = String(_payload.get("continue_text", "ВЕРНУТЬСЯ НА КАРТУ ->"))
	_continue_btn.visible = false
	_continue_btn.add_theme_font_size_override("font_size", 10)
	_continue_btn.pressed.connect(_on_continue_pressed)
	root_vbox.add_child(_continue_btn)

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_accept") or (event is InputEventKey and event.pressed and not event.echo and (event.keycode == KEY_SPACE or event.keycode == KEY_ENTER or event.keycode == KEY_KP_ENTER)):
		if _advance_dialogue_or_continue():
			get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if _advance_dialogue_or_continue():
			get_viewport().set_input_as_handled()

func _advance_dialogue_or_continue() -> bool:
	if _continue_btn != null and _continue_btn.visible:
		_on_continue_pressed()
		return true
	elif _choices_box != null and _choices_box.get_child_count() == 1:
		var btn: Button = _choices_box.get_child(0) as Button
		if btn != null and btn.visible:
			btn.emit_signal("pressed")
			return true
	return false

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

func _update_illustration(tex: Texture2D) -> void:
	if tex == null:
		_illustration_panel.visible = false
		return

	_illustration_rect.texture = tex
	_illustration_panel.visible = true

	var tw: float = float(tex.get_width())
	var th: float = float(tex.get_height())
	var aspect: float = tw / maxf(th, 1.0)

	var max_w: float = 280.0
	var max_h: float = 144.0

	var target_w: float = max_w
	var target_h: float = round(target_w / aspect)
	if target_h > max_h:
		target_h = max_h
		target_w = round(target_h * aspect)

	_illustration_rect.custom_minimum_size = Vector2(target_w, target_h)

func _parse_dtl_timeline(path: String) -> void:
	_lines.clear()
	_choices.clear()
	_line_cursor = 0

	var full_path: String = path
	if not FileAccess.file_exists(full_path):
		var cand: String = full_path
		if not cand.begins_with("res://"):
			cand = "res://data/dialogues/" + cand
		if not cand.ends_with(".dtl"):
			cand += ".dtl"
		if FileAccess.file_exists(cand):
			full_path = cand

	if not FileAccess.file_exists(full_path):
		_lines.append({
			"char": "felix",
			"mood": "normal",
			"text": "Пойман слабый сигнал с ретранслятора Бремен-4.",
			"image": "res://assets/sprites/story/story_cat_alone_road.png",
			"sfx": ""
		})
		_choices.append({"label": "Собрать лом (+30 Лома)", "signal": "safe_scrap", "branch_lines": []})
		return

	var file: FileAccess = FileAccess.open(full_path, FileAccess.READ)
	var raw_lines: PackedStringArray = file.get_as_text().split("\n")
	file.close()

	var current_choice: Dictionary = {}
	var current_image: String = String(_payload.get("image_path", _payload.get("image", _payload.get("photo_path", ""))))
	var current_sfx: String = ""
	for raw: String in raw_lines:
		var line: String = raw.strip_edges()
		if line == "" or line.begins_with("#"):
			continue
		if line.begins_with("[image"):
			var img_q1: int = line.find("\"")
			var img_q2: int = line.rfind("\"")
			if img_q1 != -1 and img_q2 > img_q1:
				current_image = line.substr(img_q1 + 1, img_q2 - img_q1 - 1)
		elif line.begins_with("[sound") or line.begins_with("[audio") or line.begins_with("[sfx"):
			var sfx_q1: int = line.find("\"")
			var sfx_q2: int = line.rfind("\"")
			if sfx_q1 != -1 and sfx_q2 > sfx_q1:
				current_sfx = line.substr(sfx_q1 + 1, sfx_q2 - sfx_q1 - 1)
		elif line.begins_with("- "):
			var def_sig: String = "safe_scrap"
			var lbl: String = line.substr(2).strip_edges()
			if lbl.find("Yes") != -1 or lbl.find("Да") != -1:
				def_sig = "boomer_true"
			elif lbl.find("No") != -1 or lbl.find("Нет") != -1:
				def_sig = "boomer_false"
			current_choice = {"label": lbl, "signal": def_sig, "branch_lines": []}
			_choices.append(current_choice)
		elif line.begins_with("[signal"):
			var start_q: int = line.find("\"")
			var end_q: int = line.rfind("\"")
			if start_q != -1 and end_q > start_q and not current_choice.is_empty():
				current_choice["signal"] = line.substr(start_q + 1, end_q - start_q - 1)
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
			var parsed_item: Dictionary = {"char": char_id, "mood": mood, "text": body, "image": current_image, "sfx": current_sfx}
			current_sfx = ""
			if not _choices.is_empty() and (raw.begins_with("\t") or raw.begins_with("  ")):
				var bl: Array = current_choice.get("branch_lines", []) as Array
				bl.append(parsed_item)
				current_choice["branch_lines"] = bl
			else:
				_lines.append(parsed_item)

func _render_dialogue_state() -> void:
	for child: Node in _choices_box.get_children():
		child.queue_free()

	if _line_cursor < _lines.size():
		var item: Dictionary = _lines[_line_cursor]
		var cid: String = String(item["char"])
		var mood: String = String(item["mood"])
		var img_path: String = String(item.get("image", ""))
		if img_path != "":
			var tex: Texture2D = null
			if ResourceLoader.exists(img_path):
				tex = load(img_path) as Texture2D
			if tex == null:
				var gpath: String = ProjectSettings.globalize_path(img_path)
				if FileAccess.file_exists(gpath) or FileAccess.file_exists(img_path):
					var img: Image = Image.load_from_file(gpath if FileAccess.file_exists(gpath) else img_path)
					if img != null and not img.is_empty():
						img.generate_mipmaps()
						tex = ImageTexture.create_from_image(img)
			if tex != null:
				_update_illustration(tex)
			else:
				_illustration_panel.visible = (_illustration_rect.texture != null)
		else:
			_illustration_panel.visible = (_illustration_rect.texture != null)

		var p_path: String = "res://assets/sprites/portraits/" + cid + "_" + mood + ".png"
		if ResourceLoader.exists(p_path):
			_portrait_rect.texture = load(p_path) as Texture2D
		elif ResourceLoader.exists("res://assets/sprites/portraits/" + cid + "_normal.png"):
			_portrait_rect.texture = load("res://assets/sprites/portraits/" + cid + "_normal.png") as Texture2D
		elif ResourceLoader.exists("res://assets/sprites/enemies/boss_" + cid + ".png"):
			_portrait_rect.texture = load("res://assets/sprites/enemies/boss_" + cid + ".png") as Texture2D
		elif ResourceLoader.exists("res://assets/sprites/enemies/" + cid + ".png"):
			_portrait_rect.texture = load("res://assets/sprites/enemies/" + cid + ".png") as Texture2D

		var line_sfx: String = String(item.get("sfx", ""))
		if line_sfx != "":
			AudioManager.play_sfx(line_sfx)

		_speaker_label.text = String(SPEAKER_NAMES.get(cid, cid.to_upper())) + " [" + mood.to_upper() + "]"
		_dialogue_text.text = String(item["text"])

		# Прогрессивная сюжетная мелодия, темы боссов и финальный концерт с Резонатором (Issue #9)
		if (
			img_path.ends_with("story_cat_exile.png")
			or img_path.ends_with("story_cat_alone_road.png")
			or img_path.ends_with("1-cat-start.jpg")
		):
			AudioManager.play_story_stage(1)
		elif img_path.ends_with("story_meet_hound.png") or img_path.ends_with("2-cat-and-hound-together.jpg"):
			AudioManager.play_story_stage(2)
		elif img_path.ends_with("story_mill_mule_captive.png") or img_path.ends_with("3-press-boss-appirance.jpg"):
			AudioManager.play_boss_theme(1)
		elif (
			img_path.ends_with("story_mule_joins.png")
			or img_path.ends_with("4a-press-boss-win.jpg")
			or img_path.find("rescue_mule") != -1
		):
			AudioManager.play_story_stage(3)
		elif img_path.ends_with("story_tavern_cock_soup.png") or img_path.ends_with("5-atamansha-boss-apperiance.jpg"):
			AudioManager.play_boss_theme(2)
		elif (
			img_path.ends_with("story_cock_joins_quartet.png")
			or img_path.ends_with("6a-atamansha-boss-win.jpg")
			or img_path.find("rescue_cock") != -1
		):
			AudioManager.play_story_stage(4)
		elif (
			img_path.ends_with("story_cabin_mega_pyramid.png")
			or img_path.ends_with("story_bremen_window_pyramid.png")
			or img_path.ends_with("7-sputnik-boss-apperiance.jpg")
		):
			AudioManager.play_boss_theme(3)
		elif (
			img_path.ends_with("story_bremen_victory_concert.png")
			or img_path.ends_with("8a-sputnik-boss-win.jpg")
			or img_path.ends_with("9-final.jpg")
		):
			AudioManager.play_pyramid_theme(4)
		else:
			AudioManager.sync_music_to_party(SaveManager.party)

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
		var ch_ref: Dictionary = ch
		c_btn.pressed.connect(func() -> void:
			AudioManager.play_sfx("ui_click")
			_on_choice_selected(ch_ref)
		)
		_choices_box.add_child(c_btn)

func _on_choice_selected(ch: Dictionary) -> void:
	var sig_arg: String = String(ch.get("signal", ""))
	if sig_arg != "":
		_on_dialogic_signal_event(sig_arg)
	var b_lines: Array = ch.get("branch_lines", []) as Array
	if not b_lines.is_empty():
		_lines.clear()
		for b: Variant in b_lines:
			_lines.append(b as Dictionary)
		_line_cursor = 0
		_choices.clear()
		_render_dialogue_state()

func _on_dialogic_signal_event(argument: Variant) -> void:
	var code: String = String(argument)
	EventBus.dialogic_event_triggered.emit(code, 1)

func _on_eventbus_dialogic_reward(event_code: String, _amount: int) -> void:
	for child: Node in _choices_box.get_children():
		child.queue_free()

	var summary: String = ""
	match event_code:
		"boomer_yes", "boomer_true":
			SaveManager.set_player_is_boomer(true)
			AudioManager.play_sfx("pyramid_siren")
			summary = "Вы признались: «Да, чистая правда, я скуф!» Кот шипит на Пса за слом 4-й стены."
		"boomer_no", "boomer_false":
			SaveManager.set_player_is_boomer(false)
			AudioManager.play_sfx("qte_perfect")
			summary = "Вы заявили: «Нет, я моложе!» Кот угрожает замоггать Пса прямо внутри слияния."
		"risky_container":
			var c: CatMechInstance = SaveManager.party[0]
			c.apply_part_damage(PartData.PartSlot.ARMS, 15, true)
			SaveManager.add_run_scrap(35)
			SaveManager.spare_parts_inventory.append({"part_id": "titan_arms", "current_hp": 70})
			AudioManager.play_sfx("part_break")
			summary = "Взрыв конденсатора задел манипуляторы (-15 HP Рукам), но внутри найден [Рельсотрон «Авангард»] и +35 Лома!"
		"safe_scrap":
			SaveManager.add_run_scrap(30)
			SaveManager.add_sync(20)
			AudioManager.play_sfx("heal")
			summary = "Музыканты аккуратно собрали ресурсы вокруг повозки: +30 Лома и +20% Гармонии!"
		"field_recharge":
			for cat: CatMechInstance in SaveManager.party:
				cat.body_part.repair(25)
				cat.arms_part.repair(25)
				cat.legs_part.repair(25)
			AudioManager.play_sfx("heal")
			summary = "Энергия аккумулятора направлена на сервоприводы: +25 HP всем деталям отряда!"
		"hack_convoy":
			SaveManager.add_run_scrap(45)
			SaveManager.add_meta_rewards(15, 1)
			AudioManager.play_sfx("qte_perfect")
			summary = "C.O.C.K. успешно заглушил конвой! Получено +45 Лома и +1 Ядро ИИ!"
		"record_harmony":
			SaveManager.add_sync(50)
			AudioManager.play_sfx("pyramid_siren")
			summary = "Записана генеральная репетиция на кассету: +50% к шкале Гармонии «Пирамиды Бремена»!"
		"salvage_relay":
			SaveManager.add_run_scrap(30)
			for cat2: CatMechInstance in SaveManager.party:
				cat2.body_part.repair_full()
			AudioManager.play_sfx("heal")
			summary = "Ретранслятор разобран: +30 Лома, все Корпуса отряда полностью отремонтированы!"
		"plasma_dive":
			var target_cat: CatMechInstance = SaveManager.party[SaveManager.party.size() - 1]
			target_cat.apply_part_damage(PartData.PartSlot.BODY, 12, true)
			SaveManager.add_run_scrap(25)
			SaveManager.spare_parts_inventory.append({"part_id": "titan_legs", "current_hp": 85})
			AudioManager.play_sfx("qte_perfect")
			summary = "Щит M.U.L.E. принял тепловой удар (-12 HP Корпусу) и достал из горна [Турбо-траки «Бастион»] + 25 Лома!"
		"plasma_charge":
			SaveManager.add_sync(40)
			SaveManager.add_run_scrap(20)
			AudioManager.play_sfx("heal")
			summary = "Инструменты настроены у тёплого горна: +40% Гармонии и +20 Лома!"
		_:
			SaveManager.add_run_scrap(40)
			AudioManager.play_sfx("heal")
			summary = "Слито охлаждающее масло и редкие сплавы: +40 Лома!"

	_outcome_label.text = "ИТОГ СОБЫТИЯ: " + summary
	_outcome_label.visible = true
	_continue_btn.text = String(_payload.get("continue_text", "ВЕРНУТЬСЯ НА КАРТУ ->"))
	_continue_btn.visible = true
