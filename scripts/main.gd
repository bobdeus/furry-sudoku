extends Control

const Puzzle = preload("res://scripts/puzzle_engine.gd")
const ScoreRules = preload("res://scripts/score_rules.gd")
const CAT = preload("res://assets/cat.png")
const FONT = preload("res://assets/Nunito.ttf")
const SAVE := "user://progress.json"
const BG := Color("f8f4ee")
const INK := Color("80615e")
const MUTED := Color("b39a90")
const GREEN := Color("4ba77c")
const PALETTE := [Color("4ba77c"), Color("62b3c6"), Color("e9bcdf"), Color("edce80"), Color("a9c8e2"), Color("b48b6e"), Color("bdb25e"), Color("9e91ca"), Color("eaa392"), Color("94b795")]
const BOARD := Rect2(30, 440, 660, 660)

var engine := Puzzle.new()
var worker: Thread
var worker_engine: RefCounted
var puzzle: Dictionary = {}
var cats: Array = []
var marks: Array = []
var history: Array = []
var level := 0
var round_number := 1
var lives := 3
var round_seed := 0
var previous_layout := ""
var cleared_rounds := 0
var cleared_puzzles := 0
var total_score := 0
var level_scores: Dictionary = {}
var level_misses := 0
var level_undos := 0
var revealed_hints: Array = []
var challenge: Dictionary = {}
var screen := "home"
var modal := ""
var loading := false
var level_won := false
var cat_mode := false
var settings := {"haptics": true, "auto_mark": false}
var hint: Dictionary = {}
var hint_stage := 0
var buttons: Array = []
var clock_time := 0.0
var elapsed := 0.0
var error_cell := -1
var error_until := 0.0
var placed_cell := -1
var placed_at := 0.0
var toast := ""
var toast_until := 0.0
var last_cell := -1
var last_tap := -1.0
var dragging := false
var drag_value := true
var drag_cells: Array = []
var hovered := -1
var keyboard_cell := 0
var keyboard_visible := false
var design_scale := 1.0
var design_offset := Vector2.ZERO
var confetti: Array = []
var ui_font := FontVariation.new()
var heading_font := FontVariation.new()
var persistence_enabled := true

func _ready() -> void:
	get_tree().auto_accept_quit = false
	ui_font.base_font = FONT
	ui_font.variation_opentype = {TextServerManager.get_primary_interface().name_to_tag("wght"): 600.0}
	heading_font.base_font = FONT
	heading_font.variation_opentype = {TextServerManager.get_primary_interface().name_to_tag("wght"): 800.0}
	_load_progress()
	resized.connect(queue_redraw)
	queue_redraw()
	if OS.get_cmdline_user_args().has("--play"):
		_action("play")

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		_save_progress()
		_stop_worker()
		get_tree().quit()
	elif what == NOTIFICATION_APPLICATION_PAUSED or what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		_save_progress()
	elif what == NOTIFICATION_WM_GO_BACK_REQUEST:
		_back()

func _exit_tree() -> void:
	_stop_worker()

func _stop_worker() -> void:
	if worker != null and worker.is_started():
		worker_engine.cancelled = true
		worker.wait_to_finish()
	worker = null

func _process(delta: float) -> void:
	clock_time += delta
	if screen == "game" and not loading and modal.is_empty() and not level_won:
		elapsed += delta
	if worker != null and not worker.is_alive():
		var result: Dictionary = worker.wait_to_finish()
		worker = null
		loading = false
		if result.is_empty():
			modal = "generation_error"
		else:
			puzzle = result
			challenge = ScoreRules.profile(puzzle)
			cats.clear()
			marks.clear()
			history.clear()
			elapsed = 0.0
			level_won = false
			_save_progress()
	for piece in confetti:
		piece.p += piece.v * delta
		piece.v.y += 100.0 * delta
		piece.angle += delta * piece.spin
	confetti = confetti.filter(func(piece): return piece.p.y < 1500)
	queue_redraw()

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), BG)
	design_scale = minf(size.x / 720.0, size.y / 1440.0)
	design_offset = (size - Vector2(720, 1440) * design_scale) * 0.5
	draw_set_transform(design_offset, 0, Vector2.ONE * design_scale)
	buttons.clear()
	if screen == "home":
		_draw_home()
	else:
		_draw_game()
	if not toast.is_empty() and clock_time < toast_until:
		_panel(Rect2(76, 1140, 568, 76), Color("80615e"), 24, false)
		_text(toast, Rect2(90, 1157, 540, 42), 23, Color.WHITE)
	if not modal.is_empty():
		_draw_modal()
	for piece in confetti:
		draw_set_transform(design_offset + piece.p * design_scale, piece.angle, Vector2.ONE * design_scale)
		draw_rect(Rect2(-4, -8, 8, 16), piece.color)
	draw_set_transform(Vector2.ZERO)

