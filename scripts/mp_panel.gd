class_name MpPanel
extends PanelContainer

# Race info shown to a player who has finished: their time, this race's standings and the leaderboard.

const MAX_LINES := 8

var title: Label
var body: Label
var footer: Label


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_theme_stylebox_override("panel", Ui.panel_style())
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	add_child(box)
	title = Ui.ink_label("", 26)
	body = Ui.ink_label("", 18)
	footer = Ui.ink_label("", 18)
	for l in [title, body, footer]:
		l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		box.add_child(l)


func _ready() -> void:
	MP.state_changed.connect(refresh)
	refresh()


func _process(_delta: float) -> void:
	footer.text = _footer_text()


func refresh() -> void:
	title.text = MP.race_label()
	var lines: Array[String] = []
	var mine := MP.my_finish()
	if not mine.is_empty():
		lines.append("Your time: %s" % MP.time_text(float(mine["time"])))
		lines.append("")
	lines.append("This race")
	lines.append_array(_capped(MP.standings_lines()))
	lines.append("")
	lines.append("Leaderboard")
	lines.append_array(_capped(MP.leaderboard_lines()))
	body.text = "\n".join(lines)


func _capped(lines: Array[String]) -> Array[String]:
	if lines.size() <= MAX_LINES:
		return lines
	var out: Array[String] = []
	for i in MAX_LINES:
		out.append(lines[i])
	out.append("+%d more" % (lines.size() - MAX_LINES))
	return out


func _footer_text() -> String:
	match MP.phase():
		"racing":
			return "Waiting for the other racers..." + ("\nHost: press Enter to end the race" if Net.is_host else "")
		"between":
			return "Next race in %d" % ceili(MP.countdown)
	return ""
