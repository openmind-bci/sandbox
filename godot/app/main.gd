extends Control
## Cockpit window: menu bar, the object scene on the left, panels on the right.
##
## Scenes are swapped inside a SubViewport without restarting the application.
## Keyboard: Ctrl+1..4 switch scene, Ctrl+P shows or hides the panels,
## F11 toggles full screen, Ctrl+Q quits; menus open with the mouse or Tab/arrows.

signal scene_changed(scene_id: String)

## Object scenes: id -> [title, path]. Order = menu order and Ctrl+1..4.
const SCENES := {
	"robot_twin": ["Robot twin", "res://scenes/robot_twin/robot_twin.tscn"],
	"bird": ["Bird (guided calibration)", "res://scenes/bird/bird.tscn"],
	"wheelchair": ["Wheelchair", "res://scenes/wheelchair/wheelchair.tscn"],
	"boat": ["Boat", "res://scenes/boat/boat.tscn"],
}
const DEFAULT_SCENE := "robot_twin"

enum MenuId {
	PROFILE_INFO = 100,
	CALIBRATION_START = 200,
	CALIBRATION_TEST_MARKER = 201,
	SCENE_BASE = 300,
	SETTINGS_BRIDGE = 400,
	SETTINGS_RECONNECT = 401,
	SETTINGS_PANELS = 402,
	SETTINGS_FULLSCREEN = 403,
	SETTINGS_QUIT = 404,
	SETTINGS_REALISTIC = 405,
	SETTINGS_DEMO = 407,
	SETTINGS_LIGHT = 406,
}

var current_scene_id := ""
## Graphics quality: GraphicsQuality.REALISTIC or LIGHT.
var quality := GraphicsQuality.REALISTIC
var current_scene: Node = null
var viewport: SubViewport
var panels: Control
var command_panel: CommandPanel
var brain_panel: BrainPanel
var signal_panel: SignalPanel
var connection_panel: ConnectionPanel
var score_panel: ScorePanel

var _theme: Theme
var _profile_menu: PopupMenu
var _settings_menu: PopupMenu
var _bridge_dialog: ConfirmationDialog
var _bridge_edit: LineEdit
var _openmind: Node = null


func _ready() -> void:
	_theme = OpenMindTheme.build()
	theme = _theme
	_openmind = get_node_or_null("/root/OpenMind")
	_build_layout()
	_build_dialogs()
	set_quality(GraphicsQuality.load_saved(), false)
	if _openmind != null:
		_openmind.status_changed.connect(_on_status)
	switch_scene(DEFAULT_SCENE)


## Replace the object scene; returns false for an unknown id.
func switch_scene(scene_id: String) -> bool:
	if not SCENES.has(scene_id):
		push_warning("Unknown scene %s" % scene_id)
		return false
	var packed: PackedScene = load(SCENES[scene_id][1])
	if packed == null:
		return false
	if current_scene != null:
		viewport.remove_child(current_scene)
		current_scene.queue_free()
	current_scene = packed.instantiate()
	if current_scene is Control:
		current_scene.theme = _theme  # themes do not cross the SubViewport
	viewport.add_child(current_scene)
	if current_scene.has_method("apply_quality"):
		current_scene.apply_quality(quality)
	current_scene_id = scene_id
	command_panel.bind_controller(current_scene.get_node_or_null("ObjectController"))
	get_window().title = "OpenMind Sandbox — %s" % SCENES[scene_id][0]
	scene_changed.emit(scene_id)
	return true


## Switch between realistic and light graphics (remembered when [param save]).
func set_quality(new_quality: String, save: bool = true) -> void:
	quality = new_quality
	GraphicsQuality.apply_engine(quality, viewport)
	if current_scene != null and current_scene.has_method("apply_quality"):
		current_scene.apply_quality(quality)
	if _settings_menu != null:
		_settings_menu.set_item_checked(
				_settings_menu.get_item_index(MenuId.SETTINGS_REALISTIC), quality == GraphicsQuality.REALISTIC)
		_settings_menu.set_item_checked(
				_settings_menu.get_item_index(MenuId.SETTINGS_LIGHT), quality == GraphicsQuality.LIGHT)
	if save:
		GraphicsQuality.save(quality)


