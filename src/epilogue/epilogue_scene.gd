class_name EpilogueScene
extends Control

## EpilogueScene: Двухактный эпилог после победы над финальным боссом (ADR-002, Issue #34)
## Акт 1: Изба разбойников (Оммаж сказке Братьев Гримм, смена спрайта Мега-Пирамиды на живую пирамиду, крики разбойников, панчлайн Кота)
## Акт 2: Победный Рок-Концерт (4-трековый полифонический трек, анимированные риги квартета, свет, пиротехника, титры, разблокировка tape_bremen_triumph и NG+)

enum Act {
	CABIN = 1,
	CONCERT = 2
}

var current_act: Act = Act.CABIN
var _payload: Dictionary = {}

# --- Состояние Акта 1: Изба разбойников ---
var _act1_root: Control = null
var _cabin_bg: TextureRect = null
var _cabin_illustration_panel: PanelContainer = null
var _cabin_illustration_rect: TextureRect = null
var _portrait_rect: TextureRect = null
var _speaker_label: Label = null
var _dialogue_text: RichTextLabel = null
var _next_btn: Button = null
var _to_concert_btn: Button = null
var _skip_cabin_btn: Button = null
var _line_cursor: int = 0
var _lines: Array[Dictionary] = []

var current_cabin_sprite: String = ""
var sprite_switched_to_animal_pyramid: bool = false
var last_comic_sfx: String = ""

# --- Состояние Акта 2: Победный Рок-Концерт ---
var _act2_root: Control = null
var _concert_bg: TextureRect = null
var _concert_stage: Node2D = null
var _character_rigs: Array[Dictionary] = []
var _spotlights: Array[Node2D] = []
var _pyro_cannons: Array[CPUParticles2D] = []
var _credits_layer: Control = null
var _credits_vbox: VBoxContainer = null
var _credits_scroll_y: float = 360.0
var _credits_speed: float = 28.0
var _beat_timer: float = 0.0
var _pyro_timer: float = 0.0
var _is_concert_active: bool = false
var _skip_to_hub_btn: Button = null

