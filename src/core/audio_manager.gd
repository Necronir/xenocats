extends Node

## AudioManager: Управление аварийными кассетами (Music Tapes) и SFX (ADR-001 Section 2.3)

var _music_player: AudioStreamPlayer = null
var _sfx_players: Array[AudioStreamPlayer] = []
var _sfx_cache: Dictionary = {}
var _theme_cache: Dictionary = {}
var current_tape_id: StringName = &""
var current_theme_id: StringName = &""
var current_story_stage: int = 0
var active_instruments: Array[String] = []
var last_sfx_played: String = ""
var is_muted: bool = false
var is_pause_ducked: bool = false

const BUS_MASTER: StringName = &"Master"
const BUS_MUSIC: StringName = &"Music"
const BUS_SFX: StringName = &"SFX"

const SFX_PATHS: Dictionary = {
	"hit": "res://assets/audio/sfx/hit.wav",
	"laser": "res://assets/audio/sfx/laser.wav",
	"part_break": "res://assets/audio/sfx/part_break.wav",
	"qte_perfect": "res://assets/audio/sfx/qte_perfect.wav",
	"qte_good": "res://assets/audio/sfx/qte_good.wav",
	"qte_miss": "res://assets/audio/sfx/qte_miss.wav",
	"pyramid_siren": "res://assets/audio/sfx/pyramid_siren.wav",
	"pyramid_undock": "res://assets/audio/sfx/pyramid_undock.wav",
	"ui_click": "res://assets/audio/sfx/ui_click.wav",
	"heal": "res://assets/audio/sfx/heal.wav"
}

const CHAR_THEME_PATHS: Dictionary = {
	"FELIX": "res://assets/audio/themes/theme_felix_guitar.wav",
	"MULE": "res://assets/audio/themes/theme_mule_bass.wav",
	"HOUND": "res://assets/audio/themes/theme_hound_drums.wav",
	"COCK": "res://assets/audio/themes/theme_cock_synth.wav",
	"DUO": "res://assets/audio/themes/theme_duo_cat_hound.wav",
	"TRIO": "res://assets/audio/themes/theme_trio_cat_hound_mule.wav",
	"ENSEMBLE": "res://assets/audio/themes/theme_bremen_ensemble.wav",
	"PYRAMID_2": "res://assets/audio/themes/theme_pyramid_2.wav",
	"PYRAMID_3": "res://assets/audio/themes/theme_pyramid_3.wav",
	"PYRAMID_4": "res://assets/audio/themes/theme_pyramid_4.wav",
	"BOSS_1": "res://assets/audio/themes/theme_boss_sector1.wav",
	"BOSS_2": "res://assets/audio/themes/theme_boss_sector2.wav",
	"BOSS_3": "res://assets/audio/themes/theme_boss_sector3.wav"
}

const CHAR_INSTRUMENTS: Dictionary = {
	"FELIX": "Гитара",
	"MULE": "Бас",
	"HOUND": "Барабан",
	"COCK": "Синтезатор",
	"PYRAMID": "Резонатор «Бремен»"
}

const STORY_STAGE_CONFIG: Dictionary = {
	1: {
		"key": "FELIX",
		"instruments": ["Гитара"]
	},
	2: {
		"key": "DUO",
		"instruments": ["Гитара", "Барабан"]
	},
	3: {
		"key": "TRIO",
		"instruments": ["Гитара", "Барабан", "Бас"]
	},
	4: {
		"key": "ENSEMBLE",
		"instruments": ["Гитара", "Барабан", "Бас", "Синтезатор"]
	}
}

const PYRAMID_STAGE_CONFIG: Dictionary = {
	2: {
		"key": "PYRAMID_2",
		"instruments": ["Гитара", "Барабан", "Резонатор «Бремен»"]
	},
	3: {
		"key": "PYRAMID_3",
		"instruments": ["Гитара", "Барабан", "Бас", "Резонатор «Бремен»"]
	},
	4: {
		"key": "PYRAMID_4",
		"instruments": ["Гитара", "Барабан", "Бас", "Синтезатор", "Резонатор «Бремен»"]
	}
}

