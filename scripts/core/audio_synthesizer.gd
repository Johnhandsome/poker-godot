extends Node

# A procedural audio synthesizer for creating sound effects mathematically.
# Uses AudioStreamWAV to bake generated waveforms for zero-latency playback.

var players_pool = []
var pool_size = 8
var cached_sounds = {}

func _ready() -> void:
	# Khởi tạo pool với nhiều player để phát đè âm thanh
	for i in range(pool_size):
		var p = AudioStreamPlayer.new()
		add_child(p)
		players_pool.append(p)
		
	# Bake âm thanh sẵn vào bộ nhớ (WAV format)
	cached_sounds["click"] = _generate_wav("click", 0.05, 0.4)
	cached_sounds["clink"] = _generate_wav("clink", 0.08, 0.6)
	cached_sounds["slide"] = _generate_wav("slide", 0.15, 0.2)
	cached_sounds["win"] = _generate_wav("win", 1.5, 0.5)

func _get_available_player() -> AudioStreamPlayer:
	for p in players_pool:
		if not p.playing:
			return p
	# Nếu tất cả đều bận, mượn cái đầu tiên ngắt ngang
	var player = players_pool[0]
	player.stop()
	return player

func play_ui_click() -> void:
	_play_cached("click")

func play_chip_clink() -> void:
	_play_cached("clink")

func play_card_slide() -> void:
	_play_cached("slide")
	
func play_win() -> void:
	_play_cached("win")

# Hàm chạy tự động lấy từ Cache
func _play_cached(type: String) -> void:
	if not cached_sounds.has(type): return
	var player = _get_available_player()
	player.stream = cached_sounds[type]
	
	# Tính toán volume theo SettingsManager
	var db_volume = 0.0
	if has_node("/root/SettingsManager"):
		var sm = get_node("/root/SettingsManager")
		var target_linear = sm.master_volume * sm.sfx_volume
		if target_linear <= 0.01:
			db_volume = -80.0
		else:
			db_volume = linear_to_db(target_linear)
			
	player.volume_db = db_volume
	player.play()

# --- Procedural Synthesis Heart ---
# Generate âm thanh và lưu thành AudioStreamWAV trên RAM
func _generate_wav(type: String, duration: float, volume: float) -> AudioStreamWAV:
	var sample_hz = 44100
	var num_frames = int(sample_hz * duration)
	var data = PackedByteArray()
	data.resize(num_frames * 2) # 16-bit PCM = 2 bytes per frame (Mono)
	
	for i in range(num_frames):
		var time = float(i) / sample_hz
		var sample_val = 0.0
		var envelope = 1.0
		
		match type:
			"click":
				# Xung vuông ngắn tạo tiếng Click gọn
				sample_val = 1.0 if fmod(time * 800.0, 1.0) > 0.5 else -1.0
				envelope = exp(-time * 40.0) # Tắt tiếng rất nhanh
				
			"clink":
				# Tiếng nhựa va chạm bằng cách trộn sóng tần số rất cao
				var s1 = sin(time * 2.0 * PI * 3500.0)
				var s2 = sin(time * 2.0 * PI * 5200.0)
				sample_val = (s1 + s2) * 0.5
				envelope = exp(-time * 30.0) # Vang ngắn
				
			"slide":
				# Tiếng bài cọ vào bàn (White noise có chọn lọc)
				sample_val = randf_range(-1.0, 1.0)
				# Lọc bớt tần số chói (Low pass giả lập)
				sample_val = sample_val * 0.5 + sin(time * 2.0 * PI * 800.0) * 0.1
				# Envelope vuốt lên rồi vuốt xuống mượt mà (Attack & Decay)
				envelope = sin((time / duration) * PI) 
				
			"win":
				# Tiếng chuông báo hiệu chiến thắng (Vibraphone/Bell chord)
				var f1 = sin(time * 2.0 * PI * 440.0) # Nốt A4
				var f2 = sin(time * 2.0 * PI * 554.37) # Nốt C#5
				var f3 = sin(time * 2.0 * PI * 659.25) # Nốt E5
				sample_val = (f1 + f2 + f3) * 0.33
				envelope = exp(-time * 2.5) # Ngân dài
				
		sample_val *= envelope * volume
		# Kẹp chống vỡ tiếng (Clipping)
		sample_val = clamp(sample_val, -1.0, 1.0)
		
		var int_val = int(sample_val * 32767.0)
		
		# Ghi byte (Little Endian 16-bit)
		var byte_idx = i * 2
		data[byte_idx] = int_val & 0xFF
		data[byte_idx + 1] = (int_val >> 8) & 0xFF
		
	var stream = AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = sample_hz
	stream.data = data
	return stream
