extends Node

signal settings_changed

const SAVE_PATH = "user://settings.json"

var master_volume: float = 1.0
var sfx_volume: float = 1.0
var bgm_volume: float = 0.5
var fast_bot_mode: bool = false
var num_bots: int = 4

func _ready() -> void:
	load_settings()

func save_settings() -> void:
	var data = {
		"master_volume": master_volume,
		"sfx_volume": sfx_volume,
		"bgm_volume": bgm_volume,
		"fast_bot_mode": fast_bot_mode,
		"num_bots": num_bots
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
		file.close()

func apply_and_save() -> void:
	save_settings()
	emit_signal("settings_changed")
