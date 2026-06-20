extends Node

# High score manager - persists high scores to a JSON file
# Accessible as an autoload singleton

var high_scores: Array = []
var max_scores: int = 10
var save_path: String = "user://high_scores.json"

func _ready():
	load_high_scores()

# Load high scores from file
func load_high_scores():
	var file = FileAccess.open(save_path, FileAccess.READ)
	if file:
		var data = JSON.parse_string(file.get_as_text())
		if data and data is Array:
			high_scores = data
		file.close()
	else:
		# No file exists yet, start with empty list
		high_scores = []

# Save high scores to file
func save_high_scores():
	var file = FileAccess.open(save_path, FileAccess.WRITE)
	if file:
		var json = JSON.stringify(high_scores)
		file.store_string(json)
		file.close()

# Add a new high score entry
func add_high_score(score_name: String, score: int):
	var entry = {
		"name": score_name,
		"score": score,
		"date": Time.get_datetime_string_from_system()
	}
	high_scores.append(entry)
	# Sort by score descending (highest first)
	high_scores.sort_custom(func(a, b): return a.score > b.score)
	# Keep only top N scores
	if high_scores.size() > max_scores:
		high_scores.resize(max_scores)
	save_high_scores()

# Get formatted high score list
func get_high_scores() -> Array:
	return high_scores

# Get the highest score
func get_top_score() -> int:
	if high_scores.is_empty():
		return 0
	return high_scores[0].score

# Get high score display text
func get_high_score_text() -> String:
	if high_scores.is_empty():
		return "No high scores yet"
	
	var text = ""
	for entry in high_scores:
		var entry_name = entry.get("name", "Unknown")
		var score = entry.get("score", 0)
		text += "%s: %d\n" % [entry_name, score]
	return text.trim_suffix("\n")
