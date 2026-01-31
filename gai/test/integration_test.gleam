/// Integration tests demonstrating full request/response flows.
///
/// These are low-level API tests for manual request/response control.
/// For agent-based tests with tool loops, see gai_erlang/test/.
import gai
import gai/anthropic
import gai/google
import gai/openai
import gai/provider
import gai/request
import gai/response
import gai/streaming
import gai/tool
import gleam/http/response as http_response
import gleam/list
import sextant

// ============================================================================
// Shared Types
// ============================================================================

pub type SearchParams {
  SearchParams(query: String)
}

fn search_schema() -> sextant.JsonSchema(SearchParams) {
  use query <- sextant.field("query", sextant.string())
  sextant.success(SearchParams(query:))
}

// ============================================================================
// Request Integration Tests (Low-level API)
// ============================================================================

pub fn openai_request_test() {
  // Low-level test: build request manually
  let config = openai.new("sk-test-key")

  let search_tool =
    tool.ToolSchema(
      name: "search",
      description: "Search the web",
      schema_json: sextant.to_json(search_schema()),
    )

  let req =
    request.new("gpt-4o", [
      gai.system("You are a helpful assistant."),
      gai.user_text("Search for Gleam"),
    ])
    |> request.with_max_tokens(100)
    |> request.with_temperature(0.7)
    |> request.with_tools([search_tool])
    |> request.with_tool_choice(request.Auto)

  let http_req = openai.build_request(config, req)

  let assert "api.openai.com" = http_req.host
  assert http_req.body != ""
  Nil
}

pub fn anthropic_request_test() {
  let config = anthropic.new("sk-ant-test")

  let req =
    request.new("claude-3-opus-20240229", [
      gai.system("You are Claude."),
      gai.user_text("What is 2+2?"),
    ])
    |> request.with_max_tokens(100)

  let http_req = anthropic.build_request(config, req)

  let assert "api.anthropic.com" = http_req.host
  Nil
}

pub fn google_request_test() {
  let config = google.new("test-api-key")

  let req =
    request.new("gemini-1.5-pro", [
      gai.system("You are Gemini."),
      gai.user_text("Hello!"),
    ])
    |> request.with_max_tokens(50)

  let http_req = google.build_request(config, req)

  let assert "generativelanguage.googleapis.com" = http_req.host
  Nil
}

// ============================================================================
// Response Parsing Tests
// ============================================================================

pub fn openai_response_parsing_test() {
  let json_body =
    "{
    \"id\": \"chatcmpl-test\",
    \"model\": \"gpt-4o\",
    \"choices\": [{
      \"message\": {
        \"role\": \"assistant\",
        \"content\": \"Hello world!\"
      },
      \"finish_reason\": \"stop\"
    }],
    \"usage\": {\"prompt_tokens\": 10, \"completion_tokens\": 5}
  }"

  let http_resp =
    http_response.new(200)
    |> http_response.set_body(json_body)

  let assert Ok(completion) = openai.parse_response(http_resp)
  let assert "Hello world!" = response.text_content(completion)
  Nil
}

pub fn anthropic_response_parsing_test() {
  let json_body =
    "{
    \"id\": \"msg_test\",
    \"model\": \"claude-3-opus\",
    \"content\": [{\"type\": \"text\", \"text\": \"2 + 2 = 4\"}],
    \"stop_reason\": \"end_turn\",
    \"usage\": {\"input_tokens\": 20, \"output_tokens\": 10}
  }"

  let http_resp =
    http_response.new(200)
    |> http_response.set_body(json_body)

  let assert Ok(completion) = anthropic.parse_response(http_resp)
  let assert "2 + 2 = 4" = response.text_content(completion)
  Nil
}

pub fn google_response_parsing_test() {
  let json_body =
    "{
    \"candidates\": [{
      \"content\": {
        \"parts\": [{\"text\": \"Hello from Gemini!\"}],
        \"role\": \"model\"
      },
      \"finishReason\": \"STOP\"
    }],
    \"usageMetadata\": {\"promptTokenCount\": 5, \"candidatesTokenCount\": 8}
  }"

  let http_resp =
    http_response.new(200)
    |> http_response.set_body(json_body)

  let assert Ok(completion) = google.parse_response(http_resp)
  let assert "Hello from Gemini!" = response.text_content(completion)
  Nil
}

// ============================================================================
// Provider Abstraction Test
// ============================================================================

pub fn provider_abstraction_test() {
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

  let assert "openai" = provider.name(openai_provider)
  let assert "anthropic" = provider.name(anthropic_provider)
  let assert "google" = provider.name(google_provider)
  Nil
}

// ============================================================================
// Streaming Test
// ============================================================================

pub fn streaming_test() {
  let raw_sse =
    "data: {\"choices\":[{\"delta\":{\"content\":\"Hello\"}}]}\n\ndata: {\"choices\":[{\"delta\":{\"content\":\" world!\"}}]}\n\ndata: {\"choices\":[{\"finish_reason\":\"stop\"}],\"usage\":{\"prompt_tokens\":10,\"completion_tokens\":2}}\n\ndata: [DONE]\n\n"

  let events = streaming.parse_sse(raw_sse)
  let assert 4 = list.length(events)

  let deltas =
    events
    |> list.filter_map(openai.parse_stream_chunk)

  let acc =
    deltas
    |> list.fold(streaming.new_accumulator(), streaming.accumulate)

  let assert Ok(completion) = streaming.finish(acc)
  let assert "Hello world!" = response.text_content(completion)
  Nil
}
