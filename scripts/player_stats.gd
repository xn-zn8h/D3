extends Node

# Centralized player stat manager
# All stat modifications go through this script for consistency

signal stat_changed(stat_name, new_value)
signal health_changed(current_health, max_health)
signal player_died

# Base stats (can be modified by items)
var attack: int = 30
var max_health: int = 100
var armor: int = 0
var coins: int = 0

# Current state
var current_health: int = 100

func _ready():
	current_health = max_health

# Apply damage with armor reduction
func apply_damage(damage: int) -> int:
	var actual_damage = max(1, damage - armor)
	current_health -= actual_damage
	if current_health < 0:
		current_health = 0
	health_changed.emit(current_health, max_health)
	if current_health == 0:
		player_died.emit()
	return actual_damage

# Heal player
func heal(amount: int) -> int:
	var healed = min(amount, max_health - current_health)
	current_health += healed
	health_changed.emit(current_health, max_health)
	return healed

# Modify a stat (used by items)
func modify_stat(stat_name: String, amount: int) -> int:
	match stat_name.to_lower():
		"attack":
			attack += amount
		"max_health":
			max_health += amount
			current_health += amount  # Also heal when increasing max health
		"armor":
			armor += amount
			if armor < 0:
				armor = 0
		"coins":
			coins += amount
	stat_changed.emit(stat_name, _get_stat_value(stat_name))
	return _get_stat_value(stat_name)

# Get current stat value
func _get_stat_value(stat_name: String) -> int:
	match stat_name.to_lower():
		"attack":
			return attack
		"max_health":
			return max_health
		"armor":
			return armor
		"coins":
			return coins
	return 0

# Reset all stats to defaults (for game restart)
func reset_stats():
	attack = 30
	max_health = 100
	armor = 0
	coins = 0
	current_health = max_health
	health_changed.emit(current_health, max_health)
