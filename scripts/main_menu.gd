extends Control

# Main menu scene
# Displays start button, high score, credits, settings, and exit option

@onready var start_button: Button = $VBoxContainer/StartButton
@onready var high_score_label: Label = $HighScoreLabel
@onready var exit_button: Button = $VBoxContainer/ExitButton
@onready var high_scores_button: Button = $VBoxContainer/HighScoresButton
@onready var credits_button: Button = $VBoxContainer/CreditsButton
@onready var credits_label: Label = $VBoxContainer/CreditsLabel
@onready var settings_button: Button = $VBoxContainer/SettingsButton
@onready var settings_panel: Panel = $SettingsPanel
@onready var resolution_option_button: OptionButton = $SettingsPanel/SettingsVBox/ResolutionOptionButton
@onready var apply_button: Button = $SettingsPanel/SettingsVBox/ApplyButton

# Available resolutions
var resolutions = [
	Vector2i(1280, 720),
	Vector2i(1920, 1080)
]

# Settings file path (same directory as high scores)
const SETTINGS_FILE = "user://settings.json"

# High scores toggle state
var showing_full_scores: bool = false

func _ready():
	update_high_score_display()
	populate_resolution_dropdown()
	load_settings()
	# Connect button signals
	start_button.pressed.connect(_on_start_button_pressed)
	exit_button.pressed.connect(_on_exit_button_pressed)
	high_scores_button.pressed.connect(_on_high_scores_button_pressed)
	credits_button.pressed.connect(_on_credits_button_pressed)
	settings_button.pressed.connect(_on_settings_button_pressed)
	apply_button.pressed.connect(_on_apply_button_pressed)

func populate_resolution_dropdown():
	# Add resolution options to the dropdown
	for resolution in resolutions:
		var res_text = "%dx%d" % [resolution.x, resolution.y]
		resolution_option_button.add_item(res_text)

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
	if showing_full_scores:
		update_high_score_display()
	else:
		var scores_text = HighScoreManager.get_high_score_text()
		high_score_label.text = scores_text
	showing_full_scores = !showing_full_scores

func _on_credits_button_pressed():
	# Toggle credits visibility
	credits_label.visible = !credits_label.visible

func _on_settings_button_pressed():
	# Toggle settings panel visibility
	settings_panel.visible = !settings_panel.visible

func _on_apply_button_pressed():
	# Apply resolution change and save settings
	var selected_index = resolution_option_button.selected
	if selected_index >= 0 and selected_index < resolutions.size():
		var resolution = resolutions[selected_index]
		DisplayServer.window_set_size(resolution)
		save_settings()

func load_settings():
	# Load saved settings from JSON file
	if not FileAccess.file_exists(SETTINGS_FILE):
		return
	var file = FileAccess.open(SETTINGS_FILE, FileAccess.READ)
	if file:
		var json = JSON.new()
		var data = json.parse(file.get_as_text())
		if data is Dictionary:
			# Load resolution setting
			if data.has("resolution_index"):
				var res_index = data["resolution_index"]
				if res_index >= 0 and res_index < resolutions.size():
					resolution_option_button.selected = res_index
		file.close()

func save_settings():
	# Save settings to JSON file
	var data = {
		"resolution_index": resolution_option_button.selected
	}
	var file = FileAccess.open(SETTINGS_FILE, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(data))
		file.close()
