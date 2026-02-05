## Basic Features
A cross-platform simple native ui to run curl request command and render response as JSON using Odin and Its Vendor library. 
These are the basic features:
- [x] Minimal UI
- [x] search saved command by title (top left)
- [x] saved curl command that I want to use later (below search on the left)
- [x] one input box for curl command (1/4 screen on the right)
- [x] response that can be scrolled and copied (3/4 screen on the right below curl command box)
- [x] run cURL via the system shell directly
- [x] saved command has custom names
- [x] able to edit or delete saved command

## MVP Priority Additions
- [x] Response status code display (show HTTP 200, 404, 500, etc.)
- [x] Loading indicator while request is in progress
- [x] Error handling for network errors
- [x] Error handling for invalid commands
- [x] Persistence mechanism (JSON file for saved commands)

## Fonts
- Use system fonts instead of bundled fonts
- Use system fonts for all text
- Use system fonts for all UI elements

## Response
- [x] Response body should be displayed in a separate section, should be in current position but using tab (left tab)
- [x] Response headers should be displayed in a separate tab after response body (right tab)
- [x] Response headers and body should be scrollable
- [x] Response headers and body should be copyable
- [x] Response body should be formatted as JSON
- [x] Response body should be syntax highlighted
- [x] Response headers and body should be syntax highlighted

## Bug fixes
- [x] Add ResponseTab enum and active_tab state
- [x] Implement tab bar UI in main_content_component
- [x] Implement conditional rendering for Body/Headers
- [x] Fix JSON response layout (ensure tokens flow horizontally)
- [x] Update interaction handling for tab switching
- [x] Support multi-line cURL commands (backslash continuation)
- [x] Error handling for invalid command
- [x] Verify tab functionality and layout
- [x] Set application icon (resources/liteman.png)
- [x] Implement cross-platform font detection (Windows, macOS, Linux)
- [x] Fix search command functionality
- [x] Fix text selection in cURL input (multi-line support)
- [x] Implement scrollbar for response body
- [x] Add mouse drag support for scrollbar
- [x] Add scrollbar to sidebar command list