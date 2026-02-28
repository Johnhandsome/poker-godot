extends Node

signal settings_changed

const SAVE_PATH = "user://settings.json"

var master_volume: float = 1.0
var sfx_volume: float = 1.0
var bgm_volume: float = 0.5
var fast_bot_mode: bool = false
var num_bots: int = 4
var language: String = "en" # "en" or "vi"
var table_size: int = 6  # 6 or 9 for online mode
var last_game_mode: String = "practice"  # practice, friends, online

func _ready() -> void:
	load_settings()

func save_settings() -> void:
	var data = {
		"master_volume": master_volume,
		"sfx_volume": sfx_volume,
		"bgm_volume": bgm_volume,
		"fast_bot_mode": fast_bot_mode,
		"num_bots": num_bots,
		"language": language,
		"table_size": table_size,
		"last_game_mode": last_game_mode
	}
	
	var file = FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file:
		var json_string = JSON.stringify(data)
		file.store_string(json_string)
		file.close()

func load_settings() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		return # Use defaults
		
	var file = FileAccess.open(SAVE_PATH, FileAccess.READ)
	if file:
		var json_string = file.get_as_text()
		var json = JSON.new()
		var error = json.parse(json_string)
		if error == OK:
			var data = json.get_data()
			if typeof(data) == TYPE_DICTIONARY:
				if data.has("master_volume"): master_volume = data["master_volume"]
				if data.has("sfx_volume"): sfx_volume = data["sfx_volume"]
				if data.has("bgm_volume"): bgm_volume = data["bgm_volume"]
				if data.has("fast_bot_mode"): fast_bot_mode = data["fast_bot_mode"]
				if data.has("num_bots"): num_bots = int(data["num_bots"])
				if data.has("language"): language = data["language"]
				if data.has("table_size"): table_size = int(data["table_size"])
				if data.has("last_game_mode"): last_game_mode = data["last_game_mode"]
		file.close()

func apply_and_save() -> void:
	save_settings()
	emit_signal("settings_changed")

func tc(en: String, vi: String) -> String:
	if language == "en": return en
	return vi
