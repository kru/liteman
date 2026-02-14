package main

import "core:fmt"
import "core:testing"

@(test)
test_tokenize_simple_url :: proc(t: ^testing.T) {
	input := "curl https://api.example.com/v1/users"
	tokens, _ := tokenize_curl(input)
	defer delete(tokens)

	testing.expect_value(t, len(tokens), 3) // Command, Whitespace, URL

	if len(tokens) >= 3 {
		testing.expect_value(t, tokens[0].type, TokenType.Command)
		testing.expect_value(t, tokens[2].type, TokenType.URL)
	}
}

@(test)
test_tokenize_method_flag :: proc(t: ^testing.T) {
	input := "curl -X POST https://example.com"
	tokens, _ := tokenize_curl(input)
	defer delete(tokens)

	// Command, ws, Flag, ws, Method, ws, URL
	// curl, " ", -X, " ", POST, " ", https...

	// Let's verify specific tokens
	found_flag := false
	found_method := false

	for token in tokens {
		if token.type == .Flag {found_flag = true}
		if token.type == .Method {found_method = true}
	}

	testing.expect(t, found_flag, "Should find flag -X")
	testing.expect(t, found_method, "Should find method POST")
}

@(test)
test_tokenize_headers :: proc(t: ^testing.T) {
	input := "curl -H \"Content-Type: application/json\" https://example.com"
	tokens, _ := tokenize_curl(input)
	defer delete(tokens)

	// curl, -H, "Content-Type...", URL

	found_string := false
	for token in tokens {
		if token.type == .String {
			// content check?
			// The tokenizer doesn't store string content in token, just indices.
			// But we know it should be identified as a String token because of quotes
			// AND because of -H context it might be highlighted differently if we had detailed types
			// but here it is just String type.
			found_string = true
		}
	}

	testing.expect(t, found_string, "Should find quoted header string")
}

@(test)
test_tokenize_json_body :: proc(t: ^testing.T) {
	// curl -d '{"key": "value"}' ...
	input := "curl -d '{\"key\": \"value\"}'"
	tokens, _ := tokenize_curl(input)
	defer delete(tokens)

	// Verify we get a String token for the body
	found_string := false
	for token in tokens {
		if token.type == .String {
			found_string = true
		}
	}
	testing.expect(t, found_string, "Should find string token for JSON body")
}

@(test)
test_tokenize_multiline_backslash :: proc(t: ^testing.T) {
	input := "curl \\\nhttps://example.com"
	tokens, _ := tokenize_curl(input)
	defer delete(tokens)

	// curl, ws, Backslash, Newline, URL (or Data if no space)
	// Actually:
	// curl (Command)
	// " " (Whitespace)
	// \ (Backslash)
	// \n (Newline)
	// https://... (URL)

	found_backslash := false
	found_newline := false
	found_url := false

	for token in tokens {
		if token.type == .Backslash {found_backslash = true}
		if token.type == .Newline {found_newline = true}
		if token.type == .URL {found_url = true}
	}

	testing.expect(t, found_backslash, "Should find backslash")
	testing.expect(t, found_newline, "Should find newline")
	testing.expect(t, found_url, "Should find URL on second line")
}
