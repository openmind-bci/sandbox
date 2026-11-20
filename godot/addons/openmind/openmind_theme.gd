class_name OpenMindTheme
extends RefCounted
## Shared look of the cockpit: logo colors, Space Grotesk font (SIL OFL 1.1),
## readable contrast and controls at least 44 px high.

const BACKGROUND := Color("#0E1424")
const PANEL := Color("#141B2E")
const PANEL_BORDER := Color("#2F4FB8")
const PRIMARY := Color("#5B82F0")
const PRIMARY_LIGHT := Color("#9DB8FF")
const ACCENT := Color("#2CC7AE")
const ACCENT_LIGHT := Color("#8EF1DA")
const TEXT := Color("#F3F5FA")
const TEXT_MUTED := Color("#B7C2DC")
const WARNING := Color("#FFC857")
const DANGER := Color("#FF7A8A")

const FONT_PATH := "res://addons/openmind/fonts/SpaceGrotesk.ttf"
const FONT_SIZE := 18
## Minimum height of buttons and menu entries, in pixels (touch target).
const MIN_TARGET := 44


## Build the theme; applied once to the root control of the cockpit.
static func build() -> Theme:
	var theme := Theme.new()
	var font: Font = load(FONT_PATH) if ResourceLoader.exists(FONT_PATH) else null
	if font != null:
		theme.default_font = font
	theme.default_font_size = FONT_SIZE

	for type in ["Label", "Button", "MenuBar", "PopupMenu", "LineEdit", "CheckBox",
			"FoldableContainer", "OptionButton"]:
		theme.set_color("font_color", type, TEXT)
	theme.set_color("font_hover_color", "Button", ACCENT_LIGHT)
	theme.set_color("font_focus_color", "Button", ACCENT_LIGHT)
	theme.set_color("font_pressed_color", "Button", TEXT)
	theme.set_color("font_disabled_color", "Button", TEXT_MUTED)
	theme.set_color("font_hover_color", "MenuBar", ACCENT_LIGHT)
	theme.set_color("font_hover_color", "PopupMenu", BACKGROUND)
	theme.set_color("font_disabled_color", "PopupMenu", TEXT_MUTED)
	theme.set_color("font_separator_color", "PopupMenu", TEXT_MUTED)

	var button := _box(PANEL, PANEL_BORDER)
	button.content_margin_top = 13
	button.content_margin_bottom = 13
	theme.set_stylebox("normal", "Button", button)
	theme.set_stylebox("hover", "Button", _box(PANEL_BORDER, PRIMARY))
	theme.set_stylebox("pressed", "Button", _box(PRIMARY, PRIMARY_LIGHT))
	theme.set_stylebox("focus", "Button", _focus())
	theme.set_stylebox("disabled", "Button", _box(BACKGROUND, PANEL))

	theme.set_stylebox("normal", "MenuBar", _box(BACKGROUND, BACKGROUND))
	theme.set_stylebox("hover", "MenuBar", _box(PANEL, PANEL_BORDER))
	theme.set_stylebox("pressed", "MenuBar", _box(PANEL_BORDER, PRIMARY))
	theme.set_stylebox("focus", "MenuBar", _focus())
	theme.set_stylebox("panel", "PopupMenu", _box(PANEL, PANEL_BORDER))
	theme.set_stylebox("hover", "PopupMenu", _box(ACCENT_LIGHT, ACCENT_LIGHT))
	# Menu entries at least MIN_TARGET px high: font size + vertical separation.
	theme.set_constant("v_separation", "PopupMenu", MIN_TARGET - FONT_SIZE)

	theme.set_stylebox("panel", "PanelContainer", _box(PANEL, PANEL))
	theme.set_stylebox("panel", "FoldableContainer", _box(PANEL, PANEL))
	theme.set_stylebox("title_panel", "FoldableContainer", _box(PANEL_BORDER, PANEL_BORDER))
	theme.set_stylebox("title_hover_panel", "FoldableContainer", _box(PRIMARY, PRIMARY))
	theme.set_stylebox("title_collapsed_panel", "FoldableContainer",
			_box(PANEL_BORDER, PANEL_BORDER))
	theme.set_stylebox("title_collapsed_hover_panel", "FoldableContainer", _box(PRIMARY, PRIMARY))
	theme.set_stylebox("focus", "FoldableContainer", _focus())

	theme.set_stylebox("background", "ProgressBar", _box(BACKGROUND, PANEL_BORDER))
	theme.set_stylebox("fill", "ProgressBar", _box(ACCENT, ACCENT))
	theme.set_color("font_color", "ProgressBar", TEXT)
	return theme


static func _box(fill: Color, border: Color) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = fill
	box.border_color = border
	box.set_border_width_all(1)
	box.set_corner_radius_all(6)
	box.content_margin_left = 12
	box.content_margin_right = 12
	box.content_margin_top = 6
	box.content_margin_bottom = 6
	return box


static func _focus() -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.draw_center = false
	box.border_color = ACCENT_LIGHT
	box.set_border_width_all(2)
	box.set_corner_radius_all(6)
	return box
