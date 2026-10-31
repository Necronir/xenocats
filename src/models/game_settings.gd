class_name GameSettings
extends RefCounted

## GameSettings: Модель пользовательских настроек звука, экрана и подсказок обучения (user://settings.cfg)

signal changed()

const DEFAULT_PATH: String = "user://settings.cfg"

var master_volume: float = 1.0
var music_volume: float = 0.85
var sfx_volume: float = 0.90
var fullscreen: bool = false
var tutorials_enabled: bool = true
var seen_tutorials: Array[String] = []

func load_from_disk(path: String = DEFAULT_PATH) -> bool:
	var cfg: ConfigFile = ConfigFile.new()
	var err: Error = cfg.load(path)
	if err != OK:
		return false

	master_volume = clampf(float(cfg.get_value("audio", "master", 1.0)), 0.0, 1.0)
	music_volume = clampf(float(cfg.get_value("audio", "music", 0.85)), 0.0, 1.0)
	sfx_volume = clampf(float(cfg.get_value("audio", "sfx", 0.90)), 0.0, 1.0)
	fullscreen = bool(cfg.get_value("display", "fullscreen", false))
	tutorials_enabled = bool(cfg.get_value("tutorial", "enabled", true))

	seen_tutorials.clear()
	var raw_seen: Variant = cfg.get_value("tutorial", "seen", [])
	if raw_seen is Array:
		for item: Variant in raw_seen as Array:
			var s: String = String(item)
			if s != "" and not seen_tutorials.has(s):
				seen_tutorials.append(s)
	return true

func save_to_disk(path: String = DEFAULT_PATH) -> bool:
	var cfg: ConfigFile = ConfigFile.new()
	cfg.set_value("audio", "master", master_volume)
	cfg.set_value("audio", "music", music_volume)
	cfg.set_value("audio", "sfx", sfx_volume)
	cfg.set_value("display", "fullscreen", fullscreen)
	cfg.set_value("tutorial", "enabled", tutorials_enabled)
	cfg.set_value("tutorial", "seen", seen_tutorials.duplicate())
	return cfg.save(path) == OK

func set_bus_linear(bus_name: StringName, linear_val: float) -> void:
	var v: float = clampf(linear_val, 0.0, 1.0)
	if bus_name == AudioManager.BUS_MASTER:
		master_volume = v
	elif bus_name == AudioManager.BUS_MUSIC:
		music_volume = v
	elif bus_name == AudioManager.BUS_SFX:
		sfx_volume = v

	AudioManager._ensure_audio_buses()
	var idx: int = AudioServer.get_bus_index(bus_name)
	if idx >= 0:
		if v <= 0.001:
			AudioServer.set_bus_mute(idx, true)
			AudioServer.set_bus_volume_db(idx, -80.0)
		else:
			AudioServer.set_bus_mute(idx, false)
			AudioServer.set_bus_volume_db(idx, linear_to_db(v))
	changed.emit()

func apply_audio() -> void:
	set_bus_linear(AudioManager.BUS_MASTER, master_volume)
	set_bus_linear(AudioManager.BUS_MUSIC, music_volume)
	set_bus_linear(AudioManager.BUS_SFX, sfx_volume)

func set_fullscreen(enabled: bool) -> void:
	fullscreen = enabled
	apply_display()
	changed.emit()

func apply_display() -> void:
	if DisplayServer.get_name() == "headless":
		return
	var target_mode: DisplayServer.WindowMode = (
		DisplayServer.WINDOW_MODE_FULLSCREEN
		if fullscreen
		else DisplayServer.WINDOW_MODE_WINDOWED
	)
	if DisplayServer.window_get_mode() != target_mode:
		DisplayServer.window_set_mode(target_mode)

func apply_all() -> void:
	apply_audio()
	apply_display()

func is_tutorial_needed(tutorial_id: StringName) -> bool:
	var key: String = String(tutorial_id)
	return tutorials_enabled and key != "" and not seen_tutorials.has(key)

func mark_tutorial_seen(tutorial_id: StringName) -> void:
	var key: String = String(tutorial_id)
	if key != "" and not seen_tutorials.has(key):
		seen_tutorials.append(key)
		changed.emit()

func reset_tutorials() -> void:
	seen_tutorials.clear()
	tutorials_enabled = true
	changed.emit()

