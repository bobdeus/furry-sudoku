class_name PuzzleEngine
extends RefCounted

var rng := RandomNumberGenerator.new()
var nodes := 0
var search_limit := 200000
var cancelled := false

func conflicts(a: int, b: int, n: int, regions: Array) -> bool:
	return a / n == b / n or a % n == b % n or regions[a] == regions[b] or (absi(a / n - b / n) <= 1 and absi(a % n - b % n) <= 1)

func candidates(puzzle: Dictionary, cats: Array, marks: Array) -> Array:
	var result: Array = []
	var n: int = puzzle.n
	for i in range(n * n):
		if cats.has(i) or marks.has(i):
			continue
		var allowed := true
		for cat in cats:
			if conflicts(i, cat, n, puzzle.regions):
				allowed = false
				break
		if allowed:
			result.append(i)
	return result

func groups(puzzle: Dictionary, cats: Array, options: Array) -> Array:
	var result: Array = []
	var n: int = puzzle.n
	for kind in range(3):
		for id in range(n):
			var occupied := false
			for c in cats:
				if unit(c, kind, n, puzzle.regions) == id:
					occupied = true
					break
			if occupied:
				continue
			var cells: Array = []
			for c in options:
				if unit(c, kind, n, puzzle.regions) == id:
					cells.append(c)
			result.append({"kind": kind, "id": id, "cells": cells})
	return result

func unit(cell: int, kind: int, n: int, regions: Array) -> int:
	if kind == 0:
		return cell / n
	if kind == 1:
		return cell % n
	return int(regions[cell])

func group_name(g: Dictionary) -> String:
	if g.kind == 0:
		return "row %d" % (g.id + 1)
	if g.kind == 1:
		return "column %d" % (g.id + 1)
	return "the highlighted color"

func step(tier: int, title: String, text: String, action: String, cells: Array, focus: Array) -> Dictionary:
	return {"tier": tier, "title": title, "text": text, "action": action, "cells": cells, "focus": focus}

func next_hint(puzzle: Dictionary, cats: Array, marks: Array, max_tier: int = 4) -> Dictionary:
	var n: int = puzzle.n
	# Direct consequences always precede the more involved deductions.
	for cat in cats:
		var excluded: Array = []
		for i in range(n * n):
			if not cats.has(i) and not marks.has(i) and conflicts(cat, i, n, puzzle.regions):
				excluded.append(i)
		if not excluded.is_empty():
			return step(0, "Give this cat some space", "Its row, column, color and touching squares cannot hold another cat. Cross out the outlined squares.", "mark", excluded, [cat])
	var options := candidates(puzzle, cats, marks)
	var units := groups(puzzle, cats, options)
	for g in units:
		if g.cells.is_empty():
			return {"contradiction": true, "text": "%s has nowhere left for its cat" % group_name(g)}
	# Prefer a colored-region single, then row/column singles.
	for kind in [2, 0, 1]:
		for g in units:
			if g.kind == kind and g.cells.size() == 1:
				return step(1, "Only one cozy spot", "There is just one possible square in %s. Its cat must go here." % group_name(g), "cat", g.cells, g.cells)
	if max_tier < 2:
		return {}
	for g in units:
		var removed: Array = []
		for c in options:
			if g.cells.has(c):
				continue
			var blocked_by_all := true
			for source in g.cells:
				if not conflicts(c, source, n, puzzle.regions):
					blocked_by_all = false
					break
			if blocked_by_all:
				removed.append(c)
		if not removed.is_empty():
			return step(2, "Follow the overlap", "One of the highlighted squares in %s must hold a cat. Every possible choice rules out the outlined squares." % group_name(g), "mark", removed, g.cells)
	if max_tier < 3:
		return {}
	# Hall sets across row, column and colored-region constraints.
	for source_kind in range(3):
		var source_units: Array = units.filter(func(g): return g.kind == source_kind)
		for target_kind in range(3):
			if source_kind == target_kind:
				continue
			for a in range(source_units.size()):
				for b in range(a + 1, source_units.size()):
					var paired := _locked_set(puzzle, options, [source_units[a], source_units[b]], source_kind, target_kind)
					if not paired.is_empty():
						return paired
					for c in range(b + 1, source_units.size()):
						var tripled := _locked_set(puzzle, options, [source_units[a], source_units[b], source_units[c]], source_kind, target_kind)
						if not tripled.is_empty():
							return tripled
	if max_tier < 4:
		return {}
	# A trial is a proof of impossibility, never an unverified guess.
	for g in units:
		if g.cells.size() > 3:
			continue
		for c in g.cells:
			var trial_cats := cats.duplicate()
			trial_cats.append(c)
			var trial_marks := marks.duplicate()
			var chain := 0
			for iteration in range(n * n):
				var deduction := next_hint(puzzle, trial_cats, trial_marks, 2)
				if deduction.has("contradiction"):
					return step(4, "Think a few moves ahead", "Try a cat at row %d, column %d. After %d deductions, %s. That starting square must be empty." % [c / n + 1, c % n + 1, chain, deduction.text], "mark", [c], g.cells)
				if deduction.is_empty():
					break
				apply_step(deduction, trial_cats, trial_marks)
				chain += 1
	# Exact search handles the rare puzzle needing deeper chained reasoning.
	for c in options:
		var assumed := cats.duplicate()
		assumed.append(c)
		var proof := solve(puzzle, assumed, marks, 1)
		if proof.count == 0 and not proof.exhausted:
			return step(4, "Trace the possibilities", "A cat at row %d, column %d leaves no complete arrangement satisfying all three rules. Follow its consequences; this square can be crossed out." % [c / n + 1, c % n + 1], "mark", [c], [c])
	return {}