func _panel(rect: Rect2, color: Color = Color.WHITE, radius: int = 26, shadow: bool = true, border: Color = Color.TRANSPARENT, width: int = 0) -> void:
	if shadow:
		var shade := StyleBoxFlat.new()
		shade.bg_color = Color(0.59, 0.40, 0.28, 0.07)
		shade.set_corner_radius_all(radius)
		shade.shadow_color = Color(0.54, 0.35, 0.23, 0.08)
		shade.shadow_size = 12
		shade.shadow_offset = Vector2(0, 5)
		draw_style_box(shade, Rect2(rect.position + Vector2(0, 5), rect.size))
	var box := StyleBoxFlat.new()
	box.bg_color = color
	box.set_corner_radius_all(radius)
	box.border_color = border
	box.set_border_width_all(width)
	box.anti_aliasing = true
	draw_style_box(box, rect)

func _text(value: String, rect: Rect2, font_size: int = 28, color: Color = INK, align: HorizontalAlignment = HORIZONTAL_ALIGNMENT_CENTER) -> void:
	var line := TextLine.new()
	line.add_string(value, heading_font if font_size >= 32 else ui_font, font_size)
	line.width = rect.size.x
	line.alignment = align
	line.draw(get_canvas_item(), rect.position, color)

func _wrap(value: String, rect: Rect2, font_size: int = 24, color: Color = INK, align: HorizontalAlignment = HORIZONTAL_ALIGNMENT_CENTER) -> void:
	var paragraph := TextParagraph.new()
	paragraph.add_string(value, ui_font, font_size)
	paragraph.width = rect.size.x
	paragraph.alignment = align
	paragraph.break_flags = TextServer.BREAK_MANDATORY | TextServer.BREAK_WORD_BOUND | TextServer.BREAK_ADAPTIVE
	paragraph.draw(get_canvas_item(), rect.position, color)

func _button(id: String, rect: Rect2, label: String, filled: bool = false, font_size: int = 28) -> void:
	_panel(rect, GREEN if filled else Color.WHITE, 28, true)
	_text(label, Rect2(rect.position + Vector2(10, (rect.size.y - font_size * 1.4) * 0.5), rect.size - Vector2(20, 0)), font_size, Color.WHITE if filled else INK)
	buttons.append({"id": id, "rect": rect})

func _circle_button(id: String, center: Vector2, symbol: String) -> void:
	_panel(Rect2(center - Vector2(39, 39), Vector2(78, 78)), Color.WHITE, 39)
	_icon(symbol, center, 23, INK)
	buttons.append({"id": id, "rect": Rect2(center - Vector2(44, 44), Vector2(88, 88))})

func _icon(kind: String, center: Vector2, s: float, color: Color) -> void:
	if kind == "back":
		draw_polyline(PackedVector2Array([center + Vector2(7, -s * 0.6), center + Vector2(-8, 0), center + Vector2(7, s * 0.6)]), color, 5, true)
	elif kind == "settings":
		for i in range(8):
			var angle := i * TAU / 8
			var direction := Vector2(cos(angle), sin(angle))
			draw_line(center + direction * s * 0.65, center + direction * s, color, 8, true)
		draw_arc(center, s * 0.65, 0, TAU, 32, color, 8, true)
		draw_circle(center, s * 0.22, color)
	elif kind == "undo":
		draw_arc(center + Vector2(4, 3), s * 0.7, -PI * 0.85, PI * 0.5, 26, color, 6, true)
		draw_polyline(PackedVector2Array([center + Vector2(-s, -s * 0.6), center + Vector2(-s * 0.9, s * 0.05), center + Vector2(-s * 0.3, -s * 0.05)]), color, 6, true)
	elif kind == "bulb":
		draw_circle(center + Vector2(0, -s * 0.2), s * 0.65, Color("f6d16b"))
		draw_circle(center + Vector2(-s * 0.2, -s * 0.42), s * 0.21, Color("ffe9a1"))
		_panel(Rect2(center + Vector2(-s * 0.3, s * 0.3), Vector2(s * 0.6, s * 0.4)), Color("b1a0b7"), 5, false)
		draw_line(center + Vector2(-s * 0.22, s * 0.87), center + Vector2(s * 0.22, s * 0.87), INK, 4, true)
	elif kind == "close":
		draw_line(center + Vector2(-s * 0.5, -s * 0.5), center + Vector2(s * 0.5, s * 0.5), color, 5, true)
		draw_line(center + Vector2(s * 0.5, -s * 0.5), center + Vector2(-s * 0.5, s * 0.5), color, 5, true)

func _heart(center: Vector2, s: float, active: bool) -> void:
	var color := Color("e99588") if active else Color("e9e0d6")
	var points := PackedVector2Array()
	for i in range(65):
		var t := i * TAU / 64.0
		var x := 16.0 * pow(sin(t), 3)
		var y := -(13.0 * cos(t) - 5.0 * cos(2 * t) - 2.0 * cos(3 * t) - cos(4 * t))
		points.append(center + Vector2(x, y) * s / 17.0)
	var shadow_points := PackedVector2Array()
	for p in points:
		shadow_points.append(p + Vector2(0, 3))
	draw_colored_polygon(shadow_points, Color(0.5, 0.25, 0.15, 0.08))
	draw_colored_polygon(points, color)
	if active:
		draw_arc(center + Vector2(-s * 0.4, -s * 0.3), s * 0.26, PI * 1.1, PI * 1.75, 12, Color("fbc3b2"), 3, true)

