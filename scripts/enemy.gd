extends CharacterBody2D

signal enemy_destroyed(enemy)

@export var health: int = 100
@export var speed: float = 60.0
@export var damage: int = 25

# Dash attack properties
@export var dash_speed: float = 800.0
@export var dash_telegraph_duration: float = 0.6 # Time to warn player before dash
@export var dash_cooldown_min: float = 1.0 # Min time between dashes
@export var dash_cooldown_max: float = 2.5 # Max time between dashes
@export var dash_damage: int = 40
@export var dash_path_damage: int = 120 # Triple damage for being in dash path

# Electrified status effect
@export var electrified_duration: float = 5.0 # How long electrified lasts
@export var electrified_damage_multiplier: float = 3.5 # 3.5x damage multiplier
@export var electrified_backstab_multiplier: float = 5.0 # 5x damage for backstab

enum State { IDLE, TELEGRAPH, DASH, COOLDOWN }

var player: CharacterBody2D
var push_dir: Vector2 = Vector2(0, 0)
var push_strength: float = 0.0
var push_timer: float = 0.0

# State machine
var current_state: State = State.IDLE
var state_timer: float = 0.0
var dash_direction: Vector2 = Vector2.RIGHT
var dash_target: Vector2
var dash_has_hit: bool = false

# Electrified state
var is_electrified: bool = false
var electrified_timer: float = 0.0

# Facing direction for backstab detection
var facing_direction: Vector2 = Vector2.RIGHT

# Telegraph visuals
var telegraph_box: ColorRect
var telegraph_arrows: Label
var dash_path_line: Line2D
var dash_path_active: bool = false
var dash_path_has_hit: bool = false
var dash_path_width: float = 40.0

@onready var animation_tree: AnimationTree = $AnimationTree
@onready var damage_text: Label = $DamageTextContainer/DamageText
@onready var blood_particle = preload("res://scenes/blood_particle.tscn")

func _ready():
	damage_text.visible = false
	_create_telegraph_visuals()
	_create_electrified_visuals()

func _create_telegraph_visuals():
	# Telegraph rectangle - shows where the dash will land
	telegraph_box = ColorRect.new()
	telegraph_box.color = Color(1, 0, 0, 0.4) # Red semi-transparent
	telegraph_box.size = Vector2(32, 48)
	telegraph_box.position = Vector2(0, -24) # Centered
	telegraph_box.visible = false
	add_child(telegraph_box)
	
	# Telegraph arrows - ">>" above enemy
	telegraph_arrows = Label.new()
	telegraph_arrows.text = ">>> "
	telegraph_arrows.position = Vector2(0, -40)
	telegraph_arrows.visible = false
	add_child(telegraph_arrows)
	
	# Dash path line - visualizes the trajectory
	dash_path_line = Line2D.new()
	dash_path_line.default_color = Color(1, 0.2, 0, 0.8)
	dash_path_line.width = 4.0
	dash_path_line.jmiter = 1
	dash_path_line.visible = false
	add_child(dash_path_line)

func _create_electrified_visuals():
	# Electric aura around enemy when electrified
	var electric_aura = ColorRect.new()
	electric_aura.name = "ElectricAura"
	electric_aura.color = Color(0.3, 0.5, 1.0, 0.3) # Blue semi-transparent
	electric_aura.size = Vector2(48, 64)
	electric_aura.position = Vector2(-24, -32)
	electric_aura.visible = false
	add_child(electric_aura)

func setup(pos: Vector2, _player: CharacterBody2D):
	position = pos
	player = _player

func _physics_process(delta):
	if not player:
		return
	
	# Handle electrified timer
	if is_electrified:
		electrified_timer -= delta
		if electrified_timer <= 0:
			_remove_electrified()
	
	# State machine
	match current_state:
		State.IDLE:
			_chase_player(delta)
			state_timer += delta
			if state_timer >= randf_range(dash_cooldown_min, dash_cooldown_max):
				_transition_to(State.TELEGRAPH)
		
		State.TELEGRAPH:
			_telegraph_phase(delta)
		
		State.DASH:
			_dash_phase(delta)
		
		State.COOLDOWN:
			state_timer += delta
			if state_timer >= 1.0: # Cooldown duration
				_transition_to(State.IDLE)

func _chase_player(delta):
	var dir = (player.global_position - global_position).normalized()
	facing_direction = dir
	position += dir * delta * speed
	# Handle push
	push_back(delta)

func _telegraph_phase(delta):
	# Stop moving, show telegraph indicators
	state_timer += delta
	
	# Calculate dash direction (toward player at start of telegraph)
	if state_timer == delta: # First frame
		dash_direction = (player.global_position - global_position).normalized()
		dash_target = global_position + dash_direction * 150 # Dash distance
		dash_has_hit = false
		dash_path_has_hit = false
		
		# Position telegraph box at dash target
		telegraph_box.global_position = dash_target
		telegraph_box.visible = true
		telegraph_arrows.visible = true
		
		# Draw dash path line from enemy to target
		dash_path_line.clear_points()
		dash_path_line.add_point(global_position - global_position) # Start at enemy position (local)
		dash_path_line.add_point(dash_target - global_position) # End at dash target
		dash_path_line.visible = true
		dash_path_active = true
		
		# Rotate arrows based on dash direction
		if dash_direction.x < 0:
			telegraph_arrows.text = " <<<"
			telegraph_arrows.position = Vector2(0, -40)
		else:
			telegraph_arrows.text = ">>>"
			telegraph_arrows.position = Vector2(0, -40)
	
	# Flash the telegraph box and line
	telegraph_box.modulate.a = 0.5 + sin(state_timer * 10.0) * 0.5
	dash_path_line.default_color.a = 0.5 + sin(state_timer * 10.0) * 0.5
	
	if state_timer >= dash_telegraph_duration:
		telegraph_box.visible = false
		telegraph_arrows.visible = false
		dash_path_line.visible = false
		dash_path_active = false
		_transition_to(State.DASH)

