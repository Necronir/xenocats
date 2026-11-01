class_name VideoPlayerScene
extends Control

## VideoPlayerScene: Полноэкранный плеер сюжетных кат-сцен и фото-артов (Issue #24)

var _payload: Dictionary = {}
var _video_player: VideoStreamPlayer = null
var _photo_rect: TextureRect = null
var _title_label: Label = null
var _skip_btn: Button = null
var _is_finishing: bool = false
var _elapsed_time: float = 0.0
var _estimated_duration: float = 6.0

func setup_video(payload: Dictionary) -> void:
	_payload = payload
	if is_inside_tree() and not _is_finishing:
		_start_media()

func _ready() -> void:
	_build_ui()
	if not _payload.is_empty():
		_start_media()

func _build_ui() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)

	# 1. Чёрный фон подложки
	var bg: ColorRect = ColorRect.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.color = Color(0.01, 0.01, 0.03, 1.0)
	add_child(bg)

	# 2. Полноэкранный показ фото-артов (16:9)
	_photo_rect = TextureRect.new()
	_photo_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_photo_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_photo_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_photo_rect.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_photo_rect.visible = false
	add_child(_photo_rect)

	# 3. Видеоплеер с масштабированием по экрану
	_video_player = VideoStreamPlayer.new()
	_video_player.set_anchors_preset(Control.PRESET_FULL_RECT)
	_video_player.expand = true
	_video_player.loop = false
	_video_player.bus = AudioManager.BUS_MASTER
	_video_player.finished.connect(_on_video_finished)
	_video_player.visible = false
	add_child(_video_player)

	# 4. Верхняя плашка с заголовком ролика/арта
	var top_panel: PanelContainer = PanelContainer.new()
	top_panel.position = Vector2(8, 6)
	top_panel.size = Vector2(624, 22)
	var st_top: StyleBoxFlat = StyleBoxFlat.new()
	st_top.bg_color = Color(0.04, 0.06, 0.1, 0.82)
	st_top.border_color = Color(0.35, 0.85, 1.0, 0.75)
	st_top.set_border_width_all(1)
	st_top.set_corner_radius_all(3)
	st_top.set_content_margin_all(3)
	top_panel.add_theme_stylebox_override("panel", st_top)
	add_child(top_panel)

	_title_label = Label.new()
	_title_label.text = "▶ СЮЖЕТНАЯ КАТ-СЦЕНА"
	_title_label.add_theme_font_size_override("font_size", 9)
	_title_label.add_theme_color_override("font_color", Color(0.85, 0.95, 1.0))
	top_panel.add_child(_title_label)

	# 5. Кнопка перехода / пропуска в правом нижнем углу
	_skip_btn = Button.new()
	_skip_btn.text = "ПРОДОЛЖИТЬ [SPACE / ENTER] ❯❯"
	_skip_btn.position = Vector2(400, 326)
	_skip_btn.size = Vector2(232, 26)
	_skip_btn.add_theme_font_size_override("font_size", 9)
	_skip_btn.add_theme_color_override("font_color", Color(1.0, 0.85, 0.35))
	var st_skip: StyleBoxFlat = StyleBoxFlat.new()
	st_skip.bg_color = Color(0.06, 0.08, 0.14, 0.88)
	st_skip.border_color = Color(0.9, 0.65, 0.25, 0.9)
	st_skip.set_border_width_all(1)
	st_skip.set_corner_radius_all(3)
	_skip_btn.add_theme_stylebox_override("normal", st_skip)
	_skip_btn.pressed.connect(_on_skip_pressed)
	add_child(_skip_btn)

func _start_media() -> void:
	_elapsed_time = 0.0

	var title_text: String = String(_payload.get("title", ""))
	if title_text != "":
		_title_label.text = "▶ " + title_text

	var img_path: String = String(_payload.get("image_path", _payload.get("photo_path", "")))
	var vid_path: String = String(_payload.get("video_path", ""))

	# Если video_path на самом деле указывает на изображение
	if img_path == "" and (vid_path.ends_with(".jpg") or vid_path.ends_with(".png") or vid_path.ends_with(".jpeg") or vid_path.ends_with(".webp")):
		img_path = vid_path
		vid_path = ""

	# Режим фото-арта (Photo Slide Cutscene)
	if img_path != "" and ResourceLoader.exists(img_path):
		var tex: Texture2D = ResourceLoader.load(img_path) as Texture2D
		if tex != null:
			_video_player.visible = false
			_photo_rect.texture = tex
			_photo_rect.visible = true
			_skip_btn.text = "ПРОДОЛЖИТЬ [SPACE / ENTER] ❯❯"
			_estimated_duration = float(_payload.get("duration", 6.0))

			var st_stage: int = int(_payload.get("story_stage", 0))
			if st_stage > 0:
				AudioManager.play_story_stage(st_stage)
			elif _payload.has("boss_theme"):
				AudioManager.play_boss_theme(int(_payload["boss_theme"]))

			if DisplayServer.get_name() == "headless":
				call_deferred("_finish_media")
			return

	# Режим видеоролика (Video Player)
	if vid_path != "" and ResourceLoader.exists(vid_path):
		var stream: VideoStream = ResourceLoader.load(vid_path) as VideoStream
		if stream != null:
			AudioManager.stop_music()
			_photo_rect.visible = false
			_video_player.visible = true
			_video_player.stream = stream
			_skip_btn.text = "ПРОПУСТИТЬ [ESC / SPACE] ❯❯"
			_estimated_duration = 14.0
			if DisplayServer.get_name() != "headless":
				_video_player.play()
			else:
				call_deferred("_finish_media")
			return

	call_deferred("_finish_media")

func _process(delta: float) -> void:
	if _is_finishing:
		return
	_elapsed_time += delta
	# Автоматический переход по истечении длительности (6 сек для фото)
	if _elapsed_time > _estimated_duration:
		_finish_media()

func _unhandled_input(event: InputEvent) -> void:
	if _is_finishing:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode in [KEY_ESCAPE, KEY_SPACE, KEY_ENTER]:
			get_viewport().set_input_as_handled()
			_on_skip_pressed()
	elif event is InputEventMouseButton and event.pressed:
		_on_skip_pressed()

func _on_skip_pressed() -> void:
	AudioManager.play_sfx("ui_click")
	_finish_media()

func _on_video_finished() -> void:
	_finish_media()

func _finish_media() -> void:
	if _is_finishing:
		return
	_is_finishing = true

	if _video_player != null and is_instance_valid(_video_player):
		_video_player.stop()

	if _payload.has("next_scene"):
		var next_scene: StringName = _payload.get("next_scene", &"HUB")
		var next_payload: Dictionary = _payload.get("next_payload", {})
		EventBus.request_scene_change.emit(next_scene, next_payload)