const CABIN_LINES: Array[Dictionary] = [
	{
		"speaker": "felix",
		"speaker_name": "FELIX (Бродячий Кот-Музыкант)",
		"mood": "battle",
		"text": "Внимание, банда! Впереди логово главарей мародёров на холме. По привычке — стыкуемся в боевую РОБО-МЕГА-ПИРАМИДУ!",
		"sfx": "pyramid_siren",
		"image": "res://assets/photos/6-1-fake-boss-apperiance.jpg"
	},
	{
		"speaker": "hound",
		"speaker_name": "H.O.U.N.D. (Загнанный Пёс-Барабанщик)",
		"mood": "battle",
		"text": "ГАВ! Стыковка завершена! Мощность на максимуме, орудийные пилоны взведены!",
		"sfx": "",
		"image": "res://assets/photos/6-1-fake-boss-apperiance.jpg"
	},
	{
		"speaker": "mule",
		"speaker_name": "M.U.L.E. (Мельничный Осёл-Басист)",
		"mood": "battle",
		"text": "И-а! Басовые гидравлические сервоприводы готовы снести стену!",
		"sfx": "",
		"image": "res://assets/photos/6-1-fake-boss-apperiance.jpg"
	},
	{
		"speaker": "cock",
		"speaker_name": "C.O.C.K. (Голосистый Петух-Солист)",
		"mood": "battle",
		"text": "КУ-КА-РЕ-КУ! Синтезатор наведения зафиксирован прямо на окне радиорубки!",
		"sfx": "",
		"image": "res://assets/photos/6-2-fake-boss-monster.jpg"
	},
	{
		"speaker": "felix",
		"speaker_name": "FELIX (Бродячий Кот-Музыкант)",
		"mood": "normal",
		"text": "...Стоп. Подождите. Мы же просто хотели заглянуть в окно и узнать, кто там внутри? Кажется, мы переборщили?",
		"sfx": "",
		"image": "res://assets/photos/6-2-fake-boss-monster.jpg"
	},
	{
		"speaker": "hound",
		"speaker_name": "H.O.U.N.D. (Загнанный Пёс-Барабанщик)",
		"mood": "normal",
		"text": "Ой... Мы же пятнадцатиметровый боевой титан, мы сейчас всю хижину раздавим в пыль!",
		"sfx": "",
		"image": "res://assets/photos/6-2-fake-boss-monster.jpg"
	},
	{
		"speaker": "felix",
		"speaker_name": "FELIX (Бродячий Кот-Музыкант)",
		"mood": "happy",
		"text": "Отставить боевой режим! Быстро рассыпаемся и встаем в классическую живую пирамиду Братьев Гримм: Петух на Коте, Кот на Псе, Пёс на Осле!",
		"sfx": "comic_slide",
		"image": "res://assets/photos/6-3-fake-boss-piramide.jpg",
		"switch_pyramid": true
	},
	{
		"speaker": "cock",
		"speaker_name": "C.O.C.K. (Голосистый Петух-Солист)",
		"mood": "happy",
		"text": "Раз-два, прыг-скок! Классическая сказочная пирамида на подоконнике готова!",
		"sfx": "",
		"image": "res://assets/photos/6-3-fake-boss-piramide.jpg"
	},
	{
		"speaker": "outlaw",
		"speaker_name": "ГЛАВАРЬ РАЗБОЙНИКОВ (Мародёр из Избы)",
		"mood": "shocked",
		"text": "*слышит грохот снаружи, зажигает лучину и с диким ужасом выглядывает в тёмное окно*",
		"sfx": "dissonance",
		"image": "res://assets/photos/6-4-fake-boss-win.jpg"
	},
	{
		"speaker": "outlaw",
		"speaker_name": "ГЛАВАРЬ РАЗБОЙНИКОВ (Мародёр из Избы)",
		"mood": "panic",
		"text": "КАРАУЛ! СПАСАЙТЕСЬ! Ох, в этой избе сидит страшная ведьма — она зашипела и исцарапала мне лицо длинными когтями! У двери чёрт с ножом пырнул меня в ногу, во дворе чёрное чудовище с дубиной, а на крыше грозный судья кричит нечеловеческим голосом: «Подайте мне вора сюда!»",
		"sfx": "",
		"image": "res://assets/photos/6-4-fake-boss-win.jpg"
	},
	{
		"speaker": "felix",
		"speaker_name": "FELIX (Бродячий Кот-Музыкант)",
		"mood": "normal",
		"text": "Ха-ха-ха! Глядите, как они сверкают пятками во тьму! Представляете, что бы с ними было, если бы они увидели робопетухокотопсоосла!?",
		"sfx": "",
		"image": "res://assets/photos/6-3-fake-boss-piramide.jpg"
	},
	{
		"speaker": "hound",
		"speaker_name": "H.O.U.N.D. (Загнанный Пёс-Барабанщик)",
		"mood": "happy",
		"text": "Разбойники в панике разбежались! Концертный зал Бремен-4 очищен и свободен для нашего великого победного рок-концерта!",
		"sfx": "",
		"image": "res://assets/photos/6-3-fake-boss-piramide.jpg"
	}
]

func setup_epilogue(payload: Dictionary) -> void:
	_payload = payload
	if is_inside_tree():
		var start_act_val: int = int(_payload.get("act", 1))
		if start_act_val == 2:
			start_act_2_concert()
		else:
			start_act_1_cabin()

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	clip_contents = true
	DataCatalog.ensure_loaded()
	_build_ui_roots()

	var start_act_val: int = int(_payload.get("act", 1))
	if start_act_val == 2:
		start_act_2_concert()
	else:
		start_act_1_cabin()

func _build_ui_roots() -> void:
	# Корневой контейнер Акта 1
	_act1_root = Control.new()
	_act1_root.name = "Act1_Cabin"
	_act1_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_act1_root)
	_build_act1_ui()

	# Корневой контейнер Акта 2
	_act2_root = Control.new()
	_act2_root.name = "Act2_Concert"
	_act2_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_act2_root.visible = false
	add_child(_act2_root)
	_build_act2_ui()

# =============================================================================
# АКТ 1: ИЗБА РАЗБОЙНИКОВ
# =============================================================================

