extends Node

# Signal for UI updates
signal player_connected(peer_id, player_info)
signal player_disconnected(peer_id)
signal server_disconnected()
signal connection_failed()
signal game_started()

const PORT = 8910
const DEFAULT_SERVER_IP = "127.0.0.1"
const MAX_PLAYERS = 9

# Player info dictionary: { peer_id: { "name": "PlayerName", "id": 1 } }
var players = {}
var player_info = {"name": "Player"}

func _ready():
	multiplayer.peer_connected.connect(_on_player_connected)
	multiplayer.peer_disconnected.connect(_on_player_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_ok)
	multiplayer.connection_failed.connect(_on_connected_fail)
	multiplayer.server_disconnected.connect(_on_server_disconnected)

func host_game(player_name: String):
	var peer = ENetMultiplayerPeer.new()
	var error = peer.create_server(PORT, MAX_PLAYERS)
	if error != OK:
		print("Cannot host: " + str(error))
		return
		
	peer.host.compress(ENetConnection.COMPRESS_RANGE_CODER)
	multiplayer.multiplayer_peer = peer
	
	player_info["name"] = player_name
	players[1] = player_info
	emit_signal("player_connected", 1, player_info)
	print("Hosting on port " + str(PORT))

func join_game(address: String, player_name: String):
	if address.is_empty():
		address = DEFAULT_SERVER_IP
		
	var peer = ENetMultiplayerPeer.new()
	var error = peer.create_client(address, PORT)
	if error != OK:
		print("Cannot join: " + str(error))
		return
		
	peer.host.compress(ENetConnection.COMPRESS_RANGE_CODER)
	multiplayer.multiplayer_peer = peer
	player_info["name"] = player_name
	print("Joining " + address)

func _on_player_connected(id):
	# When a peer connects, send my info to them
	_register_player.rpc_id(id, player_info)

func _on_player_disconnected(id):
	players.erase(id)
	emit_signal("player_disconnected", id)

func _on_connected_ok():
	var peer_id = multiplayer.get_unique_id()
	players[peer_id] = player_info
	emit_signal("player_connected", peer_id, player_info)

func _on_connected_fail():
	multiplayer.multiplayer_peer = null
	emit_signal("connection_failed")

func _on_server_disconnected():
	multiplayer.multiplayer_peer = null
	players.clear()
	emit_signal("server_disconnected")

@rpc("any_peer", "reliable")
func _register_player(info):
	var new_player_id = multiplayer.get_remote_sender_id()
	players[new_player_id] = info
	emit_signal("player_connected", new_player_id, info)

@rpc("authority", "call_local", "reliable")
func start_game_rpc():
	emit_signal("game_started")
	# Load game scene
	get_tree().change_scene_to_file("res://scenes/main.tscn")

func start_game():
	start_game_rpc.rpc()
