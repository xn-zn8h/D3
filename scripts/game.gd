extends Node2D

@export var noise_shake_speed: float = 15.0
@export var noise_shake_strength: float = 16.0
@export var shake_decay_rate: float = 20.0

var start_pos: Vector2
var enemy_list: Array = []
var noise_i: float = 0.0
var shake_strength: float = 0.0

@onready var camera: Camera2D = $Camera2D
@onready var enemy_class = preload("res://scenes/enemy.tscn")
@onready var door_class = preload("res://scenes/door.tscn")
@onready var urn_class = preload("res://scenes/urn.tscn")
@onready var item_drop_class = preload("res://scenes/item_drop.tscn")
@onready var player: CharacterBody2D = $Player
@onready var noise = FastNoiseLite.new()
@onready var rand = RandomNumberGenerator.new()
@onready var player_stats: Node = $PlayerStats
var room_manager = RoomManager
@onready var hud_health_bar: ProgressBar = $HUD/HealthBar
@onready var hud_health_text: Label = $HUD/HealthText
@onready var hud_floor_text: Label = $HUD/FloorText
@onready var hud_key_text: Label = $HUD/KeyText
@onready var hud_enemy_counter: Label = $HUD/EnemyCounterText
@onready var game_over_label: Label = $HUD/GameOverLabel
@onready var pause_menu: Control = $HUD/PauseMenu
@onready var death_screen: Control = $HUD/DeathScreen
@onready var death_score_label: Label = $HUD/DeathScreen/DeathVBox/ScoreLabel
@onready var name_input: LineEdit = $HUD/DeathScreen/DeathVBox/NameInput
@onready var submit_score_button: Button = $HUD/DeathScreen/DeathVBox/SubmitScoreButton
@onready var high_score_display: Label = $HUD/DeathScreen/DeathVBox/HighScoreDisplay

var is_game_over: bool = false
var is_paused: bool = false
var is_transitioning: bool = false  # Guard against rapid room transitions
var urn_list: Array = []  # Track active urns in current room
var door_list: Array = []  # Track active doors in current room
var current_score: int = 0  # Score metric (current floor)

# Inventory system
var inventory: Dictionary = {}  # item_id -> count
var inventory_panel: Control = null
var inventory_vbox: VBoxContainer = null

