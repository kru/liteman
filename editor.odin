package main

import "core:fmt"
import "core:strings"
import "core:unicode/utf8"
import "vendor:raylib"

// Platform specific modifier checks
is_key_down_cmd :: proc() -> bool {
	when ODIN_OS == .Darwin {
		return raylib.IsKeyDown(.LEFT_SUPER) || raylib.IsKeyDown(.RIGHT_SUPER)
	} else {
		return raylib.IsKeyDown(.LEFT_CONTROL) || raylib.IsKeyDown(.RIGHT_CONTROL)
	}
}

is_key_down_ctrl :: proc() -> bool {
	return raylib.IsKeyDown(.LEFT_CONTROL) || raylib.IsKeyDown(.RIGHT_CONTROL)
}

is_key_down_alt :: proc() -> bool {
	return raylib.IsKeyDown(.LEFT_ALT) || raylib.IsKeyDown(.RIGHT_ALT)
}

is_key_down_shift :: proc() -> bool {
	return raylib.IsKeyDown(.LEFT_SHIFT) || raylib.IsKeyDown(.RIGHT_SHIFT)
}

// Editor Action Type for Undo/Redo
EditActionType :: enum {
	Insert,
	Delete,
	Replace, // For selection replacement
}

EditAction :: struct {
	type:         EditActionType,
	text:         string, // Text inserted or deleted
	start:        int, // Position where action occurred
	end:          int, // End position (for range deletions/replacements)
	cursor_after: int, // Cursor position after this action is undone/redone
}

Editor :: struct {
	text:             [dynamic]u8,
	cursor:           int,
	selection_anchor: Maybe(int),
	undo_stack:       [dynamic]EditAction,
	redo_stack:       [dynamic]EditAction,
	preferred_col:    f32, // For up/down navigation to maintain column
	scroll_y:         f32, // Vertical scroll position
	target_scroll_y:  f32, // For smooth scrolling
}

// Initialize a new editor
init_editor :: proc(allocator := context.allocator) -> Editor {
	return Editor {
		text = make([dynamic]u8, allocator),
		cursor = 0,
		undo_stack = make([dynamic]EditAction, allocator),
		redo_stack = make([dynamic]EditAction, allocator),
	}
}

// Destroy editor resources
destroy_editor :: proc(editor: ^Editor) {
	delete(editor.text)
	for action in editor.undo_stack {
		delete(action.text)
	}
	delete(editor.undo_stack)
	for action in editor.redo_stack {
		delete(action.text)
	}
	delete(editor.redo_stack)
}

// Set text content
editor_set_text :: proc(editor: ^Editor, text: string) {
	clear(&editor.text)
	append(&editor.text, ..transmute([]u8)text)
	editor.cursor = len(editor.text)
	editor.selection_anchor = nil

	// Clear undo/redo stacks on setting new text (optional, but usually good practice)
	clear_undo_redo(editor)
}

clear_undo_redo :: proc(editor: ^Editor) {
	for action in editor.undo_stack {delete(action.text)}
	clear(&editor.undo_stack)
	for action in editor.redo_stack {delete(action.text)}
	clear(&editor.redo_stack)
}

// Get text content as string
editor_get_text :: proc(editor: ^Editor) -> string {
	return string(editor.text[:])
}

// Clear redo stack
clear_redo :: proc(editor: ^Editor) {
	for action in editor.redo_stack {
		delete(action.text)
	}
	clear(&editor.redo_stack)
}

// Push action to undo stack
push_undo :: proc(editor: ^Editor, action: EditAction) {
	append(&editor.undo_stack, action)
	clear_redo(editor)
}

// Get selection range (start, end)
get_selection_range :: proc(editor: ^Editor) -> (start, end: int, has_selection: bool) {
	if anchor, ok := editor.selection_anchor.?; ok && anchor != editor.cursor {
		return min(anchor, editor.cursor), max(anchor, editor.cursor), true
	}
	return editor.cursor, editor.cursor, false
}

// Delete selection if exists
delete_selection :: proc(editor: ^Editor) -> bool {
	start, end, has_sel := get_selection_range(editor)
	if !has_sel {return false}

	// Record for undo
	deleted_text := string(editor.text[start:end])
	text_copy := strings.clone(deleted_text)

	action := EditAction {
		type         = .Delete,
		text         = text_copy,
		start        = start,
		end          = end,
		cursor_after = start,
	}
	push_undo(editor, action)

	// Remove text
	remove_range(&editor.text, start, end)

	editor.cursor = start
	editor.selection_anchor = nil
	return true
}

