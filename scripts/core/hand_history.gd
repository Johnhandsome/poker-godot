class_name HandHistory
extends RefCounted

# Stores a record of each completed hand for review

class HandRecord:
	var hand_number: int = 0
	var blinds: String = ""
	var players: Array = []  # Array of {id, hole_cards_str, chips_before, chips_after}
	var community_cards: String = ""
	var winner_id: String = ""
	var winning_hand: String = ""
	var pot_total: int = 0
	var actions: Array = []  # Array of {player_id, action_str, amount, street}
	
	func to_display_string() -> String:
		var s = "Hand #" + str(hand_number) + " | Blinds: " + blinds + "\n"
		s += "Board: " + community_cards + "\n"
		for a in actions:
			s += "  " + a["player_id"] + " " + a["action_str"]
			if a["amount"] > 0:
				s += " $" + str(a["amount"])
			s += " [" + a["street"] + "]\n"
		s += "Winner: " + winner_id + " — " + winning_hand + " (+$" + str(pot_total) + ")\n"
		return s

var history: Array[HandRecord] = []
var _current_hand: HandRecord = null
var _current_street: String = "Pre-Flop"
var max_history_size: int = 50

func start_new_hand(hand_num: int, blinds_str: String) -> void:
	_current_hand = HandRecord.new()
	_current_hand.hand_number = hand_num
	_current_hand.blinds = blinds_str
	_current_street = "Pre-Flop"

func set_street(street: String) -> void:
	_current_street = street

func record_action(player_id: String, action_str: String, amount: int = 0) -> void:
	if not _current_hand: return
	_current_hand.actions.append({
		"player_id": player_id,
		"action_str": action_str,
		"amount": amount,
		"street": _current_street
	})

func finish_hand(community_str: String, winner_id: String, winning_hand: String, pot: int) -> void:
	if not _current_hand: return
	_current_hand.community_cards = community_str
	_current_hand.winner_id = winner_id
	_current_hand.winning_hand = winning_hand
	_current_hand.pot_total = pot
	history.append(_current_hand)
	if history.size() > max_history_size:
		history.remove_at(0)
	_current_hand = null

func get_last_n(n: int) -> Array[HandRecord]:
	var start = max(0, history.size() - n)
	var result: Array[HandRecord] = []
	for i in range(start, history.size()):
		result.append(history[i])
	return result
