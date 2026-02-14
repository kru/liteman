package main

import "core:strings"
import "core:testing"

@(test)
test_search_recursive :: proc(t: ^testing.T) {
	// Setup commands
	commands := make([dynamic]SavedCommand)
	defer {
		for cmd in commands {delete(cmd.name)}
		delete(commands)
	}

	c1 := SavedCommand {
		id   = 1,
		name = strings.clone("Get Users"),
	}
	c2 := SavedCommand {
		id   = 2,
		name = strings.clone("Post Data"),
	}
	c3 := SavedCommand {
		id   = 3,
		name = strings.clone("Delete Item"),
	}

	append(&commands, c1)
	append(&commands, c2)
	append(&commands, c3)

	// Search for "user"
	result := make([dynamic]^SavedCommand)
	defer delete(result)

	search_recursive(commands[:], "user", &result)

	testing.expect_value(t, len(result), 1)
	if len(result) > 0 {
		testing.expect_value(t, result[0].id, 1)
	}
}

@(test)
test_search_recursive_nested :: proc(t: ^testing.T) {
	// Root -> Folder (matches) -> Child (matches)
	//      -> Other (no match)

	commands := make([dynamic]SavedCommand)
	defer delete(commands) // minimal cleanup

	folder := SavedCommand {
		id       = 1,
		name     = strings.clone("User Folder"),
		children = make([dynamic]SavedCommand),
	}

	child := SavedCommand {
		id   = 2,
		name = strings.clone("Get User"),
	}
	append(&folder.children, child)

	append(&commands, folder)

	result := make([dynamic]^SavedCommand)
	defer delete(result)

	search_recursive(commands[:], "user", &result)

	testing.expect_value(t, len(result), 2) // Both folder and child match
}
