class_name AudioBank
extends Node

# ============================================================
# AudioBank.gd
# 効果音をコードで合成して鳴らす（外部音声ファイル不要）。
# 鳴らすか否か（alarm_on / sfx_on）の判定は呼び出し側(Main)が行う。
# ============================================================

var _alert: AudioStreamPlayer
var _attack: AudioStreamPlayer
var _heal: AudioStreamPlayer


func _ready() -> void:
	_alert = _make_player(_make_beep(880.0, 0.18, 0.5))
	_attack = _make_player(_make_beep(190.0, 0.06, 0.25))
	_heal = _make_player(_make_beep(620.0, 0.14, 0.30))


func play_alert() -> void:
	if _alert:
		_alert.play()


func play_attack() -> void:
	if _attack:
		_attack.play()


func play_heal() -> void:
	if _heal:
		_heal.play()


func _make_player(stream: AudioStream) -> AudioStreamPlayer:
	var p: AudioStreamPlayer = AudioStreamPlayer.new()
	p.stream = stream
	add_child(p)
	return p


func _make_beep(freq: float, secs: float, volume: float) -> AudioStreamWAV:
	var rate: int = 22050
	var count: int = int(rate * secs)
	var data: PackedByteArray = PackedByteArray()
	data.resize(count * 2)
	for i in count:
		var t: float = float(i) / float(rate)
		var env: float = 1.0 - (float(i) / float(count))
		var s: float = sin(TAU * freq * t) * volume * env
		var v: int = int(clamp(s, -1.0, 1.0) * 32767.0)
		data.encode_s16(i * 2, v)
	var wav: AudioStreamWAV = AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = rate
	wav.stereo = false
	wav.data = data
	return wav
