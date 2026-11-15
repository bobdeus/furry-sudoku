extends SceneTree

func _initialize() -> void:
	_render.call_deferred()

func _render() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() < 2:
		printerr("Usage: --script res://tools/render.gd -- puzzle.json output.png [game|hint|deep|guided|retry|home|how|scoring|won|lost] [level-number] [interactive]")
		quit(1)
		return
	var game = load("res://scenes/main.tscn").instantiate()
	game.persistence_enabled = false
	root.add_child(game)
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(args[0]))
	data.n = int(data.n)
	data.regions = data.regions.map(func(v): return int(v))
	data.solution = data.solution.map(func(v): return int(v))
	game.puzzle = data
	game.challenge = game.ScoreRules.profile(data)
	game.cats = []
	game.marks = []
	game.level = 9 if data.difficulty == "super" else (4 if data.difficulty == "hard" else 0)
	if args.size() > 3:
		game.level = maxi(1, args[3].to_int()) - 1
	game.round_number = game.level / 10 + 1
	game.level_won = false
	game.screen = "game"
	game.lives = game._starting_lives()
	var view := args[2] if args.size() > 2 else "game"
	if view == "home":
		game.screen = "home"
	elif view == "won":
		for cell in data.solution:
			game._place(cell)
	elif view in ["guided", "retry"]:
		for i in range(3):
			game._action("hint")
			print("Hint %d: %d points" % [game.revealed_hints.size(), game._level_score()])
			game._action("hint")
			game._action("hint")
		if view == "retry":
			var old_layout: String = game.engine.layout_key(data)
			for cell in range(data.n * data.n):
				if not data.solution.has(cell):
					game._place(cell)
					if game.lives == 0:
						break
			game._action("retry_puzzle")
			while game.loading:
				await process_frame
			if game.puzzle.is_empty():
				printerr("Could not render the regenerated puzzle.")
				quit(1)
				return
			print("Retry: level %d, %d hearts, %d hints, %d misses, %d points, total %d, different layout: %s" % [game.level + 1, game.lives, game.revealed_hints.size(), game.level_misses, game._level_score(), game.total_score, old_layout != game.engine.layout_key(game.puzzle)])
	elif view == "lost":
		for cell in range(data.n * data.n):
			if not data.solution.has(cell):
				game._place(cell)
				if game.lives == 0:
					break
	elif view in ["how", "scoring"]:
		game.modal = view
	else:
		for iteration in range(200):
			var clue: Dictionary = game.engine.next_hint(data, game.cats, game.marks)
			if clue.is_empty() or clue.has("contradiction"):
				break
			if (view == "hint" and clue.tier >= 3) or (view == "deep" and clue.tier == 4) or (view == "game" and game.cats.size() >= 2):
				if view in ["hint", "deep"]:
					game._action("hint")
					game._action("hint")
				break
			game.engine.apply_step(clue, game.cats, game.marks)
	game.queue_redraw()
	await process_frame
	await RenderingServer.frame_post_draw
	var error := root.get_texture().get_image().save_png(args[1])
	print("Rendered %s: %s" % [view, args[1]])
	if error == OK and args.has("interactive"):
		root.title = "Furry Sudoku Preview"
		return
	quit(error)
