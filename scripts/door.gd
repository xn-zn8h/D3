extends Area2D

signal door_entered(direction)

@export var door_direction: String = "right"  # right, left, up, down, next_floor
@export var door_color: Color = Color(0.55, 0.35, 0.2, 1.0)  # Brown default for normal doors

var triggered: bool = false

@onready var collision_shape: CollisionShape2D = $CollisionShape2D
@onready var color_rect: ColorRect = $ColorRect
@onready var label: Label = $Label

func _ready():
	triggered = false
	# Set initial color so doors aren't white on spawn
	if color_rect:
		color_rect.color = door_color

func mark_triggered():
	triggered = true
	if color_rect:
		color_rect.color = door_color
	if label:
		match door_direction:
			"next_floor":
				label.text = "🔑"
			_:
				label.text = "»"

func _on_body_entered(body):
	if triggered:
		return
	if body is CharacterBody2D and body.name == "Player":
		# Don't set triggered yet - wait for successful transition
		# The game script will call mark_triggered() on success
		emit_signal("door_entered", door_direction)
