extends Node

# Room Manager - handles room transitions, floor progression, keys, and enemy kill tracking
# Persistent room layouts per floor - rooms are randomly generated once per floor and persist throughout
signal floor_changed(new_floor)
signal key_received
signal room_changed(new_room)

var current_floor: int = 1
var current_room: int = 0
var total_enemies_on_floor: int = 0
var enemies_defeated_on_floor: int = 0
var player_has_key: bool = false

# Floor layout - generated once per floor and persists
# 2D grid layout with 3-4 connected rooms per floor
# Key: room_id (int), Value: {
#   grid_pos: Vector2i,           # Room position on 2D grid (row, col)
#   connections: Dictionary,      # Which walls have doors: {up: bool, down: bool, left: bool, right: bool}
#   enemy_count: int,
#   enemy_positions: Array[Vector2],
#   enemy_health: Array[int],
#   enemies_defeated: int,
#   is_cleared: bool,
#   urn_count: int,
#   urn_positions: Array[Vector2],
#   urn_broken: Array[bool],
#   has_progression_door: bool
# }
var floor_layout: Dictionary = {}

# Configuration
var enemies_per_room: int = 3
var kill_threshold_percent: float = 0.75
var max_floors: int = 5
var rooms_per_floor: int = 0  # Calculated in _ready() as 3-4 constant

# Room bounds
const ROOM_WIDTH: float = 1088.0
const ROOM_HEIGHT: float = 584.0
const ROOM_MARGIN: float = 16.0 # Minimum distance from edge

func get_room_bounds() -> Rect2:
	return Rect2(
		Vector2(ROOM_MARGIN, ROOM_MARGIN),
		Vector2(ROOM_WIDTH - ROOM_MARGIN, ROOM_HEIGHT - ROOM_MARGIN)
	)

func clamp_to_room_bounds(position: Vector2) -> Vector2:
	return Vector2(
		clampf(position.x, ROOM_MARGIN, ROOM_WIDTH - ROOM_MARGIN),
		clampf(position.y, ROOM_MARGIN, ROOM_HEIGHT - ROOM_MARGIN)
	)

func is_within_room_bounds(position: Vector2) -> bool:
	return (
		position.x >= ROOM_MARGIN and
		position.x <= ROOM_WIDTH - ROOM_MARGIN and
		position.y >= ROOM_MARGIN and
		position.y <= ROOM_HEIGHT - ROOM_MARGIN
	)

func _ready():
	current_floor = 1
	current_room = 0
	rooms_per_floor = randi() % 2 + 3  # Random 3-4 rooms per floor, constant
	total_enemies_on_floor = enemies_per_room * rooms_per_floor
	enemies_defeated_on_floor = 0
	player_has_key = false
	floor_layout = {}
	generate_floor_layout(current_floor)

func reset_room_manager():
	# Reset all room manager state for a fresh game
	current_floor = 1
	current_room = 0
	total_enemies_on_floor = enemies_per_room * rooms_per_floor
	enemies_defeated_on_floor = 0
	player_has_key = false
	floor_layout = {}
	generate_floor_layout(current_floor)