func _locked_set(puzzle: Dictionary, options: Array, chosen: Array, source_kind: int, target_kind: int) -> Dictionary:
	var target_ids: Array = []
	var source_ids: Array = []
	var focus: Array = []
	for g in chosen:
		source_ids.append(g.id)
		for cell in g.cells:
			focus.append(cell)
			var id := unit(cell, target_kind, puzzle.n, puzzle.regions)
			if not target_ids.has(id):
				target_ids.append(id)
	if target_ids.size() != chosen.size():
		return {}
	var removed: Array = []
	for cell in options:
		if not source_ids.has(unit(cell, source_kind, puzzle.n, puzzle.regions)) and target_ids.has(unit(cell, target_kind, puzzle.n, puzzle.regions)):
			removed.append(cell)
	if removed.is_empty():
		return {}
	var names := ["rows", "columns", "colored regions"]
	return step(3, "Reserve a group of spaces", "These %d %s need %d cats, all within the same %d %s. Those %s are reserved; cross out the outlined alternatives." % [chosen.size(), names[source_kind], chosen.size(), chosen.size(), names[target_kind], names[target_kind]], "mark", removed, focus)

func apply_step(hint: Dictionary, cats: Array, marks: Array) -> void:
	if hint.action == "cat":
		for cell in hint.cells:
			if not cats.has(cell):
				cats.append(cell)
			marks.erase(cell)
	else:
		for cell in hint.cells:
			if not marks.has(cell):
				marks.append(cell)

func grade(puzzle: Dictionary) -> Dictionary:
	var cats: Array = []
	var marks: Array = []
	var highest := 0
	var counts := [0, 0, 0, 0, 0]
	for iteration in range(puzzle.n * puzzle.n * 2):
		if cats.size() == puzzle.n:
			return {"tier": highest, "steps": counts, "solved": true}
		var hint := next_hint(puzzle, cats, marks, 3)
		if hint.is_empty():
			return {"tier": 4, "steps": counts, "solved": false}
		if hint.has("contradiction"):
			return {"tier": -1, "steps": counts, "solved": false}
		highest = maxi(highest, hint.tier)
		counts[hint.tier] += 1
		apply_step(hint, cats, marks)
	return {"tier": 4, "steps": counts, "solved": false}

func solve(puzzle: Dictionary, cats: Array = [], marks: Array = [], limit: int = 2) -> Dictionary:
	nodes = 0
	var n: int = puzzle.n
	var rows: Array = []
	rows.resize(n)
	rows.fill(-1)
	var columns := 0
	var colors := 0
	for cat in cats:
		for other in cats:
			if cat != other and conflicts(cat, other, n, puzzle.regions):
				return {"count": 0, "solution": [], "exhausted": false}
		rows[cat / n] = cat
		columns |= 1 << (cat % n)
		colors |= 1 << int(puzzle.regions[cat])
	var allowed: Array = []
	for r in range(n):
		var cells: Array = []
		for c in range(n):
			if not marks.has(r * n + c):
				cells.append(r * n + c)
		allowed.append(cells)
	var result := {"count": 0, "solution": [], "examples": [], "exhausted": false}
	_search(puzzle, rows, allowed, columns, colors, limit, result)
	return result

