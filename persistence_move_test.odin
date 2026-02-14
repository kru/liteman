package main

import "core:strings"
import "core:testing"

@(test)
test_is_descendant :: proc(t: ^testing.T) {
	// Setup tree: Root -> Folder(1) -> Child(2)
	parent := SavedCommand {
		id       = 1,
		type     = .Folder,
		children = make([dynamic]SavedCommand),
	}
	defer {
		delete(parent.children)
		// We don't alloc strings here for simplicity needed for this test
	}

	child := SavedCommand {
		id = 2,
	}
	append(&parent.children, child)

	testing.expect(t, is_descendant(parent, 2), "2 should be descendant of 1")
	testing.expect(t, !is_descendant(parent, 3), "3 should not be descendant")
}

@(test)
test_move_command_logic :: proc(t: ^testing.T) {
	// Initialize AppState with a simple tree
	// Root
	//  - Folder A (1)
	//  - Item B (2)

	state := AppState {
		commands = make([dynamic]SavedCommand),
	}
	defer {
		// Clean up
		if len(state.commands) > 0 {
			// After move: commands[0] is root folder (1), commands[0].children[0] is item (2)
			folder := state.commands[0]
			delete(folder.name)

			if len(folder.children) > 0 {
				item := folder.children[0]
				delete(item.name)
				// Item has no children
			}
			delete(folder.children)
		}
		delete(state.commands)
	}

	folder := SavedCommand {
		id       = 1,
		type     = .Folder,
		name     = strings.clone("Folder A"),
		children = make([dynamic]SavedCommand),
	}
	item := SavedCommand {
		id   = 2,
		type = .Request,
		name = strings.clone("Item B"),
	}

	append(&state.commands, folder)
	append(&state.commands, item)

	// Move Item B (2) into Folder A (1)
	success := move_command(&state, 2, 1)
	testing.expect(t, success, "Move should succeed")

	// Verify structure
	// Root should have 1 item (Folder A)
	testing.expect_value(t, len(state.commands), 1)
	testing.expect_value(t, state.commands[0].id, 1)

	// Folder A should have 1 child (Item B)
	testing.expect_value(t, len(state.commands[0].children), 1)
	testing.expect_value(t, state.commands[0].children[0].id, 2)
}

@(test)
test_move_command_cycle_prevention :: proc(t: ^testing.T) {
	// Root -> Folder A (1) -> Folder B (2)
	// Try to move Folder A into Folder B (should fail)

	state := AppState {
		commands = make([dynamic]SavedCommand),
	}
	defer delete(state.commands) // minimal cleanup

	folder_a := SavedCommand {
		id       = 1,
		type     = .Folder,
		children = make([dynamic]SavedCommand),
	}
	folder_b := SavedCommand {
		id   = 2,
		type = .Folder,
	}

	append(&folder_a.children, folder_b)
	append(&state.commands, folder_a)

	// Try to move 1 into 2
	success := move_command(&state, 1, 2)
	testing.expect(t, !success, "Move to descendant should fail")
}
