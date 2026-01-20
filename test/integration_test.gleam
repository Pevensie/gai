/// Integration tests demonstrating full request/response flows.
import gai
import gai/anthropic
import gai/google
import gai/openai
import gai/provider
import gai/request
import gai/response
import gai/streaming
import gai/tool
import gleam/dynamic/decode as gleam_decode
import gleam/http/response as http_response
import gleam/json as gleam_json
import gleam/option
import sextant

// ============================================================================
// OpenAI Integration Test
// ============================================================================

pub type SearchParams {
  SearchParams(query: String)
}

type TestCtx {
  TestCtx
}

fn search_schema() -> sextant.JsonSchema(SearchParams) {
  use query <- sextant.field("query", sextant.string())
  sextant.success(SearchParams(query:))
}

pub fn openai_full_flow_test() {
  // 1. Create config
  let config = openai.new("sk-test-key")

  // 2. Create tool
  let search_tool =
    tool.tool(
      name: "search",
      description: "Search the web",
      schema: search_schema(),
      execute: fn(_ctx: TestCtx, _args: SearchParams) { Ok("results") },
    )
    |> tool.to_schema

  // 3. Build request
  let req =
    request.new("gpt-4o", [
      gai.system("You are a helpful assistant."),
      gai.user_text("Search for Gleam programming language"),
    ])
    |> request.with_max_tokens(100)
    |> request.with_temperature(0.7)
    |> request.with_tools([search_tool])
    |> request.with_tool_choice(request.Auto)

  // 4. Build HTTP request
  let http_req = openai.build_request(config, req)

  // Verify request was built
  let assert "api.openai.com" = http_req.host
  assert http_req.body != ""

  // 5. Simulate response
  let json_body =
    "{
    \"id\": \"chatcmpl-integration\",
    \"model\": \"gpt-4o-2024-05-13\",
    \"choices\": [{
      \"message\": {
        \"role\": \"assistant\",
        \"content\": null,
        \"tool_calls\": [{
          \"id\": \"call_abc\",
          \"type\": \"function\",
          \"function\": {
            \"name\": \"search\",
            \"arguments\": \"{\\\"query\\\": \\\"Gleam programming language\\\"}\"
          }
        }]
      },
      \"finish_reason\": \"tool_calls\"
    }],
    \"usage\": {\"prompt_tokens\": 50, \"completion_tokens\": 20}
  }"

  let http_resp =
    http_response.new(200)
    |> http_response.set_body(json_body)

  // 6. Parse response
  let assert Ok(completion) = openai.parse_response(http_resp)

  // 7. Verify response
  assert response.has_tool_calls(completion)
  let assert response.CompletionResponse(stop_reason: gai.ToolUsed, ..) =
    completion
  let assert [gai.ToolUse(id: "call_abc", name: "search", arguments_json:)] =
    response.tool_calls(completion)

  // 8. Parse tool arguments directly with sextant
  let assert Ok(dynamic_args) =
    gleam_json.parse(arguments_json, gleam_decode.dynamic)
  let assert Ok(SearchParams(query: "Gleam programming language")) =
    sextant.run(dynamic_args, search_schema())
}

// ============================================================================
// Anthropic Integration Test
// ============================================================================

pub fn anthropic_full_flow_test() {
  // 1. Create config
  let config = anthropic.new("sk-ant-test")

  // 2. Build request
  let req =
    request.new("claude-3-opus-20240229", [
      gai.system("You are Claude."),
      gai.user_text("What is 2+2?"),
    ])
    |> request.with_max_tokens(100)

  // 3. Build HTTP request
  let http_req = anthropic.build_request(config, req)

  // Verify request was built
  let assert "api.anthropic.com" = http_req.host

  // 4. Simulate response
  let json_body =
    "{
    \"id\": \"msg_integration\",
    \"model\": \"claude-3-opus-20240229\",
    \"content\": [{\"type\": \"text\", \"text\": \"2 + 2 = 4\"}],
    \"stop_reason\": \"end_turn\",
    \"usage\": {\"input_tokens\": 20, \"output_tokens\": 10}
  }"

  let http_resp =
    http_response.new(200)
    |> http_response.set_body(json_body)

  // 5. Parse response
  let assert Ok(completion) = anthropic.parse_response(http_resp)

  // 6. Verify response
  let assert "2 + 2 = 4" = response.text_content(completion)
  let assert response.CompletionResponse(stop_reason: gai.EndTurn, ..) =
    completion
}