func set_panels_visible(value: bool) -> void:
	panels.visible = value


# --- Layout ------------------------------------------------------------------------


func _build_layout() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var background := ColorRect.new()
	background.color = OpenMindTheme.BACKGROUND
	background.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(background)

	var root := VBoxContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(root)
	root.add_child(_build_menu_bar())

	var split := HSplitContainer.new()
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(split)

	var container := SubViewportContainer.new()
	container.stretch = true
	container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	container.size_flags_stretch_ratio = 2.6
	split.add_child(container)
	viewport = SubViewport.new()
	viewport.own_world_3d = true
	viewport.handle_input_locally = true
	viewport.transparent_bg = false  # 3D scenes draw their own sky
	container.add_child(viewport)

	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.custom_minimum_size = Vector2(340, 0)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	split.add_child(scroll)
	panels = scroll
	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation", 10)
	scroll.add_child(column)

	command_panel = CommandPanel.new()
	command_panel.name = "CommandPanel"
	command_panel.demo_follow = _demo_command
	connection_panel = ConnectionPanel.new()
	connection_panel.name = "ConnectionPanel"
	score_panel = ScorePanel.new()
	score_panel.name = "ScorePanel"
	brain_panel = BrainPanel.new()
	brain_panel.name = "BrainPanel"
	column.add_child(_fold("3D brain", brain_panel))
	signal_panel = SignalPanel.new()
	signal_panel.name = "SignalPanel"
	column.add_child(_fold("Signal", signal_panel))
	column.add_child(_fold("Command", command_panel))
	column.add_child(_fold("Progress", score_panel))
	column.add_child(_fold("Connection", connection_panel))


func _fold(title: String, content: Control) -> FoldableContainer:
	var fold := FoldableContainer.new()
	fold.title = title
	fold.name = title.replace(" ", "") + "Fold"
	fold.add_child(content)
	return fold


func _build_menu_bar() -> MenuBar:
	var bar := MenuBar.new()
	bar.custom_minimum_size = Vector2(0, OpenMindTheme.MIN_TARGET)
	# Keep the menus in the window on every platform (macOS would move them to
	# the system menu bar, away from the keyboard navigation of the cockpit).
	bar.prefer_global_menu = false

	_profile_menu = _menu(bar, "Profile")
	_profile_menu.add_item("User: — (from the decoder)", MenuId.PROFILE_INFO)
	_profile_menu.set_item_disabled(0, true)

	var calibration := _menu(bar, "Calibration")
	calibration.add_item("Guided calibration (bird)", MenuId.CALIBRATION_START)
	calibration.add_item("Send a test marker", MenuId.CALIBRATION_TEST_MARKER)

	var objects := _menu(bar, "Objects")
	var index := 0
	for scene_id in SCENES:
		objects.add_item(SCENES[scene_id][0], MenuId.SCENE_BASE + index,
				KEY_MASK_CTRL | (KEY_1 + index))
		index += 1

	var settings := _menu(bar, "Settings")
	_settings_menu = settings
	settings.add_item("Demo mode: simulated decoder and brain", MenuId.SETTINGS_DEMO,
			KEY_MASK_CTRL | KEY_D)
	settings.add_radio_check_item("Graphics: realistic", MenuId.SETTINGS_REALISTIC)
	settings.add_radio_check_item("Graphics: light (while the decoder trains)",
			MenuId.SETTINGS_LIGHT)
	settings.add_separator()
	settings.add_item("Bridge address…", MenuId.SETTINGS_BRIDGE)
	settings.add_item("Reconnect to the bridge", MenuId.SETTINGS_RECONNECT)
	settings.add_item("Show / hide panels", MenuId.SETTINGS_PANELS, KEY_MASK_CTRL | KEY_P)
	settings.add_item("Full screen", MenuId.SETTINGS_FULLSCREEN, KEY_F11)
	settings.add_separator()
	settings.add_item("Quit", MenuId.SETTINGS_QUIT, KEY_MASK_CTRL | KEY_Q)
	return bar


