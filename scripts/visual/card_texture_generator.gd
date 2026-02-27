class_name CardTextureGenerator
extends RefCounted

# Tạo texture rõ ràng cho lá bài — resolution cao, font lớn, dễ đọc

static var _cache: Dictionary = {}
static var _back_texture: Texture2D = null

const CARD_WIDTH: int = 512
const CARD_HEIGHT: int = 768

static func get_card_texture(card: Card) -> Texture2D:
	var key = str(card.rank) + "_" + str(card.suit)
	if _cache.has(key):
		return _cache[key]
		
	# Fallback an toàn: Ưu tiên tải hình PNG asset thật
	var rank_str = ""
	match card.rank:
		Card.Rank.ACE: rank_str = "A"
		Card.Rank.TWO: rank_str = "2"
		Card.Rank.THREE: rank_str = "3"
		Card.Rank.FOUR: rank_str = "4"
		Card.Rank.FIVE: rank_str = "5"
		Card.Rank.SIX: rank_str = "6"
		Card.Rank.SEVEN: rank_str = "7"
		Card.Rank.EIGHT: rank_str = "8"
		Card.Rank.NINE: rank_str = "9"
		Card.Rank.TEN: rank_str = "0"
		Card.Rank.JACK: rank_str = "J"
		Card.Rank.QUEEN: rank_str = "Q"
		Card.Rank.KING: rank_str = "K"
	var suit_str = ""
	match card.suit:
		Card.Suit.SPADES: suit_str = "S"
		Card.Suit.DIAMONDS: suit_str = "D"
		Card.Suit.HEARTS: suit_str = "H"
		Card.Suit.CLUBS: suit_str = "C"
		
	var res_path = "res://assets/cards/" + rank_str + suit_str + ".png"
	if ResourceLoader.exists(res_path):
		var tex = load(res_path) as Texture2D
		if tex:
			_cache[key] = tex
			return tex
	
	# Nếu ko tìm thấy file, fallback procedural tự vẽ
	var tex = _create_card_texture(card)
	_cache[key] = tex
	return tex

static func get_back_texture() -> Texture2D:
	if _back_texture != null:
		return _back_texture
		
	var res_path = "res://assets/cards/back.png"
	if ResourceLoader.exists(res_path):
		_back_texture = load(res_path) as Texture2D
		if _back_texture:
			return _back_texture
	_back_texture = _create_back_texture()
	return _back_texture

static func _create_card_texture(card: Card) -> ImageTexture:
	var img = Image.create(CARD_WIDTH, CARD_HEIGHT, false, Image.FORMAT_RGBA8)
	
	# Nền trắng kem
	img.fill(Color(0.97, 0.95, 0.92))
	
	# Viền đen dày
	_draw_rect_outline(img, 0, 0, CARD_WIDTH - 1, CARD_HEIGHT - 1, Color(0.15, 0.15, 0.15), 4)
	# Viền trong mỏng
	_draw_rect_outline(img, 6, 6, CARD_WIDTH - 7, CARD_HEIGHT - 7, Color(0.7, 0.7, 0.7), 1)
	
	# Màu chất
	var suit_color = Color(0.85, 0.05, 0.05) if card.is_red() else Color(0.1, 0.1, 0.1)
	
	# Vẽ suit symbol LỚN ở giữa
	_draw_suit_symbol(img, card.suit, CARD_WIDTH / 2, CARD_HEIGHT / 2, 80, suit_color)
	
	# Vẽ rank TO góc trên-trái (scale 5x)
	var rank_str = card.get_rank_string()
	_draw_rank_big(img, rank_str, 20, 20, suit_color)
	
	# Suit nhỏ dưới rank góc trên-trái
	_draw_suit_symbol(img, card.suit, 45, 110, 20, suit_color)
	
	# Góc dưới-phải
	_draw_rank_big(img, rank_str, CARD_WIDTH - 80, CARD_HEIGHT - 80, suit_color)
	_draw_suit_symbol(img, card.suit, CARD_WIDTH - 55, CARD_HEIGHT - 120, 20, suit_color)
	
	img.generate_mipmaps() # Khử mờ trên hình 3D
	var tex = ImageTexture.create_from_image(img)
	return tex

static func _create_back_texture() -> ImageTexture:
	var img = Image.create(CARD_WIDTH, CARD_HEIGHT, false, Image.FORMAT_RGBA8)
	
	# Nền xanh đậm sang trọng
	img.fill(Color(0.08, 0.15, 0.45))
	
	# Viền vàng
	_draw_rect_outline(img, 0, 0, CARD_WIDTH - 1, CARD_HEIGHT - 1, Color(0.85, 0.75, 0.3), 6)
	_draw_rect_outline(img, 16, 16, CARD_WIDTH - 17, CARD_HEIGHT - 17, Color(0.85, 0.75, 0.3), 3)
	
	# Hoa văn đan chéo
	for y in range(24, CARD_HEIGHT - 24, 16):
		for x in range(24, CARD_WIDTH - 24, 16):
			if (x + y) % 32 < 16:
				_draw_filled_rect(img, x, y, x + 7, y + 7, Color(0.12, 0.20, 0.50))
			else:
				_draw_filled_rect(img, x, y, x + 7, y + 7, Color(0.18, 0.30, 0.60))
	
	# Kim cương lớn ở giữa
	_draw_diamond(img, CARD_WIDTH / 2, CARD_HEIGHT / 2, 50, Color(0.9, 0.8, 0.3))
	
	img.generate_mipmaps()
	var tex = ImageTexture.create_from_image(img)
	return tex