func _build_act1_ui() -> void:
	# Тёмный ночной фон избы
	_cabin_bg = TextureRect.new()
	_cabin_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	_cabin_bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_cabin_bg.stretch_mode = TextureRect.STRETCH_SCALE
	_cabin_bg.modulate = Color(0.35, 0.38, 0.55, 1.0)
	var bg_path: String = "res://assets/sprites/backgrounds/bg_sector4.png"
	if not ResourceLoader.exists(bg_path):
		bg_path = "res://assets/sprites/backgrounds/bg_sector3.png"
	if ResourceLoader.exists(bg_path):
		_cabin_bg.texture = load(bg_path) as Texture2D
	_act1_root.add_child(_cabin_bg)

	var main_panel: PanelContainer = PanelContainer.new()
	main_panel.position = Vector2(20, 24)
	main_panel.size = Vector2(600, 318)
	var st: StyleBoxFlat = StyleBoxFlat.new()
	st.bg_color = Color(0.05, 0.07, 0.12, 0.96)
	st.border_color = Color(0.55, 0.35, 0.9, 1.0)
	st.set_border_width_all(2)
	st.set_corner_radius_all(4)
	st.set_content_margin_all(8)
	main_panel.add_theme_stylebox_override("panel", st)
	_act1_root.add_child(main_panel)

	var root_vbox: VBoxContainer = VBoxContainer.new()
	root_vbox.add_theme_constant_override("separation", 6)
	main_panel.add_child(root_vbox)

	var top_hbox: HBoxContainer = HBoxContainer.new()
	root_vbox.add_child(top_hbox)

	var top_title: Label = Label.new()
	top_title.text = "АКТ 1: ИЗБА РАЗБОЙНИКОВ // СКАЗКА БРАТЬЕВ ГРИММ"
	top_title.add_theme_font_size_override("font_size", 10)
	top_title.add_theme_color_override("font_color", Color(1.0, 0.85, 0.35))
	top_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top_hbox.add_child(top_title)

	_skip_cabin_btn = Button.new()
	_skip_cabin_btn.text = "ПРОПУСТИТЬ К КОНЦЕРТУ ❯❯"
	_skip_cabin_btn.add_theme_font_size_override("font_size", 8)
	_skip_cabin_btn.pressed.connect(start_act_2_concert)
	top_hbox.add_child(_skip_cabin_btn)

	# Сюжетная иллюстрация
	_cabin_illustration_panel = PanelContainer.new()
	_cabin_illustration_panel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var pic_st: StyleBoxFlat = StyleBoxFlat.new()
	pic_st.bg_color = Color(0.02, 0.03, 0.07, 0.98)
	pic_st.border_color = Color(0.35, 0.85, 1.0, 0.9)
	pic_st.set_border_width_all(1)
	pic_st.set_content_margin_all(3)
	_cabin_illustration_panel.add_theme_stylebox_override("panel", pic_st)
	root_vbox.add_child(_cabin_illustration_panel)

	_cabin_illustration_rect = TextureRect.new()
	_cabin_illustration_rect.custom_minimum_size = Vector2(256, 144)
	_cabin_illustration_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_cabin_illustration_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_cabin_illustration_rect.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	_cabin_illustration_panel.add_child(_cabin_illustration_rect)

	# Портрет и диалоговая панель
	var speaker_hbox: HBoxContainer = HBoxContainer.new()
	speaker_hbox.add_theme_constant_override("separation", 10)
	root_vbox.add_child(speaker_hbox)

	_portrait_rect = TextureRect.new()
	_portrait_rect.custom_minimum_size = Vector2(64, 64)
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
	_dialogue_text.custom_minimum_size = Vector2(470, 66)
	_dialogue_text.bbcode_enabled = true
	_dialogue_text.add_theme_font_size_override("normal_font_size", 9)
	text_vbox.add_child(_dialogue_text)

	# Кнопки навигации
	var bottom_hbox: HBoxContainer = HBoxContainer.new()
	bottom_hbox.add_theme_constant_override("separation", 8)
	root_vbox.add_child(bottom_hbox)

	_next_btn = Button.new()
	_next_btn.text = "Далее ->"
	_next_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_next_btn.add_theme_font_size_override("font_size", 10)
	_next_btn.pressed.connect(_on_next_line_pressed)
	bottom_hbox.add_child(_next_btn)

	_to_concert_btn = Button.new()
	_to_concert_btn.text = "В КОНЦЕРТНЫЙ ЗАЛ НА ПОБЕДНЫЙ РОК-КОНЦЕРТ ❯❯"
	_to_concert_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_to_concert_btn.visible = false
	_to_concert_btn.add_theme_font_size_override("font_size", 10)
	_to_concert_btn.add_theme_color_override("font_color", Color(1.0, 0.9, 0.35))
	_to_concert_btn.pressed.connect(start_act_2_concert)
	bottom_hbox.add_child(_to_concert_btn)