func _ready():
	var screen_size = get_viewport_rect().size
	start_pos = Vector2(screen_size.x/2, screen_size.y/2)
	player.setup(start_pos)
	# Wire up stat manager to player
	player.stats = player_stats
	# Connect signals
	player_stats.player_died.connect(_on_player_died)
	player_stats.health_changed.connect(_on_health_changed)
	room_manager.key_received.connect(_on_key_received)
	room_manager.floor_changed.connect(_on_floor_changed)
	room_manager.room_changed.connect(_on_room_changed)
	# Initialize HUD - ensure visibility
	print("[HUD] Initializing HUD elements...")
	var default_font = ThemeDB.fallback_font
	for child in $HUD.get_children():
		if child != game_over_label and child != pause_menu and child != death_screen:
			child.visible = true
			if child is Label:
				child.add_theme_color_override("font_color", Color.WHITE)
				child.add_theme_font_override("font", default_font)
				child.add_theme_font_size_override("font_size", 16)
				print("[HUD] Made visible: ", child.name, " - text: WHITE, size: 16")
			elif child is ProgressBar:
				print("[HUD] Made visible: ", child.name)
	game_over_label.add_theme_font_override("font", default_font)
	game_over_label.add_theme_font_size_override("font_size", 48)
	print("[HUD] GameOverLabel font size: 48")
	
	hud_health_bar.max_value = player_stats.max_health
	hud_health_bar.value = player_stats.current_health
	hud_health_text.text = "HP: %d/%d" % [player_stats.current_health, player_stats.max_health]
	hud_key_text.visible = false
	game_over_label.visible = false
	
	# Create inventory HUD panel
	_create_inventory_hud()
	pause_menu.visible = false
	death_screen.visible = false
	
	# Apply theme overrides to death screen labels for readability
	var death_title: Label = $HUD/DeathScreen/DeathVBox/DeathTitle
	death_title.add_theme_color_override("font_color", Color.WHITE)
	death_title.add_theme_font_override("font", default_font)
	death_title.add_theme_font_size_override("font_size", 32)
	death_score_label.add_theme_color_override("font_color", Color(1.0, 0.4, 0.4, 1.0))
	death_score_label.add_theme_font_override("font", default_font)
	death_score_label.add_theme_font_size_override("font_size", 18)
	$HUD/DeathScreen/DeathVBox/HighScoreDisplay.add_theme_color_override("font_color", Color(0.7, 1.0, 0.7, 1.0))
	$HUD/DeathScreen/DeathVBox/HighScoreDisplay.add_theme_font_override("font", default_font)
	$HUD/DeathScreen/DeathVBox/HighScoreDisplay.add_theme_font_size_override("font_size", 16)
	
	# Connect pause menu button signals
	$HUD/PauseMenu/PauseVBox/ResumeButton.pressed.connect(_on_resume_button_pressed)
	$HUD/PauseMenu/PauseVBox/RestartButton.pressed.connect(_on_restart_button_pressed)
	$HUD/PauseMenu/PauseVBox/QuitButton.pressed.connect(_on_quit_button_pressed)
	
	# Connect death screen button signals
	$HUD/DeathScreen/DeathVBox/SubmitScoreButton.pressed.connect(_on_submit_score_pressed)
	$HUD/DeathScreen/DeathVBox/DeathRestartButton.pressed.connect(_on_death_restart_pressed)
	$HUD/DeathScreen/DeathVBox/DeathQuitButton.pressed.connect(_on_death_quit_pressed)
	
	# CRITICAL: Set process mode to ALWAYS so _input() works when tree is paused
	# This allows ESC key to toggle pause/unpause and work during death screen
	process_mode = Node.PROCESS_MODE_ALWAYS
	
	# Set initial floor text before room setup
	hud_floor_text.text = "Floor: %d" % room_manager.current_floor
	print("[HUD] Initial floor: ", room_manager.current_floor)
	print("[HUD] All HUD elements initialized")
	# Camera shake related
	rand.randomize()
	noise.seed = rand.randi()
	noise.frequency = 0.1
	# Initial room setup (will call update_floor_hud and update_enemy_counter_hud internally)
	setup_room()

func setup_room():
	# GUARD: Prevent re-entrant room setup during transitions
	if is_transitioning:
		return
	
	is_transitioning = true
	
	# CRITICAL FIX: Clean up ALL enemies before checking room state
	# This prevents enemies from being in mid-attack state when destroyed
	for enemy in enemy_list:
		if is_instance_valid(enemy):
			# Stop all processing before freeing
			enemy.set_process(false)
			enemy.set_physics_process(false)
			enemy.queue_free()
	enemy_list.clear()
	
	# Clean up all urns from previous room
	for urn in urn_list:
		if is_instance_valid(urn):
			urn.queue_free()
	urn_list.clear()
	
	# Clean up all doors from previous room
	for door in door_list:
		if is_instance_valid(door):
			door.queue_free()
	door_list.clear()
	
	# Clean up any item drops
	for child in get_children():
		if child.has_method("is_in_group") and child.is_in_group("item_drop"):
			child.queue_free()
	
	# Room state is already generated by room_manager.generate_floor_layout()
	# Get persistent enemy data for this room
	var enemy_positions = room_manager.get_enemy_positions()
	var enemies_remaining = room_manager.get_remaining_enemies()
	
	# Spawn remaining enemies at persistent positions
	for i in range(enemies_remaining):
		if i < enemy_positions.size():
			spawn_enemy_at(enemy_positions[i])
		else:
			spawn_enemy()
	
	# Spawn urns at persistent positions (skip already-broken urns)
	var urn_positions = room_manager.get_urn_positions()
	var urn_broken_states = room_manager.get_urn_broken_states()
	for i in range(urn_positions.size()):
		if not (i < urn_broken_states.size() and urn_broken_states[i]):
			spawn_urn_at(urn_positions[i], i)
	
	# Spawn doors
	spawn_doors()
	
	# Update all HUD elements after room setup
	update_floor_hud()
	update_enemy_counter_hud()
	_enforce_hud_visibility()
	
	# Small delay to ensure cleanup is complete before allowing next transition
	await get_tree().create_timer(0.1).timeout
	is_transitioning = false