// Helper to remove range from dynamic array
remove_range :: proc(buffer: ^[dynamic]u8, start, end: int) {
	if start >= end || start < 0 || end > len(buffer) {return}
	copy(buffer[start:], buffer[end:])
	resize(buffer, len(buffer) - (end - start))
}

// Helper to insert string into dynamic array
insert_string :: proc(buffer: ^[dynamic]u8, pos: int, s: string) {
	if pos < 0 || pos > len(buffer) {return}

	// Make space
	s_len := len(s)
	resize(buffer, len(buffer) + s_len)
	copy(buffer[pos + s_len:], buffer[pos:])
	copy(buffer[pos:], transmute([]u8)s)
}

// Insert text at cursor
editor_insert :: proc(editor: ^Editor, text: string) {
	// First delete selection if any
	start, end, has_sel := get_selection_range(editor)

	if has_sel {
		// Replace action
		deleted_text := strings.clone(string(editor.text[start:end]))

		action := EditAction {
			type         = .Replace,
			text         = deleted_text, // Store deleted text to restore on undo
			start        = start,
			end          = len(text), // Store length of inserted text to delete on undo
			cursor_after = start + len(text),
		}
		// Special case: we need to store BOTH deleted and inserted text for Replace?
		// Simpler approach: Treat as Delete then Insert in undo stack?
		// Let's just do Delete Selection manually then regular Insert to keep it simple for now.
		// Or implement Replace properly.

		// Let's do Delete then Insert as separate actions for simplicity first,
		// or combined if we want atomic undo. atomic is better.
		// For now, let's just use delete_selection() which pushes a Delete action,
		// then insert which pushes an Insert action.
		// User might have to undo twice, but we can group them later.
		delete_selection(editor)
	}

	insert_string(&editor.text, editor.cursor, text)

	text_copy := strings.clone(text)
	action := EditAction {
		type         = .Insert,
		text         = text_copy,
		start        = editor.cursor,
		end          = editor.cursor + len(text),
		cursor_after = editor.cursor + len(text),
	}
	push_undo(editor, action)

	editor.cursor += len(text)
	editor.preferred_col = -1 // Reset preferred column on edit
}

// Backspace
editor_backspace :: proc(editor: ^Editor) {
	if delete_selection(editor) {return}

	if editor.cursor > 0 {
		// Simple backspace of 1 character (byte for now, TODO: utf8)
		// Check for utf8 start byte
		prev_char_len := 1
		// if editor.cursor >= 1 && (editor.text[editor.cursor-1] & 0xC0) == 0x80 { ... }
		// For simplicity assuming ascii/single-byte mostly or implementing proper utf8 later

		// Correct UTF-8 backspacing
		start_pos := editor.cursor
		for start_pos > 0 {
			start_pos -= 1
			// If it's a start byte (0xxxxxxx or 11xxxxxx) or we reached 0, break
			if (editor.text[start_pos] & 0xC0) != 0x80 {
				break
			}
		}

		del_len := editor.cursor - start_pos
		deleted_text := strings.clone(string(editor.text[start_pos:editor.cursor]))

		action := EditAction {
			type         = .Delete,
			text         = deleted_text,
			start        = start_pos,
			end          = editor.cursor,
			cursor_after = start_pos,
		}
		push_undo(editor, action)

		remove_range(&editor.text, start_pos, editor.cursor)
		editor.cursor = start_pos
		editor.preferred_col = -1
	}
}

// Delete (forward)
editor_delete :: proc(editor: ^Editor) {
	if delete_selection(editor) {return}

	if editor.cursor < len(editor.text) {
		// UTF-8 forward delete
		end_pos := editor.cursor + 1
		for end_pos < len(editor.text) {
			if (editor.text[end_pos] & 0xC0) != 0x80 {
				break
			}
			end_pos += 1
		}

		deleted_text := strings.clone(string(editor.text[editor.cursor:end_pos]))

		action := EditAction {
			type         = .Delete,
			text         = deleted_text,
			start        = editor.cursor,
			end          = end_pos,
			cursor_after = editor.cursor,
		}
		push_undo(editor, action)

		remove_range(&editor.text, editor.cursor, end_pos)
		editor.preferred_col = -1
	}
}

