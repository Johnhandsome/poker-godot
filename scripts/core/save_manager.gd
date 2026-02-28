extends Node

const SAVE_FILE_PATH = "user://poker_save.json"

var human_chips: int = 5000
var games_played: int = 0

func _ready() -> void:
	load_data()

func load_data() -> void:
	if not FileAccess.file_exists(SAVE_FILE_PATH):
		print("Save file not found. Using defaults.")
		save_data() # Create initial save file
		return
		
	var file = FileAccess.open(SAVE_FILE_PATH, FileAccess.READ)
	if file:
		var content = file.get_as_text()
		var parse_result = JSON.parse_string(content)
		if parse_result is Dictionary:
			human_chips = parse_result.get("human_chips", 5000)
			games_played = parse_result.get("games_played", 0)
			print("Data loaded successfully. Chips: ", human_chips)
		else:
			print("Error parsing save file or invalid format.")
		file.close()

func save_data() -> void:
	var save_dict = {
		"human_chips": human_chips,
		"games_played": games_played
	}
	var file = FileAccess.open(SAVE_FILE_PATH, FileAccess.WRITE)
	if file:
		var json_string = JSON.stringify(save_dict, "\t")
		file.store_string(json_string)
		file.close()
		print("Data saved successfully.")

func get_chips() -> int:
	return human_chips

func update_chips(amount: int) -> void:
	human_chips = amount
	save_data()

func add_game_played() -> void:
	games_played += 1
	save_data()

func reset_save() -> void:
	human_chips = 5000
	games_played = 0
	save_data()