const BOSS_STAGE_CONFIG: Dictionary = {
	1: {
		"key": "BOSS_1",
		"instruments": ["Гитара", "Барабан"]
	},
	2: {
		"key": "BOSS_2",
		"instruments": ["Гитара", "Барабан", "Бас"]
	},
	3: {
		"key": "BOSS_3",
		"instruments": ["Гитара", "Барабан", "Бас", "Синтезатор"]
	}
}

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_ensure_audio_buses()

	_music_player = AudioStreamPlayer.new()
	_music_player.bus = BUS_MUSIC
	_music_player.volume_db = -9.0
	_music_player.finished.connect(_on_music_finished)
	add_child(_music_player)

	for i: int in range(6):
		var p: AudioStreamPlayer = AudioStreamPlayer.new()
		p.bus = BUS_SFX
		p.volume_db = -4.0
		add_child(p)
		_sfx_players.append(p)

	if SaveManager.settings != null:
		SaveManager.settings.apply_audio()

	for sfx_key: Variant in SFX_PATHS.keys():
		var path: String = String(SFX_PATHS[sfx_key])
		if ResourceLoader.exists(path):
			var stream: AudioStream = ResourceLoader.load(path) as AudioStream
			if stream != null:
				_sfx_cache[String(sfx_key)] = stream

	for theme_key: Variant in CHAR_THEME_PATHS.keys():
		var t_path: String = String(CHAR_THEME_PATHS[theme_key])
		if ResourceLoader.exists(t_path):
			var t_stream: AudioStream = ResourceLoader.load(t_path) as AudioStream
			if t_stream != null:
				_theme_cache[String(theme_key)] = t_stream

func _exit_tree() -> void:
	if _music_player != null:
		_music_player.stop()
		_music_player.stream = null
	for p: AudioStreamPlayer in _sfx_players:
		if p != null:
			p.stop()
			p.stream = null
	_sfx_cache.clear()
	_theme_cache.clear()

func get_character_instrument(cat_id: StringName) -> String:
	var key: String = String(cat_id).to_upper()
	return String(CHAR_INSTRUMENTS.get(key, "Гитара"))

func get_character_theme_path(cat_id: StringName) -> String:
	var key: String = String(cat_id).to_upper()
	return String(CHAR_THEME_PATHS.get(key, CHAR_THEME_PATHS["FELIX"]))

func play_story_stage(stage: int) -> void:
	var clamped_stage: int = clampi(stage, 1, 4)
	var cfg: Dictionary = STORY_STAGE_CONFIG[clamped_stage] as Dictionary
	var key: String = String(cfg["key"])
	var inst_list: Array[String] = []
	for item_str: Variant in cfg["instruments"] as Array:
		inst_list.append(String(item_str))

	var stage_changed: bool = (current_story_stage != clamped_stage) or (current_theme_id != StringName(key))
	current_story_stage = clamped_stage
	current_theme_id = StringName(key)
	active_instruments = inst_list
	if stage_changed:
		EventBus.character_theme_changed.emit(current_theme_id, active_instruments)

	if is_muted or DisplayServer.get_name() == "headless":
		return
	var stream: AudioStream = _theme_cache.get(key, null) as AudioStream
	if stream == null:
		var path: String = String(CHAR_THEME_PATHS[key])
		if ResourceLoader.exists(path):
			stream = ResourceLoader.load(path) as AudioStream
	if stream != null and _music_player != null:
		if _music_player.stream == stream and _music_player.playing:
			return
		var pos: float = _music_player.get_playback_position() if _music_player.playing else 0.0
		_music_player.stream = stream
		_music_player.play(pos)

func sync_music_to_party(party_cats: Array = []) -> void:
	var count: int = party_cats.size()
	if count <= 0:
		count = SaveManager.party.size()
	play_story_stage(clampi(maxi(1, count), 1, 4))

func play_pyramid_theme(tier: int = 4) -> void:
	var clamped_tier: int = clampi(tier, 2, 4)
	var cfg: Dictionary = PYRAMID_STAGE_CONFIG[clamped_tier] as Dictionary
	var key: String = String(cfg["key"])
	var inst_list: Array[String] = []
	for item_str: Variant in cfg["instruments"] as Array:
		inst_list.append(String(item_str))

	var theme_changed: bool = (current_theme_id != StringName(key))
	current_theme_id = StringName(key)
	active_instruments = inst_list
	if theme_changed:
		EventBus.character_theme_changed.emit(current_theme_id, active_instruments)

	if is_muted or DisplayServer.get_name() == "headless":
		return
	var stream: AudioStream = _theme_cache.get(key, null) as AudioStream
	if stream == null:
		var path: String = String(CHAR_THEME_PATHS[key])
		if ResourceLoader.exists(path):
			stream = ResourceLoader.load(path) as AudioStream
	if stream != null and _music_player != null:
		if _music_player.stream == stream and _music_player.playing:
			return
		var pos: float = _music_player.get_playback_position() if _music_player.playing else 0.0
		_music_player.stream = stream
		_music_player.play(pos)

