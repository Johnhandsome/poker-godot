class_name Player
extends Node

var id: String
var chips: int = 1000
var current_bet: int = 0
var is_folded: bool = false
var is_all_in: bool = false
var is_eliminated: bool = false
var hole_cards: Array[Card] = []
var hand_result: HandEvaluator.EvaluationResult = null

# Node 3D vị trí ngồi của người chơi để ném chip/bài từ đây
var seat_position: Vector3 = Vector3.ZERO
var is_ai: bool = false

signal card_drawn(card: Card)

func _init(p_id: String, initial_chips: int = 1000):
	id = p_id
	chips = initial_chips

func reset_for_new_round() -> void:
	current_bet = 0
	is_folded = false
	is_all_in = false
	hole_cards.clear()
	hand_result = null

func draw_card(card: Card) -> void:
	hole_cards.append(card)
	# Tín hiệu cho UI hoặc hệ thống vật lý để spawn PhysicalCard
	card_drawn.emit(card)

# Virtual function để AI hoặc Human xử lý
func request_action(_current_table_bet: int, _min_raise: int) -> void:
	pass