func generate_floor_layout(floor_number: int):
	# Generate 2D grid layout with 3-4 connected rooms
	# All rooms are connected - if no room exists on a wall, no door spawns there
	floor_layout = {}
	
	var total_rooms = rooms_per_floor
	
	# Generate random grid positions for rooms on a small grid
	# Use a 3x3 grid max, rooms won't overlap
	var grid_size = 3
	var room_positions = []
	
	# Place first room at center
	room_positions.append(Vector2i(1, 1))
	
	# Place remaining rooms adjacent to existing rooms
	for i in range(1, total_rooms):
		var placed = false
		var attempts = 0
		while not placed and attempts < 20:
			# Pick a random existing room to place next to
			var base_room_pos = room_positions[randi() % room_positions.size()]
			# Pick a random direction
			var directions = [Vector2i(-1, 0), Vector2i(1, 0), Vector2i(0, -1), Vector2i(0, 1)]
			var direction = directions[randi() % 4]
			var new_pos = base_room_pos + direction
			
			# Check bounds and no overlap
			if new_pos.x >= 0 and new_pos.x < grid_size and new_pos.y >= 0 and new_pos.y < grid_size:
				if not new_pos in room_positions:
					room_positions.append(new_pos)
					placed = true
			attempts += 1
		
		# Fallback: if can't place, just add a random position
		if not placed:
			var fallback_pos = Vector2i(randi() % grid_size, randi() % grid_size)
			while fallback_pos in room_positions:
				fallback_pos = Vector2i(randi() % grid_size, randi() % grid_size)
			room_positions.append(fallback_pos)
	
	# Build connections between adjacent rooms
	var connections = {}
	for i in range(total_rooms):
		connections[i] = {
			"up": false,
			"down": false,
			"left": false,
			"right": false
		}
	
	# Check each pair of rooms for adjacency
	for i in range(total_rooms):
		for j in range(i + 1, total_rooms):
			var pos_i = room_positions[i]
			var pos_j = room_positions[j]
			
			# Check if rooms are adjacent
			if pos_i.x == pos_j.x:
				# Same column, check vertical adjacency
				if pos_i.y == pos_j.y - 1:
					# i is above j
					connections[i]["down"] = true
					connections[j]["up"] = true
				elif pos_i.y == pos_j.y + 1:
					# i is below j
					connections[i]["up"] = true
					connections[j]["down"] = true
			elif pos_i.y == pos_j.y:
				# Same row, check horizontal adjacency
				if pos_i.x == pos_j.x - 1:
					# i is left of j
					connections[i]["right"] = true
					connections[j]["left"] = true
				elif pos_i.x == pos_j.x + 1:
					# i is right of j
					connections[i]["left"] = true
					connections[j]["right"] = true
	
	# Pick a random room for the progression door
	var progression_room = randi() % total_rooms
	
	for i in range(total_rooms):
		var enemy_count = enemies_per_room + floor_number  # Scale with floor
		
		# Generate random enemy positions for this room (stored for persistence)
		# Safe spawn zone: X: 150-900, Y: 150-500 (within room bounds 1088x584)
		var enemy_positions = []
		for j in range(enemy_count):
			enemy_positions.append(Vector2(randf_range(150, 900), randf_range(150, 500)))
		
		# Generate random urn positions (urns are rare - only 30% chance per room)
		var urn_count = 0
		if randf() < 0.3:  # 30% chance to spawn urns
			if floor_number >= 1:
				urn_count = 1  # Always just 1 urn when they do spawn
		
		var urn_positions = []
		for j in range(urn_count):
			urn_positions.append(Vector2(randf_range(150, 900), randf_range(150, 500)))
		
		var room_has_progression_door = false
		if i == progression_room:
			room_has_progression_door = true
		
		var broken_states = []
		for _b in range(urn_count):
			broken_states.append(false)
		
		floor_layout[i] = {
			"grid_pos": room_positions[i],
			"connections": connections[i],
			"enemy_count": enemy_count,
			"enemy_positions": enemy_positions,
			"enemy_health": [],  # Tracked as enemies are defeated
			"enemies_defeated": 0,
			"is_cleared": false,
			"urn_count": urn_count,
			"urn_positions": urn_positions,
			"urn_broken": broken_states,  # Track which urns are broken
			"has_progression_door": room_has_progression_door
		}
	
	# Calculate total enemies on this floor
	total_enemies_on_floor = 0
	for room_id in floor_layout:
		total_enemies_on_floor += floor_layout[room_id]["enemy_count"]

# Get connections for current room
func get_room_connections() -> Dictionary:
	if floor_layout.has(current_room):
		return floor_layout[current_room]["connections"]
	return {"up": false, "down": false, "left": false, "right": false}