func _cat(rect: Rect2, alpha: float = 1.0) -> void:
	draw_texture_rect(CAT, rect, false, Color(1, 1, 1, alpha))

func _draw_home() -> void:
	_circle_button("settings", Vector2(648, 90), "settings")
	_text("F U R R Y   S U D O K U", Rect2(80, 86, 560, 40), 21, MUTED)
	for i in range(5):
		var x := 165.0 + i * 78
		_panel(Rect2(x, 218 + sin(i * 1.8) * 24, 63, 63), PALETTE[i].lightened(0.28), 17, false)
	_cat(Rect2(224, 280 + sin(clock_time * 1.4) * 5, 272, 280))
	_text("A little logic.", Rect2(50, 595, 620, 66), 48)
	_text("A lot of cats.", Rect2(50, 660, 620, 66), 48)
	_text("Find a cozy spot for every cat.", Rect2(50, 752, 620, 42), 26, MUTED)
	_panel(Rect2(110, 847, 500, 85), Color("f0e9df"), 24, false)
	_text("TOTAL SCORE   %s" % _number(total_score), Rect2(110, 868, 500, 46), 28, GREEN)
	buttons.append({"id": "scoring", "rect": Rect2(110, 847, 500, 85)})
	var continuing := not puzzle.is_empty() or round_seed != 0
	_button("play", Rect2(110, 976, 500, 94), "Continue level %d" % (level + 1) if continuing else "Let's play", true, 29)
	_button("how", Rect2(185, 1100, 350, 80), "How to play", false, 26)
	_text("%d puzzles solved   ·   %d rounds completed" % [cleared_puzzles, cleared_rounds], Rect2(50, 1258, 620, 42), 22, MUTED)
	_text("Just you and the cats. Always offline.", Rect2(50, 1370, 620, 34), 21, MUTED)

func _difficulty(index: int = -1) -> String:
	var target := (level if index == -1 else index) % 10
	return "super" if target == 9 else ("hard" if target == 4 else "easy")

func _starting_lives(index: int = -1) -> int:
	var target := level if index == -1 else index
	return 1 if target % 10 == 6 else 3

func _number(value: int) -> String:
	var digits := str(value)
	var result := ""
	for i in range(digits.length()):
		if i > 0 and (digits.length() - i) % 3 == 0:
			result += ","
		result += digits[i]
	return result

func _level_score() -> int:
	if level_won:
		return int(level_scores.get(str(level + 1), 0))
	return ScoreRules.points(int(challenge.get("base", 0)), revealed_hints.size(), level_misses, _starting_lives() == 1, level_undos)

func _estimate() -> String:
	return "Approximately %d%% can solve without hints or misses" % int(challenge.get("clean_percent", 0))

