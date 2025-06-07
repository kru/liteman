package main

import "base:runtime"
import clay "clay-odin"
import "core:encoding/json"
import "core:fmt"
import "core:math"
import "core:strings"
import "vendor:raylib"

COLOR_LIGHT :: clay.Color{224, 215, 210, 255}
COLOR_RED :: clay.Color{168, 66, 28, 255}
COLOR_ORANGE :: clay.Color{225, 138, 50, 255}
COLOR_BLACK :: clay.Color{0, 0, 0, 255}

windowWidth: i32 = 1024
windowHeight: i32 = 768

FONT_ID_BODY_16 :: 0
FONT_ID_BODY_36 :: 5
FONT_ID_BODY_30 :: 6
FONT_ID_BODY_28 :: 7
FONT_ID_BODY_24 :: 8

Raylib_Font :: struct {
	fontId: u16,
	font:   raylib.Font,
}

clay_color_to_rl_color :: proc(color: clay.Color) -> raylib.Color {
	return {u8(color.r), u8(color.g), u8(color.b), u8(color.a)}
}

loadFont :: proc(fontId: u16, fontSize: u16, path: cstring) {
	assign_at(
		&raylib_fonts,
		fontId,
		Raylib_Font {
			font = raylib.LoadFontEx(path, cast(i32)fontSize * 2, nil, 0),
			fontId = cast(u16)fontId,
		},
	)
	raylib.SetTextureFilter(raylib_fonts[fontId].font.texture, raylib.TextureFilter.TRILINEAR)
}

raylib_fonts := [dynamic]Raylib_Font{}

draw_arc :: proc(
	x, y: f32,
	inner_rad, outer_rad: f32,
	start_angle, end_angle: f32,
	color: clay.Color,
) {
	raylib.DrawRing(
		{math.round(x), math.round(y)},
		math.round(inner_rad),
		outer_rad,
		start_angle,
		end_angle,
		10,
		clay_color_to_rl_color(color),
	)
}

draw_rect :: proc(x, y, w, h: f32, color: clay.Color) {
	raylib.DrawRectangle(
		i32(math.round(x)),
		i32(math.round(y)),
		i32(math.round(w)),
		i32(math.round(h)),
		clay_color_to_rl_color(color),
	)
}

draw_rect_rounded :: proc(x, y, w, h: f32, radius: f32, color: clay.Color) {
	raylib.DrawRectangleRounded({x, y, w, h}, radius, 8, clay_color_to_rl_color(color))
}

measure_text :: proc "c" (
	text: clay.StringSlice,
	config: ^clay.TextElementConfig,
	userData: rawptr,
) -> clay.Dimensions {
	line_width: f32 = 0

	font := raylib_fonts[config.fontId].font

	for i in 0 ..< text.length {
		glyph_index := text.chars[i] - 32

		glyph := font.glyphs[glyph_index]

		if glyph.advanceX != 0 {
			line_width += f32(glyph.advanceX)
		} else {
			line_width += font.recs[glyph_index].width + f32(glyph.offsetX)
		}
	}

	return {width = line_width / 2, height = f32(config.fontSize)}
}

error_handler :: proc "c" (err_data: clay.ErrorData) {
	context = runtime.default_context()
	fmt.printfln("%s", err_data.errorText)
}

// Layout config is just a struct that can be declacred static, or inline
sidebar_item_layout := clay.LayoutConfig {
	sizing = {width = clay.SizingGrow({}), height = clay.SizingFixed(50)},
}

// Re-usable components are just normal
sidebar_item_component :: proc(index: u32) {
	if clay.UI()(
	{
		id = clay.ID("SidebarBlob", index),
		layout = sidebar_item_layout,
		backgroundColor = COLOR_ORANGE,
	},
	) {}
}