func play_boss_theme(sector: int = 1) -> void:
	var clamped_sec: int = clampi(sector, 1, 3)
	var cfg: Dictionary = BOSS_STAGE_CONFIG[clamped_sec] as Dictionary
	var key: String = String(cfg["key"])
	var inst_list: Array[String] = []
	for item_str: Variant in cfg["instruments"] as Array:
		inst_list.append(String(item_str))

	var theme_changed: bool = (current_theme_id != StringName(key))
	current_story_stage = clamped_sec + 1
	current_theme_id = StringName(key)
	active_instruments = inst_list
	if theme_changed:
		EventBus.character_theme_changed.emit(current_theme_id, active_instruments)

	if is_muted or DisplayServer.get_name() == "headless":
		return
	var stream: AudioStream = _theme_cache.get(key, null) as AudioStream
	if stream == null:
		var path: String = String(CHAR_THEME_PATHS[key])
		if ResourceLoader.exists(path):
			stream = ResourceLoader.load(path) as AudioStream
	if stream != null and _music_player != null:
		if _music_player.stream == stream and _music_player.playing:
			return
		var pos: float = _music_player.get_playback_position() if _music_player.playing else 0.0
		_music_player.stream = stream
		_music_player.play(pos)

func play_character_theme(cat_id: StringName) -> void:
	var key: String = String(cat_id).to_upper()
	if not CHAR_THEME_PATHS.has(key):
		key = "FELIX"
	current_story_stage = 1 if key == "FELIX" else 0
	current_theme_id = StringName(key)
	active_instruments = [get_character_instrument(current_theme_id)]
	EventBus.character_theme_changed.emit(current_theme_id, active_instruments)
	if is_muted or DisplayServer.get_name() == "headless":
		return
	var stream: AudioStream = _theme_cache.get(key, null) as AudioStream
	if stream == null:
		var path: String = String(CHAR_THEME_PATHS[key])
		if ResourceLoader.exists(path):
			stream = ResourceLoader.load(path) as AudioStream
	if stream != null and _music_player != null:
		if _music_player.stream != stream or not _music_player.playing:
			_music_player.stream = stream
			_music_player.play()

func play_ensemble_theme(_party_cats: Array = []) -> void:
	play_story_stage(4)

func play_tape(tape_id: StringName) -> void:
	current_tape_id = tape_id
	var tape: MusicTapeData = DataCatalog.get_tape(String(tape_id))
	if tape == null or is_muted or DisplayServer.get_name() == "headless":
		return
	if ResourceLoader.exists(tape.track_path):
		var stream: AudioStream = ResourceLoader.load(tape.track_path) as AudioStream
		if stream != null:
			_music_player.stream = stream
			_music_player.play()
	EventBus.music_tape_changed.emit(tape_id)

func stop_music() -> void:
	if _music_player != null:
		_music_player.stop()

func _on_music_finished() -> void:
	if not is_muted and _music_player.stream != null:
		_music_player.play()

func play_sfx(sfx_name: String) -> void:
	last_sfx_played = sfx_name
	if is_muted or DisplayServer.get_name() == "headless":
		return
	var stream: AudioStream = _sfx_cache.get(sfx_name, null) as AudioStream
	if stream == null:
		return
	for p: AudioStreamPlayer in _sfx_players:
		if not p.playing:
			p.stream = stream
			p.play()
			return
	_sfx_players[0].stream = stream
	_sfx_players[0].play()

func _ensure_audio_buses() -> void:
	var music_idx: int = AudioServer.get_bus_index(BUS_MUSIC)
	if music_idx < 0:
		music_idx = AudioServer.bus_count
		AudioServer.add_bus(music_idx)
		AudioServer.set_bus_name(music_idx, String(BUS_MUSIC))
		AudioServer.set_bus_send(music_idx, BUS_MASTER)

	if AudioServer.get_bus_effect_count(music_idx) < 2:
		while AudioServer.get_bus_effect_count(music_idx) > 0:
			AudioServer.remove_bus_effect(music_idx, 0)
		var lpf: AudioEffectLowPassFilter = AudioEffectLowPassFilter.new()
		lpf.cutoff_hz = 900.0
		AudioServer.add_bus_effect(music_idx, lpf, 0)
		AudioServer.set_bus_effect_enabled(music_idx, 0, is_pause_ducked)

		var amp: AudioEffectAmplify = AudioEffectAmplify.new()
		amp.volume_db = -8.0
		AudioServer.add_bus_effect(music_idx, amp, 1)
		AudioServer.set_bus_effect_enabled(music_idx, 1, is_pause_ducked)

	var sfx_idx: int = AudioServer.get_bus_index(BUS_SFX)
	if sfx_idx < 0:
		sfx_idx = AudioServer.bus_count
		AudioServer.add_bus(sfx_idx)
		AudioServer.set_bus_name(sfx_idx, String(BUS_SFX))
		AudioServer.set_bus_send(sfx_idx, BUS_MASTER)

func set_pause_duck(enabled: bool) -> void:
	is_pause_ducked = enabled
	_ensure_audio_buses()
	var music_idx: int = AudioServer.get_bus_index(BUS_MUSIC)
	if music_idx >= 0:
		for fx_i: int in range(AudioServer.get_bus_effect_count(music_idx)):
			AudioServer.set_bus_effect_enabled(music_idx, fx_i, enabled)

