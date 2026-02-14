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

// Mock measure function for testing
mock_measure :: proc(text: string) -> f32 {
	return f32(len(text)) * 100.0 // Scaled up to avoid precision issues
}

@(test)
test_format_display_lines_wrapping :: proc(t: ^testing.T) {
	input := "curl https://very-long-url.com/resource"
	tokens, _ := tokenize_curl(input)
	defer delete(tokens)

	// "curl " -> 5 chars * 100 = 500 width
	// URL -> 33 chars * 100 = 3300 width
	// Max width -> 1000 (10 chars space)

	// Line 1: "curl " (500 width) + next needs space?
	// Available: 1000 - 500 = 500.
	// URL chunk needs to fit in 500.
	// URL: "https" (5 chars) -> 500. Fits?
	// So "curl https" fits on line 1?

	// Wait, format_display_lines logic for splitting requires:
	// If fits entirely, append.

	// Token "https://..." is 3300 width.
	// 500 remaining. Can it split?
	// Yes, 5 chars fit.
	// So "https" fits.
	// Line 1: "curl https"
	// Remainder: ://very-long-url.com/resource

	// Line 2: Indent "     " (500 width)
	// Available: 1000 - 500 = 500.
	// 5 chars fit. "://ve"

	// And so on.

	// Let's test simply that it wraps.

	lines := format_display_lines(input, tokens[:], 1000.0, mock_measure)
	defer free_display_lines(&lines)

	// Check we have multiple lines
	testing.expect(t, len(lines) > 2, "Should wrap into multiple lines")

	// First line should have 2 tokens: "curl " and part of URL "https"
	if len(lines) > 0 {
		l1 := lines[0]
		testing.expect_value(t, len(l1.tokens), 2)
	}
}

@(test)
test_tokenize_missing_space_method_url :: proc(t: ^testing.T) {
	// Bug report: curl -X GET"https..." fails
	input := "curl -X GET\"https://example.com\""
	tokens, _ := tokenize_curl(input)
	defer delete(tokens)

	// Should identify:
	// curl (Command)
	// -X (Flag)
	// GET (Method)
	// "https://example.com" (String? or URL?)

	// If it parses GET"https..." as one Data token, that's the bug.

	found_method := false
	found_url_or_string := false

	for token in tokens {
		if token.type == .Method {found_method = true}
		if token.type == .String || token.type == .URL {found_url_or_string = true}
	}

	testing.expect(t, found_method, "Should find Method GET even without space before quote")
	testing.expect(t, found_url_or_string, "Should find URL/String")
}