func _search(puzzle: Dictionary, rows: Array, allowed: Array, columns: int, colors: int, limit: int, result: Dictionary) -> void:
	nodes += 1
	if nodes > search_limit or cancelled:
		result.exhausted = true
		return
	var n: int = puzzle.n
	var best := -1
	var choices: Array = []
	for r in range(n):
		if rows[r] >= 0:
			continue
		var valid: Array = []
		for cell in allowed[r]:
			var c: int = cell % n
			if (columns & (1 << c)) or (colors & (1 << int(puzzle.regions[cell]))):
				continue
			if r > 0 and rows[r - 1] >= 0 and absi(rows[r - 1] % n - c) <= 1:
				continue
			if r < n - 1 and rows[r + 1] >= 0 and absi(rows[r + 1] % n - c) <= 1:
				continue
			valid.append(cell)
		if valid.is_empty():
			return
		if best == -1 or valid.size() < choices.size():
			best = r
			choices = valid
	if best == -1:
		result.count += 1
		result.solution = rows.duplicate()
		result.examples.append(rows.duplicate())
		return
	for cell in choices:
		rows[best] = cell
		_search(puzzle, rows, allowed, columns | (1 << (cell % n)), colors | (1 << int(puzzle.regions[cell])), limit, result)
		rows[best] = -1
		if result.count >= limit or result.exhausted:
			return

func layout_key(puzzle: Dictionary) -> String:
	var colors: Dictionary = {}
	var shape: Array = []
	for region in puzzle.regions:
		if not colors.has(region):
			colors[region] = colors.size()
		shape.append(colors[region])
	return JSON.stringify(shape)

func generate(difficulty: String, seed_value: int, size_hint: int = 8, max_attempts: int = 20000, excluded_layout: String = "") -> Dictionary:
	rng.seed = seed_value
	var started := Time.get_ticks_msec()
	var distribution := [0, 0, 0, 0, 0]
	var solutions_found := [0, 0, 0]
	var invalid_grades := 0
	for attempt in range(max_attempts):
		if cancelled:
			return {}
		var n := maxi(8, size_hint)
		if difficulty == "hard":
			n = 8
		elif difficulty == "super":
			n = 9
		var puzzle: Dictionary
		if difficulty != "easy" and attempt % 4 != 3:
			puzzle = _seed_variant(difficulty)
		else:
			var original_solution := _permutation(n)
			puzzle = {"n": n, "regions": _regions(n, original_solution), "solution": original_solution, "difficulty": difficulty}
		puzzle.seed = seed_value
		var solution: Array = puzzle.solution
		var proof := solve(puzzle)
		for refinement in range(60):
			if proof.count == 1 or proof.exhausted or cancelled:
				break
			var alternative: Array = []
			for example in proof.examples:
				if example != solution:
					alternative = example
					break
			if alternative.is_empty() or not _remove_alternative(puzzle, alternative):
				break
			proof = solve(puzzle)
		solutions_found[mini(2, proof.count)] += 1
		if proof.count != 1 or proof.exhausted:
			continue
		var rating := grade(puzzle)
		if rating.tier >= 0:
			distribution[rating.tier] += 1
		else:
			invalid_grades += 1
		var matches: bool = (difficulty == "easy" and rating.tier == 2) or (difficulty == "hard" and rating.tier == 3) or (difficulty == "super" and rating.tier == 4)
		if matches:
			if not excluded_layout.is_empty() and layout_key(puzzle) == excluded_layout:
				continue
			puzzle.rating = rating
			puzzle.attempts = attempt + 1
			puzzle.generation_ms = Time.get_ticks_msec() - started
			print("Generated %s: %dx%d, deduction tier %d, unique solution, %d attempts, %d ms" % [difficulty, n, n, rating.tier, attempt + 1, puzzle.generation_ms])
			return puzzle
	print("Search distribution: ", distribution, " solutions: ", solutions_found, " invalid: ", invalid_grades)
	return {}

