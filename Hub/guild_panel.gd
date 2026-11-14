class_name GuildPanel
extends HubPanel

# Mining guild: the contract board on the left, the player's contracts on the right, and the
# guild rank underneath. Rules in Guild and Contract; money and ore in GameState.

const WIDTH: float = 1180.0
const ROMAN: Array[String] = ["I", "II", "III", "IV"]

var _board: VBoxContainer
var _mine: VBoxContainer
var _mine_title: Label
var _rank: VBoxContainer


func _init() -> void:
	super("MINING GUILD")
	custom_minimum_size = Vector2(WIDTH, 0)
	size = Vector2(WIDTH, 0)


func _build() -> void:
	var columns := HBoxContainer.new()
	columns.add_theme_constant_override(&"separation", 24)
	body.add_child(columns)

	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.add_theme_constant_override(&"separation", 8)
	columns.add_child(left)
	left.add_child(HubStyle.label("CONTRACT BOARD (new offers after every run)", 13, HubStyle.DIM))
	_board = VBoxContainer.new()
	_board.add_theme_constant_override(&"separation", 8)
	left.add_child(_board)

	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_theme_constant_override(&"separation", 8)
	columns.add_child(right)
	_mine_title = HubStyle.label("", 13, HubStyle.DIM)
	right.add_child(_mine_title)
	_mine = VBoxContainer.new()
	_mine.add_theme_constant_override(&"separation", 8)
	right.add_child(_mine)

	var note := HubStyle.label("Deliveries are handed in from your hold when you dock. Other contracts count during one run and pay when you dock; they start over if you don't make it back. Dropping a contract costs nothing.", 13, HubStyle.DIM)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	right.add_child(note)

	body.add_child(HSeparator.new())
	_rank = VBoxContainer.new()
	_rank.add_theme_constant_override(&"separation", 6)
	body.add_child(_rank)

	GameState.guild_changed.connect(refresh)
	GameState.credits_changed.connect(refresh)
	GameState.storage_changed.connect(refresh)


func refresh() -> void:
	_clear(_board)
	_clear(_mine)
	_clear(_rank)
	var guild := GameState.guild

	for i in guild.offers.size():
		var offer := guild.offers[i]
		var card := _make_card(offer, false)
		var accept := HubStyle.button("TAKE IT" if guild.can_accept() else "YOU HAVE %d ALREADY" % Guild.MAX_ACTIVE, 14)
		accept.disabled = not guild.can_accept()
		accept.pressed.connect(_on_accept.bind(i))
		card.get_child(0).add_child(accept)
		_board.add_child(card)

	if guild.offers.is_empty():
		_board.add_child(HubStyle.label("Nothing left on the board. Come back after your next run.", 15))

	_mine_title.text = "YOUR CONTRACTS (%d/%d) · %d completed" % [guild.active.size(), Guild.MAX_ACTIVE, guild.completed_count]

	for contract in guild.active:
		var card := _make_card(contract, true)
		var buttons := HBoxContainer.new()
		buttons.add_theme_constant_override(&"separation", 8)

		if contract.is_delivery():
			var stored := GameState.get_stored(contract.ore_id)
			var hand_in := HubStyle.button("HAND IN FROM STORAGE (%d u held)" % floori(stored), 14)
			hand_in.disabled = stored < 1.0 or contract.type == Contract.Type.RUSH_DELIVERY and stored < contract.target - contract.progress
			hand_in.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			hand_in.pressed.connect(_on_hand_in.bind(contract))
			buttons.add_child(hand_in)

		var drop := HubStyle.button("DROP", 14)
		drop.custom_minimum_size.x = 90
		drop.pressed.connect(_on_drop.bind(contract))
		buttons.add_child(drop)
		card.get_child(0).add_child(buttons)
		_mine.add_child(card)

	if guild.active.is_empty():
		_mine.add_child(HubStyle.label("None yet. Take one from the board.", 15))

	_build_rank()


func _make_card(contract: Contract, is_mine: bool) -> PanelContainer:
	var card := PanelContainer.new()
	card.add_theme_stylebox_override(&"panel", HubStyle.box(Color(0.12, 0.12, 0.11), CockpitPalette.OUTLINE, 2, 10))
	var column := VBoxContainer.new()
	column.add_theme_constant_override(&"separation", 4)
	card.add_child(column)

	var header := HBoxContainer.new()
	column.add_child(header)
	var title := HubStyle.label(contract.get_title().to_upper(), 17, HubStyle.ACCENT)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	header.add_child(HubStyle.label(HubStyle.format_credits(contract.reward), 17, HubStyle.GOOD))

	var goal := HubStyle.label(contract.get_goal_text(), 15)
	goal.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(goal)

	if not contract.get_needs_text().is_empty():
		column.add_child(HubStyle.label(contract.get_needs_text(), 13, HubStyle.DIM))

	if is_mine and contract.is_delivery():
		column.add_child(HubStyle.label("Handed in: %s" % contract.get_progress_text(), 13, HubStyle.TEXT))

	if is_mine and contract.runs_left > 0:
		column.add_child(HubStyle.label("Due by the end of your next run", 13, HubStyle.BAD))

	return card


# The rank goes up on its own with completed contracts: bigger offers, rarer ores asked for.
func _build_rank() -> void:
	var rank := GameState.get_guild_rank()
	_rank.add_child(HubStyle.label("GUILD RANK %s" % ROMAN[rank - 1], 18, HubStyle.ACCENT))

	var next := GameState.get_next_rank()

	if next.is_empty():
		_rank.add_child(HubStyle.label("Top rank: the guild offers you its biggest contracts.", 14, HubStyle.DIM))
		return

	var text := HubStyle.label("Rank %s after %d completed contracts (you have %d). Higher ranks get bigger contracts." % [ROMAN[next.rank - 1], next.contracts, GameState.guild.completed_count], 15)
	text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_rank.add_child(text)


func _clear(container: Container) -> void:
	for child in container.get_children():
		container.remove_child(child)
		child.queue_free()


func _on_accept(offer_index: int) -> void:
	GameState.accept_contract(offer_index)


func _on_drop(contract: Contract) -> void:
	GameState.drop_contract(contract)


func _on_hand_in(contract: Contract) -> void:
	GameState.hand_in_from_storage(contract)
