class_name Card
extends RefCounted

enum Suit { SPADES, HEARTS, DIAMONDS, CLUBS }
enum Rank { TWO = 2, THREE = 3, FOUR = 4, FIVE = 5, SIX = 6, SEVEN = 7, EIGHT = 8, NINE = 9, TEN = 10, JACK = 11, QUEEN = 12, KING = 13, ACE = 14 }

var suit: Suit = Suit.SPADES
var rank: Rank = Rank.TWO

func _init(s: Suit, r: Rank):
	suit = s
	rank = r

func get_value() -> int:
	return int(rank)

func get_suit_string() -> String:
	match suit:
		Suit.SPADES: return "Spades"
		Suit.HEARTS: return "Hearts"
		Suit.DIAMONDS: return "Diamonds"
		Suit.CLUBS: return "Clubs"
	return "Unknown"

func get_rank_string() -> String:
	match rank:
		Rank.JACK: return "J"
		Rank.QUEEN: return "Q"
		Rank.KING: return "K"
		Rank.ACE: return "A"
		_: return str(get_value())

func get_name() -> String:
	var suit_symbol = ""
	match suit:
		Suit.SPADES: suit_symbol = "♠"
		Suit.HEARTS: suit_symbol = "♥"
		Suit.DIAMONDS: suit_symbol = "♦"
		Suit.CLUBS: suit_symbol = "♣"
	return get_rank_string() + suit_symbol

func is_red() -> bool:
	return suit == Suit.HEARTS or suit == Suit.DIAMONDS

func is_black() -> bool:
	return not is_red()

func compare_to(other: Card) -> int:
	if self.get_value() > other.get_value():
		return 1
	elif self.get_value() < other.get_value():
		return -1
	return 0
