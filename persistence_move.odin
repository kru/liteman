package main

import "core:slice"
import "core:strings"

// Check if child is a descendant of parent (recursive)
is_descendant :: proc(parent: SavedCommand, child_id: u32) -> bool {
	for child in parent.children {
		if child.id == child_id {
			return true
		}
		if is_descendant(child, child_id) {
			return true
		}
	}
	return false
}

// Extract a command by ID from a list (recursive)
// Returns the command and true if found, removing it from the list
// Does NOT free the command's memory (as we want to move it)
extract_command_recursive :: proc(
	commands: ^[dynamic]SavedCommand,
	id: u32,
) -> (
	SavedCommand,
	bool,
) {
	for &cmd, i in commands {
		if cmd.id == id {
			// Found it
			found_cmd := cmd
			// Remove from list without freeing strings (using ordered_remove from core:slice or manual)
			ordered_remove(commands, i)
			return found_cmd, true
		}

		// Search children
		if len(cmd.children) > 0 {
			found_cmd, found := extract_command_recursive(&cmd.children, id)
			if found {
				return found_cmd, true
			}
		}
	}
	return SavedCommand{}, false
}

// Insert a command into a parent's children (recursive)
insert_command_recursive :: proc(
	commands: ^[dynamic]SavedCommand,
	parent_id: u32,
	cmd_to_insert: SavedCommand,
) -> bool {
	for &cmd in commands {
		if cmd.id == parent_id {
			append(&cmd.children, cmd_to_insert)
			return true
		}

		if len(cmd.children) > 0 {
			if insert_command_recursive(&cmd.children, parent_id, cmd_to_insert) {
				return true
			} // else continue searching
		}
	}
	return false
}

// Move command to new parent (0 for root)
move_command :: proc(state: ^AppState, cmd_id: u32, new_parent_id: u32) -> bool {
	if cmd_id == new_parent_id {
		return false // Can't move to self
	}

	// 1. Check validity (avoid cycles)
	// We need to find the command first to check its children
	cmd_ptr := find_command(state, cmd_id)
	if cmd_ptr == nil {
		return false // Command not found
	}

	// If moving to a folder, ensure the folder is not a child of the command we are moving
	if new_parent_id != 0 {
		if is_descendant(cmd_ptr^, new_parent_id) {
			return false // Can't move into own descendant
		}
	}

	// 2. Extract
	cmd, found := extract_command_recursive(&state.commands, cmd_id)
	if !found {
		return false // Should have found it since find_command succeeded, but safety check
	}

	// 3. Insert
	if new_parent_id == 0 {
		append(&state.commands, cmd)
		save_commands(state.commands[:])
		return true
	} else {
		if insert_command_recursive(&state.commands, new_parent_id, cmd) {
			// Expand the new parent folder so user sees the moved item
			parent := find_command(state, new_parent_id)
			if parent != nil {
				parent.expanded = true
			}
			save_commands(state.commands[:])
			return true
		} else {
			// Failed to find parent (maybe it was deleted concurrently? unlikely)
			// Re-insert at root to prevent data loss
			append(&state.commands, cmd)
			save_commands(state.commands[:])
			return false
		}
	}
}