func _draw_game() -> void:
	_circle_button("home", Vector2(68, 90), "back")
	_circle_button("settings", Vector2(652, 90), "settings")
	_text("Level %d" % (level + 1), Rect2(150, 51, 420, 70), 48)
	var round_label := "ROUND %d" % round_number
	if _starting_lives() == 1:
		round_label += "  ·  ONE HEART"
	_text(round_label, Rect2(150, 122, 420, 32), 19, MUTED)
	for i in range(10):
		var c := GREEN if i < level % 10 else (INK if i == level % 10 else Color("e3d9cf"))
		var pos := Vector2(220 + i * 31, 179)
		if i == 4 or i == 9:
			var pts := PackedVector2Array([pos + Vector2(0, -7), pos + Vector2(7, 0), pos + Vector2(0, 7), pos + Vector2(-7, 0)])
			draw_colored_polygon(pts, c)
		else:
			draw_circle(pos, 5.5, c)
	_panel(Rect2(155, 218, 176, 64), Color.WHITE, 32, false)
	_cat(Rect2(170, 225, 51, 51))
	_text("%d / %d" % [cats.size(), int(puzzle.get("n", 0))], Rect2(223, 229, 100, 43), 29, GREEN)
	_panel(Rect2(365, 218, 200, 64), Color.WHITE, 32, false)
	for i in range(_starting_lives()):
		_heart(Vector2(465 + (i - (_starting_lives() - 1) * 0.5) * 57, 249), 23, i < lives)
	for i in range(2):
		var x := 30 + i * 340
		_panel(Rect2(x, 295, 320, 61), Color("edf4eb") if i == 0 else Color.WHITE, 19, false)
		_text("LEVEL SCORE" if i == 0 else "TOTAL SCORE", Rect2(x + 12, 303, 124, 24), 15, MUTED)
		var value := _number(_level_score() if i == 0 else total_score)
		_text(value, Rect2(x + 137, 307, 170, 40), 26 if value.length() < 10 else 21, GREEN if i == 0 else INK, HORIZONTAL_ALIGNMENT_RIGHT)
	buttons.append({"id": "scoring", "rect": Rect2(30, 295, 660, 61)})
	_panel(Rect2(30, 367, 660, 61), Color.WHITE, 19, false)
	_text("Rules", Rect2(300, 376, 120, 36), 23, GREEN)
	draw_line(Vector2(333, 408), Vector2(387, 408), GREEN, 1.5, true)
	buttons.append({"id": "how", "rect": Rect2(285, 365, 150, 60)})
	if loading:
		_panel(BOARD, Color.WHITE, 25, false)
		_cat(Rect2(276, 630 + sin(clock_time * 3) * 8, 168, 172))
		_text("Finding a cozy puzzle" + ".".repeat(int(clock_time * 2) % 4), Rect2(70, 844, 580, 45), 28)
		_text("Checking every possibility", Rect2(70, 903, 580, 40), 22, MUTED)
	elif not puzzle.is_empty():
		_draw_board()
	var difficulty: String = puzzle.get("difficulty", _difficulty())
	if hint.is_empty():
		var label := "STANDARD"
		var color := MUTED
		if difficulty == "hard":
			label = "HARD"
			color = Color("b88e4d")
		elif difficulty == "super":
			label = "SUPER HARD"
			color = Color("9e78b0")
		if not puzzle.is_empty():
			_text("%s  ·  Difficulty %d/5" % [label, int(challenge.get("stars", 0))], Rect2(40, 1116, 640, 34), 22, color)
			_wrap(_estimate(), Rect2(40, 1155, 640, 54), 21, INK)
		_text("Tap to mark ×  ·  Double-tap to place a cat", Rect2(40, 1220, 640, 30), 20, MUTED)
	else:
		_draw_hint()
	for i in range(3):
		var pos := Vector2(170 + i * 190, 1320)
		_panel(Rect2(pos - Vector2(48, 48), Vector2(96, 96)), Color("edf4eb") if i == 1 and cat_mode else Color.WHITE, 48)
		if i == 0:
			_icon("undo", pos, 25, INK if not history.is_empty() else Color("d6c7bc"))
		elif i == 1:
			_cat(Rect2(pos - Vector2(35, 35), Vector2(70, 72)))
		else:
			_icon("bulb", pos, 32, INK)
		var labels := ["Undo · −10%", "Place cat" if cat_mode else "Mark ×", "Hint · %d/3" % mini(3, revealed_hints.size()) if hint.is_empty() else ("Explain" if hint_stage == 0 else "Apply hint")]
		_text(labels[i], Rect2(pos.x - 88, 1384, 176, 36), 22)
		buttons.append({"id": ["undo", "mode", "hint"][i], "rect": Rect2(pos - Vector2(70, 58), Vector2(140, 155))})

func _cell_rect(index: int) -> Rect2:
	var n: int = puzzle.n
	var pitch := 644.0 / n
	return Rect2(BOARD.position + Vector2(8 + (index % n) * pitch + 3, 8 + (index / n) * pitch + 3), Vector2.ONE * (pitch - 6))

func _draw_board() -> void:
	_panel(BOARD, Color.WHITE, 24, false)
	for i in range(puzzle.n * puzzle.n):
		var rect := _cell_rect(i)
		var color: Color = PALETTE[int(puzzle.regions[i]) % PALETTE.size()]
		if i == hovered and not cats.has(i):
			color = color.lightened(0.08)
		_panel(rect, color, 8, false)
		if not hint.is_empty():
			if hint.focus.has(i):
				_panel(rect.grow(-2), Color.TRANSPARENT, 7, false, Color("fff1a4"), 4)
			if hint_stage > 0 and hint.cells.has(i):
				_panel(rect.grow(-5), Color(1, 1, 1, 0.14), 7, false, Color.WHITE, 3)
		if cats.has(i):
			var pop := 1.0
			if i == placed_cell and clock_time - placed_at < 0.35:
				pop = 1.0 + sin((clock_time - placed_at) / 0.35 * PI) * 0.13
			var cat_size := rect.size * 1.07 * pop
			_cat(Rect2(rect.get_center() - cat_size * 0.5 - Vector2(0, 2), cat_size))
		elif marks.has(i):
			var offset := rect.size.x * 0.255
			var center := rect.get_center()
			var cross_color := Color("f7faf8")
			if i == error_cell and clock_time < error_until:
				cross_color = Color("f16c45")
			var thick := maxf(5, rect.size.x * 0.11)
			for direction in [-1, 1]:
				var from := center + Vector2(-offset, -offset * direction)
				var to := center + Vector2(offset, offset * direction)
				draw_line(from, to, cross_color, thick, true)
				draw_circle(from, thick * 0.5, cross_color)
				draw_circle(to, thick * 0.5, cross_color)
		if keyboard_visible and i == keyboard_cell:
			_panel(rect.grow(-3), Color.TRANSPARENT, 8, false, INK, 3)