func start_act_1_cabin() -> void:
	current_act = Act.CABIN
	_act1_root.visible = true
	_act2_root.visible = false
	_is_concert_active = false
	_line_cursor = 0
	_lines = CABIN_LINES.duplicate(true)

	sprite_switched_to_animal_pyramid = false
	last_comic_sfx = ""
	current_cabin_sprite = "res://assets/photos/6-2-fake-boss-monster.jpg"

	# Начальный спрайт: Робо-Мега-Пирамида
	_set_cabin_sprite("res://assets/photos/6-2-fake-boss-monster.jpg")
	AudioManager.play_pyramid_theme(4)
	_render_act1_dialogue()

func _set_cabin_sprite(path: String) -> void:
	current_cabin_sprite = path
	var tex: Texture2D = null
	if ResourceLoader.exists(path):
		tex = load(path) as Texture2D
	elif ResourceLoader.exists("res://assets/sprites/cats/bremen_pyramid.png"):
		tex = load("res://assets/sprites/cats/bremen_pyramid.png") as Texture2D

	if tex != null:
		_cabin_illustration_rect.texture = tex
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
		_cabin_illustration_rect.custom_minimum_size = Vector2(target_w, target_h)

func _render_act1_dialogue() -> void:
	if _line_cursor < 0 or _line_cursor >= _lines.size():
		_next_btn.visible = false
		_to_concert_btn.visible = true
		return

	var item: Dictionary = _lines[_line_cursor]
	var speaker_id: String = String(item["speaker"])
	var mood: String = String(item["mood"])
	var text_body: String = String(item["text"])
	var sfx_to_play: String = String(item.get("sfx", ""))
	var img_to_show: String = String(item.get("image", ""))
	var should_switch: bool = bool(item.get("switch_pyramid", false))

	# Проверка переключения спрайта на классическую живую пирамиду (с комичным SFX)
	if should_switch or img_to_show.ends_with("story_bremen_window_pyramid.png") or img_to_show.ends_with("bremen_animal_pyramid.png"):
		if not sprite_switched_to_animal_pyramid:
			sprite_switched_to_animal_pyramid = true
			last_comic_sfx = "comic_slide"
			AudioManager.play_sfx("comic_slide")
			_set_cabin_sprite("res://assets/photos/6-3-fake-boss-piramide.jpg")
	elif img_to_show != "" and img_to_show != current_cabin_sprite:
		_set_cabin_sprite(img_to_show)

	if sfx_to_play != "" and sfx_to_play != "comic_slide":
		AudioManager.play_sfx(sfx_to_play)

	# Загрузка портрета
	var p_path: String = "res://assets/sprites/portraits/" + speaker_id + "_" + mood + ".png"
	if ResourceLoader.exists(p_path):
		_portrait_rect.texture = load(p_path) as Texture2D
	elif ResourceLoader.exists("res://assets/sprites/portraits/" + speaker_id + "_normal.png"):
		_portrait_rect.texture = load("res://assets/sprites/portraits/" + speaker_id + "_normal.png") as Texture2D
	elif ResourceLoader.exists("res://assets/sprites/portraits/satellite_glitch.png"):
		_portrait_rect.texture = load("res://assets/sprites/portraits/satellite_glitch.png") as Texture2D

	_speaker_label.text = String(item["speaker_name"]) + " [" + mood.to_upper() + "]"
	_dialogue_text.text = text_body

	if _line_cursor >= _lines.size() - 1:
		_next_btn.visible = false
		_to_concert_btn.visible = true
	else:
		_next_btn.visible = true
		_next_btn.text = "Далее (" + str(_line_cursor + 1) + "/" + str(_lines.size()) + ") ->"
		_to_concert_btn.visible = false

func _on_next_line_pressed() -> void:
	AudioManager.play_sfx("ui_click")
	_line_cursor += 1
	_render_act1_dialogue()

func advance_cabin_dialogue() -> bool:
	if _line_cursor < _lines.size() - 1:
		_line_cursor += 1
		_render_act1_dialogue()
		return true
	elif _line_cursor == _lines.size() - 1:
		start_act_2_concert()
		return true
	return false

func get_cabin_sprite_path() -> String:
	return current_cabin_sprite

func is_animal_pyramid_active() -> bool:
	return sprite_switched_to_animal_pyramid

func has_comic_sfx_played() -> bool:
	return last_comic_sfx == "comic_slide" or AudioManager.last_sfx_played == "comic_slide" or AudioManager.last_sfx_played == "pyramid_undock"

func get_dialogue_line(idx: int) -> Dictionary:
	if idx >= 0 and idx < _lines.size():
		return _lines[idx]
	return {}

# =============================================================================
# АКТ 2: ПОБЕДНЫЙ РОК-КОНЦЕРТ
# =============================================================================

