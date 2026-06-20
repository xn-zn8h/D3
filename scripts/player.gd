extends CharacterBody2D

@export var speed: float = 360.0
@export var attack_damage: int = 30
@export var attack_duration: float = 0.12
@export var melee_cooldown: float = 0.12
@export var ranged_cooldown: float = 0.45
@export var ranged_charge_time: float = 0.25
@export var charge_delay: float = 0.1 # Delay before charge bar appears
@export var ranged_projectile_speed: float = 800.0
@export var lr_flag: bool = true # Enable body left right animation
@export var rotate_flag: bool = true # Enable body rotation

var screen_size # Size of the game window.
var lr: bool = true # Default face right
var aim_pos: Vector2 = Vector2(0, 0)
var is_shot_cd: bool = false
var is_charging_shot: bool = false
var shot_hold_time: float = 0.0
var ranged_shot_fired: bool = false
var attack_time_left: float = 0.0
var hit_enemies: Array = []
var push_dir: Vector2 = Vector2(0, 0)
var push_strength: float = 0.0
var push_timer: float = 0.0
var stats: Node = null # Reference to player_stats manager
var is_invulnerable: bool = false
var invulnerability_timer: float = 0.0
var attack_cone_visible: bool = false

# Reference
@onready var body_lr: Polygon2D = $BodyLR
@onready var body_rotate: Polygon2D = $BodyRotate
@onready var body_lr_player: AnimationPlayer = $BodyLRPlayer
@onready var body_rotete_player: AnimationPlayer = $BodyRotatePlayer
@onready var move_trail_effect: GPUParticles2D = $MovementTrailEffect
@onready var sword_pivot: Node2D = $BodyRotate/SwordPivot
@onready var sword_hitbox: Area2D = $BodyRotate/SwordPivot/SwordHitbox
@onready var shot_timer: Timer = $ShotTimer
@onready var body_lr_collider: CollisionPolygon2D = $CollisionBodyLR
@onready var audio_player: AudioStreamPlayer = $AudioStreamPlayer
@onready var charge_bar: ProgressBar = $ChargeBar
@onready var bullet_class = preload("res://scenes/bullet.tscn")

func _ready():
	screen_size = get_viewport_rect().size
	sword_pivot.rotation = 0.0
	hide()
	charge_bar.visible = false
	charge_bar.min_value = 0.0
	charge_bar.max_value = ranged_charge_time
	charge_bar.value = 0.0
	
	# Create attack cone visualization for melee attacks
	var attack_cone = Polygon2D.new()
	attack_cone.name = "AttackCone"
	var cone_points = PackedVector2Array()
	var cone_angle: float = deg_to_rad(180.0) # 180-degree cone
	var cone_length: float = 64.0 # Match sword range
	var segments: int = 20
	# Create sector shape
	cone_points.append(Vector2(0, 0)) # Center point
	for i in range(segments + 1):
		var angle = -cone_angle / 2.0 + (cone_angle * i / segments)
		cone_points.append(Vector2(cos(angle) * cone_length, sin(angle) * cone_length))
	cone_points.append(Vector2(0, 0)) # Close the shape
	attack_cone.polygon = cone_points
	attack_cone.color = Color(1.0, 0.8, 0.2, 0.4) # Golden semi-transparent
	attack_cone.visible = false
	sword_pivot.add_child(attack_cone)

func _physics_process(delta):
	velocity = Vector2.ZERO # The player's movement vector.
	# Movement input
	if Input.is_action_pressed("move_right"):
		velocity.x += 1
	if Input.is_action_pressed("move_left"):
		velocity.x -= 1
	if Input.is_action_pressed("move_down"):
		velocity.y += 1
	if Input.is_action_pressed("move_up"):
		velocity.y -= 1
	# Attack input - Quick tap = melee, Hold = ranged
	if Input.is_action_just_pressed("shot") and not is_shot_cd:
		is_charging_shot = true
		shot_hold_time = 0.0
		ranged_shot_fired = false
	if is_charging_shot and not is_shot_cd:
		shot_hold_time += delta
		if shot_hold_time >= charge_delay:
			charge_bar.visible = true
			charge_bar.value = shot_hold_time - charge_delay
		if shot_hold_time >= ranged_charge_time and not ranged_shot_fired:
			fire_ranged_attack()
			ranged_shot_fired = true
			charge_bar.visible = false
	if Input.is_action_just_released("shot"):
		if is_charging_shot and not ranged_shot_fired and not is_shot_cd:
			attack()
			is_shot_cd = true
			shot_timer.start(melee_cooldown)
		is_charging_shot = false
		charge_bar.visible = false
	# Normalize velocity if move along x and y together
	if velocity.length() > 0:
		velocity = velocity.normalized() * speed
		move_trail_effect.emitting = true # Play movement trail effect
	else:
		move_trail_effect.emitting = false # Stop trail when not moving
	update_sword_attack(delta)
	# Handle body_lr
	update_body_lr()
	# Handle push
	push_back(delta)
	# Handle invulnerability (iFrames)
	if is_invulnerable:
		invulnerability_timer -= delta
		if invulnerability_timer <= 0:
			is_invulnerable = false
	# Limit the player movement, add your character scale if needed
	position.x = clamp(position.x, 0, screen_size.x)
	position.y = clamp(position.y, 0, screen_size.y)
	move_and_slide()

