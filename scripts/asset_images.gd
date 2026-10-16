class_name AssetImages
extends RefCounted

# Finds pictures in res://assets/images/ by a word in their file name, so a map can use whatever art
# is there (an evil Forrest, a dog) and fall back to a drawn stand-in when it isn't.

const ROOT := "res://assets/images"
const SKIPPED_FOLDERS: Array[String] = ["framedphotos"]  # the wall photos are not sprites

static var _files: Array[String] = []
static var _scanned := false
static var _cache := {}


# The first picture whose file name contains one of the `words` (case-insensitive), or null.
static func find(words: Array) -> Texture2D:
	var key := ",".join(words)
	if _cache.has(key):
		return _cache[key]
	_scan()
	var found: Texture2D = null
	for path in _files:
		var file_name := path.get_file().to_lower()
		for word in words:
			if file_name.contains(String(word).to_lower()):
				found = load(path) as Texture2D
				break
		if found != null:
			break
	_cache[key] = found
	return found


static func _scan() -> void:
	if _scanned:
		return
	_scanned = true
	_scan_folder(ROOT)
	_files.sort()


static func _scan_folder(folder: String) -> void:
	if not DirAccess.dir_exists_absolute(folder):
		return
	for sub in DirAccess.get_directories_at(folder):
		if not SKIPPED_FOLDERS.has(sub):
			_scan_folder(folder + "/" + sub)
	for file in DirAccess.get_files_at(folder):
		var file_name := file.trim_suffix(".import")  # exported builds only list the .import files
		var path := folder + "/" + file_name
		if file_name.get_extension().to_lower() in ["png", "jpg", "jpeg", "webp"] and not _files.has(path):
			_files.append(path)


# A flat dark silhouette (head, body, two glowing eyes) for when there is no picture to use.
static func figure(body_color: Color, eye_color: Color, width := 96, height := 192) -> Texture2D:
	var img := Image.create(width, height, false, Image.FORMAT_RGBA8)
	var centre := width / 2.0
	for y in height:
		for x in width:
			var inside := false
			var head := Vector2(x - centre, y - height * 0.16).length() < width * 0.24
			var torso := absf(x - centre) < width * 0.3 * (0.6 + 0.4 * float(y) / height) and y > height * 0.28 and y < height * 0.68
			var legs := (absf(x - centre - width * 0.14) < width * 0.1 or absf(x - centre + width * 0.14) < width * 0.1) and y >= height * 0.68
			var arms := (absf(x - centre) > width * 0.28 and absf(x - centre) < width * 0.42) and y > height * 0.3 and y < height * 0.6
			inside = head or torso or legs or arms
			if inside:
				img.set_pixel(x, y, body_color)
	for side in [-1.0, 1.0]:
		var eye := Vector2(centre + side * width * 0.09, height * 0.15)
		for y in range(int(eye.y) - 4, int(eye.y) + 5):
			for x in range(int(eye.x) - 4, int(eye.x) + 5):
				if Vector2(x, y).distance_to(eye) <= 4.0:
					img.set_pixel(x, y, eye_color)
	return ImageTexture.create_from_image(img)
