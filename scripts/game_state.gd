class_name GameState
extends RefCounted

# What the next level load should use. Set by the menu, the win screen and the debug cycle.

const TEMPLATES := {
	"studio": "Studio apartment",
	"two_bedroom": "2 bedroom",
	"loft": "Loft",
	"three_bedroom": "3 bedroom",
	"house": "House",
	"attic": "House with attic",
	"basement": "House with basement",
	"maze": "Scary maze",
	"motel": "Motel",
	"townhouse": "Townhouse",
	"mansion": "Mansion",
	"railroad": "Railroad flat",
	"upside_down": "Upside-down house",
	"castle": "Castle",
	"crypt": "Crypt",
	"cloud_walk": "Cloud walk",
	"beach": "Beach episode",
	"runaway_bottles": "Run-away bottles",
	"runaway_shower": "Run-away shower",
	"boiler_room": "Boiler room",
	"giant_house": "Giant house",
	"bathroom": "Bathroom only",
}
const STORY_SEED := "SINGLEPLAYER"
const DEFAULT_RULES := {"run_bottles": false, "run_shower": false, "need_boiler": false,
		"item_freq": "regular", "keys": 0, "no_fake_keys": false}

# Free play options, the same ones the multiplayer lobby offers.
static var rules: Dictionary = DEFAULT_RULES.duplicate()
static var free_timer := "shower"

static var mode := "surprise"  # "story", "free" or "surprise"
static var template := ""  # "" picks a random template
static var seed_value := 0  # 0 picks a random seed
static var seed_text := ""  # what the player typed, for display
static var story_index := 0


static func story_order() -> Array[String]:
	var order: Array[String] = ["bathroom"]
	for key in TEMPLATES.keys():
		if key != "bathroom":
			order.append(key)
	return order


static func seed_from_text(text: String) -> int:
	var t := text.strip_edges()
	var value := t.to_int() if t.is_valid_int() else t.hash()
	return value if value != 0 else 1


static func reset_rules() -> void:
	rules = DEFAULT_RULES.duplicate()
	free_timer = "shower"


static func start_story() -> void:
	mode = "story"
	story_index = 0
	template = story_order()[0]
	seed_text = STORY_SEED
	seed_value = seed_from_text(STORY_SEED)


static func start_free(chosen_template: String, text: String) -> void:
	mode = "free"
	template = chosen_template
	seed_text = text.strip_edges()
	seed_value = seed_from_text(seed_text) if seed_text != "" else 0


static func start_multiplayer(chosen_template: String, seed_number: int, text: String) -> void:
	mode = "multiplayer"
	template = chosen_template
	seed_text = text
	seed_value = seed_number


static func start_surprise() -> void:
	mode = "surprise"
	template = ""
	seed_text = ""
	seed_value = 0


static func has_next() -> bool:
	return mode != "story" or story_index < story_order().size() - 1


# Free play moves through the templates on the same seed; surprise rerolls both.
static func advance() -> void:
	match mode:
		"story":
			story_index += 1
			template = story_order()[story_index]
		"free":
			var keys := TEMPLATES.keys()
			template = keys[(keys.find(template) + 1) % keys.size()]
		_:
			template = ""
			seed_value = 0