func _menu(bar: MenuBar, title: String) -> PopupMenu:
	var menu := PopupMenu.new()
	menu.name = title
	menu.id_pressed.connect(_on_menu)
	bar.add_child(menu)
	return menu


func _build_dialogs() -> void:
	_bridge_dialog = ConfirmationDialog.new()
	_bridge_dialog.title = "Bridge address"
	_bridge_edit = LineEdit.new()
	_bridge_edit.custom_minimum_size = Vector2(360, OpenMindTheme.MIN_TARGET)
	_bridge_dialog.add_child(_bridge_edit)
	_bridge_dialog.register_text_enter(_bridge_edit)
	_bridge_dialog.confirmed.connect(_on_bridge_confirmed)
	add_child(_bridge_dialog)


# --- Actions -----------------------------------------------------------------------


func _on_menu(id: int) -> void:
	if id >= MenuId.SCENE_BASE and id < MenuId.SCENE_BASE + SCENES.size():
		switch_scene(SCENES.keys()[id - MenuId.SCENE_BASE])
		return
	match id:
		MenuId.CALIBRATION_START:
			switch_scene("bird")
		MenuId.CALIBRATION_TEST_MARKER:
			if _openmind != null and not _openmind.send_marker("event", "test", 0, "cockpit"):
				push_warning("Test marker not sent: bridge not connected")
		MenuId.SETTINGS_BRIDGE:
			_bridge_edit.text = _openmind.url if _openmind != null else ""
			_bridge_dialog.popup_centered()
			_bridge_edit.grab_focus()
		MenuId.SETTINGS_RECONNECT:
			if _openmind != null:
				_openmind.connect_to(_openmind.url)
		MenuId.SETTINGS_DEMO:
			command_panel.toggle_demo()
		MenuId.SETTINGS_REALISTIC:
			set_quality(GraphicsQuality.REALISTIC)
		MenuId.SETTINGS_LIGHT:
			set_quality(GraphicsQuality.LIGHT)
		MenuId.SETTINGS_PANELS:
			set_panels_visible(not panels.visible)
		MenuId.SETTINGS_FULLSCREEN:
			var window := get_window()
			window.mode = (Window.MODE_WINDOWED if window.mode == Window.MODE_FULLSCREEN
					else Window.MODE_FULLSCREEN)
		MenuId.SETTINGS_QUIT:
			get_tree().quit()


func _shortcut_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	if key.ctrl_pressed and key.keycode >= KEY_1 and key.keycode < KEY_1 + SCENES.size():
		_on_menu(MenuId.SCENE_BASE + key.keycode - KEY_1)
	elif key.ctrl_pressed and key.keycode == KEY_D:
		_on_menu(MenuId.SETTINGS_DEMO)
	elif key.ctrl_pressed and key.keycode == KEY_P:
		_on_menu(MenuId.SETTINGS_PANELS)
	elif key.keycode == KEY_F11:
		_on_menu(MenuId.SETTINGS_FULLSCREEN)
	elif key.ctrl_pressed and key.keycode == KEY_Q:
		_on_menu(MenuId.SETTINGS_QUIT)
	else:
		return
	get_viewport().set_input_as_handled()


func _on_bridge_confirmed() -> void:
	var address := _bridge_edit.text.strip_edges()
	if _openmind != null and (address.begins_with("ws://") or address.begins_with("wss://")):
		_openmind.connect_to(address)


## Command the demo should send: the current scene's cue when it has one.
func _demo_command() -> String:
	if current_scene != null and current_scene.has_method("demo_command"):
		return current_scene.demo_command()
	return ""


func _on_status(status: Dictionary) -> void:
	var user: Variant = status.get("user")
	_profile_menu.set_item_text(0, "User: %s (from the decoder)" % (user if user != null else "—"))