func _draw_hint() -> void:
	_panel(Rect2(30, 1122, 660, 130), Color("fff9e8"), 20, false)
	_text(hint.title, Rect2(50, 1133, 575, 34), 23, INK, HORIZONTAL_ALIGNMENT_LEFT)
	var explanation: String = hint.text if hint_stage > 0 else "Look at the golden squares. What do the three rules tell you? Tap Explain for the next nudge."
	_wrap(explanation, Rect2(50, 1173, 620, 76), 20, INK, HORIZONTAL_ALIGNMENT_LEFT)
	_icon("close", Vector2(657, 1149), 17, MUTED)
	buttons.append({"id": "dismiss_hint", "rect": Rect2(632, 1127, 50, 45)})

func _rule_illustration(rule: int, area: Rect2) -> void:
	var cat_cells: Array = [[4, 11], [1, 7, 8, 14], [5]][rule]
	var blocked := [0, 1, 2, 4, 6, 8, 9, 10]
	var pitch := area.size.x / 4.0
	for cell in range(16):
		var tile := Rect2(area.position + Vector2(cell % 4, cell / 4) * pitch, Vector2.ONE * (pitch - 3))
		var color: Color = PALETTE[1 if cell % 4 < 2 else 2] if rule == 0 else PALETTE[3 + cell / 4]
		if rule == 2:
			color = Color("dfb7bb") if blocked.has(cell) else Color("e8e0d6")
		_panel(tile, color, 5, false)
		if cat_cells.has(cell):
			_cat(tile.grow(2))
		elif rule == 2 and blocked.has(cell):
			var center := tile.get_center()
			for direction in [-1, 1]:
				draw_line(center + Vector2(-5, -5 * direction), center + Vector2(5, 5 * direction), Color.WHITE, 3, true)