func _enforce_hud_visibility():
	# Ensure all HUD elements are visible after room transitions
	# Exclude pause_menu, death_screen, game_over_label, and inventory_panel from being forced visible
	for child in $HUD.get_children():
		if child != game_over_label and child != pause_menu and child != death_screen and child != inventory_panel:
			child.visible = true
	# Inventory should be hidden unless paused
	if inventory_panel:
		inventory_panel.visible = is_paused

func spawn_enemy():
	var enemy = enemy_class.instantiate()
	enemy.connect("enemy_destroyed", on_enemy_destroyed)
	var pos = Vector2(randf_range(100, 1000), randf_range(150, 500))
	enemy.setup(pos, player)
	get_tree().root.add_child.call_deferred(enemy)
	enemy_list.append(enemy)

func spawn_enemy_at(pos: Vector2):
	var enemy = enemy_class.instantiate()
	enemy.connect("enemy_destroyed", on_enemy_destroyed)
	enemy.setup(pos, player)
	get_tree().root.add_child.call_deferred(enemy)
	enemy_list.append(enemy)

func spawn_urn():
	var urn = urn_class.instantiate()
	urn.load_item_pool()
	_urn_connect_and_add(urn, Vector2(randf_range(100, 1000), randf_range(150, 500)), -1)

func spawn_urn_at(pos: Vector2, urn_index: int):
	var urn = urn_class.instantiate()
	urn.load_item_pool()
	_urn_connect_and_add(urn, pos, urn_index)

func _urn_connect_and_add(urn, pos: Vector2, urn_index: int):
	# Store urn index as metadata for broken tracking
	urn.set_meta("urn_index", urn_index)
	urn.connect("urn_broken", _on_urn_broken)
	urn.position = pos
	add_child.call_deferred(urn)
	urn_list.append(urn)

func _on_urn_broken(item_data: Resource, urn_position: Vector2):
	# Find the urn by position and mark it as broken in room_manager
	for urn in urn_list:
		if is_instance_valid(urn) and urn.position == urn_position:
			var urn_index = urn.get_meta("urn_index", -1)
			if urn_index != -1:
				room_manager.mark_urn_broken(urn_index)
			break
	# Spawn item drop at urn position (deferred to avoid physics flush during signal callback)
	var item_drop = item_drop_class.instantiate()
	item_drop.item_resource = item_data
	item_drop.position = urn_position
	# Signal already carries item_resource, so handler receives it directly - no .bind() needed
	item_drop.item_picked_up.connect(func(item_resource):
		_on_item_picked_up(item_resource)
	)
	add_child.call_deferred(item_drop)
	# Note: Notification is shown in _on_item_picked_up when player actually collects the item

func show_item_notification(item_data: Resource):
	# Create floating text notification
	var notif = Label.new()
	notif.text = "📦 " + item_data.display_name
	notif.position = Vector2(544, 100)
	notif.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	notif.add_theme_color_override("font_color", Color(1, 1, 1, 1))
	notif.add_theme_font_size_override("font_size", 20)
	$HUD.add_child(notif)
	# Animate notification
	var tween = create_tween()
	tween.tween_property(notif, "position:y", 50, 2.0)
	tween.tween_property(notif, "modulate:a", 0.0, 1.0)
	tween.tween_interval(1.0)
	tween.tween_property(notif, "modulate:a", 0.0, 0.5)
	tween.tween_callback(notif.queue_free)