# Navigate to connected room in given direction
func navigate_to_room(direction: String) -> int:
	# Find connected room in the given direction
	if not floor_layout.has(current_room):
		return -1
	
	var current_pos = floor_layout[current_room]["grid_pos"]
	var target_pos = current_pos
	
	match direction:
		"up":
			target_pos = current_pos + Vector2i(0, -1)
		"down":
			target_pos = current_pos + Vector2i(0, 1)
		"left":
			target_pos = current_pos + Vector2i(-1, 0)
		"right":
			target_pos = current_pos + Vector2i(1, 0)
	
	# Find room at target position
	for room_id in floor_layout:
		if floor_layout[room_id]["grid_pos"] == target_pos:
			return room_id
	
	return -1

func enemy_defeated():
	enemies_defeated_on_floor += 1
	# Track enemy defeat in current room state
	if floor_layout.has(current_room):
		floor_layout[current_room]["enemies_defeated"] += 1
		if floor_layout[current_room]["enemies_defeated"] >= floor_layout[current_room]["enemy_count"]:
			floor_layout[current_room]["is_cleared"] = true
		check_key_threshold()

func check_key_threshold():
	var threshold = total_enemies_on_floor * kill_threshold_percent
	if enemies_defeated_on_floor >= threshold and not player_has_key:
		player_has_key = true
		emit_signal("key_received")

func enter_door(direction: String) -> bool:
	if direction == "next_floor":
		# Move to next floor with key
		if player_has_key:
			current_floor += 1
			current_room = 0
			rooms_per_floor = randi() % 2 + 3  # 3-4 rooms per floor
			total_enemies_on_floor = 0
			enemies_defeated_on_floor = 0
			player_has_key = false
			generate_floor_layout(current_floor)
			emit_signal("floor_changed", current_floor)
			return true
		return false
	
	# For regular doors, navigate to connected room
	var target_room = navigate_to_room(direction)
	if target_room >= 0:
		current_room = target_room
		emit_signal("room_changed", current_room)
		return true
	
	return false

func get_enemy_count_for_room() -> int:
	if floor_layout.has(current_room):
		return floor_layout[current_room]["enemy_count"]
	return enemies_per_room + current_floor

# Get remaining enemies to spawn in current room
func get_remaining_enemies() -> int:
	if floor_layout.has(current_room):
		var remaining = floor_layout[current_room]["enemy_count"] - floor_layout[current_room]["enemies_defeated"]
		return max(0, remaining)
	return 0

# Get enemy positions for current room (for persistent spawning)
func get_enemy_positions() -> Array:
	if floor_layout.has(current_room):
		return floor_layout[current_room]["enemy_positions"]
	return []

# Get urn count for current room
func get_urn_count() -> int:
	if floor_layout.has(current_room):
		return floor_layout[current_room]["urn_count"]
	return 1

# Get urn positions for current room
func get_urn_positions() -> Array:
	if floor_layout.has(current_room):
		return floor_layout[current_room]["urn_positions"]
	return []

# Get which urns are already broken
func get_urn_broken_states() -> Array:
	if floor_layout.has(current_room):
		return floor_layout[current_room]["urn_broken"]
	return []

# Mark an urn as broken at a specific index
func mark_urn_broken(index: int):
	if floor_layout.has(current_room) and index < floor_layout[current_room]["urn_broken"].size():
		floor_layout[current_room]["urn_broken"][index] = true

# Check if current room has a progression door
func has_progression_door() -> bool:
	if floor_layout.has(current_room):
		return floor_layout[current_room]["has_progression_door"]
	return false

# Check if this room has been cleared before
func is_room_cleared() -> bool:
	if floor_layout.has(current_room):
		return floor_layout[current_room]["is_cleared"]
	return false

# Get number of enemies remaining to reach key threshold
func get_enemies_remaining_for_key() -> int:
	var threshold = total_enemies_on_floor * kill_threshold_percent
	var remaining = ceil(threshold) - enemies_defeated_on_floor
	return max(0, remaining)

# Check if player has the key for this floor
func has_key() -> bool:
	return player_has_key