func _build_act2_ui() -> void:
	# 1. Задний план сцены
	_concert_bg = TextureRect.new()
	_concert_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	_concert_bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_concert_bg.stretch_mode = TextureRect.STRETCH_SCALE
	var bg_path: String = "res://assets/sprites/backgrounds/bg_sector4.png"
	if ResourceLoader.exists("res://assets/photos/7-final.jpg"):
		bg_path = "res://assets/photos/7-final.jpg"
	if ResourceLoader.exists(bg_path):
		_concert_bg.texture = load(bg_path) as Texture2D
	_act2_root.add_child(_concert_bg)

	# 2. 2D сцена с анимированными персонажами и светом
	_concert_stage = Node2D.new()
	_concert_stage.name = "ConcertStage"
	_act2_root.add_child(_concert_stage)

	_build_stage_lighting()
	_build_character_rigs()
	_build_pyrotechnics()

	# 3. Верхняя неоновая плашка
	var top_panel: PanelContainer = PanelContainer.new()
	top_panel.position = Vector2(8, 6)
	top_panel.size = Vector2(624, 26)
	var st: StyleBoxFlat = StyleBoxFlat.new()
	st.bg_color = Color(0.08, 0.04, 0.14, 0.92)
	st.border_color = Color(1.0, 0.85, 0.25, 0.95)
	st.set_border_width_all(1)
	st.set_corner_radius_all(3)
	st.set_content_margin_all(4)
	top_panel.add_theme_stylebox_override("panel", st)
	_act2_root.add_child(top_panel)

	var title_lbl: Label = Label.new()
	title_lbl.text = "★ КОНЦЕРТНЫЙ ЗАЛ БРЕМЕН-4 ОСВОБОЖДЁН! ВЕЛИКИЙ ПОБЕДНЫЙ РОК-КОНЦЕРТ ★"
	title_lbl.add_theme_font_size_override("font_size", 10)
	title_lbl.add_theme_color_override("font_color", Color(1.0, 0.9, 0.4))
	title_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	top_panel.add_child(title_lbl)

	# 4. Слой бегущих титров (Rolling Credits)
	_credits_layer = Control.new()
	_credits_layer.name = "CreditsLayer"
	_credits_layer.position = Vector2(170, 360)
	_credits_layer.size = Vector2(300, 720)
	_act2_root.add_child(_credits_layer)

	_credits_vbox = VBoxContainer.new()
	_credits_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_credits_vbox.add_theme_constant_override("separation", 6)
	_credits_layer.add_child(_credits_vbox)

	_build_credits_content()

	# 5. Кнопка пропуска в Хаб
	_skip_to_hub_btn = Button.new()
	_skip_to_hub_btn.text = "В ЛАГЕРЬ БРОДЯГ (ХАБ) [SPACE / ESC] ❯❯"
	_skip_to_hub_btn.position = Vector2(390, 324)
	_skip_to_hub_btn.size = Vector2(242, 28)
	_skip_to_hub_btn.add_theme_font_size_override("font_size", 9)
	_skip_to_hub_btn.add_theme_color_override("font_color", Color(1.0, 0.88, 0.35))
	var st_btn: StyleBoxFlat = StyleBoxFlat.new()
	st_btn.bg_color = Color(0.08, 0.05, 0.16, 0.95)
	st_btn.border_color = Color(0.4, 0.9, 1.0, 0.9)
	st_btn.set_border_width_all(2)
	st_btn.set_corner_radius_all(3)
	_skip_to_hub_btn.add_theme_stylebox_override("normal", st_btn)
	_skip_to_hub_btn.pressed.connect(_on_return_to_hub)
	_act2_root.add_child(_skip_to_hub_btn)

func _build_stage_lighting() -> void:
	_spotlights.clear()
	var light_colors: Array[Color] = [
		Color(0.25, 0.65, 1.0, 0.45), # Синий (Felix)
		Color(1.0, 0.35, 0.35, 0.45), # Красный (Hound)
		Color(1.0, 0.85, 0.25, 0.45), # Жёлтый (Mule)
		Color(0.35, 1.0, 0.55, 0.45)  # Зелёный (Cock)
	]
	var light_positions: Array[Vector2] = [
		Vector2(110, 40),
		Vector2(240, 35),
		Vector2(390, 35),
		Vector2(530, 40)
	]

	for i: int in range(4):
		var spot: Node2D = Node2D.new()
		spot.name = "Spotlight_" + str(i)
		spot.position = light_positions[i]
		spot.set_meta("base_pos", light_positions[i])
		spot.set_meta("color", light_colors[i])
		spot.set_meta("phase", float(i) * 1.57)
		_concert_stage.add_child(spot)
		_spotlights.append(spot)