func _input(event):
	if event is InputEventMouseMotion:
		update_body_rotate(event.position)

func setup(pos: Vector2):
	position = pos
	show()

func update_body_lr():
	if not lr_flag:
		return
	# Play body animation
	if velocity.length() > 0:
		# Move up / down
		if lr:
			body_lr_player.play("MoveR")
		else:
			body_lr_player.play("MoveL")
		# Move left / right
		if velocity.x > 0:
			body_lr_player.play("MoveR")
			body_lr_collider.scale.x = -1
			lr = true
		elif velocity.x < 0:
			body_lr_player.play("MoveL")
			body_lr_collider.scale.x = 1
			lr = false
	else:
		# Idle
		if lr:
			body_lr_player.play("IdleR")
		else:
			body_lr_player.play("IdleL")

func update_body_rotate(mouse_pos: Vector2):
	if not rotate_flag:
		return
	# Rotate with mouse
	body_rotate.look_at(mouse_pos)
	aim_pos = mouse_pos.normalized()

func attack():
	body_rotete_player.play("Shot")
	attack_time_left = attack_duration
	hit_enemies.clear()
	sword_pivot.rotation = deg_to_rad(-110.0)
	set_push(Vector2.RIGHT.rotated(body_rotate.rotation), 90.0, 0.1)
	# Show attack cone visualization
	var attack_cone = sword_pivot.get_node_or_null("AttackCone")
	if attack_cone:
		attack_cone.visible = true
		attack_cone.modulate.a = 1.0
	# Play attack sound
	audio_player.play()
	apply_sword_damage()

func fire_ranged_attack():
	var bullet = bullet_class.instantiate()
	var direction = Vector2.RIGHT.rotated(body_rotate.global_rotation)
	var spawn_position = sword_pivot.global_position + direction * 32.0
	bullet.damage = get_attack_damage()
	bullet.speed = ranged_projectile_speed
	bullet.setup(Transform2D(body_rotate.global_rotation, spawn_position))
	get_tree().current_scene.add_child(bullet)
	is_shot_cd = true
	shot_timer.start(ranged_cooldown)

func update_sword_attack(delta: float):
	if attack_time_left > 0.0:
		attack_time_left = maxf(attack_time_left - delta, 0.0)
		var progress = 1.0 - (attack_time_left / attack_duration)
		sword_pivot.rotation = deg_to_rad(lerp(-110.0, 70.0, progress))
		apply_sword_damage()
		# Fade attack cone
		var attack_cone = sword_pivot.get_node_or_null("AttackCone")
		if attack_cone:
			attack_cone.modulate.a = lerp(1.0, 0.0, progress)
	else:
		sword_pivot.rotation = 0.0
		# Hide attack cone when attack ends
		var attack_cone = sword_pivot.get_node_or_null("AttackCone")
		if attack_cone:
			attack_cone.visible = false
			attack_cone.modulate.a = 0.0

func apply_sword_damage():
	for body in sword_hitbox.get_overlapping_bodies():
		if body.is_in_group("enemy") and not hit_enemies.has(body):
			hit_enemies.append(body)
			if body.has_method("get_hit"):
				body.get_hit(get_attack_damage(), sword_hitbox.global_transform)

func set_push(dir: Vector2, strength: float, timer: float):
	push_dir = dir
	push_strength = strength
	push_timer = timer

func push_back(delta: float):
	if push_timer > 0.0:
		position -= push_dir * push_strength * delta
		push_timer -= delta
	else:
		push_timer = 0.0

func _on_shot_timer_timeout():
	is_shot_cd = false

func get_attack_damage() -> int:
	# Get attack damage from stats if available, fallback to local value
	if self.stats:
		return self.stats.attack
	return attack_damage

# Check if player is currently attacking (used by urns for break detection)
func is_attacking() -> bool:
	return attack_time_left > 0.0

# Take damage from enemies
func take_damage(damage: int, knockback_dir: Vector2):
	if is_invulnerable:
		return
	if stats:
		stats.apply_damage(damage)
	# Start iFrames
	is_invulnerable = true
	invulnerability_timer = 1.0  # 1 second of invulnerability
	# Knockback
	set_push(knockback_dir, 300.0, 0.15)
