class_name HandEvaluator
extends RefCounted

enum HandRank {
	HIGH_CARD,
	PAIR,
	TWO_PAIR,
	THREE_OF_A_KIND,
	STRAIGHT,
	FLUSH,
	FULL_HOUSE,
	FOUR_OF_A_KIND,
	STRAIGHT_FLUSH,
	ROYAL_FLUSH
}

class EvaluationResult:
	var rank: HandRank
	var kickers: Array[int] = [] # Values ordered by importance, e.g., Pair rank, then kickers
	var best_cards: Array[Card] = []
	
	func compare_to(other: EvaluationResult) -> int:
		if rank > other.rank:
			return 1
		elif rank < other.rank:
			return -1
			
		# Same rank, compare kickers
		for i in range(min(kickers.size(), other.kickers.size())):
			if kickers[i] > other.kickers[i]:
				return 1
			elif kickers[i] < other.kickers[i]:
				return -1
		return 0

static func evaluate(hole_cards: Array[Card], community_cards: Array[Card]) -> EvaluationResult:
	var all_cards = hole_cards.duplicate()
	all_cards.append_array(community_cards)
	
	# Sort cards by value descending
	all_cards.sort_custom(func(a: Card, b: Card) -> bool: return a.get_value() > b.get_value())
	
	var result = EvaluationResult.new()
	
	# Check for Flush and Straight
	var flush_cards: Array[Card] = _get_flush_cards(all_cards)
	var is_flush = flush_cards.size() >= 5
	
	var straight_cards: Array[Card] = _get_straight_cards(all_cards)
	var is_straight = straight_cards.size() >= 5
	
	if is_flush and is_straight:
		# Check for Straight Flush (flush cards that form a straight)
		var straight_flush_cards: Array[Card] = _get_straight_cards(flush_cards)
		if straight_flush_cards.size() >= 5:
			result.best_cards = straight_flush_cards.slice(0, 5)
			# Special case for Royal Flush
			if result.best_cards[0].get_value() == Card.Rank.ACE and result.best_cards[4].get_value() == Card.Rank.TEN:
				result.rank = HandRank.ROYAL_FLUSH
			else:
				result.rank = HandRank.STRAIGHT_FLUSH
			result.kickers = [result.best_cards[0].get_value()]
			return result
			
	# Count frequencies
	var value_counts = {}
	for card in all_cards:
		var val = card.get_value()
		if value_counts.has(val):
			value_counts[val] += 1
		else:
			value_counts[val] = 1
			
	var pairs = []
	var three_of_a_kind = -1
	var four_of_a_kind = -1
	
	for val in value_counts.keys():
		var count = value_counts[val]
		if count == 4:
			four_of_a_kind = val
		elif count == 3:
			# We only track the highest three of a kind if there are multiple
			if val > three_of_a_kind:
				if three_of_a_kind != -1: # Move the smaller 3-of-a-kind to pairs to help with full house
					pairs.append(three_of_a_kind)
				three_of_a_kind = val
			else:
				pairs.append(val)
		elif count == 2:
			pairs.append(val)
			
	pairs.sort_custom(func(a: int, b: int) -> bool: return a > b)
	
	# Check Four of a Kind
	if four_of_a_kind != -1:
		result.rank = HandRank.FOUR_OF_A_KIND
		result.kickers = [four_of_a_kind]
		# Find highest kicker
		for card in all_cards:
			if card.get_value() != four_of_a_kind:
				result.kickers.append(card.get_value())
				break
		return result
		
	# Check Full House
	if three_of_a_kind != -1 and pairs.size() > 0:
		result.rank = HandRank.FULL_HOUSE
		result.kickers.clear()
		result.kickers.append(three_of_a_kind)
		result.kickers.append(pairs[0])
		return result
		
	# Check Flush
	if is_flush:
		result.rank = HandRank.FLUSH
		result.best_cards = flush_cards.slice(0, 5)
		for i in range(5):
			result.kickers.append(result.best_cards[i].get_value())
		return result
		
	# Check Straight
	if is_straight:
		result.rank = HandRank.STRAIGHT
		result.best_cards = straight_cards.slice(0, 5)
		result.kickers.append(result.best_cards[0].get_value())
		# Check low Ace straight exception (5,4,3,2,A) where 5 is the highest
		if result.best_cards[0].get_value() == 5 and result.best_cards[4].get_value() == Card.Rank.ACE:
			result.kickers.clear()
			result.kickers.append(5) # The 5 is the top of the straight
		return result
		
	# Check Three of a Kind
	if three_of_a_kind != -1:
		result.rank = HandRank.THREE_OF_A_KIND
		result.kickers.append(three_of_a_kind)
		var added_kickers = 0
		for card in all_cards:
			if card.get_value() != three_of_a_kind:
				result.kickers.append(card.get_value())
				added_kickers += 1
				if added_kickers == 2: break
		return result
		
	# Check Two Pair
	if pairs.size() >= 2:
		result.rank = HandRank.TWO_PAIR
		result.kickers.append(pairs[0])
		result.kickers.append(pairs[1])
		# Find the best 5th card that is NOT part of the two pairs
		for card in all_cards:
			var val = card.get_value()
			if val != pairs[0] and val != pairs[1]:
				result.kickers.append(val)
				break
		return result
		
	# Check Pair
	if pairs.size() == 1:
		result.rank = HandRank.PAIR
		result.kickers.append(pairs[0])
		var added_kickers = 0
		for card in all_cards:
			if card.get_value() != pairs[0]:
				result.kickers.append(card.get_value())
				added_kickers += 1
				if added_kickers == 3: break
		return result
		
	# High Card
	result.rank = HandRank.HIGH_CARD
	for i in range(5):
		if i < all_cards.size():
			result.kickers.append(all_cards[i].get_value())
			
	return result

