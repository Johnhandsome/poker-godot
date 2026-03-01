class_name PotManager
extends RefCounted

class Pot:
	var amount: int = 0
	var eligible_players: Array = [] # Array of player IDs
	
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

func gather_bets(active_players: Array, all_in_players: Array):
	# active_players: IDs of players who are NOT folded (still active in hand)
	# all_in_players: IDs of players who are currently All-In (from this or previous rounds)
	
	# 1. Check if the current last pot is "capped" by a PREVIOUS All-In
	# If there are bets this round, and the last pot contains an All-In player who bet 0 this round,
	# we must close that pot and start a new one.
	var current_bets_sum = 0
	for amt in active_bets.values():
		current_bets_sum += amt
		
	if current_bets_sum > 0 and not pots.is_empty():
		var last_pot = pots.back()
		var needs_new_pot = false
		for pid in last_pot.eligible_players:
			# If player is in the pot, is All-In, and bet 0 this round -> they cap the pot
			if all_in_players.has(pid) and active_bets.get(pid, 0) == 0:
				needs_new_pot = true
				break
		
		if needs_new_pot:
			pots.append(Pot.new())

	if active_bets.is_empty():
		return

	# 2. Identify contributors: ALL players who bet contribute money to the pot.
	# Folded players lose their bets but are not eligible to win.
	var contributors = []
	for pid in active_bets.keys():
		if active_bets[pid] > 0:
			contributors.append(pid)
	
	if contributors.is_empty():
		active_bets.clear()
		return

	# 3. Sort unique positive bet amounts
	var unique_bets = []
	for pid in contributors:
		var bet = active_bets[pid]
		if not unique_bets.has(bet):
			unique_bets.append(bet)
	unique_bets.sort()
	
	# 4. Slice bets into pots
	var last_deducted = 0
	for bet_level in unique_bets:
		var amount_slice = bet_level - last_deducted
		var pot_addition = 0
		var level_contributors = []
		
		# Who contributed at least this much?
		for pid in contributors:
			if active_bets[pid] >= bet_level:
				pot_addition += amount_slice
				level_contributors.append(pid)
			elif active_bets[pid] > last_deducted:
				# Partial contribution (All-in)
				var partial = active_bets[pid] - last_deducted
				pot_addition += partial
				level_contributors.append(pid)
		
		# Add to current pot
		var target_pot = pots.back()
		target_pot.amount += pot_addition
		
		# Update eligibility: Union of (Existing Valid Players) + (Current Contributors)
		# Existing players are kept ONLY if they are still active (not folded).
		# Exception: All-In players stay even if they didn't contribute to this slice? 
		# No, if it's a new slice (Side Pot), only contributors are eligible.
		# If it's an existing pot (Main), previous members stay.
		
		# Simplified: If this is a FRESH pot (amount was 0 before this loop step), start with empty.
		# If it's an existing pot, filter existing members.
		# THEN add new contributors.
		
		# Since we might have just appended a pot in step 1 or previous loop iteration...
		# We need to be careful.
		
		# Approach: Just ensure contributors are added.
		# If a player was already in the pot (from previous rounds), they stay if not folded.
		
		# Filter existing
		var next_eligible = []
		for existing in target_pot.eligible_players:
			# Keep if not folded (active or all-in)
			if active_players.has(existing) or all_in_players.has(existing):
				next_eligible.append(existing)
				
		# Add new contributors (only non-folded players are eligible to win the pot)
		for c in level_contributors:
			if not next_eligible.has(c) and (active_players.has(c) or all_in_players.has(c)):
				next_eligible.append(c)
				
		target_pot.eligible_players = next_eligible
		
		# If this bet level is NOT the max bet, it means someone went All-In here (capped).
		# We must spawn a new pot for the remaining higher bets.
		if bet_level < unique_bets.back():
			pots.append(Pot.new())
			
		last_deducted = bet_level
		
	active_bets.clear()

func get_total_pot() -> int:
	var total = 0
	for pot in pots:
		total += pot.amount
	for bet in active_bets.values():
		total += bet
	return total

func get_pot_breakdown() -> Array:
	# Returns array of {"label": "Main"/"Side 1"/etc, "amount": int}
	var result = []
	var idx = 0
	for pot in pots:
		if pot.amount == 0: continue
		var label = "Main" if idx == 0 else "Side " + str(idx)
		result.append({"label": label, "amount": pot.amount})
		idx += 1
	# Include uncommitted bets
	var pending = 0
	for bet in active_bets.values():
		pending += bet
	if pending > 0 and result.size() > 0:
		result.back()["amount"] += pending
	elif pending > 0:
		result.append({"label": "Main", "amount": pending})
	return result

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