func _draw_modal() -> void:
	buttons.clear()
	draw_rect(Rect2(0, 0, 720, 1440), Color(0.30, 0.23, 0.22, 0.30))
	_panel(Rect2(60, 230, 600, 1000) if modal == "how" else Rect2(60, 350, 600, 740), BG, 38)
	if modal == "settings":
		_text("Make yourself at home", Rect2(90, 395, 540, 52), 33)
		for i in range(2):
			var key: String = ["haptics", "auto_mark"][i]
			var name: String = ["Gentle vibration", "Auto-mark around cats"][i]
			_button("toggle_" + key, Rect2(100, 535 + i * 120, 520, 80), name + ("   ON" if settings[key] else "   OFF"), false, 25)
		_button("how", Rect2(100, 825, 520, 72), "How to play", false, 24)
		_button("close", Rect2(185, 949, 350, 80), "Back to the cats", true, 26)
	elif modal == "how":
		_text("A cozy spot for every cat", Rect2(90, 273, 540, 55), 34)
		_text("Three little rules. One clever puzzle.", Rect2(90, 338, 540, 38), 23, MUTED)
		var titles := ["One cat per color", "One cat per row and column", "Cats cannot touch"]
		var descriptions := ["Each colored area needs exactly one cat. Find its perfect spot.", "Every row across and every column down needs exactly one cat.", "Leave space between cats. They cannot sit side by side or meet corner to corner."]
		for i in range(3):
			var top := 408 + i * 174
			_panel(Rect2(85, top, 550, 158), Color.WHITE, 22, false)
			_rule_illustration(i, Rect2(104, top + 25, 112, 112))
			_wrap(titles[i], Rect2(236, top + 17, 375, 54), 24, INK, HORIZONTAL_ALIGNMENT_LEFT)
			_wrap(descriptions[i], Rect2(236, top + 79, 375, 65), 20, INK, HORIZONTAL_ALIGNMENT_LEFT)
		_wrap("Tap or drag to mark ×. Double-tap or right-click to place a cat. Undo costs 10% of this level's remaining points.", Rect2(100, 960, 520, 92), 22, MUTED)
		_button("close", Rect2(185, 1100, 350, 78), "Back to the puzzle", true, 26)
	elif modal == "scoring":
		_text("The Nine Lives score", Rect2(90, 395, 540, 52), 35)
		_wrap("Rarer clean solves earn more. Hints keep 44%, then 11%, then 0%. Misses compound. Each Undo keeps 90% of the remaining points.", Rect2(100, 471, 520, 101), 22)
		_text("Puzzle value: %s" % _number(int(challenge.get("base", 0))), Rect2(90, 595, 540, 38), 25)
		_text("One-heart bonus: %s" % ("+20%" if _starting_lives() == 1 else "not this level"), Rect2(90, 641, 540, 38), 23)
		_text("%d hints  ·  %d misses  ·  %d undos" % [revealed_hints.size(), level_misses, level_undos], Rect2(90, 694, 540, 38), 24)
		_text("LEVEL  %s" % _number(_level_score()), Rect2(90, 750, 540, 45), 32, GREEN)
		_text("TOTAL  %s" % _number(total_score), Rect2(90, 806, 540, 40), 27)
		_wrap("Points bank when you finish. Explain, Apply and reopening a clue cost no extra. A retry gives a new puzzle and full potential points. Hints stay available at zero.", Rect2(100, 864, 520, 96), 21, MUTED)
		_button("close", Rect2(185, 986, 350, 76), "Got it", true)
	elif modal in ["won", "round_won"]:
		_cat(Rect2(278, 378, 164, 168))
		_text("Round %d complete!" % round_number if modal == "round_won" else "Everybody's cozy!", Rect2(80, 558, 560, 52), 35)
		_text("Level %d complete" % (level + 1), Rect2(90, 614, 540, 35), 24, MUTED)
		_panel(Rect2(110, 666, 500, 112), Color("edf4eb"), 24, false)
		_text("+%s points" % _number(_level_score()), Rect2(120, 678, 480, 50), 38, GREEN)
		_text("TOTAL SCORE  %s" % _number(total_score), Rect2(120, 735, 480, 33), 23)
		var result := "%d hints  ·  %d misses  ·  %d undos" % [revealed_hints.size(), level_misses, level_undos]
		if not level_scores.has(str(level + 1)):
			result = "Completed before scoring was introduced"
		elif revealed_hints.is_empty() and level_misses == 0 and level_undos == 0:
			result = "Perfect paws! No hints, misses or undos."
		_text(result, Rect2(85, 797, 550, 36), 23)
		_wrap(_estimate() + ".", Rect2(95, 847, 530, 72), 20, MUTED)
		_button("next", Rect2(135, 958, 450, 88), "On to level %d" % (level + 2), true)
	elif modal == "lost":
		_cat(Rect2(275, 415, 170, 174))
		_text("Give it another try.", Rect2(90, 637, 540, 60), 40)
		_text("That was your last heart.", Rect2(90, 723, 540, 44), 27)
		_wrap("Your total score and level are safe. Retry with a brand-new puzzle, fresh hearts and full potential points.", Rect2(110, 804, 500, 100), 25, MUTED)
		_button("retry_puzzle", Rect2(135, 945, 450, 88), "Retry level %d" % (level + 1), true)
	elif modal == "generation_error":
		_text("Let's find another puzzle", Rect2(90, 540, 540, 60), 34)
		_wrap("That search took longer than expected. Your progress and lives are safe.", Rect2(110, 680, 500, 110), 26)
		_button("retry", Rect2(135, 910, 450, 88), "Try again", true)

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		_key(event)
		return
	if event is InputEventMouseMotion:
		var point: Vector2 = (event.position - design_offset) / design_scale
		hovered = _cell_at(point)
		if dragging and hovered >= 0 and not drag_cells.has(hovered):
			drag_cells.append(hovered)
			_mark(hovered, drag_value, false)
		return
	if event is InputEventMouseButton:
		if not event.pressed:
			if dragging:
				_save_progress()
			dragging = false
			return
		var point: Vector2 = (event.position - design_offset) / design_scale
		keyboard_visible = false
		for button in buttons:
			if button.rect.has_point(point):
				_action(button.id)
				get_viewport().set_input_as_handled()
				return
		var cell := _cell_at(point)
		if cell < 0:
			return
		var double_tap := cell == last_cell and clock_time - last_tap < 0.34
		if event.button_index == MOUSE_BUTTON_RIGHT or cat_mode or double_tap:
			_place(cell)
			last_cell = -1
			last_tap = -1
		else:
			last_cell = cell
			last_tap = clock_time
			drag_value = not marks.has(cell)
			drag_cells = [cell]
			dragging = true
			_mark(cell, drag_value, true)

func _key(event: InputEventKey) -> void:
	if event.keycode == KEY_ESCAPE:
		_back()
	elif screen == "game" and modal.is_empty() and not loading and not puzzle.is_empty():
		var n: int = puzzle.n
		if event.keycode in [KEY_LEFT, KEY_RIGHT, KEY_UP, KEY_DOWN]:
			keyboard_visible = true
			var change: int = {KEY_LEFT: -1, KEY_RIGHT: 1, KEY_UP: -n, KEY_DOWN: n}[event.keycode]
			keyboard_cell = clampi(keyboard_cell + change, 0, n * n - 1)
		elif event.keycode == KEY_SPACE or event.keycode == KEY_X:
			_mark(keyboard_cell, not marks.has(keyboard_cell), true)
		elif event.keycode == KEY_ENTER:
			_place(keyboard_cell)
		elif event.keycode == KEY_H:
			_action("hint")
		elif event.keycode == KEY_Z:
			_action("undo")

func _cell_at(point: Vector2) -> int:
	if screen != "game" or loading or not modal.is_empty() or puzzle.is_empty() or level_won:
		return -1
	var inner := BOARD.grow(-8)
	if not inner.has_point(point):
		return -1
	var n: int = puzzle.n
	var x := clampi(int((point.x - inner.position.x) / (644.0 / n)), 0, n - 1)
	var y := clampi(int((point.y - inner.position.y) / (644.0 / n)), 0, n - 1)
	return y * n + x