// ============================================================================
// Google Gemini Integration Test
// ============================================================================

pub fn google_full_flow_test() {
  // 1. Create config
  let config = google.new("test-api-key")

  // 2. Build request
  let req =
    request.new("gemini-1.5-pro", [
      gai.system("You are Gemini."),
      gai.user_text("Hello!"),
    ])
    |> request.with_max_tokens(50)

  // 3. Build HTTP request
  let http_req = google.build_request(config, req)

  // Verify request was built
  let assert "generativelanguage.googleapis.com" = http_req.host

  // 4. Simulate response
  let json_body =
    "{
    \"candidates\": [{
      \"content\": {
        \"parts\": [{\"text\": \"Hello! How can I help you?\"}],
        \"role\": \"model\"
      },
      \"finishReason\": \"STOP\"
    }],
    \"usageMetadata\": {\"promptTokenCount\": 5, \"candidatesTokenCount\": 8}
  }"

  let http_resp =
    http_response.new(200)
    |> http_response.set_body(json_body)

  // 5. Parse response
  let assert Ok(completion) = google.parse_response(http_resp)

  // 6. Verify response
  let assert "Hello! How can I help you?" = response.text_content(completion)
}

// ============================================================================
// Provider Abstraction Test
// ============================================================================

pub fn provider_abstraction_test() {
  // Test that the Provider type enables provider-agnostic code
  let openai_provider =
    openai.new("sk-test")
    |> openai.provider

  let anthropic_provider =
    anthropic.new("sk-ant-test")
    |> anthropic.provider

  let google_provider =
    google.new("test-key")
    |> google.provider

  // All providers can be used with the same interface
  let req =
    request.new("model", [gai.user_text("Hello")])
    |> request.with_max_tokens(100)

  let _openai_http = provider.build_request(openai_provider, req)
  let _anthropic_http = provider.build_request(anthropic_provider, req)
  let _google_http = provider.build_request(google_provider, req)

  // Provider names are correct
  let assert "openai" = provider.name(openai_provider)
  let assert "anthropic" = provider.name(anthropic_provider)
  let assert "google" = provider.name(google_provider)
}

// ============================================================================
// Streaming Integration Test
// ============================================================================

pub fn streaming_integration_test() {
  // Simulate a complete streaming session
  let raw_sse =
    "data: {\"choices\":[{\"delta\":{\"content\":\"Hello\"}}]}\n\ndata: {\"choices\":[{\"delta\":{\"content\":\" \"}}]}\n\ndata: {\"choices\":[{\"delta\":{\"content\":\"world!\"}}]}\n\ndata: {\"choices\":[{\"finish_reason\":\"stop\"}],\"usage\":{\"prompt_tokens\":10,\"completion_tokens\":2}}\n\ndata: [DONE]\n\n"

  // 1. Parse SSE events
  let events = streaming.parse_sse(raw_sse)
  let assert 5 = length(events)

  // 2. Process each event through OpenAI parser
  let deltas =
    events
    |> filter_map(fn(e) {
      case openai.parse_stream_chunk(e) {
        Ok(d) -> option.Some(d)
        Error(_) -> option.None
      }
    })

  // 3. Accumulate into final response
  let acc =
    deltas
    |> fold(streaming.new_accumulator(), streaming.accumulate)

  // 4. Finish and verify
  let assert Ok(completion) = streaming.finish(acc)
  let assert "Hello world!" = response.text_content(completion)
}

// Helper functions for tests
fn length(list: List(a)) -> Int {
  case list {
    [] -> 0
    [_, ..rest] -> 1 + length(rest)
  }
}

fn filter_map(list: List(a), f: fn(a) -> option.Option(b)) -> List(b) {
  case list {
    [] -> []
    [first, ..rest] ->
      case f(first) {
        option.Some(b) -> [b, ..filter_map(rest, f)]
        option.None -> filter_map(rest, f)
      }
  }
}

fn fold(list: List(a), acc: b, f: fn(b, a) -> b) -> b {
  case list {
    [] -> acc
    [first, ..rest] -> fold(rest, f(acc, first), f)
  }
}