// An example function to create your layout tree
create_layout :: proc() -> clay.ClayArray(clay.RenderCommand) {
	// Begin constructing the layout.
	clay.BeginLayout()

	// An example of laying out a UI with a fixed-width sidebar and flexible-width main content
	// NOTE: To create a scope for child components, the Odin API uses `if` with components that have children
	if clay.UI()(
	{
		id = clay.ID("OuterContainer"),
		layout = {
			sizing = {width = clay.SizingGrow({}), height = clay.SizingGrow({})},
			padding = {16, 16, 16, 16},
			childGap = 16,
		},
		backgroundColor = {250, 250, 255, 255},
	},
	) {
		if clay.UI()(
		{
			id = clay.ID("SideBar"),
			layout = {
				layoutDirection = .TopToBottom,
				sizing = {width = clay.SizingFixed(300), height = clay.SizingGrow({})},
				padding = {16, 16, 16, 16},
				childGap = 16,
			},
			backgroundColor = COLOR_LIGHT,
		},
		) {
			if clay.UI()(
			{
				id = clay.ID("ProfilePictureOuter"),
				layout = {
					sizing = {width = clay.SizingGrow({})},
					padding = {16, 16, 16, 16},
					childGap = 16,
					childAlignment = {y = .Center},
				},
				backgroundColor = COLOR_RED,
				cornerRadius = {6, 6, 6, 6},
			},
			) {
				if clay.UI()(
				{
					id = clay.ID("ProfilePicture"),
					layout = {
						sizing = {width = clay.SizingFixed(60), height = clay.SizingFixed(60)},
					},
				},
				) {}

				clay.Text(
					"Clay - UI Library",
					clay.TextConfig({textColor = COLOR_BLACK, fontSize = 16}),
				)
			}

			// Standard Odin code like loops, etc. work inside components.
			// Here we render 5 sidebar items.
			for i in u32(0) ..< 5 {
				sidebar_item_component(i)
			}
		}

		if clay.UI()(
		{
			id = clay.ID("MainContent"),
			layout = {sizing = {width = clay.SizingGrow({}), height = clay.SizingGrow({})}},
			backgroundColor = COLOR_LIGHT,
		},
		) {}
	}

	// Returns a list of render commands
	return clay.EndLayout()
}

clay_raylib_render :: proc(
	render_commands: ^clay.ClayArray(clay.RenderCommand),
	allocator := context.temp_allocator,
) {
	for i in 0 ..< render_commands.length {
		render_command := clay.RenderCommandArray_Get(render_commands, i)
		bounds := render_command.boundingBox

		switch render_command.commandType {
		case .None: // None
		case .Text:
			config := render_command.renderData.text

			text := string(config.stringContents.chars[:config.stringContents.length])

			// Raylib uses C strings instead of Odin strings, so we need to clone
			// Assume this will be freed elsewhere since we default to the temp allocator
			cstr_text := strings.clone_to_cstring(text, allocator)

			font := raylib_fonts[config.fontId].font
			raylib.DrawTextEx(
				font,
				cstr_text,
				{bounds.x, bounds.y},
				f32(config.fontSize),
				f32(config.letterSpacing),
				clay_color_to_rl_color(config.textColor),
			)
		case .Image:
			config := render_command.renderData.image
			tint := config.backgroundColor
			if tint == 0 {
				tint = {255, 255, 255, 255}
			}

			imageTexture := (^raylib.Texture2D)(config.imageData)
			raylib.DrawTextureEx(
				imageTexture^,
				{bounds.x, bounds.y},
				0,
				bounds.width / f32(imageTexture.width),
				clay_color_to_rl_color(tint),
			)
		case .ScissorStart:
			raylib.BeginScissorMode(
				i32(math.round(bounds.x)),
				i32(math.round(bounds.y)),
				i32(math.round(bounds.width)),
				i32(math.round(bounds.height)),
			)
		case .ScissorEnd:
			raylib.EndScissorMode()
		case .Rectangle:
			config := render_command.renderData.rectangle
			if config.cornerRadius.topLeft > 0 {
				radius: f32 = (config.cornerRadius.topLeft * 2) / min(bounds.width, bounds.height)
				draw_rect_rounded(
					bounds.x,
					bounds.y,
					bounds.width,
					bounds.height,
					radius,
					config.backgroundColor,
				)
			} else {
				draw_rect(bounds.x, bounds.y, bounds.width, bounds.height, config.backgroundColor)
			}
		case .Border:
			config := render_command.renderData.border
			// Left border
			if config.width.left > 0 {
				draw_rect(
					bounds.x,
					bounds.y + config.cornerRadius.topLeft,
					f32(config.width.left),
					bounds.height - config.cornerRadius.topLeft - config.cornerRadius.bottomLeft,
					config.color,
				)
			}
			// Right border
			if config.width.right > 0 {
				draw_rect(
					bounds.x + bounds.width - f32(config.width.right),
					bounds.y + config.cornerRadius.topRight,
					f32(config.width.right),
					bounds.height - config.cornerRadius.topRight - config.cornerRadius.bottomRight,
					config.color,
				)
			}
			// Top border
			if config.width.top > 0 {
				draw_rect(
					bounds.x + config.cornerRadius.topLeft,
					bounds.y,
					bounds.width - config.cornerRadius.topLeft - config.cornerRadius.topRight,
					f32(config.width.top),
					config.color,
				)
			}
			// Bottom border
			if config.width.bottom > 0 {
				draw_rect(
					bounds.x + config.cornerRadius.bottomLeft,
					bounds.y + bounds.height - f32(config.width.bottom),
					bounds.width -
					config.cornerRadius.bottomLeft -
					config.cornerRadius.bottomRight,
					f32(config.width.bottom),
					config.color,
				)
			}

			// Rounded Borders
			if config.cornerRadius.topLeft > 0 {
				draw_arc(
					bounds.x + config.cornerRadius.topLeft,
					bounds.y + config.cornerRadius.topLeft,
					config.cornerRadius.topLeft - f32(config.width.top),
					config.cornerRadius.topLeft,
					180,
					270,
					config.color,
				)
			}
			if config.cornerRadius.topRight > 0 {
				draw_arc(
					bounds.x + bounds.width - config.cornerRadius.topRight,
					bounds.y + config.cornerRadius.topRight,
					config.cornerRadius.topRight - f32(config.width.top),
					config.cornerRadius.topRight,
					270,
					360,
					config.color,
				)
			}
			if config.cornerRadius.bottomLeft > 0 {
				draw_arc(
					bounds.x + config.cornerRadius.bottomLeft,
					bounds.y + bounds.height - config.cornerRadius.bottomLeft,
					config.cornerRadius.bottomLeft - f32(config.width.top),
					config.cornerRadius.bottomLeft,
					90,
					180,
					config.color,
				)
			}
			if config.cornerRadius.bottomRight > 0 {
				draw_arc(
					bounds.x + bounds.width - config.cornerRadius.bottomRight,
					bounds.y + bounds.height - config.cornerRadius.bottomRight,
					config.cornerRadius.bottomRight - f32(config.width.bottom),
					config.cornerRadius.bottomRight,
					0.1,
					90,
					config.color,
				)
			}
		case clay.RenderCommandType.Custom:
		// Implement custom element rendering here
		}
	}
}