// Undo
editor_undo :: proc(editor: ^Editor) {
	if len(editor.undo_stack) == 0 {return}

	action := pop(&editor.undo_stack)
	append(&editor.redo_stack, action) // Move to redo

	switch action.type {
	case .Insert:
		// Undo Insert: Delete the inserted text
		remove_range(&editor.text, action.start, action.end)
		editor.cursor = action.start
	case .Delete:
		// Undo Delete: Insert the deleted text back
		insert_string(&editor.text, action.start, action.text)
		editor.cursor = action.start + len(action.text)
	case .Replace:
	// Not used yet
	}

	editor.selection_anchor = nil
	editor.preferred_col = -1
}

// Redo
editor_redo :: proc(editor: ^Editor) {
	if len(editor.redo_stack) == 0 {return}

	action := pop(&editor.redo_stack)
	append(&editor.undo_stack, action) // Move back to undo

	switch action.type {
	case .Insert:
		// Redo Insert: Re-insert the text
		insert_string(&editor.text, action.start, action.text)
		editor.cursor = action.end
	case .Delete:
		// Redo Delete: Delete the text again
		remove_range(&editor.text, action.start, action.end)
		editor.cursor = action.start
	case .Replace:
	// Not used yet
	}

	editor.selection_anchor = nil
	editor.preferred_col = -1
}

// Move cursor
editor_move_left :: proc(editor: ^Editor, select: bool, word_jump: bool) {
	if select {
		if editor.selection_anchor == nil {
			editor.selection_anchor = editor.cursor
		}
	} else {
		if _, _, has := get_selection_range(editor); has {
			// If selection exists and we just press left, go to start of selection
			start, _, _ := get_selection_range(editor)
			editor.cursor = start
			editor.selection_anchor = nil
			editor.preferred_col = -1
			return
		}
		editor.selection_anchor = nil
	}

	if editor.cursor > 0 {
		if word_jump {
			// Move back until start of word
			// 1. Skip spaces backwards
			for editor.cursor > 0 && is_whitespace(editor.text[editor.cursor - 1]) {
				editor.cursor -= 1
			}
			// 2. Skip non-spaces backwards
			for editor.cursor > 0 && !is_whitespace(editor.text[editor.cursor - 1]) {
				editor.cursor -= 1
			}
		} else {
			// Move back one utf-8 char
			editor.cursor -= 1
			for editor.cursor > 0 && (editor.text[editor.cursor] & 0xC0) == 0x80 {
				editor.cursor -= 1
			}
		}
	}
	editor.preferred_col = -1
}

editor_move_right :: proc(editor: ^Editor, select: bool, word_jump: bool) {
	if select {
		if editor.selection_anchor == nil {
			editor.selection_anchor = editor.cursor
		}
	} else {
		if _, _, has := get_selection_range(editor); has {
			// If selection exists and we just press right, go to end of selection
			_, end, _ := get_selection_range(editor)
			editor.cursor = end
			editor.selection_anchor = nil
			editor.preferred_col = -1
			return
		}
		editor.selection_anchor = nil
	}

	if editor.cursor < len(editor.text) {
		if word_jump {
			// Move forward until end of word
			// 1. Skip non-spaces forward
			for editor.cursor < len(editor.text) && !is_whitespace(editor.text[editor.cursor]) {
				editor.cursor += 1
			}
			// 2. Skip spaces forward
			for editor.cursor < len(editor.text) && is_whitespace(editor.text[editor.cursor]) {
				editor.cursor += 1
			}
		} else {
			// Move forward one utf-8 char
			editor.cursor += 1
			for editor.cursor < len(editor.text) && (editor.text[editor.cursor] & 0xC0) == 0x80 {
				editor.cursor += 1
			}
		}
	}
	editor.preferred_col = -1
}


is_whitespace :: proc(c: u8) -> bool {
	return c == ' ' || c == '\n' || c == '\t' || c == '\r'
}

// TODO: Up/Down navigation requires knowledge of layout/lines
// We can implement basic line seeking here:

get_line_start :: proc(editor: ^Editor, pos: int) -> int {
	p := pos
	for p > 0 {
		if editor.text[p - 1] == '\n' {return p}
		p -= 1
	}
	return 0
}

get_line_end :: proc(editor: ^Editor, pos: int) -> int {
	p := pos
	for p < len(editor.text) {
		if editor.text[p] == '\n' {return p}
		p += 1
	}
	return len(editor.text)
}