func spawn_doors():
	# Defer door spawning to avoid physics flush errors during signal callback
	# Doors are spawned from _on_door_entered -> setup_room -> spawn_doors
	# which happens during physics query processing
	_spawn_doors.call_deferred()

func _spawn_doors():
	var room_width = 1088
	var room_height = 584
	var center_x = float(room_width) / 2
	var center_y = float(room_height) / 2
	
	# Get room connections for 2D grid navigation
	var connections = room_manager.get_room_connections()
	var has_up = connections.get("up", false)
	var has_down = connections.get("down", false)
	var has_left = connections.get("left", false)
	var has_right = connections.get("right", false)
	
	# Door to the right (only if room exists in that direction)
	if has_right:
		var door_right = door_class.instantiate()
		door_right.door_direction = "right"
		door_right.position = Vector2(1060, center_y)
		door_right.name = "Door"
		door_right.connect("door_entered", _on_door_entered)
		add_child(door_right)
		door_list.append(door_right)
	
	# Door to the left (only if room exists in that direction)
	if has_left:
		var door_left = door_class.instantiate()
		door_left.door_direction = "left"
		door_left.position = Vector2(92, center_y)
		door_left.name = "Door"
		door_left.connect("door_entered", _on_door_entered)
		add_child(door_left)
		door_list.append(door_left)
	
	# Door to the up (only if room exists in that direction)
	if has_up:
		var door_up = door_class.instantiate()
		door_up.door_direction = "up"
		door_up.position = Vector2(center_x, 50)  # Top of screen (leads to room above)
		door_up.name = "Door"
		door_up.connect("door_entered", _on_door_entered)
		add_child(door_up)
		door_list.append(door_up)

	# Door to the down (only if room exists in that direction)
	if has_down:
		var door_down = door_class.instantiate()
		door_down.door_direction = "down"
		door_down.position = Vector2(center_x, 560)  # Bottom of screen (leads to room below)
		door_down.name = "Door"
		door_down.connect("door_entered", _on_door_entered)
		add_child(door_down)
		door_list.append(door_down)
	
	# Progression door to next floor (spawns in CENTER of room)
	if room_manager.has_progression_door():
		var door_next = door_class.instantiate()
		door_next.door_direction = "next_floor"
		door_next.door_color = Color(0.8, 0.6, 0.2, 1.0)
		door_next.position = Vector2(center_x, center_y)  # CENTER of room
		door_next.name = "Door"
		door_next.connect("door_entered", _on_door_entered)
		add_child(door_next)
		door_list.append(door_next)

func _on_door_entered(direction: String):
	var success = room_manager.enter_door(direction)
	if success:
		# Mark the triggering door as triggered so it can't be reused
		for door in door_list:
			if is_instance_valid(door) and door.door_direction == direction and not door.triggered:
				door.mark_triggered()
				break
		setup_room()
		# Move player to door position based on direction entered
		match direction:
			"right":
				# Entered right door, spawn at left side of new room
				player.position = Vector2(150, 292)
			"left":
				# Entered left door, spawn at right side of new room
				player.position = Vector2(900, 292)
			"up":
				# Entered up door, spawn at bottom of new room
				player.position = Vector2(544, 500)
			"down":
				# Entered down door, spawn at top of new room
				player.position = Vector2(544, 150)
			"next_floor":
				# Next floor, spawn at center
				player.position = Vector2(544, 292)
			_:
				# Default to center for unknown directions
				player.position = Vector2(544, 292)
		update_floor_hud()
		if direction == "next_floor":
			hud_key_text.visible = false