main :: proc() {
	min_mem_size := clay.MinMemorySize()
	memory := make([^]u8, min_mem_size)
	arena := clay.CreateArenaWithCapacityAndMemory(uint(min_mem_size), memory)

	clay.Initialize(
		arena,
		{cast(f32)raylib.GetScreenWidth(), cast(f32)raylib.GetScreenHeight()},
		{handler = error_handler},
	)
	clay.SetMeasureTextFunction(measure_text, nil)

	raylib.SetConfigFlags({.VSYNC_HINT, .WINDOW_RESIZABLE, .MSAA_4X_HINT})
	raylib.InitWindow(windowWidth, windowHeight, "liteman")
	raylib.SetTargetFPS(raylib.GetMonitorRefreshRate(0))

	loadFont(FONT_ID_BODY_36, 36, "resources/Quicksand.ttf")
	loadFont(FONT_ID_BODY_30, 30, "resources/Quicksand.ttf")
	loadFont(FONT_ID_BODY_28, 28, "resources/Quicksand.ttf")
	loadFont(FONT_ID_BODY_24, 24, "resources/Quicksand.ttf")
	loadFont(FONT_ID_BODY_16, 16, "resources/Quicksand.ttf")
	allocator := context.temp_allocator

	for !raylib.WindowShouldClose() {
		defer free_all(allocator)

		windowWidth = raylib.GetScreenWidth()
		windowHeight = raylib.GetScreenHeight()

		clay.SetLayoutDimensions(
			{cast(f32)raylib.GetScreenWidth(), cast(f32)raylib.GetScreenHeight()},
		)
		clay.SetPointerState(
			transmute(clay.Vector2)raylib.GetMousePosition(),
			raylib.IsMouseButtonDown(raylib.MouseButton.LEFT),
		)
		clay.UpdateScrollContainers(
			false,
			transmute(clay.Vector2)raylib.GetMouseWheelMoveV(),
			raylib.GetFrameTime(),
		)

		render_commands := create_layout()

		raylib.BeginDrawing()
		clay_raylib_render(&render_commands)
		raylib.EndDrawing()
	}
}
