extends Node

## AudioManager: Управление аварийными кассетами (Music Tapes) и SFX (ADR-001 Section 2.3)

var _music_player: AudioStreamPlayer = null
var _sfx_players: Array[AudioStreamPlayer] = []
var _sfx_cache: Dictionary = {}
var current_tape_id: StringName = &""
var is_muted: bool = false

const SFX_PATHS: Dictionary = {
	"hit": "res://assets/audio/sfx/hit.wav",
	"laser": "res://assets/audio/sfx/laser.wav",
	"part_break": "res://assets/audio/sfx/part_break.wav",
	"qte_perfect": "res://assets/audio/sfx/qte_perfect.wav",
	"qte_good": "res://assets/audio/sfx/qte_good.wav",
	"qte_miss": "res://assets/audio/sfx/qte_miss.wav",
	"pyramid_siren": "res://assets/audio/sfx/pyramid_siren.wav",
	"ui_click": "res://assets/audio/sfx/ui_click.wav",
	"heal": "res://assets/audio/sfx/heal.wav"
}

func _ready() -> void:
	_music_player = AudioStreamPlayer.new()
	_music_player.volume_db = -9.0
	_music_player.finished.connect(_on_music_finished)
	add_child(_music_player)

	for i: int in range(6):
		var p: AudioStreamPlayer = AudioStreamPlayer.new()
		p.volume_db = -4.0
		add_child(p)
		_sfx_players.append(p)

	for sfx_key: Variant in SFX_PATHS.keys():
		var path: String = String(SFX_PATHS[sfx_key])
		if ResourceLoader.exists(path):
			var stream: AudioStream = ResourceLoader.load(path) as AudioStream
			if stream != null:
				_sfx_cache[String(sfx_key)] = stream

func _exit_tree() -> void:
	if _music_player != null:
		_music_player.stop()
		_music_player.stream = null
	for p: AudioStreamPlayer in _sfx_players:
		if p != null:
			p.stop()
			p.stream = null
	_sfx_cache.clear()

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
