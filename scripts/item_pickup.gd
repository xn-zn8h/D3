extends Area2D
class_name ItemPickup

# Item drop that can be picked up by the player
@export var item_resource: Resource = null

var pickup_cooldown: float = 0.0
var float_offset: float = 0.0
var float_speed: float = 2.0
var float_amplitude: float = 5.0

# Emitted when the item is picked up
signal item_picked_up(item_data: Resource)

func _ready():
	# Set up collision layer (item layer)
	area_entered.connect(_on_area_entered)
	body_entered.connect(_on_body_entered)

func _process(delta):
	# Floating animation
	float_offset += float_speed * delta
	# Gentle bobbing motion
	position.y += sin(float_offset) * float_amplitude * delta
	
	# Cooldown timer
	if pickup_cooldown > 0:
		pickup_cooldown -= delta

func _on_body_entered(body):
	# Only pick up if player and not on cooldown
	if body is CharacterBody2D and body.name == "Player" and pickup_cooldown <= 0:
		pickup_item()

func _on_area_entered(area):
	# Handle area-based collision (for player hitbox if it's an Area2D)
	if area.name == "Player" and pickup_cooldown <= 0:
		pickup_item()

func pickup_item():
	# Emit signal with item data
	if item_resource:
		emit_signal("item_picked_up", item_resource)
	
	# Visual feedback - scale up and fade out
	var tween = create_tween()
	tween.tween_property(self, "scale", Vector2(2.0, 2.0), 0.2)
	tween.tween_callback(queue_free)
	
	# Set cooldown to prevent double pickup
	pickup_cooldown = 1.0
