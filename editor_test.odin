package main

import "core:strings"
import "core:testing"

@(test)
test_editor_insert_delete :: proc(t: ^testing.T) {
	editor := init_editor()
	defer destroy_editor(&editor)

	editor_insert(&editor, "Hello")
	testing.expect_value(t, editor_get_text(&editor), "Hello")
	testing.expect_value(t, editor.cursor, 5)

	editor_backspace(&editor)
	testing.expect_value(t, editor_get_text(&editor), "Hell")
	testing.expect_value(t, editor.cursor, 4)

	editor.cursor = 0
	editor_delete(&editor)
	testing.expect_value(t, editor_get_text(&editor), "ell")
}

@(test)
test_editor_selection_delete :: proc(t: ^testing.T) {
	editor := init_editor()
	defer destroy_editor(&editor)

	editor_insert(&editor, "Hello World")
	// Select "World"
	editor.cursor = 11
	editor.selection_anchor = 6

	delete_selection(&editor)
	testing.expect_value(t, editor_get_text(&editor), "Hello ")
	testing.expect_value(t, editor.cursor, 6)
}

@(test)
test_editor_undo_redo :: proc(t: ^testing.T) {
	editor := init_editor()
	defer destroy_editor(&editor)

	editor_insert(&editor, "A")
	editor_insert(&editor, "B")
	testing.expect_value(t, editor_get_text(&editor), "AB")

	editor_undo(&editor)
	testing.expect_value(t, editor_get_text(&editor), "A")

	editor_undo(&editor)
	testing.expect_value(t, editor_get_text(&editor), "")

	editor_redo(&editor)
	testing.expect_value(t, editor_get_text(&editor), "A")

	editor_redo(&editor)
	testing.expect_value(t, editor_get_text(&editor), "AB")
}

@(test)
test_editor_move_word :: proc(t: ^testing.T) {
	editor := init_editor()
	defer destroy_editor(&editor)

	editor_insert(&editor, "Hello World")
	editor.cursor = 0

	// Move right by word
	editor_move_right(&editor, false, true)
	testing.expect_value(t, editor.cursor, 6) // "Hello "

	editor_move_right(&editor, false, true)
	testing.expect_value(t, editor.cursor, 11) // "Hello World"

	// Move left by word
	editor_move_left(&editor, false, true)
	testing.expect_value(t, editor.cursor, 6)
}