func _build_character_rigs() -> void:
	_character_rigs.clear()

	var rig_configs: Array[Dictionary] = [
		{
			"id": "MULE",
			"name": "M.U.L.E.",
			"instrument": "Бас-гитара",
			"pos": Vector2(110, 240),
			"body": "res://assets/sprites/cats/mule_body.png",
			"arms": "res://assets/sprites/cats/mule_arms.png",
			"legs": "res://assets/sprites/cats/mule_legs.png",
			"color": Color(0.85, 0.65, 0.15)
		},
		{
			"id": "FELIX",
			"name": "FELIX",
			"instrument": "Соло-электрогитара",
			"pos": Vector2(240, 226),
			"body": "res://assets/sprites/cats/felix_body.png",
			"arms": "res://assets/sprites/cats/felix_arms.png",
			"legs": "res://assets/sprites/cats/felix_legs.png",
			"color": Color(0.2, 0.6, 0.95)
		},
		{
			"id": "HOUND",
			"name": "H.O.U.N.D.",
			"instrument": "Ударная установка",
			"pos": Vector2(390, 226),
			"body": "res://assets/sprites/cats/hound_body.png",
			"arms": "res://assets/sprites/cats/hound_arms.png",
			"legs": "res://assets/sprites/cats/hound_legs.png",
			"color": Color(0.85, 0.25, 0.25)
		},
		{
			"id": "COCK",
			"name": "C.O.C.K.",
			"instrument": "Аналоговый синтезатор",
			"pos": Vector2(530, 240),
			"body": "res://assets/sprites/cats/cock_body.png",
			"arms": "res://assets/sprites/cats/cock_arms.png",
			"legs": "res://assets/sprites/cats/cock_legs.png",
			"color": Color(0.3, 0.85, 0.45)
		}
	]

	for cfg: Dictionary in rig_configs:
		var root: Node2D = Node2D.new()
		root.name = "ConcertRig_" + String(cfg["id"])
		root.position = cfg["pos"]
		_concert_stage.add_child(root)

		# Спрайт ног
		var legs_spr: Sprite2D = Sprite2D.new()
		legs_spr.name = "Legs"
		legs_spr.position = Vector2(0, 14)
		if ResourceLoader.exists(String(cfg["legs"])):
			legs_spr.texture = load(String(cfg["legs"])) as Texture2D
		root.add_child(legs_spr)

		# Спрайт корпуса
		var body_spr: Sprite2D = Sprite2D.new()
		body_spr.name = "Body"
		body_spr.position = Vector2(0, -4)
		if ResourceLoader.exists(String(cfg["body"])):
			body_spr.texture = load(String(cfg["body"])) as Texture2D
		root.add_child(body_spr)

		# Спрайт рук / инструмента
		var arms_spr: Sprite2D = Sprite2D.new()
		arms_spr.name = "Arms"
		arms_spr.position = Vector2(2, 2)
		if ResourceLoader.exists(String(cfg["arms"])):
			arms_spr.texture = load(String(cfg["arms"])) as Texture2D
		root.add_child(arms_spr)

		# Подпись персонажа и инструмента
		var lbl: Label = Label.new()
		lbl.position = Vector2(-40, -38)
		lbl.size = Vector2(80, 16)
		lbl.text = String(cfg["name"]) + "\n[" + String(cfg["instrument"]) + "]"
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lbl.add_theme_font_size_override("font_size", 7)
		lbl.add_theme_color_override("font_color", cfg["color"])
		root.add_child(lbl)

		_character_rigs.append({
			"id": String(cfg["id"]),
			"root": root,
			"base_pos": cfg["pos"],
			"body": body_spr,
			"arms": arms_spr,
			"legs": legs_spr,
			"anim_phase": float(_character_rigs.size()) * 0.8
		})

func _build_pyrotechnics() -> void:
	_pyro_cannons.clear()
	var pyro_positions: Array[Vector2] = [
		Vector2(40, 310),
		Vector2(320, 305),
		Vector2(600, 310)
	]

	for pos: Vector2 in pyro_positions:
		var p: CPUParticles2D = CPUParticles2D.new()
		p.position = pos
		p.emitting = false
		p.amount = 32
		p.lifetime = 0.9
		p.one_shot = true
		p.explosiveness = 0.92
		p.direction = Vector2(0, -1)
		p.spread = 24.0
		p.initial_velocity_min = 160.0
		p.initial_velocity_max = 240.0
		p.gravity = Vector2(0, 180)
		p.color = Color(1.0, 0.85, 0.3)
		_concert_stage.add_child(p)
		_pyro_cannons.append(p)

