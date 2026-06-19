class_name ItemData
extends Resource

# Item definition resource
# Each item can modify player stats and have special effects

@export_group("Identity")
@export var item_id: String = "default_item"
@export var display_name: String = "Unknown Item"
@export var description: String = ""

@export_group("Stat Modifications")
# Positive = buff, Negative = debuff
@export var attack_mod: int = 0
@export var max_health_mod: int = 0
@export var armor_mod: int = 0

@export_group("Rarity")
@export_enum("Common", "Uncommon", "Rare", "Legendary") var rarity: int = 0

# Get color based on rarity for UI display
func get_rarity_color() -> Color:
	match rarity:
		0: return Color(0.7, 0.7, 0.7)  # Common - gray
		1: return Color(0.3, 0.8, 0.3)  # Uncommon - green
		2: return Color(0.3, 0.3, 1.0)  # Rare - blue
		3: return Color(1.0, 0.5, 0.0)  # Legendary - orange
	return Color.WHITE

# Apply this item's stat modifications to the player stats manager
func apply_to_stats(stats: Node) -> Dictionary:
	var applied = {}
	if attack_mod != 0:
		applied["attack"] = stats.modify_stat("attack", attack_mod)
	if max_health_mod != 0:
		applied["max_health"] = stats.modify_stat("max_health", max_health_mod)
	if armor_mod != 0:
		applied["armor"] = stats.modify_stat("armor", armor_mod)
	return applied