func _on_item_picked_up(item_data: Resource):
	# Apply item stats to player
	if item_data:
		item_data.apply_to_stats(player_stats)
		# Track in inventory
		var item_id = item_data.item_id if item_data is ItemData else "unknown"
		if item_id == "":
			item_id = "unknown"
		if inventory.has(item_id):
			inventory[item_id] += 1
		else:
			inventory[item_id] = 1
		update_inventory(item_id, inventory[item_id])
		# Show pickup confirmation
		show_item_notification(item_data)

func _on_key_received():
	hud_key_text.visible = true
	hud_key_text.text = "KEY ACQUIRED!"

func _on_floor_changed(_new_floor: int):
	update_floor_hud()
	update_enemy_counter_hud()

func _on_room_changed(_new_room: int):
	# Update HUD when changing rooms
	update_enemy_counter_hud()

func update_floor_hud():
	print("[HUD] Updating floor text to: ", room_manager.current_floor)
	hud_floor_text.text = "Floor: %d" % room_manager.current_floor
	hud_floor_text.visible = true

func update_enemy_counter_hud():
	print("[HUD] Updating enemy counter...")
	if room_manager.has_key():
		hud_enemy_counter.text = "Key: ACQUIRED"
		hud_enemy_counter.modulate = Color(1, 0.8, 0.2, 1)
	else:
		var remaining = room_manager.get_enemies_remaining_for_key()
		hud_enemy_counter.text = "Enemies to door: %d" % remaining
		hud_enemy_counter.modulate = Color(0.9, 0.9, 0.9, 1)
	hud_enemy_counter.visible = true

func _process(delta: float):
	if not is_game_over and enemy_list.size() == 0:
		# Only auto-spawn if not in a room transition
		pass
	shake_camera(delta)

func _on_player_died():
	is_game_over = true
	current_score = room_manager.current_floor  # Score = floors completed
	# Stop all enemies and player
	for enemy in enemy_list:
		if is_instance_valid(enemy):
			enemy.queue_free()
	enemy_list.clear()
	# Disable player input
	player.set_process(false)
	player.set_physics_process(false)
	# Show death screen with high score entry
	game_over_label.visible = false
	death_screen.visible = true
	# CRITICAL: Set death screen to always process so UI works when tree is paused
	death_screen.process_mode = Node.PROCESS_MODE_ALWAYS
	death_score_label.text = "You reached floor %d" % current_score
	name_input.text = ""
	name_input.grab_focus()
	submit_score_button.visible = true
	high_score_display.visible = false
	# Pause the game AFTER showing death screen and grabbing focus
	get_tree().paused = true

func _on_health_changed(current_health: int, max_health: int):
	hud_health_bar.max_value = max_health
	hud_health_bar.value = current_health
	hud_health_text.text = "HP: %d/%d" % [current_health, max_health]

func _create_inventory_hud():
	# Create panel for inventory
	inventory_panel = Panel.new()
	inventory_panel.name = "InventoryPanel"
	inventory_panel.anchor_right = 0.0
	inventory_panel.anchor_bottom = 1.0
	inventory_panel.offset_left = 10.0
	inventory_panel.offset_top = 10.0
	inventory_panel.offset_right = 160.0
	inventory_panel.offset_bottom = -100.0
	$HUD.add_child(inventory_panel)
	
	# Create VBoxContainer for inventory items
	inventory_vbox = VBoxContainer.new()
	inventory_vbox.name = "InventoryVBox"
	inventory_panel.add_child(inventory_vbox)
	
	# Add title label
	var title_label = Label.new()
	title_label.text = "— INVENTORY —"
	title_label.add_theme_color_override("font_color", Color.WHITE)
	title_label.add_theme_font_override("font", ThemeDB.fallback_font)
	title_label.add_theme_font_size_override("font_size", 14)
	inventory_vbox.add_child(title_label)

func update_inventory(item_id: String, count: int):
	# Update inventory dictionary
	if count <= 0:
		inventory.erase(item_id)
	else:
		inventory[item_id] = count
	
	# Refresh HUD display
	_refresh_inventory_hud()