func _action(id: String) -> void:
	if id.begins_with("toggle_"):
		var key := id.trim_prefix("toggle_")
		settings[key] = not settings[key]
		_save_progress()
		return
	match id:
		"play":
			screen = "game"
			if round_seed == 0:
				round_seed = randi_range(1, 2000000000)
			if puzzle.is_empty():
				_generate()
			elif lives == 0:
				modal = "lost"
			elif level_won:
				modal = "round_won" if level % 10 == 9 else "won"
		"home":
			screen = "home"
			_save_progress()
		"settings":
			modal = "settings"
		"how":
			modal = "how"
		"scoring":
			modal = "scoring"
		"close":
			modal = ""
			if screen == "game":
				if level_won:
					modal = "round_won" if level % 10 == 9 else "won"
				elif lives == 0:
					modal = "lost"
		"next":
			if not level_won:
				return
			level += 1
			previous_layout = ""
			level_misses = 0
			level_undos = 0
			revealed_hints.clear()
			round_number = level / 10 + 1
			lives = _starting_lives()
			round_seed = randi_range(1, 2000000000)
			modal = ""
			_generate()
		"retry_puzzle":
			if lives > 0 or level_won:
				return
			previous_layout = engine.layout_key(puzzle)
			lives = _starting_lives()
			level_misses = 0
			level_undos = 0
			revealed_hints.clear()
			round_seed = (round_seed - 1 + randi_range(1, 1999999999)) % 2000000000 + 1
			modal = ""
			_generate()
		"retry":
			modal = ""
			round_seed = randi_range(1, 2000000000)
			_generate()
		"mode":
			cat_mode = not cat_mode
			last_cell = -1
		"undo":
			if not history.is_empty() and not loading and not level_won and lives > 0:
				marks = history.pop_back()
				level_undos += 1
				hint.clear()
				_save_progress()
		"hint":
			if not loading and not puzzle.is_empty() and not level_won and lives > 0:
				_show_hint()
		"dismiss_hint":
			hint.clear()

func _back() -> void:
	if not modal.is_empty() and modal in ["settings", "how", "scoring"]:
		_action("close")
	elif screen == "game":
		modal = ""
		screen = "home"
	_save_progress()

func _generate() -> void:
	_stop_worker()
	puzzle.clear()
	challenge.clear()
	cats.clear()
	marks.clear()
	history.clear()
	hint.clear()
	level_won = false
	loading = true
	cat_mode = false
	last_cell = -1
	dragging = false
	drag_cells.clear()
	error_cell = -1
	placed_cell = -1
	toast = ""
	elapsed = 0
	_save_progress()
	worker_engine = Puzzle.new()
	worker = Thread.new()
	worker.start(worker_engine.generate.bind(_difficulty(), round_seed + level * 104729, 8, 20000, previous_layout))

func _mark(cell: int, value: bool, remember: bool) -> void:
	if cats.has(cell) or level_won or loading:
		return
	if remember:
		history.append(marks.duplicate())
		if history.size() > 100:
			history.pop_front()
	hint.clear()
	if value and not marks.has(cell):
		marks.append(cell)
	elif not value:
		marks.erase(cell)
	_save_progress()

func _place(cell: int) -> void:
	if cats.has(cell) or level_won or lives <= 0 or loading:
		return
	hint.clear()
	history.clear()
	dragging = false
	if puzzle.solution.has(cell):
		cats.append(cell)
		marks.erase(cell)
		placed_cell = cell
		placed_at = clock_time
		if settings.auto_mark:
			for other in range(puzzle.n * puzzle.n):
				if not cats.has(other) and not marks.has(other) and engine.conflicts(cell, other, puzzle.n, puzzle.regions):
					marks.append(other)
		_check_win()
	else:
		lives -= 1
		level_misses += 1
		if not marks.has(cell):
			marks.append(cell)
		error_cell = cell
		error_until = clock_time + 2.5
		if settings.haptics and OS.get_name() == "Android":
			Input.vibrate_handheld(70)
		if lives == 0:
			modal = "lost"
		else:
			toast = "%d %s left in this puzzle" % [lives, "hearts" if lives != 1 else "heart"]
			toast_until = clock_time + 2.2
	_save_progress()

func _check_win() -> void:
	if level_won or cats.size() != puzzle.n:
		return
	level_won = true
	var score_key := str(level + 1)
	if not level_scores.has(score_key):
		var earned := ScoreRules.points(int(challenge.get("base", 0)), revealed_hints.size(), level_misses, _starting_lives() == 1, level_undos)
		level_scores[score_key] = earned
		total_score += earned
	cleared_puzzles += 1
	for i in range(puzzle.n * puzzle.n):
		if not cats.has(i) and not marks.has(i):
			marks.append(i)
	if cleared_puzzles % 10 == 0:
		cleared_rounds += 1
	modal = "round_won" if level % 10 == 9 else "won"
	for i in range(70):
		confetti.append({"p": Vector2(randf_range(70, 650), randf_range(-160, 200)), "v": Vector2(randf_range(-45, 45), randf_range(100, 260)), "angle": randf() * TAU, "spin": randf_range(-3, 3), "color": PALETTE[i % PALETTE.size()]})

