extends Area2D

# Urn - Breakable container that drops items when attacked
signal urn_broken(item_data: Resource, position: Vector2)

var health: int = 1
var is_broken: bool = false

@onready var color_rect: ColorRect = $ColorRect
@onready var collision_shape: CollisionShape2D = $CollisionShape2D
@onready var hit_area: Area2D = $HitArea

# Item pool for drops
var item_pool: Array[Resource] = []

func _ready():
	health = 1
	is_broken = false
	# Use area_entered to detect sword hitbox (Area2D) instead of body_entered
	hit_area.area_entered.connect(_on_area_entered)
	
	print("[Urn] Script loaded successfully - Godot 4 API working!")
	
	# Load item definitions from the data/items folder
	load_item_pool()

func load_item_pool():
	# Hardcode item pool to avoid .tres loading issues
	var item_script = load("res://scripts/item_data.gd")
	
	# Demon Core - Rare offensive/defensive item
	var demon_core = item_script.new()
	demon_core.set("item_id", "demon_core")
	demon_core.set("display_name", "Demon Core")
	demon_core.set("description", "The core of a demon, pulsing with dark energy.")
	demon_core.set("attack_mod", 5)
	demon_core.set("max_health_mod", 1)
	demon_core.set("armor_mod", 5)
	demon_core.set("rarity", 3)
	item_pool.append(demon_core)
	
	# Magic Stick - Uncommon utility item (reduces charge time by 5%)
	var magic_stick = item_script.new()
	magic_stick.set("item_id", "magic_stick")
	magic_stick.set("display_name", "Magic Stick")
	magic_stick.set("description", "A wand that shortens spell charging.")
	magic_stick.set("attack_mod", 0)
	magic_stick.set("max_health_mod", 0)
	magic_stick.set("armor_mod", 0)
	magic_stick.set("rarity", 2)
	item_pool.append(magic_stick)
	
	# Health Tonic - Common healing item
	var health_tonic = item_script.new()
	health_tonic.set("item_id", "health_tonic")
	health_tonic.set("display_name", "Health Tonic")
	health_tonic.set("description", "A restorative tonic.")
	health_tonic.set("attack_mod", 0)
	health_tonic.set("max_health_mod", 0)
	health_tonic.set("armor_mod", 0)
	health_tonic.set("rarity", 0)
	item_pool.append(health_tonic)
	
	# Iron Shell - Uncommon defensive item
	var iron_shell = item_script.new()
	iron_shell.set("item_id", "iron_shell")
	iron_shell.set("display_name", "Iron Shell")
	iron_shell.set("description", "A sturdy shell for protection.")
	iron_shell.set("attack_mod", 0)
	iron_shell.set("max_health_mod", 0)
	iron_shell.set("armor_mod", 10)
	iron_shell.set("rarity", 2)
	item_pool.append(iron_shell)
	
	# Sharp Blade - Common offensive item
	var sharp_blade = item_script.new()
	sharp_blade.set("item_id", "sharp_blade")
	sharp_blade.set("display_name", "Sharp Blade")
	sharp_blade.set("description", "A well-crafted blade.")
	sharp_blade.set("attack_mod", 5)
	sharp_blade.set("max_health_mod", 0)
	sharp_blade.set("armor_mod", 0)
	sharp_blade.set("rarity", 1)
	item_pool.append(sharp_blade)
	
	# New Jordans - Uncommon speed item (+5% movement speed)
	var new_jordans = item_script.new()
	new_jordans.set("item_id", "new_jordans")
	new_jordans.set("display_name", "New Jordans")
	new_jordans.set("description", "Swoosh.")
	new_jordans.set("attack_mod", 0)
	new_jordans.set("max_health_mod", 0)
	new_jordans.set("armor_mod", 0)
	new_jordans.set("rarity", 2)
	item_pool.append(new_jordans)
	
	print("[Urn] Loaded ", item_pool.size(), " items into pool")

func take_damage():
	if is_broken or health <= 0:
		return
	
	health -= 1
	if health <= 0:
		break_urn()

func break_urn():
	is_broken = true
	
	# Play break animation (simple scale down)
	if color_rect:
		var tween = create_tween()
		tween.tween_property(color_rect, "scale", Vector2(0, 0), 0.2)
	
	# Drop a random item from the pool
	if item_pool.size() > 0:
		var random_item = item_pool[randi() % item_pool.size()]
		emit_signal("urn_broken", random_item, global_position)
	else:
		print("[Urn] Warning: Item pool is empty!")
	
	# Disable collision (use set_deferred to avoid physics flush errors)
	if collision_shape:
		collision_shape.set_deferred("disabled", true)
	if hit_area:
		hit_area.set_deferred("monitoring", false)
	
	# Queue free after animation
	await get_tree().create_timer(0.3).timeout
	queue_free()

func _on_area_entered(area):
	if is_broken:
		return
	
	# Detect sword hitbox from player (it's an Area2D named SwordHitbox)
	if area.name == "SwordHitbox":
		# Find the player (sword hitbox is child of player)
		var player = area.get_parent().get_parent().get_parent()
		if player and player.name == "Player":
			take_damage()
