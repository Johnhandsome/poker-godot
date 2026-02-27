class_name Deck
extends RefCounted

var cards: Array[Card] = []

func _init():
	reset()

func reset():
	cards.clear()
	for suit in Card.Suit.values():
		for rank in range(Card.Rank.TWO, Card.Rank.ACE + 1):
			cards.append(Card.new(suit as Card.Suit, rank as Card.Rank))

func shuffle():
	# Fisher-Yates shuffle
	for i in range(cards.size() - 1, 0, -1):
		var j = randi() % (i + 1)
		var temp = cards[i]
		cards[i] = cards[j]
		cards[j] = temp

func deal() -> Card:
	if cards.is_empty():
		return null
	return cards.pop_back()

func get_remaining_count() -> int:
	return cards.size()
