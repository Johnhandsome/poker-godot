class_name PotManager
extends RefCounted

class Pot:
	var amount: int = 0
	var eligible_players: Array = [] # Array of player indices or IDs
	
	func _init(amt: int = 0, players: Array = []):
		amount = amt
		eligible_players = players.duplicate()

var pots: Array[Pot] = []
var active_bets: Dictionary = {} # player_id: bet_amount

func _init():
	reset()

func reset():
	pots.clear()
	pots.append(Pot.new()) # Main pot
	active_bets.clear()

func add_bet(player_id: String, amount: int):
	if not active_bets.has(player_id):
		active_bets[player_id] = 0
	active_bets[player_id] += amount

func gather_bets(active_players: Array):
	if active_bets.is_empty():
		return
		
	# We need to handle side pots if players are all-in with different amounts
	var unique_bets = []
	for player_id in active_bets:
		var bet = active_bets[player_id]
		if bet > 0 and not unique_bets.has(bet):
			unique_bets.append(bet)
			
	unique_bets.sort()
	
	var last_deducted = 0
	for bet in unique_bets:
		var amount_to_deduct = bet - last_deducted
		var pot_addition = 0
		var eligible = []
		
		for player_id in active_bets.keys():
			if active_bets[player_id] >= bet:
				pot_addition += amount_to_deduct
				if active_players.has(player_id):
					eligible.append(player_id)
			elif active_bets[player_id] > last_deducted:
				var diff = active_bets[player_id] - last_deducted
				pot_addition += diff
				if active_players.has(player_id):
					eligible.append(player_id)
					
		# Add to the current pot
		var current_pot = pots.back()
		current_pot.amount += pot_addition
		current_pot.eligible_players = eligible.duplicate()
		
		# If there are still higher bets, create a side pot
		if bet < unique_bets.back():
			pots.append(Pot.new())
			
		last_deducted = bet
		
	active_bets.clear()

func get_total_pot() -> int:
	var total = 0
	for pot in pots:
		total += pot.amount
	for bet in active_bets.values():
		total += bet
	return total

func distribute_pots(player_results: Dictionary) -> Dictionary:
	# player_results maps player_id to their EvaluationResult
	var payouts = {} # player_id: amount won
	
	for pot in pots:
		if pot.amount == 0:
			continue
			
		var best_result: HandEvaluator.EvaluationResult = null
		var winners = []
		
		for player_id in pot.eligible_players:
			if not player_results.has(player_id):
				continue
				
			var p_result = player_results[player_id]
			if best_result == null:
				best_result = p_result
				winners = [player_id]
			else:
				var cmp = p_result.compare_to(best_result)
				if cmp > 0:
					best_result = p_result
					winners = [player_id]
				elif cmp == 0:
					winners.append(player_id)
					
		if winners.size() > 0:
			var chip_per_winner = int(pot.amount / float(winners.size()))
			var remainder = pot.amount % winners.size()
			
			for i in range(winners.size()):
				var winner = winners[i]
				if not payouts.has(winner):
					payouts[winner] = 0
				payouts[winner] += chip_per_winner
				if i < remainder:
					payouts[winner] += 1 # Distribute remainder chips one by one
					
	return payouts

# _is_player_folded method removed, trusting GameManager to array filter on active_players