func _seed_variant(difficulty: String) -> Dictionary:
	var library: Array = JSON.parse_string(FileAccess.get_file_as_string("res://assets/puzzle_seeds.json"))
	var matching: Array = library.filter(func(p): return p.difficulty == difficulty)
	var original: Dictionary = matching[rng.randi_range(0, matching.size() - 1)]
	var n := int(original.n)
	var symmetry := rng.randi_range(0, 7)
	var colors: Array = range(n)
	for i in range(n - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var value: int = colors[i]
		colors[i] = colors[j]
		colors[j] = value
	var regions: Array = []
	regions.resize(n * n)
	var solution: Array = []
	for i in range(n * n):
		var x := i % n
		var y := i / n
		if symmetry & 1:
			var old_x := x
			x = y
			y = old_x
		if symmetry & 2:
			x = n - 1 - x
		if symmetry & 4:
			y = n - 1 - y
		var dest := y * n + x
		regions[dest] = colors[int(original.regions[i])]
		if original.solution.has(float(i)):
			solution.append(dest)
	solution.sort()
	# Change region boundaries as well as orientation and color. Connectivity and
	# the seed solution are preserved; uniqueness and difficulty are re-proved.
	for mutation in range(rng.randi_range(3, 12)):
		for trial in range(100):
			var cell := rng.randi_range(0, n * n - 1)
			if solution.has(cell):
				continue
			var neighbors := _neighbors(cell, n)
			var neighbor: int = neighbors[rng.randi_range(0, neighbors.size() - 1)]
			if regions[cell] != regions[neighbor] and _connected_without(regions, regions[cell], cell, n):
				regions[cell] = regions[neighbor]
				break
	return {"n": n, "regions": regions, "solution": solution, "difficulty": difficulty}

func _remove_alternative(puzzle: Dictionary, alternative: Array) -> bool:
	var changes: Array = []
	var n: int = puzzle.n
	for cell in alternative:
		if puzzle.solution.has(cell):
			continue
		var old: int = puzzle.regions[cell]
		if not _connected_without(puzzle.regions, old, cell, n):
			continue
		for neighbor in _neighbors(cell, n):
			var target: int = puzzle.regions[neighbor]
			if target != old:
				changes.append([cell, target])
	if changes.is_empty():
		return false
	var change: Array = changes[rng.randi_range(0, changes.size() - 1)]
	puzzle.regions[change[0]] = change[1]
	return true

func _neighbors(cell: int, n: int) -> Array:
	var result: Array = []
	for next in [cell - n, cell + n, cell - 1, cell + 1]:
		if next >= 0 and next < n * n and absi(next / n - cell / n) + absi(next % n - cell % n) == 1:
			result.append(next)
	return result

func _connected_without(regions: Array, id: int, removed: int, n: int) -> bool:
	var remaining: Array = []
	for i in range(regions.size()):
		if regions[i] == id and i != removed:
			remaining.append(i)
	if remaining.is_empty():
		return false
	var reached: Array = [remaining[0]]
	var cursor := 0
	while cursor < reached.size():
		for neighbor in _neighbors(reached[cursor], n):
			if neighbor != removed and regions[neighbor] == id and not reached.has(neighbor):
				reached.append(neighbor)
		cursor += 1
	return reached.size() == remaining.size()

func _permutation(n: int) -> Array:
	var cols: Array = range(n)
	while true:
		for i in range(n - 1, 0, -1):
			var j := rng.randi_range(0, i)
			var value: int = cols[i]
			cols[i] = cols[j]
			cols[j] = value
		var valid := true
		for i in range(1, n):
			if absi(cols[i] - cols[i - 1]) <= 1:
				valid = false
				break
		if valid:
			var result: Array = []
			for i in range(n):
				result.append(i * n + cols[i])
			return result
	return []

func _regions(n: int, solution: Array) -> Array:
	var regions: Array = []
	regions.resize(n * n)
	regions.fill(-1)
	var frontiers: Array = []
	for id in range(n):
		regions[solution[id]] = id
		frontiers.append([solution[id]])
	var active: Array = range(n)
	while not active.is_empty():
		var id: int = active[rng.randi_range(0, active.size() - 1)]
		var frontier: Array = frontiers[id]
		var source: int = frontier[rng.randi_range(0, frontier.size() - 1)]
		var neighbors: Array = []
		for next in [source - n, source + n, source - 1, source + 1]:
			if next < 0 or next >= n * n:
				continue
			if absi(next / n - source / n) + absi(next % n - source % n) != 1:
				continue
			if regions[next] == -1:
				neighbors.append(next)
		if neighbors.is_empty():
			frontier.erase(source)
			if frontier.is_empty():
				active.erase(id)
		else:
			var next: int = neighbors[rng.randi_range(0, neighbors.size() - 1)]
			regions[next] = regions[source]
			frontier.append(next)
	return regions
