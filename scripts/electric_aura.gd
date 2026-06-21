extends Node2D

# Electric aura visual effect - runs independently to avoid shaking when parent moves
var aura_color: Color = Color(0.3, 0.5, 1.0, 0.5)
var aura_radius: float = 32.0
var ring_color: Color = Color(0.6, 0.8, 1.0, 0.3)
var ring_radius: float = 36.0
var pulse_timer: float = 0.0
var active: bool = false

func _process(delta: float):
	if active:
		pulse_timer += delta * 12.0
		var pulse = sin(pulse_timer) * 0.5 + 0.5
		
		# Main aura circle - pulse alpha and radius
		aura_color = Color(0.3, 0.5, 1.0, lerp(0.25, 0.6, pulse))
		aura_radius = lerp(28, 36, pulse)
		
		# Outer ring - counter-pulse for dynamic effect
		ring_color = Color(0.6, 0.8, 1.0, lerp(0.15, 0.45, 1.0 - pulse))
		ring_radius = lerp(32, 42, 1.0 - pulse)
		
		queue_redraw()

func _draw():
	if active:
		draw_circle(Vector2.ZERO, aura_radius, aura_color)
		draw_circle(Vector2.ZERO, ring_radius, ring_color)

func activate():
	active = true
	queue_redraw()

func deactivate():
	active = false
	visible = false
	queue_redraw()
