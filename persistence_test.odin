package main

import "core:os"
import "core:strings"
import "core:testing"

@(test)
test_json_conversion :: proc(t: ^testing.T) {
	// Create a SavedCommand
	cmd := SavedCommand {
		id       = 1,
		type     = .Request,
		name     = strings.clone("Test Command"),
		command  = strings.clone("curl example.com"),
		expanded = false,
	}
	defer {
		delete(cmd.name)
		delete(cmd.command)
	}

	// Convert to JSON struct
	jcmd := to_json_struct(cmd)
	defer destroy_json_struct(jcmd)

	// Verify fields
	testing.expect_value(t, jcmd.id, cmd.id)
	testing.expect_value(t, jcmd.name, cmd.name)
	testing.expect_value(t, jcmd.command, cmd.command)

	// Convert back
	cmd_back := from_json_struct(jcmd)
	defer {
		delete(cmd_back.name)
		delete(cmd_back.command)
		// children are empty
	}

	testing.expect_value(t, cmd_back.id, cmd.id)
	testing.expect_value(t, cmd_back.name, cmd.name)
	testing.expect_value(t, cmd_back.command, cmd.command)
}

@(test)
test_get_next_id :: proc(t: ^testing.T) {
	commands := make([dynamic]SavedCommand)
	defer delete(commands)

	cmd1 := SavedCommand {
		id = 10,
	}
	cmd2 := SavedCommand {
		id = 5,
	}

	append(&commands, cmd1)
	append(&commands, cmd2)

	next := get_next_id(commands[:])
	testing.expect_value(t, next, 11)
}

@(test)
test_command_hierarchy :: proc(t: ^testing.T) {
	// Test parent/child conversion
	parent := SavedCommand {
		id       = 1,
		type     = .Folder,
		name     = strings.clone("Folder"),
		children = make([dynamic]SavedCommand),
	}
	defer {
		delete(parent.name)
		for child in parent.children {
			delete(child.name)
			delete(child.command)
		}
		delete(parent.children)
		// note: recursive delete handling might be needed if deeply tested,
		// but here we manually clean up for simple test
	}

	child := SavedCommand {
		id      = 2,
		type    = .Request,
		name    = strings.clone("Child"),
		command = strings.clone("curl"),
	}
	append(&parent.children, child)

	jparent := to_json_struct(parent)
	defer destroy_json_struct(jparent)

	testing.expect_value(t, jparent.children[0].id, 2)
}

@(test)
test_get_config_dir :: proc(t: ^testing.T) {
	dir := get_config_dir()
	testing.expect(t, len(dir) > 0, "Config dir should not be empty")
}

@(test)
test_save_load_integration :: proc(t: ^testing.T) {
	// Use a temporary file for testing
	temp_file := "test_commands.json"
	defer os.remove(temp_file)

	// Create some commands
	commands := make([dynamic]SavedCommand)
	defer {
		for cmd in commands {
			delete(cmd.name)
			delete(cmd.command)
		}
		delete(commands)
	}

	cmd1 := SavedCommand {
		id      = 1,
		type    = .Request,
		name    = strings.clone("Test 1"),
		command = strings.clone("curl 1"),
	}
	append(&commands, cmd1)

	// Save to temp file
	success := save_commands(commands[:], temp_file)
	testing.expect(t, success, "Save should succeed")

	// Load directly to verify file exists and content
	loaded_commands, ok := load_commands(temp_file)
	testing.expect(t, ok, "Load should succeed")
	defer {
		for cmd in loaded_commands {
			delete(cmd.name)
			delete(cmd.command)
		}
		delete(loaded_commands)
	}

	testing.expect_value(t, len(loaded_commands), 1)
	testing.expect_value(t, loaded_commands[0].name, "Test 1")
	testing.expect_value(t, loaded_commands[0].command, "curl 1")
}
