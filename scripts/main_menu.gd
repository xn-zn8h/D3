extends Control

# Main menu scene
# Displays start button, high score, and exit option

@onready var start_button: Button = $VBoxContainer/StartButton
@onready var high_score_label: Label = $VBoxContainer/HighScoreLabel
@onready var exit_button: Button = $VBoxContainer/ExitButton
@onready var high_scores_button: Button = $VBoxContainer/HighScoresButton

func _ready():
	update_high_score_display()
	# Connect button signals
	start_button.pressed.connect(_on_start_button_pressed)
	exit_button.pressed.connect(_on_exit_button_pressed)
	high_scores_button.pressed.connect(_on_high_scores_button_pressed)

func update_high_score_display():
	var top_score = HighScoreManager.get_top_score()
	if top_score > 0:
		high_score_label.text = "Best Score: %d" % top_score
	else:
		high_score_label.text = "No scores yet"

func _on_start_button_pressed():
	# Load the game scene
	get_tree().change_scene_to_file("res://scenes/game.tscn")

func _on_exit_button_pressed():
	get_tree().quit()

func _on_high_scores_button_pressed():
	# Toggle showing full high score list
	var scores_text = HighScoreManager.get_high_score_text()
	if high_score_label.text.begins_with("No scores") or high_score_label.text.find("\n") > 0:
		high_score_label.text = scores_text
	else:
		update_high_score_display()