# ==== DRAWING HELPERS ====

static func _draw_rect_outline(img: Image, x1: int, y1: int, x2: int, y2: int, color: Color, thickness: int = 1) -> void:
	for t in range(thickness):
		for x in range(x1 + t, x2 - t + 1):
			if x >= 0 and x < CARD_WIDTH:
				if y1 + t >= 0 and y1 + t < CARD_HEIGHT:
					img.set_pixel(x, y1 + t, color)
				if y2 - t >= 0 and y2 - t < CARD_HEIGHT:
					img.set_pixel(x, y2 - t, color)
		for y in range(y1 + t, y2 - t + 1):
			if y >= 0 and y < CARD_HEIGHT:
				if x1 + t >= 0 and x1 + t < CARD_WIDTH:
					img.set_pixel(x1 + t, y, color)
				if x2 - t >= 0 and x2 - t < CARD_WIDTH:
					img.set_pixel(x2 - t, y, color)

static func _draw_filled_rect(img: Image, x1: int, y1: int, x2: int, y2: int, color: Color) -> void:
	for y in range(maxi(y1, 0), mini(y2 + 1, CARD_HEIGHT)):
		for x in range(maxi(x1, 0), mini(x2 + 1, CARD_WIDTH)):
			img.set_pixel(x, y, color)

static func _draw_diamond(img: Image, cx: int, cy: int, size: int, color: Color) -> void:
	for dy in range(-size, size + 1):
		var half_w = size - absi(dy)
		for dx in range(-half_w, half_w + 1):
			var px = cx + dx
			var py = cy + dy
			if px >= 0 and px < CARD_WIDTH and py >= 0 and py < CARD_HEIGHT:
				img.set_pixel(px, py, color)

static func _draw_circle(img: Image, cx: int, cy: int, r: int, color: Color) -> void:
	for dy in range(-r, r + 1):
		for dx in range(-r, r + 1):
			if dx * dx + dy * dy <= r * r:
				var px = cx + dx
				var py = cy + dy
				if px >= 0 and px < CARD_WIDTH and py >= 0 and py < CARD_HEIGHT:
					img.set_pixel(px, py, color)

# ==== SUIT SYMBOLS ====

static func _draw_suit_symbol(img: Image, suit: Card.Suit, cx: int, cy: int, size: int, color: Color) -> void:
	match suit:
		Card.Suit.HEARTS:
			_draw_heart(img, cx, cy, size, color)
		Card.Suit.DIAMONDS:
			_draw_diamond(img, cx, cy, size, color)
		Card.Suit.SPADES:
			_draw_spade(img, cx, cy, size, color)
		Card.Suit.CLUBS:
			_draw_club(img, cx, cy, size, color)

static func _draw_heart(img: Image, cx: int, cy: int, size: int, color: Color) -> void:
	for dy in range(-size, size + 1):
		for dx in range(-size, size + 1):
			var fx = float(dx) / float(size)
			var fy = float(dy) / float(size)
			var heart = pow(fx * fx + fy * fy - 1.0, 3.0) - fx * fx * fy * fy * fy
			if heart < 0:
				var px = cx + dx
				var py = cy + dy + size / 3
				if px >= 0 and px < CARD_WIDTH and py >= 0 and py < CARD_HEIGHT:
					img.set_pixel(px, py, color)

static func _draw_spade(img: Image, cx: int, cy: int, size: int, color: Color) -> void:
	for dy in range(-size, size + 1):
		for dx in range(-size, size + 1):
			var fx = float(dx) / float(size)
			var fy = float(-dy) / float(size)
			var heart = pow(fx * fx + fy * fy - 1.0, 3.0) - fx * fx * fy * fy * fy
			if heart < 0:
				var px = cx + dx
				var py = cy + dy - size / 4
				if px >= 0 and px < CARD_WIDTH and py >= 0 and py < CARD_HEIGHT:
					img.set_pixel(px, py, color)
	# Thân
	_draw_filled_rect(img, cx - 3, cy + size / 2, cx + 3, cy + size, color)

static func _draw_club(img: Image, cx: int, cy: int, size: int, color: Color) -> void:
	var r = int(size * 0.45)
	_draw_circle(img, cx, cy - r, r, color)
	_draw_circle(img, cx - r, cy + int(r * 0.4), r, color)
	_draw_circle(img, cx + r, cy + int(r * 0.4), r, color)
	_draw_filled_rect(img, cx - 3, cy + r / 2, cx + 3, cy + size, color)