// Count lines in text
count_lines :: proc(editor: ^Editor) -> int {
	count := 1
	for b in editor.text {
		if b == '\n' {count += 1}
	}
	return count
}

// Move cursor up
editor_move_up :: proc(editor: ^Editor, select: bool, font_id: u16, font_size: u16, width: f32) {
	if select {
		if editor.selection_anchor == nil {
			editor.selection_anchor = editor.cursor
		}
	} else {
		editor.selection_anchor = nil
	}

	// Get current visual position
	current_x, current_y := calculate_wrapped_position(
		editor.text[:],
		editor.cursor,
		width,
		font_id,
		font_size,
	)

	// Set preferred column if not set
	if editor.preferred_col < 0 {
		editor.preferred_col = current_x
	}

	// Target position
	target_y := current_y - f32(font_size)
	target_x := editor.preferred_col

	// Safety check
	if target_y < 0 {
		// Top of file, go to start
		editor.cursor = 0
		return
	}

	// Find index at target position
	editor.cursor = calculate_cursor_from_click(
		editor.text[:],
		len(editor.text),
		target_x,
		target_y,
		width,
		font_id,
		font_size,
	)
}

// Move cursor down
editor_move_down :: proc(editor: ^Editor, select: bool, font_id: u16, font_size: u16, width: f32) {
	if select {
		if editor.selection_anchor == nil {
			editor.selection_anchor = editor.cursor
		}
	} else {
		editor.selection_anchor = nil
	}

	// Get current visual position
	current_x, current_y := calculate_wrapped_position(
		editor.text[:],
		editor.cursor,
		width,
		font_id,
		font_size,
	)

	// Set preferred column if not set
	if editor.preferred_col < 0 {
		editor.preferred_col = current_x
	}

	// Target position
	target_y := current_y + f32(font_size)
	target_x := editor.preferred_col

	// Find index at target position
	// We need to check if we are already at the last visual line to avoid getting stuck or wrapping weirdly
	// calculate_cursor_from_click handles "past end" logic

	editor.cursor = calculate_cursor_from_click(
		editor.text[:],
		len(editor.text),
		target_x,
		target_y,
		width,
		font_id,
		font_size,
	)
}