static func _get_flush_cards(cards: Array[Card]) -> Array[Card]:
	var suit_buckets: Dictionary = {}
	for card in cards:
		var s = card.suit
		if not suit_buckets.has(s):
			suit_buckets[s] = []
		suit_buckets[s].append(card)
		
	for suit in suit_buckets:
		if suit_buckets[suit].size() >= 5:
			var result: Array[Card] = []
			for c in suit_buckets[suit]:
				result.append(c as Card)
			# Sort by value DESC
			result.sort_custom(func(a: Card, b: Card) -> bool: return a.get_value() > b.get_value())
			return result
	var empty: Array[Card] = []
	return empty

static func _get_straight_cards(cards: Array[Card]) -> Array[Card]:
	var empty: Array[Card] = []
	if cards.size() < 5: return empty
	
	var unique_values = []
	var value_to_card = {}
	
	for card in cards:
		var val = card.get_value()
		if not value_to_card.has(val):
			unique_values.append(val)
			value_to_card[val] = card
			
	# Handle low Ace (5-4-3-2-A)
	var has_ace = value_to_card.has(Card.Rank.ACE)
	if has_ace:
		unique_values.append(1) # Ace can also be 1
		value_to_card[1] = value_to_card[Card.Rank.ACE]
		
	unique_values.sort_custom(func(a: int, b: int) -> bool: return a > b)
	
	var current_straight: Array[Card] = []
	
	for i in range(unique_values.size()):
		if i == 0:
			current_straight = [value_to_card[unique_values[i]]]
		else:
			if unique_values[i-1] - unique_values[i] == 1:
				current_straight.append(value_to_card[unique_values[i]])
				if current_straight.size() == 5:
					return current_straight
			elif unique_values[i-1] != unique_values[i]:
				current_straight = [value_to_card[unique_values[i]]]
				
	return empty

static func format_hand_name(rank: HandRank) -> String:
	match rank:
		HandRank.ROYAL_FLUSH: return "Royal Flush"
		HandRank.STRAIGHT_FLUSH: return "Straight Flush"
		HandRank.FOUR_OF_A_KIND: return "Four of a Kind"
		HandRank.FULL_HOUSE: return "Full House"
		HandRank.FLUSH: return "Flush"
		HandRank.STRAIGHT: return "Straight"
		HandRank.THREE_OF_A_KIND: return "Three of a Kind"
		HandRank.TWO_PAIR: return "Two Pair"
		HandRank.PAIR: return "Pair"
		HandRank.HIGH_CARD: return "High Card"
		_: return "Unknown"

static func _sort_descending(a: int, b: int) -> bool:
	return a > b

static func _sort_card_descending(a: Card, b: Card) -> bool:
	return a.get_value() > b.get_value()