# ==== RANK TEXT (3x scale pixel font) ====

static func _draw_rank_big(img: Image, rank_str: String, start_x: int, start_y: int, color: Color) -> void:
	var offset_x = start_x
	for ch in rank_str:
		var pattern = _get_char_pattern(ch)
		_draw_char_scaled(img, offset_x, start_y, pattern, color, 5)
		offset_x += 30  # 5 * 5 + 5 spacing

static func _draw_char_scaled(img: Image, start_x: int, start_y: int, pattern: Array, color: Color, scale: int) -> void:
	for row in range(pattern.size()):
		for col in range(pattern[row].size()):
			if pattern[row][col] == 1:
				# Vẽ block scale x scale
				for sy in range(scale):
					for sx in range(scale):
						var px = start_x + col * scale + sx
						var py = start_y + row * scale + sy
						if px >= 0 and px < CARD_WIDTH and py >= 0 and py < CARD_HEIGHT:
							img.set_pixel(px, py, color)

static func _get_char_pattern(ch: String) -> Array:
	match ch:
		"A": return [
			[0,1,1,1,0],
			[1,0,0,0,1],
			[1,0,0,0,1],
			[1,1,1,1,1],
			[1,0,0,0,1],
			[1,0,0,0,1],
			[1,0,0,0,1]]
		"K": return [
			[1,0,0,1,0],
			[1,0,1,0,0],
			[1,1,0,0,0],
			[1,1,0,0,0],
			[1,0,1,0,0],
			[1,0,0,1,0],
			[1,0,0,0,1]]
		"Q": return [
			[0,1,1,1,0],
			[1,0,0,0,1],
			[1,0,0,0,1],
			[1,0,0,0,1],
			[1,0,1,0,1],
			[1,0,0,1,0],
			[0,1,1,0,1]]
		"J": return [
			[0,0,1,1,1],
			[0,0,0,1,0],
			[0,0,0,1,0],
			[0,0,0,1,0],
			[1,0,0,1,0],
			[1,0,0,1,0],
			[0,1,1,0,0]]
		"1": return [
			[0,0,1,0,0],
			[0,1,1,0,0],
			[0,0,1,0,0],
			[0,0,1,0,0],
			[0,0,1,0,0],
			[0,0,1,0,0],
			[0,1,1,1,0]]
		"0": return [
			[0,1,1,1,0],
			[1,0,0,0,1],
			[1,0,0,1,1],
			[1,0,1,0,1],
			[1,1,0,0,1],
			[1,0,0,0,1],
			[0,1,1,1,0]]
		"2": return [
			[0,1,1,1,0],
			[1,0,0,0,1],
			[0,0,0,0,1],
			[0,0,1,1,0],
			[0,1,0,0,0],
			[1,0,0,0,0],
			[1,1,1,1,1]]
		"3": return [
			[0,1,1,1,0],
			[1,0,0,0,1],
			[0,0,0,0,1],
			[0,0,1,1,0],
			[0,0,0,0,1],
			[1,0,0,0,1],
			[0,1,1,1,0]]
		"4": return [
			[0,0,0,1,0],
			[0,0,1,1,0],
			[0,1,0,1,0],
			[1,0,0,1,0],
			[1,1,1,1,1],
			[0,0,0,1,0],
			[0,0,0,1,0]]
		"5": return [
			[1,1,1,1,1],
			[1,0,0,0,0],
			[1,1,1,1,0],
			[0,0,0,0,1],
			[0,0,0,0,1],
			[1,0,0,0,1],
			[0,1,1,1,0]]
		"6": return [
			[0,1,1,1,0],
			[1,0,0,0,0],
			[1,0,0,0,0],
			[1,1,1,1,0],
			[1,0,0,0,1],
			[1,0,0,0,1],
			[0,1,1,1,0]]
		"7": return [
			[1,1,1,1,1],
			[0,0,0,0,1],
			[0,0,0,1,0],
			[0,0,1,0,0],
			[0,0,1,0,0],
			[0,0,1,0,0],
			[0,0,1,0,0]]
		"8": return [
			[0,1,1,1,0],
			[1,0,0,0,1],
			[1,0,0,0,1],
			[0,1,1,1,0],
			[1,0,0,0,1],
			[1,0,0,0,1],
			[0,1,1,1,0]]
		"9": return [
			[0,1,1,1,0],
			[1,0,0,0,1],
			[1,0,0,0,1],
			[0,1,1,1,1],
			[0,0,0,0,1],
			[0,0,0,0,1],
			[0,1,1,1,0]]
	return [
		[1,1,1,1,1],
		[1,0,0,0,1],
		[1,0,0,0,1],
		[1,0,0,0,1],
		[1,0,0,0,1],
		[1,0,0,0,1],
		[1,1,1,1,1]]
