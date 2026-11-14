extends SceneTree

func _initialize() -> void:
	_render.call_deferred()

func _render() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() < 2:
		printerr("Usage: --script res://tools/render.gd -- puzzle.json output.png [game|hint|home|how|won|lost]")
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
	game.cats = []
	game.marks = []
	game.level = 9 if data.difficulty == "super" else (4 if data.difficulty == "hard" else 0)
	game.level_won = false
	game.screen = "game"
	game.lives = 3
	var view := args[2] if args.size() > 2 else "game"
	if view == "home":
		game.screen = "home"
	elif view in ["how", "won", "lost"]:
		game.modal = view
	else:
		for iteration in range(200):
			var clue: Dictionary = game.engine.next_hint(data, game.cats, game.marks)
			if clue.is_empty() or clue.has("contradiction"):
				break
			if (view == "hint" and clue.tier >= 3) or (view == "deep" and clue.tier == 4) or (view == "game" and game.cats.size() >= 2):
				if view in ["hint", "deep"]:
					game.hint = clue
					game.hint_stage = 1
				break
			game.engine.apply_step(clue, game.cats, game.marks)
	game.queue_redraw()
	await process_frame
	await RenderingServer.frame_post_draw
	var error := root.get_texture().get_image().save_png(args[1])
	print("Rendered %s: %s" % [view, args[1]])
	quit(error)