func _show_hint() -> void:
	if not hint.is_empty():
		if hint_stage == 0:
			hint_stage = 1
		else:
			var chosen := hint.duplicate(true)
			hint.clear()
			if chosen.action == "cat":
				_place(chosen.cells[0])
			elif chosen.action == "unmark":
				history.append(marks.duplicate())
				for cell in chosen.cells:
					marks.erase(cell)
			else:
				history.append(marks.duplicate())
				engine.apply_step(chosen, cats, marks)
			_save_progress()
		return
	# A mistaken note is corrected before deductions are based on it.
	for cell in puzzle.solution:
		if marks.has(cell):
			hint = engine.step(0, "Take another look", "This crossed-out square still belongs in the solution. Clear its mark so it can be considered again.", "unmark", [cell], [cell])
			hint_stage = 0
			_count_hint()
			return
	hint = engine.next_hint(puzzle, cats, marks)
	if hint.has("contradiction") or hint.is_empty():
		hint.clear()
		toast = "Clear a few notes and look again."
		toast_until = clock_time + 2.5
	hint_stage = 0
	_count_hint()

func _count_hint() -> void:
	if hint.is_empty():
		return
	var cells: Array = hint.cells.duplicate()
	cells.sort()
	var key := JSON.stringify([hint.title, hint.action, cells])
	if not revealed_hints.has(key):
		revealed_hints.append(key)
	_save_progress()

func _save_progress() -> void:
	if not is_node_ready() or not persistence_enabled:
		return
	var data := {"version": 3, "round": round_number, "level": level, "lives": lives, "seed": round_seed, "puzzle": puzzle, "cats": cats, "marks": marks, "level_won": level_won, "cleared_rounds": cleared_rounds, "cleared_puzzles": cleared_puzzles, "settings": settings, "elapsed": elapsed, "level_scores": level_scores, "level_misses": level_misses, "revealed_hints": revealed_hints}
	data.previous_layout = previous_layout
	data.level_undos = level_undos
	var file := FileAccess.open(SAVE + ".tmp", FileAccess.WRITE)
	if file == null:
		push_error("Could not save progress: %s" % FileAccess.get_open_error())
		return
	file.store_string(JSON.stringify(data))
	file.close()
	var error := DirAccess.rename_absolute(SAVE + ".tmp", SAVE)
	if error != OK:
		push_error("Could not finish saving progress: %s" % error)

func _load_progress() -> void:
	if not persistence_enabled or not FileAccess.file_exists(SAVE):
		return
	var data = JSON.parse_string(FileAccess.get_file_as_string(SAVE))
	if not data is Dictionary or int(data.get("version", 0)) not in [1, 2, 3]:
		return
	level = maxi(0, int(data.get("level", 0)))
	round_seed = int(data.get("seed", 0))
	previous_layout = str(data.get("previous_layout", ""))
	cleared_rounds = maxi(0, int(data.get("cleared_rounds", 0)))
	cleared_puzzles = maxi(0, int(data.get("cleared_puzzles", 0)))
	level_won = bool(data.get("level_won", false))
	if int(data.version) == 1:
		# Old saves numbered levels within a round and counted failed attempts as rounds.
		level = maxi(level, cleared_puzzles - (1 if level_won else 0))
		cleared_rounds = maxi(cleared_rounds, cleared_puzzles / 10)
	round_number = level / 10 + 1
	lives = clampi(int(data.get("lives", _starting_lives())), 0, _starting_lives())
	if int(data.version) == 1 and lives > 0 and not level_won:
		lives = _starting_lives()
	level_scores = data.get("level_scores", {})
	total_score = 0
	for key in level_scores:
		level_scores[key] = maxi(0, int(level_scores[key]))
		total_score += level_scores[key]
	level_misses = maxi(0, int(data.get("level_misses", _starting_lives() - lives)))
	level_undos = maxi(0, int(data.get("level_undos", 0)))
	revealed_hints = data.get("revealed_hints", [])
	elapsed = float(data.get("elapsed", 0))
	for key in settings:
		settings[key] = bool(data.get("settings", {}).get(key, settings[key]))
	puzzle = data.get("puzzle", {})
	if not puzzle.is_empty():
		puzzle.n = int(puzzle.n)
		puzzle.regions = puzzle.regions.map(func(v): return int(v))
		puzzle.solution = puzzle.solution.map(func(v): return int(v))
		cats = data.get("cats", []).map(func(v): return int(v))
		marks = data.get("marks", []).map(func(v): return int(v))
		if puzzle.n < 8 and not level_won:
			# Upgrade the small legacy board without moving the player's level backward.
			puzzle.clear()
			cats.clear()
			marks.clear()
			lives = _starting_lives()
			level_misses = 0
			level_undos = 0
			revealed_hints.clear()
			elapsed = 0.0
		challenge = ScoreRules.profile(puzzle)
