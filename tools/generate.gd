extends SceneTree

const EngineClass = preload("res://scripts/puzzle_engine.gd")

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var difficulty := args[0] if args.size() > 0 else "easy"
	var seed_value := int(args[1]) if args.size() > 1 else int(Time.get_unix_time_from_system())
	var engine := EngineClass.new()
	var budget := int(args[3]) if args.size() > 3 else 20000
	var puzzle := engine.generate(difficulty, seed_value, 8, budget)
	if puzzle.is_empty():
		push_error("No qualifying puzzle found.")
		quit(1)
		return
	if args.has("explain"):
		var cats: Array = []
		var marks: Array = []
		var walkthrough: Array = []
		while cats.size() < puzzle.n:
			var hint := engine.next_hint(puzzle, cats, marks)
			if hint.is_empty() or hint.has("contradiction"):
				push_error("Could not explain this puzzle.")
				quit(1)
				return
			walkthrough.append(hint)
			engine.apply_step(hint, cats, marks)
		puzzle.walkthrough = walkthrough
		print("Explained every placement in %d logical steps." % walkthrough.size())
	if args.size() > 2:
		var file := FileAccess.open(args[2], FileAccess.WRITE)
		file.store_string(JSON.stringify(puzzle, "\t"))
	else:
		print(JSON.stringify(puzzle))
	quit()
