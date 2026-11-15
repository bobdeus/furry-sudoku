extends RefCounted

static func profile(puzzle: Dictionary) -> Dictionary:
	if puzzle.is_empty():
		return {"clean_percent": 0, "stars": 0, "base": 0}
	var rating: Dictionary = puzzle.get("rating", {})
	var tier := clampi(int(rating.get("tier", 2)), 1, 4)
	var steps: Array = rating.get("steps", [0, 0, 0, 0, 0])
	var n := int(puzzle.n)
	var boundaries := 0
	for cell in range(n * n):
		if cell % n < n - 1 and puzzle.regions[cell] != puzzle.regions[cell + 1]:
			boundaries += 1
		if cell / n < n - 1 and puzzle.regions[cell] != puzzle.regions[cell + n]:
			boundaries += 1
	# A design estimate of a clean solve, not a statistic collected from players.
	var effort := mini(12, int(steps[2]) * 2 + int(steps[3]) * 3)
	var percent: int = [86, 74, 48, 26][tier - 1] - effort - maxi(0, n - 8) * 4 - int(8.0 * boundaries / (n * n))
	percent = clampi(roundi(percent / 5.0) * 5, 10, 90)
	var base := roundi((800 + n * 100 + pow(100 - percent, 1.35) * 12) / 50.0) * 50
	return {"clean_percent": percent, "stars": clampi(ceili((100 - percent) / 20.0), 1, 5), "base": base}

static func points(base: int, hints: int, misses: int, one_heart: bool, undos: int = 0) -> int:
	var focus := pow(maxi(0, 3 - hints) / 3.0, 2)
	var accuracy := pow(0.75, misses * (misses + 1) / 2.0)
	return roundi(base * (1.2 if one_heart else 1.0) * focus * accuracy * pow(0.9, undos))
