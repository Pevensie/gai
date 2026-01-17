# Integration Test Plan

## Overview

Add real API integration tests that make actual HTTP requests to LLM providers. Tests will read API keys from environment variables and skip gracefully if not set.

## Dependencies

Add as dev dependencies:

```toml
[dev-dependencies]
envoy = ">= 1.1.0 and < 2.0.0"
gleam_httpc = ">= 5.0.0 and < 6.0.0"
```

## Environment Variables

| Variable            | Provider      |
| ------------------- | ------------- |
| `OPENAI_API_KEY`    | OpenAI        |
| `ANTHROPIC_API_KEY` | Anthropic     |
| `GOOGLE_API_KEY`    | Google Gemini |

## Test Structure

### File: `test/integration/live_test.gleam`

```gleam
import envoy
import gleam/httpc
import gai
import gai/openai
import gai/anthropic
import gai/google
import gai/request
import gai/response

// Helper to run test only if API key is available
fn with_api_key(key: String, test_fn: fn(String) -> Nil) -> Nil {
  case envoy.get(key) {
    Ok(api_key) -> test_fn(api_key)
    Error(_) -> Nil  // Skip silently
  }
}
```

### Tests to Implement

#### 1. Basic Completion Tests

- `openai_basic_completion_test` - Simple text completion
- `anthropic_basic_completion_test` - Simple text completion
- `google_basic_completion_test` - Simple text completion

#### 2. Tool Calling Tests

- `openai_tool_call_test` - Request with tool, verify tool_use response
- `anthropic_tool_call_test` - Request with tool, verify tool_use response

#### 3. Structured Output Tests

- `openai_json_mode_test` - JSON response format
- `openai_json_schema_test` - JSON Schema response format

#### 4. Error Handling Tests

- `openai_invalid_model_test` - Verify ApiError parsing
- `anthropic_invalid_model_test` - Verify ApiError parsing

## Implementation Steps

1. Add dependencies to `gleam.toml`
2. Create `test/integration/live_test.gleam`
3. Implement helper function `with_api_key`
4. Implement basic completion tests (one per provider)
5. Implement tool calling tests
6. Implement structured output tests
7. Implement error handling tests

## Test Execution

```bash
# Run all tests (integration tests skip if no keys)
gleam test

# Run with API keys
OPENAI_API_KEY=sk-... ANTHROPIC_API_KEY=sk-ant-... gleam test
```

## Example Test Implementation

```gleam
pub fn openai_basic_completion_test() {
  use api_key <- with_api_key("OPENAI_API_KEY")

  let config = openai.new(api_key)
  let req = request.new("gpt-4o-mini", [
    gai.user_text("Say 'hello' and nothing else."),
  ])
  |> request.with_max_tokens(10)

  let http_req = openai.build_request(config, req)
  let assert Ok(http_resp) = httpc.send(http_req)
  let assert Ok(completion) = openai.parse_response(http_resp)

  let text = response.text_content(completion)
  let assert True = string.contains(string.lowercase(text), "hello")
}
```

## Notes

- Use small/cheap models for tests (`gpt-5-nano`, `claude-4.5-haiku`, `gemini-3.0-flash`)
- Keep `max_tokens` low to minimise cost
- Tests should be deterministic where possible (low temperature, simple prompts)
- `gleam_httpc` is Erlang-only; JS target would need `gleam_fetch`