func _dash_phase(delta):
	# Fast movement toward dash target
	var dir = (dash_target - global_position).normalized()
	var distance_remaining = (dash_target - global_position).length()
	
	# Move toward target
	if distance_remaining > 5.0:
		position += dir * delta * dash_speed
		push_back(delta)
		
		# Update dash path line to follow enemy
		dash_path_line.clear_points()
		dash_path_line.add_point(Vector2.ZERO)
		dash_path_line.add_point(dash_target - global_position)
	else:
		# Reached target, transition to cooldown
		dash_path_active = false
		dash_path_line.visible = false
		_transition_to(State.COOLDOWN)

func _transition_to(new_state: State):
	current_state = new_state
	state_timer = 0.0
	dash_has_hit = false
	dash_path_has_hit = false

func apply_electrified(duration: float):
	is_electrified = true
	electrified_timer = duration
	$ElectricAura.visible = true

func _remove_electrified():
	is_electrified = false
	electrified_timer = 0.0
	if has_node("ElectricAura"):
		$ElectricAura.visible = false

func get_hit(incoming_damage: int, bullet_trans: Transform2D):
	var final_damage = incoming_damage
	
	# Check for electrified bonus damage
	if is_electrified:
		# Check if this is a backstab (attack from behind relative to enemy's facing direction)
		var attack_dir = (bullet_trans.origin - global_position).normalized()
		# Backstab: attack comes from opposite direction the enemy is facing
		# If enemy faces player (facing_direction toward player), backstab is from behind = opposite
		var is_backstab = (attack_dir.dot(facing_direction) < 0)
		
		if is_backstab:
			final_damage = int(final_damage * electrified_backstab_multiplier)
		else:
			final_damage = int(final_damage * electrified_damage_multiplier)
		
		# Remove electrified effect after damage is dealt
		_remove_electrified()
	
	health -= final_damage
	damage_text.text = str(final_damage)
	animation_tree['parameters/conditions/is_damaged'] = true
	if health <= 0:
		animation_tree['parameters/conditions/is_destroyed'] = true
	# Bleeding effect
	var bleeding_effect = blood_particle.instantiate()
	get_tree().root.add_child(bleeding_effect)
	bleeding_effect.setup(bullet_trans)
	set_push(Vector2.RIGHT.rotated(bullet_trans.get_rotation()), 150.0, 0.1)

func destroy():
	enemy_destroyed.emit(self)
	queue_free()

func set_push(dir: Vector2, strength: float, timer: float):
	push_dir = -dir
	push_strength = strength
	push_timer = timer

func push_back(delta: float):
	if push_timer > 0.0:
		position -= push_dir * push_strength * delta
		push_timer -= delta

func _on_damage_area_body_entered(body):
	if body == player and current_state == State.DASH:
		var knockback_dir = (player.global_position - global_position).normalized()
		
		# Check if player is in the dash path trajectory for triple damage
		var in_dash_path = false
		if dash_path_active:
			var player_to_enemy = player.global_position - global_position
			var projection = player_to_enemy.dot(dash_direction)
			var perpendicular_dist = (player_to_enemy - dash_direction * projection).length()
			in_dash_path = (perpendicular_dist < dash_path_width and projection > 0)
		
		if in_dash_path and not dash_path_has_hit:
			# Triple damage for being in the dash path
			player.take_damage(dash_path_damage, knockback_dir)
			dash_path_has_hit = true
		elif not dash_has_hit:
			# Normal touch damage for collision box contact
			player.take_damage(dash_damage, knockback_dir)
			dash_has_hit = true

func _on_animation_tree_animation_finished(anim_name):
	if anim_name == "get_damage":
		animation_tree['parameters/conditions/is_damaged'] = false
	elif anim_name == "destroy":
		animation_tree['parameters/conditions/is_destroyed'] = false
		destroy()

func _on_damage_area_body_entered(body):
	if body == player:
		# Touch damage - always deals damage when player touches enemy during dash
		if current_state == State.DASH:
			var knockback_dir = (player.global_position - global_position).normalized()
			player.take_damage(dash_damage, knockback_dir)
			if not dash_has_hit:
				dash_has_hit = true
		
		# Dash path damage - triple damage if player is in the dash trajectory
		if dash_path_active and current_state == State.DASH:
			# Check if player is within the dash path width
			var player_to_enemy = player.global_position - global_position
			var projection = player_to_enemy.dot(dash_direction)
			var perpendicular_dist = (player_to_enemy - dash_direction * projection).length()
			
			if perpendicular_dist < dash_path_width and projection > 0:
				var knockback_dir = (player.global_position - global_position).normalized()
				player.take_damage(dash_path_damage, knockback_dir)
				if not dash_path_has_hit:
					dash_path_has_hit = true