func _refresh_inventory_hud():
	# Clear existing labels (keep title)
	for child in inventory_vbox.get_children():
		if child is Label and child.text != "— INVENTORY —":
			child.queue_free()
	
	# Add labels for each item in inventory
	for item_id in inventory:
		var count = inventory[item_id]
		if count > 0:
			var label = Label.new()
			# Abbreviated name: first 2 letters of each word in item_id
			var short_name = _get_short_name(item_id)
			label.text = "%s: %d" % [short_name, count]
			label.add_theme_color_override("font_color", Color.WHITE)
			label.add_theme_font_override("font", ThemeDB.fallback_font)
			label.add_theme_font_size_override("font_size", 14)
			inventory_vbox.add_child(label)

func _get_short_name(item_id: String) -> String:
	# Convert item_id like "demon_fang" to "DeFa"
	var parts = item_id.split("_")
	var result = ""
	for part in parts:
		if part.length() >= 2:
			result += part.substr(0, 1).to_upper() + part.substr(1, 1).to_lower()
		elif part.length() == 1:
			result += part.substr(0, 1).to_upper()
	return result

func _input(event):
	# Handle pause menu toggle (ESC key)
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		if not is_game_over and not death_screen.visible:
			toggle_pause()
		return
	
	if is_paused:
		return
	
	if is_game_over and event is InputEventKey and event.pressed:
		if event.keycode == KEY_R:
			get_tree().reload_current_scene()
		if event.keycode == KEY_ESCAPE:
			# Allow ESC to quit to main menu from game over
			change_to_main_menu()

func toggle_pause():
	is_paused = !is_paused
	get_tree().paused = is_paused
	pause_menu.visible = is_paused
	# Show/hide inventory with pause menu
	if inventory_panel:
		inventory_panel.visible = is_paused
	if is_paused:
		player.set_process(false)
		player.set_physics_process(false)
	else:
		if not is_game_over:
			player.set_process(true)
			player.set_physics_process(true)

func _on_resume_button_pressed():
	toggle_pause()

func _on_restart_button_pressed():
	get_tree().paused = false
	get_tree().reload_current_scene()

func _on_quit_button_pressed():
	get_tree().paused = false
	change_to_main_menu()

func change_to_main_menu():
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")

func _on_submit_score_pressed():
	var score_name = name_input.text.strip_edges()
	if score_name.is_empty():
		score_name = "Anonymous"
	HighScoreManager.add_high_score(score_name, current_score)
	high_score_display.visible = true
	high_score_display.text = "Score saved!"
	submit_score_button.visible = false

func _on_death_restart_pressed():
	get_tree().paused = false
	get_tree().reload_current_scene()

func _on_death_quit_pressed():
	get_tree().paused = false
	change_to_main_menu()

func shake_camera(delta: float):
	# Fade out the intensity over time
	shake_strength = lerp(shake_strength, 0.0, shake_decay_rate * delta)
	var shake_offset: Vector2
	shake_offset = get_noise_offset(delta, noise_shake_speed, shake_strength)
	# Shake by adjusting camera.offset, move the camera via it's position
	camera.offset = shake_offset

func get_noise_offset(delta: float, speed: float, strength: float) -> Vector2:
	noise_i += delta * speed
	# Set the x values of each call to 'get_noise_2d' to a different value
	# so that our x and y vectors will be reading from unrelated areas of noise
	return Vector2(
		noise.get_noise_2d(1, noise_i) * strength,
		noise.get_noise_2d(100, noise_i) * strength
	)

func get_random_offset() -> Vector2:
	return Vector2(
		rand.randf_range(-shake_strength, shake_strength),
		rand.randf_range(-shake_strength, shake_strength)
	)

func on_enemy_destroyed(enemy):
	var index = enemy_list.find(enemy)
	if index != -1:
		enemy_list.remove_at(index)
	room_manager.enemy_defeated()
	update_enemy_counter_hud()