// Handle all input for the editor
// Handle all input for the editor
editor_handle_input :: proc(editor: ^Editor, width: f32, font_id: u16, font_size: u16) {
	// Mods
	ctrl := is_key_down_ctrl()
	cmd := is_key_down_cmd() // Cmd on Mac, Ctrl on Windows
	alt := is_key_down_alt()
	shift := is_key_down_shift()

	// Text Input
	for {
		char := raylib.GetCharPressed()
		if char == 0 {break}

		// Filter control characters if shortcut is pressed
		is_shortcut := false
		when ODIN_OS == .Darwin {
			is_shortcut = cmd || ctrl
		} else {
			is_shortcut = ctrl
		}

		if !is_shortcut && char >= 32 {
			// Need to convert rune to string/bytes properly
			runes: [1]rune = {char}
			s := utf8.runes_to_string(runes[:], context.temp_allocator)
			editor_insert(editor, s)
		}
	}

	// Key Navigation
	word_jump := false

	when ODIN_OS == .Darwin {
		// Mac Navigation
		word_jump = alt

		if raylib.IsKeyPressed(.LEFT) || raylib.IsKeyPressedRepeat(.LEFT) {
			if cmd {
				// Cmd+Left = Line Start
				editor_move_line_start(editor, shift)
			} else {
				editor_move_left(editor, shift, word_jump)
			}
		}
		if raylib.IsKeyPressed(.RIGHT) || raylib.IsKeyPressedRepeat(.RIGHT) {
			if cmd {
				// Cmd+Right = Line End
				editor_move_line_end(editor, shift)
			} else {
				editor_move_right(editor, shift, word_jump)
			}
		}
		if raylib.IsKeyPressed(.UP) || raylib.IsKeyPressedRepeat(.UP) {
			if cmd {
				// Cmd+Up = Doc Start
				editor_move_doc_start(editor, shift)
			} else {
				editor_move_up(editor, shift, font_id, font_size, width)
			}
		}
		if raylib.IsKeyPressed(.DOWN) || raylib.IsKeyPressedRepeat(.DOWN) {
			if cmd {
				// Cmd+Down = Doc End
				editor_move_doc_end(editor, shift)
			} else {
				editor_move_down(editor, shift, font_id, font_size, width)
			}
		}
	} else {
		// Windows/Linux Navigation
		word_jump = ctrl

		if raylib.IsKeyPressed(.LEFT) || raylib.IsKeyPressedRepeat(.LEFT) {
			editor_move_left(editor, shift, word_jump)
		}
		if raylib.IsKeyPressed(.RIGHT) || raylib.IsKeyPressedRepeat(.RIGHT) {
			editor_move_right(editor, shift, word_jump)
		}
		if raylib.IsKeyPressed(.UP) || raylib.IsKeyPressedRepeat(.UP) {
			editor_move_up(editor, shift, font_id, font_size, width)
		}
		if raylib.IsKeyPressed(.DOWN) || raylib.IsKeyPressedRepeat(.DOWN) {
			editor_move_down(editor, shift, font_id, font_size, width)
		}

		// Home/End
		if raylib.IsKeyPressed(.HOME) {
			if ctrl {
				editor_move_doc_start(editor, shift)
			} else {
				editor_move_line_start(editor, shift)
			}
		}
		if raylib.IsKeyPressed(.END) {
			if ctrl {
				editor_move_doc_end(editor, shift)
			} else {
				editor_move_line_end(editor, shift)
			}
		}
	}

	// Editing Keys
	if raylib.IsKeyPressed(.BACKSPACE) || raylib.IsKeyPressedRepeat(.BACKSPACE) {
		editor_backspace(editor)
	}
	if raylib.IsKeyPressed(.DELETE) || raylib.IsKeyPressedRepeat(.DELETE) {
		editor_delete(editor)
	}
	if raylib.IsKeyPressed(.ENTER) || raylib.IsKeyPressedRepeat(.ENTER) {
		// Ctrl+Enter is reserved for running
		if !ctrl {
			editor_insert(editor, "\n")
		}
	}

	// Copy/Paste/Cut/Undo/Redo
	// Copy/Paste/Cut/Undo/Redo
	if cmd {
		if raylib.IsKeyPressed(.C) {
			start, end, has := get_selection_range(editor)
			if has {
				selection := string(editor.text[start:end])
				cstr := strings.clone_to_cstring(selection, context.temp_allocator)
				raylib.SetClipboardText(cstr)
			}
		}
		if raylib.IsKeyPressed(.V) {
			text := raylib.GetClipboardText()
			if text != nil {
				editor_insert(editor, string(text))
			}
		}
		if raylib.IsKeyPressed(.X) {
			start, end, has := get_selection_range(editor)
			if has {
				selection := string(editor.text[start:end])
				cstr := strings.clone_to_cstring(selection, context.temp_allocator)
				raylib.SetClipboardText(cstr)
				delete_selection(editor)
			}
		}
		if raylib.IsKeyPressed(.A) {
			editor.selection_anchor = 0
			editor.cursor = len(editor.text)
		}
		if raylib.IsKeyPressed(.Z) {
			if shift { 	// Ctrl+Shift+Z = Redo
				editor_redo(editor)
			} else {
				editor_undo(editor)
			}
		}

		// Windows specific Y for redo
		when ODIN_OS != .Darwin {
			if raylib.IsKeyPressed(.Y) {
				editor_redo(editor)
			}
		}
	}
}

// Helpers for navigation actions to reduce duplication

editor_move_line_start :: proc(editor: ^Editor, select: bool) {
	if select {
		if editor.selection_anchor == nil {editor.selection_anchor = editor.cursor}
	} else {
		editor.selection_anchor = nil
	}

	editor.cursor = get_line_start(editor, editor.cursor)
	editor.preferred_col = -1
}

editor_move_line_end :: proc(editor: ^Editor, select: bool) {
	if select {
		if editor.selection_anchor == nil {editor.selection_anchor = editor.cursor}
	} else {
		editor.selection_anchor = nil
	}

	editor.cursor = get_line_end(editor, editor.cursor)
	editor.preferred_col = -1
}

editor_move_doc_start :: proc(editor: ^Editor, select: bool) {
	if select {
		if editor.selection_anchor == nil {editor.selection_anchor = editor.cursor}
	} else {
		editor.selection_anchor = nil
	}
	editor.cursor = 0
	editor.preferred_col = -1
}

editor_move_doc_end :: proc(editor: ^Editor, select: bool) {
	if select {
		if editor.selection_anchor == nil {editor.selection_anchor = editor.cursor}
	} else {
		editor.selection_anchor = nil
	}
	editor.cursor = len(editor.text)
	editor.preferred_col = -1
}