func _build_credits_content() -> void:
	var credits_items: Array[String] = [
		"★ ★ ★ XENOCATS: BREMEN-4 ★ ★ ★",
		"ПОБЕДНЫЙ РОК-КОНЦЕРТ И ОСВОБОЖДЕНИЕ ПЛАНЕТЫ",
		"",
		"=== КВАРТЕТ БРЕМЕНСКИХ МУЗЫКАНТОВ ===",
		"• FELIX — Соло-электрогитара, лидер восстания",
		"• H.O.U.N.D. — Ударная установка, ритм-секция",
		"• M.U.L.E. — Бас-гитара, суб-басовый грув",
		"• C.O.C.K. — Аналоговый синтезатор, РЭБ и вокал",
		"",
		"=== ВДОХНОВЕНИЕ СКАЗКИ ===",
		"Братья Гримм — «Бременские музыканты»",
		"(Die Bremer Stadtmusikanten)",
		"",
		"=== РАЗРАБОТКА & АРХИТЕКТУРА ===",
		"Necronir / Xenocats Team",
		"Antigravity Agentic Pair Programming",
		"Google DeepMind Architecture Engine",
		"",
		"=== МУЗЫКА И 4-ТРЕКОВАЯ ПОЛИФОНИЯ ===",
		"Ретро-чиптюн движок: 4 живых инструмента",
		"Энергетический Резонатор «Бремен-4»",
		"",
		"=== НАГРАДЫ ЗА ПРОХОЖДЕНИЕ ФИНАЛА ===",
		"★ Памятная кассета «tape_bremen_triumph» РАЗБЛОКИРОВАНА!",
		"★ Режим повышенной сложности New Game+ АКТИВИРОВАН!",
		"★ Концертный зал Бремен-4 освобождён навсегда!",
		"",
		"СПАСИБО ЗА ИГРУ!",
		"МУЗЫКА СВОБОДЫ ЗВУЧИТ НА ВСЮ ВСЕЛЕННУЮ!"
	]

	for item_text: String in credits_items:
		var lbl: Label = Label.new()
		lbl.text = item_text
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		if item_text.begins_with("★"):
			lbl.add_theme_font_size_override("font_size", 10)
			lbl.add_theme_color_override("font_color", Color(1.0, 0.9, 0.35))
		elif item_text.begins_with("==="):
			lbl.add_theme_font_size_override("font_size", 9)
			lbl.add_theme_color_override("font_color", Color(0.4, 0.95, 1.0))
		else:
			lbl.add_theme_font_size_override("font_size", 8)
			lbl.add_theme_color_override("font_color", Color(0.85, 0.9, 0.95))
		_credits_vbox.add_child(lbl)

func start_act_2_concert() -> void:
	current_act = Act.CONCERT
	_act1_root.visible = false
	_act2_root.visible = true
	_is_concert_active = true
	_credits_scroll_y = 360.0
	_credits_layer.position.y = _credits_scroll_y

	# Разблокировка наград в SaveManager (tape_bremen_triumph, highest_ng_cycle += 1, concert_hall_liberated)
	SaveManager.complete_epilogue_triumph()

	# Воспроизведение 4-трековой полифонической композиции (Гитара + Ударные + Бас + Синтезатор)
	AudioManager.play_story_stage(4)
	AudioManager.play_tape(&"tape_bremen_triumph")

	# Запуск первого залпа пиротехники
	_trigger_pyrotechnics()

func _trigger_pyrotechnics() -> void:
	for cannon: CPUParticles2D in _pyro_cannons:
		cannon.restart()
		cannon.emitting = true

