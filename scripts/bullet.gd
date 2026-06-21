extends Area2D

@export var speed: float = 800.0
@export var damage: int = 50
@export var explosion_radius: float = 100.0
@export var explosion_damage: int = 25

@onready var bullet_particle = preload("res://scenes/bullet_particle.tscn")
@onready var bullet_hit_sound = preload("res://scenes/bullet_hit_sound.tscn")

var has_exploded: bool = false
var hit_enemy: Node2D = null

func _physics_process(delta):
	position += transform.x * speed * delta

func setup(trans: Transform2D):
	transform = trans

func _on_body_entered(body):
	if body.is_in_group("enemy"):
		hit_enemy = body
		body.get_hit(damage, global_transform)
		# Apply electrified status effect
		if body.has_method("apply_electrified"):
			body.apply_electrified(5.0)
		
		# Trigger explosion to affect nearby enemies
		if not has_exploded:
			has_exploded = true
			_trigger_explosion()
	
	var bullet_effect = bullet_particle.instantiate()
	get_tree().root.add_child(bullet_effect)
	bullet_effect.setup(global_transform)
	var bullet_hit_player = bullet_hit_sound.instantiate()
	get_tree().root.add_child(bullet_hit_player)
	bullet_hit_player.play()
	queue_free()

func _trigger_explosion():
	# Find all enemies in the "enemy" group within explosion radius
	var enemies = get_tree().get_nodes_in_group("enemy")
	for enemy in enemies:
		if enemy == hit_enemy:
			continue
		var distance = global_position.distance_to(enemy.global_position)
		if distance <= explosion_radius:
			enemy.get_hit(explosion_damage, global_transform)
			# Apply electrified status effect to affected enemies
			if enemy.has_method("apply_electrified"):
				enemy.apply_electrified(3.0)
