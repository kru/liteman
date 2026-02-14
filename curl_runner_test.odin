package main

import "core:strings"
import "core:testing"

@(test)
test_sanitize_multiline :: proc(t: ^testing.T) {
	input := "curl \\\nhttps://example.com"
	sanitized := sanitize_curl_command_string(input)
	defer delete(sanitized)

	// Expect "curl https://example.com" (with space replacing \n and backslash removed)
	// Wait, `sanitize_curl_command_string` logic:
	// if backslash followed by newline -> skip both (i += 2)
	// so result should be "curl https://example.com" (literally joined?)
	// Let's check the code:
	// if next == '\n' { i += 2; continue }
	// So "curl " + "https://..." -> "curl https://..."

	expected := "curl https://example.com"
	testing.expect_value(t, sanitized, expected)
}

@(test)
test_tokenize_command_quoting :: proc(t: ^testing.T) {
	input := "curl -d \"hello world\""
	args := tokenize_command(input)
	defer {
		for arg in args {
			delete(arg)
		}
		delete(args)
	}

	testing.expect_value(t, len(args), 3)
	if len(args) >= 3 {
		testing.expect_value(t, args[0], "curl")
		testing.expect_value(t, args[1], "-d")
		testing.expect_value(t, args[2], "hello world")
	}
}

@(test)
test_tokenize_command_single_quotes :: proc(t: ^testing.T) {
	input := "curl -d '{\"json\": true}'"
	args := tokenize_command(input)
	defer {
		for arg in args {
			delete(arg)
		}
		delete(args)
	}

	testing.expect_value(t, len(args), 3)
	if len(args) >= 3 {
		testing.expect_value(t, args[2], "{\"json\": true}")
	}
}

@(test)
test_escape_arg_windows_simple :: proc(t: ^testing.T) {
	input := "simple"
	escaped := escape_arg_windows(input)
	// No spaces, should be returned as is (actually, implementation returns clone)
	// wait, `escape_arg_windows` checks `strings.contains_any(arg, " \t\n\v\"")`.
	// "simple" has none. Returns clone.
	defer delete(escaped)
	testing.expect_value(t, escaped, "simple")
}

@(test)
test_escape_arg_windows_with_space :: proc(t: ^testing.T) {
	input := "has space"
	escaped := escape_arg_windows(input)
	defer delete(escaped)
	// Should wrap in quotes
	testing.expect_value(t, escaped, "\"has space\"")
}

@(test)
test_escape_arg_windows_with_quotes :: proc(t: ^testing.T) {
	input := "has \"quotes\""
	escaped := escape_arg_windows(input)
	defer delete(escaped)
	// Expected: "has \"quotes\"" (wrapped in quotes because of space, and quotes escaped)
	// input: h a s   " q u o t e s "
	// output: " h a s   \ " q u o t e s \ " "

	expected := "\"has \\\"quotes\\\"\""
	testing.expect_value(t, escaped, expected)
}

@(test)
test_escape_arg_windows_json :: proc(t: ^testing.T) {
	input := "{\"key\": \"value\"}"
	escaped := escape_arg_windows(input)
	defer delete(escaped)

	// input has quotes, so needs_quotes = true.
	// wrapped in outer quotes.
	// inner quotes escaped.
	// input: { " key " :   " value " }
	// output: " { \ " key \ " :   \ " value \ " } "

	expected := "\"{\\\"key\\\": \\\"value\\\"}\""
	testing.expect_value(t, escaped, expected)
}