func _process(delta: float) -> void:
	if current_act != Act.CONCERT or not _is_concert_active:
		return

	_beat_timer += delta
	_pyro_timer += delta

	# 1. Анимация движения титров вверх
	_credits_scroll_y -= _credits_speed * delta
	if _credits_scroll_y < -700.0:
		_credits_scroll_y = 360.0
	_credits_layer.position.y = _credits_scroll_y

	# 2. Ритмичная пиротехника каждые 2.4 секунды
	if _pyro_timer >= 2.4:
		_pyro_timer = 0.0
		_trigger_pyrotechnics()

	# 3. Анимация ригов персонажей под темп (пульсация, прыжки, игра на инструментах)
	for rig: Dictionary in _character_rigs:
		var root: Node2D = rig["root"] as Node2D
		var body_spr: Sprite2D = rig["body"] as Sprite2D
		var arms_spr: Sprite2D = rig["arms"] as Sprite2D
		var base_pos: Vector2 = rig["base_pos"] as Vector2
		var p_phase: float = float(rig["anim_phase"])

		var tempo_freq: float = 7.0 # ~134 BPM грув
		var bounce_y: float = sin(_beat_timer * tempo_freq + p_phase) * 3.5
		root.position.y = base_pos.y + bounce_y

		var arm_rot: float = sin(_beat_timer * (tempo_freq * 1.5) + p_phase) * 0.28
		arms_spr.rotation = arm_rot
		body_spr.rotation = sin(_beat_timer * 3.5 + p_phase) * 0.06

	# 4. Анимация прожекторов сцены (вращение и изменение интенсивности под бит)
	for i: int in range(_spotlights.size()):
		var spot: Node2D = _spotlights[i]
		var base_pos: Vector2 = spot.get_meta("base_pos") as Vector2
		var p_phase: float = spot.get_meta("phase") as float
		spot.position.x = base_pos.x + sin(_beat_timer * 2.2 + p_phase) * 18.0
		spot.queue_redraw()

func _draw() -> void:
	# Отрисовка лучей сценических прожекторов в Акте 2
	if current_act == Act.CONCERT and _is_concert_active:
		for spot: Node2D in _spotlights:
			var spos: Vector2 = spot.global_position
			var scol: Color = spot.get_meta("color") as Color
			var intensity: float = 0.35 + 0.25 * sin(_beat_timer * 6.0 + (spot.get_meta("phase") as float))
			var draw_col: Color = Color(scol.r, scol.g, scol.b, intensity)
			var target_pt: Vector2 = Vector2(spos.x + sin(_beat_timer * 2.0) * 30.0, 310.0)
			var beam_poly: PackedVector2Array = PackedVector2Array([
				spos + Vector2(-6, 0),
				spos + Vector2(6, 0),
				target_pt + Vector2(28, 0),
				target_pt + Vector2(-28, 0)
			])
			draw_colored_polygon(beam_poly, draw_col)

func _unhandled_input(event: InputEvent) -> void:
	var should_advance: bool = false
	if event.is_action_pressed("ui_accept") or event.is_action_pressed("ui_cancel"):
		should_advance = true
	elif event is InputEventKey and event.pressed and not event.echo and event.keycode in [KEY_SPACE, KEY_ENTER, KEY_KP_ENTER, KEY_ESCAPE]:
		should_advance = true
	elif event is InputEventJoypadButton and event.pressed and event.button_index in [JOY_BUTTON_A, JOY_BUTTON_B, JOY_BUTTON_X, JOY_BUTTON_START]:
		should_advance = true
	elif event is InputEventScreenTouch and event.pressed:
		should_advance = true
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		should_advance = true

	if should_advance:
		if current_act == Act.CABIN:
			advance_cabin_dialogue()
			get_viewport().set_input_as_handled()
		elif current_act == Act.CONCERT:
			_on_return_to_hub()
			get_viewport().set_input_as_handled()

func _on_return_to_hub() -> void:
	AudioManager.play_sfx("ui_click")
	AudioManager.sync_music_to_party(SaveManager.party)
	SaveManager.delete_run_save()
	EventBus.request_scene_change.emit(&"HUB", {})

# =============================================================================
# МЕТОДЫ ДЛЯ АВТОТЕСТОВ И ВЕРИФИКАЦИИ
# =============================================================================

func get_current_act() -> Act:
	return current_act

func get_character_rigs() -> Array[Dictionary]:
	return _character_rigs

func is_polyphonic_track_playing() -> bool:
	return (
		AudioManager.active_instruments.has("Гитара")
		and AudioManager.active_instruments.has("Барабан")
		and AudioManager.active_instruments.has("Бас")
		and AudioManager.active_instruments.has("Синтезатор")
	)

func are_lights_and_pyro_active() -> bool:
	return _spotlights.size() >= 4 and _pyro_cannons.size() >= 3

func get_credits_scroll_position() -> float:
	return _credits_scroll_y

func skip_to_hub() -> void:
	_on_return_to_hub()
