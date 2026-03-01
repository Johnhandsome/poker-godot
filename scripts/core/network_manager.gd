extends Node

# =================================================================
# NETWORK MANAGER — Production multiplayer (ENet)
# =================================================================

signal player_connected(peer_id: int, player_info: Dictionary)
signal player_disconnected(peer_id: int)
signal server_disconnected()
signal connection_failed()
signal game_started()
signal chat_received(sender: String, message: String)
signal ping_updated(ms: int)

const PORT = 9050
const DEFAULT_SERVER_IP = "127.0.0.1"
const MAX_PLAYERS = 9
const HEARTBEAT_INTERVAL = 3.0

var players: Dictionary = {}          # peer_id -> { "name": "...", ... }
var player_info: Dictionary = {"name": "Player"}
var _heartbeat_timer: Timer
var _last_pong_time: float = 0.0
var _ping_ms: int = 0

func _ready() -> void:
	multiplayer.peer_connected.connect(_on_player_connected)
	multiplayer.peer_disconnected.connect(_on_player_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_ok)
	multiplayer.connection_failed.connect(_on_connected_fail)
	multiplayer.server_disconnected.connect(_on_server_disconnected)

	# Heartbeat timer — keeps connection alive, measures latency
	_heartbeat_timer = Timer.new()
	_heartbeat_timer.wait_time = HEARTBEAT_INTERVAL
	_heartbeat_timer.timeout.connect(_send_heartbeat)
	add_child(_heartbeat_timer)

# ============================================================
# HOST / JOIN
# ============================================================
func host_game(player_name: String) -> Error:
	var peer = ENetMultiplayerPeer.new()
	var error = peer.create_server(PORT, MAX_PLAYERS)
	if error != OK:
		push_warning("NetworkManager: Cannot host — " + error_string(error))
		return error
	peer.host.compress(ENetConnection.COMPRESS_RANGE_CODER)
	multiplayer.multiplayer_peer = peer
	player_info["name"] = player_name
	players[1] = player_info.duplicate()
	player_connected.emit(1, player_info)
	_heartbeat_timer.start()
	print("Hosting on port ", PORT)
	return OK

func join_game(address: String, player_name: String) -> Error:
	if address.strip_edges().is_empty():
		address = DEFAULT_SERVER_IP
	var peer = ENetMultiplayerPeer.new()
	var error = peer.create_client(address, PORT)
	if error != OK:
		push_warning("NetworkManager: Cannot join — " + error_string(error))
		return error
	peer.host.compress(ENetConnection.COMPRESS_RANGE_CODER)
	multiplayer.multiplayer_peer = peer
	player_info["name"] = player_name
	_heartbeat_timer.start()
	print("Joining ", address, ":", PORT)
	return OK

# ============================================================
# PEER CALLBACKS
# ============================================================
func _on_player_connected(id: int) -> void:
	_register_player.rpc_id(id, player_info)

func _on_player_disconnected(id: int) -> void:
	var pname = players.get(id, {}).get("name", str(id))
	players.erase(id)
	player_disconnected.emit(id)
	print("Player disconnected: ", pname, " (", id, ")")

func _on_connected_ok() -> void:
	var peer_id = multiplayer.get_unique_id()
	players[peer_id] = player_info.duplicate()
	player_connected.emit(peer_id, player_info)

func _on_connected_fail() -> void:
	multiplayer.multiplayer_peer = null
	_heartbeat_timer.stop()
	connection_failed.emit()

func _on_server_disconnected() -> void:
	multiplayer.multiplayer_peer = null
	players.clear()
	_heartbeat_timer.stop()
	server_disconnected.emit()

# ============================================================
# PLAYER REGISTRATION
# ============================================================
@rpc("any_peer", "reliable")
func _register_player(info: Dictionary) -> void:
	var new_id = multiplayer.get_remote_sender_id()
	players[new_id] = info
	player_connected.emit(new_id, info)
	print("Registered: ", info.get("name", "?"), " id=", new_id)

# ============================================================
# START GAME
# ============================================================
func start_game() -> void:
	if not multiplayer.is_server(): return
	# Sync game mode and table size to all clients before scene change
	var gm = get_node("/root/GameManager") if has_node("/root/GameManager") else null
	var mode_int = gm.game_mode if gm else 0
	var t_size = gm.table_size if gm else 6
	_sync_game_mode.rpc(mode_int, t_size)
	start_game_rpc.rpc()

@rpc("authority", "call_local", "reliable")
func _sync_game_mode(mode_int: int, t_size: int) -> void:
	var gm = get_node("/root/GameManager") if has_node("/root/GameManager") else null
	if gm:
		gm.game_mode = mode_int as GameManager.GameMode
		gm.table_size = t_size

@rpc("authority", "call_local", "reliable")
func start_game_rpc() -> void:
	game_started.emit()
	get_tree().change_scene_to_file("res://scenes/main.tscn")

# ============================================================
# CHAT
# ============================================================
func send_chat(sender_name: String, message: String) -> void:
	if message.strip_edges().is_empty(): return
	_broadcast_chat.rpc(sender_name, message)

@rpc("any_peer", "reliable")
func _broadcast_chat(sender_name: String, message: String) -> void:
	chat_received.emit(sender_name, message)

# ============================================================
# HEARTBEAT / PING
# ============================================================
func _send_heartbeat() -> void:
	if not multiplayer.has_multiplayer_peer(): return
	if multiplayer.multiplayer_peer.get_connection_status() != MultiplayerPeer.CONNECTION_CONNECTED:
		return
	_last_pong_time = Time.get_ticks_msec()
	_ping_rpc.rpc()

@rpc("any_peer", "unreliable")
func _ping_rpc() -> void:
	_pong_rpc.rpc_id(multiplayer.get_remote_sender_id())

@rpc("any_peer", "unreliable")
func _pong_rpc() -> void:
	_ping_ms = Time.get_ticks_msec() - int(_last_pong_time)
	ping_updated.emit(_ping_ms)

func get_ping() -> int:
	return _ping_ms

# ============================================================
# UTILITIES
# ============================================================
func get_player_name(peer_id: int) -> String:
	return players.get(peer_id, {}).get("name", "Player " + str(peer_id))

func get_player_count() -> int:
	return players.size()

func is_host() -> bool:
	return multiplayer.has_multiplayer_peer() and multiplayer.is_server()
