/// Integration tests demonstrating full request/response flows.
///
/// This file contains two types of tests:
/// 1. Agent-based tests - High-level API with automatic tool execution
/// 2. Request-based tests - Low-level API for manual control
import gai
import gai/agent
import gai/agent/loop
import gai/anthropic
import gai/google
import gai/openai
import gai/provider
import gai/request
import gai/response
import gai/runtime
import gai/streaming
import gai/tool
import gleam/http/response as http_response
import gleam/list
import gleam/option.{Some}
import sextant

// ============================================================================
// Shared Types
// ============================================================================

pub type SearchParams {
  SearchParams(query: String)
}

type TestCtx {
  TestCtx(context: String)
}

fn search_schema() -> sextant.JsonSchema(SearchParams) {
  use query <- sextant.field("query", sextant.string())
  sextant.success(SearchParams(query:))
}

// ============================================================================
// Agent Integration Tests (High-level API)
// ============================================================================

pub fn agent_openai_integration_test() {
  // 1. Create provider
  let config = openai.new("sk-test-key")
  let provider = openai.provider(config)

  // 2. Create tool with executor
  let search_tool =
    tool.tool(
      name: "search",
      description: "Search the web",
      schema: search_schema(),
      execute: fn(ctx: TestCtx, args: SearchParams) {
        Ok("Context: " <> ctx.context <> ". Query: " <> args.query)
      },
    )

  // 3. Create agent
  let my_agent =
    agent.new(provider)
    |> agent.with_system_prompt("You are a helpful assistant.")
    |> agent.with_tool(search_tool)
    |> agent.with_max_iterations(3)

  // 4. Create mock runtime that returns a tool call, then a final response
  let mock_runtime =
    runtime.new(fn(req) {
      case
        req.body
        == "{\"tools\":[{\"type\":\"function\",\"function\":{\"name\":\"search\",\"description\":\"Search the web\",\"parameters\":{\"$schema\":\"https://json-schema.org/draft/2020-12/schema\",\"required\":[\"query\"],\"type\":\"object\",\"properties\":{\"query\":{\"type\":\"string\"}},\"additionalProperties\":false}}}],\"model\":\"openai\",\"messages\":[{\"role\":\"system\",\"content\":\"You are a helpful assistant.\"},{\"role\":\"user\",\"content\":\"Search for Gleam programming language\"}]}"
      {
        False ->
          // Second call: LLM returns final response after tool execution
          Ok(
            http_response.new(200)
            |> http_response.set_body(
              "{
                \"id\": \"chatcmpl-2\",
                \"model\": \"gpt-4o\",
                \"choices\": [{
                  \"message\": {
                    \"role\": \"assistant\",
                    \"content\": \"The search results are: Context: I am the context. Query: Gleam language\"
                  },
                  \"finish_reason\": \"stop\"
                }],
                \"usage\": {\"prompt_tokens\": 70, \"completion_tokens\": 30}
              }",
            ),
          )
        True ->
          Ok(
            http_response.new(200)
            |> http_response.set_body(
              "{
            \"id\": \"chatcmpl-1\",
            \"model\": \"gpt-4o\",
            \"choices\": [{
              \"message\": {
                \"role\": \"assistant\",
                \"content\": null,
                \"tool_calls\": [{
                  \"id\": \"call_123\",
                  \"type\": \"function\",
                  \"function\": {
                    \"name\": \"search\",
                    \"arguments\": \"{\\\"query\\\": \\\"Gleam language\\\"}\"
                  }
                }]
              },
              \"finish_reason\": \"tool_calls\"
            }],
            \"usage\": {\"prompt_tokens\": 50, \"completion_tokens\": 20}
          }",
            ),
          )
      }
    })

  // 5. Run the agent
  let ctx = TestCtx("I am the context")
  let messages = [gai.user_text("Search for Gleam programming language")]

  let assert Ok(loop.RunResult(
    response: response.CompletionResponse(
      "chatcmpl-2",
      "gpt-4o",
      [
        gai.Text(
          "The search results are: Context: I am the context. Query: Gleam language",
        ),
      ],
      gai.EndTurn,
      gai.Usage(70, 30, option.None, option.None),
    ),
    messages: [
      gai.Message(
        gai.System,
        [gai.Text("You are a helpful assistant.")],
        option.None,
      ),
      gai.Message(
        gai.User,
        [gai.Text("Search for Gleam programming language")],
        option.None,
      ),
      gai.Message(
        gai.Assistant,
        [gai.ToolUse("call_123", "search", "{\"query\": \"Gleam language\"}")],
        option.None,
      ),
      gai.Message(
        gai.User,
        [
          gai.ToolResult(
            tool_use_id: "call_123",
            content: [
              gai.Text("Context: I am the context. Query: Gleam language"),
            ],
          ),
        ],
        option.None,
      ),
      gai.Message(
        gai.Assistant,
        [
          gai.Text(
            "The search results are: Context: I am the context. Query: Gleam language",
          ),
        ],
        option.None,
      ),
    ],
    iterations: 2,
  )) = loop.run(my_agent, ctx, messages, mock_runtime)
}

pub fn agent_with_config_test() {
  // Test that we can pass request config to the agent loop
  let config = anthropic.new("sk-ant-test")
  let provider = anthropic.provider(config)

  let my_agent =
    agent.new(provider)
    |> agent.with_system_prompt("You are Claude.")

  // Create a mock runtime
  let mock_runtime =
    runtime.new(fn(_req) {
      let json_body =
        "{
        \"id\": \"msg_1\",
        \"model\": \"claude-3-opus\",
        \"content\": [{\"type\": \"text\", \"text\": \"Hello!\"}],
        \"stop_reason\": \"end_turn\",
        \"usage\": {\"input_tokens\": 10, \"output_tokens\": 5}
      }"
      Ok(
        http_response.new(200)
        |> http_response.set_body(json_body),
      )
    })

  let messages = [gai.user_text("Hi")]

  // Run with custom config (max_tokens, temperature)
  let result =
    loop.run_with_config(
      my_agent,
      Nil,
      messages,
      mock_runtime,
      Some(fn(req) {
        req
        |> request.with_max_tokens(100)
        |> request.with_temperature(0.7)
      }),
    )

  let assert Ok(run_result) = result
  let assert "Hello!" = response.text_content(run_result.response)
  let assert 1 = run_result.iterations
  Nil
}

// ============================================================================
// Request Integration Tests (Low-level API)
// ============================================================================

pub fn openai_request_test() {
  // Low-level test: build request manually
  let config = openai.new("sk-test-key")

  let search_tool =
    tool.tool(
      name: "search",
      description: "Search the web",
      schema: search_schema(),
      execute: fn(_ctx: TestCtx, _args: SearchParams) { Ok("results") },
    )
    |> tool.to_schema

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
