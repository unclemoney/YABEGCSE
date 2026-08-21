extends Node

## AudioManager (autoload)
##
## M7: level music (looping) and one-shot sounds, referenced as
## library-relative WAV base names and resolved against the art library —
## the same convention as art references. Missing files return false and
## the caller logs to the debug panel (tolerate + flag). No mixing knobs:
## the preference surface stays minimalist.

var _music_player: AudioStreamPlayer


func _ready() -> void:
	_music_player = AudioStreamPlayer.new()
	_music_player.name = "MusicPlayer"
	add_child(_music_player)


## play_music(base) -> bool
##
## Loops the library WAV `base`. Already playing the same track = no-op.
func play_music(base: String) -> bool:
	var stream := _load_wav(base)
	if stream == null:
		return false
	if _music_player.stream == stream and _music_player.playing:
		return true
	_music_player.stream = stream
	_music_player.play()
	return true


func stop_music() -> void:
	_music_player.stop()


## play_sound(base) -> bool
##
## One-shot; the player node frees itself when finished.
func play_sound(base: String) -> bool:
	var stream := _load_wav(base)
	if stream == null:
		return false
	var player := AudioStreamPlayer.new()
	add_child(player)
	player.stream = stream
	player.finished.connect(player.queue_free)
	player.play()
	return true


func _load_wav(base: String) -> AudioStream:
	if base.is_empty():
		return null
	var path := ArtCache.LIBRARY_ROOT + base + ".wav"
	if not ResourceLoader.exists(path):
		return null
	var stream: AudioStream = ResourceLoader.load(path)
	if stream is AudioStreamWAV:
		var wav := stream as AudioStreamWAV
		# Loop settings live in the import; force a full-stream forward
		# loop so music behaves like the GCS MIDI loop regardless of
		# import flags (a default loop_end of 0 means no loop).
		wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
		wav.loop_begin = 0
		wav.loop_end = int(wav.get_length() * float(wav.mix_rate))
	return stream
