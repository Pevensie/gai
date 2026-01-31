import gai
import gai/provider
import gai/response as gai_response
import gai_erlang
import gai_erlang/agent
import gai_erlang/tool
import gleam/http
import gleam/http/request
import gleam/http/response
import gleam/int
import gleam/json
import gleam/option
import gleeunit
import sextant

pub fn main() -> Nil {
  gleeunit.main()
}

// Test helpers

fn mock_provider() -> provider.Provider {
  provider.Provider(
    name: "mock",
    model: "mock-model",
    build_request: fn(req) {
      request.new()
      |> request.set_method(http.Post)
      |> request.set_host("api.mock.com")
      |> request.set_path("/v1/messages")
      |> request.set_body(
        json.to_string(
          json.object([
            #("model", json.string(req.model)),
          ]),
        ),
      )
    },
    parse_response: fn(resp) {
      case resp.status {
        200 -> {
          // Parse a simple mock response
          Ok(gai_response.CompletionResponse(
            id: "mock-id",
            model: "mock-model",
            content: [gai.Text(resp.body)],
            stop_reason: gai.EndTurn,
            usage: gai.Usage(
              input_tokens: 10,
              output_tokens: 5,
              cache_creation_input_tokens: option.None,
              cache_read_input_tokens: option.None,
            ),
          ))
        }
        _ -> Error(gai.HttpError(resp.status, resp.body))
      }
    },
    parse_stream_chunk: fn(_) { Error(gai.ParseError("Not implemented")) },
  )
}

fn mock_tool_call_response(
  tool_id: String,
  tool_name: String,
  args_json: String,
) -> gai_response.CompletionResponse {
  gai_response.CompletionResponse(
    id: "mock-id",
    model: "mock-model",
    content: [gai.ToolUse(tool_id, tool_name, args_json)],
    stop_reason: gai.ToolUsed,
    usage: gai.Usage(
      input_tokens: 10,
      output_tokens: 5,
      cache_creation_input_tokens: option.None,
      cache_read_input_tokens: option.None,
    ),
  )
}

fn mock_text_response(text: String) -> gai_response.CompletionResponse {
  gai_response.CompletionResponse(
    id: "mock-id",
    model: "mock-model",
    content: [gai.Text(text)],
    stop_reason: gai.EndTurn,
    usage: gai.Usage(
      input_tokens: 10,
      output_tokens: 5,
      cache_creation_input_tokens: option.None,
      cache_read_input_tokens: option.None,
    ),
  )
}

// Tests

pub fn simple_completion_test() {
  let prov = mock_provider()
  let send = fn(_req) { Ok(response.Response(200, [], "Hello!")) }
  let ag = agent.new(prov) |> agent.with_send(send)
  let messages = [gai.user_text("Hi")]

  let assert Ok(result) = gai_erlang.run(ag, Nil, messages)

  assert result.iterations == 1
  assert gai_response.text_content(result.response) == "Hello!"
}

pub fn max_iterations_test() {
  let prov = mock_provider()
  let ag =
    agent.new(prov)
    |> agent.with_max_iterations(0)
    |> agent.with_send(fn(_req) { Ok(response.Response(200, [], "Hello!")) })
  let messages = [gai.user_text("Hi")]

  let assert Error(err) = gai_erlang.run(ag, Nil, messages)

  assert err.iterations == 0
  let assert gai.ApiError("max_iterations", _) = err.error
}

pub fn http_error_returns_loop_error_test() {
  let prov = mock_provider()
  let ag =
    agent.new(prov)
    |> agent.with_send(fn(_req) { Error(gai.HttpError(500, "Server error")) })
  let messages = [gai.user_text("Hi")]

  let assert Error(err) = gai_erlang.run(ag, Nil, messages)

  assert err.iterations == 0
  let assert gai.HttpError(500, "Server error") = err.error
}

pub fn system_message_passed_test() {
  let prov = mock_provider()
  let ag =
    agent.new(prov)
    |> agent.with_send(fn(_req) { Ok(response.Response(200, [], "Hello!")) })
  let messages = [
    gai.system("You are a helpful assistant."),
    gai.user_text("Hi"),
  ]

  let assert Ok(result) = gai_erlang.run(ag, Nil, messages)

  // The messages should include the system message at the start
  let assert [
    gai.Message(gai.System, [gai.Text("You are a helpful assistant.")], _),
    gai.Message(gai.User, [gai.Text("Hi")], _),
    ..
  ] = result.messages
}

// Tool execution tests

type AddArgs {
  AddArgs(a: Int, b: Int)
}

fn add_schema() -> sextant.JsonSchema(AddArgs) {
  use a <- sextant.field("a", sextant.integer())
  use b <- sextant.field("b", sextant.integer())
  sextant.success(AddArgs(a, b))
}

fn add_tool() -> tool.Tool(Nil) {
  tool.new(
    name: "add",
    description: "Add two numbers",
    schema: add_schema(),
    execute: fn(_ctx, args: AddArgs) { Ok(int.to_string(args.a + args.b)) },
  )
}

pub fn tool_execution_test() {
  // Create a provider that returns a tool call on first request,
  // then a text response on second request
  let call_count = erlang_ref()

  let prov =
    provider.Provider(
      name: "mock",
      model: "mock-model",
      build_request: fn(_req) {
        request.new()
        |> request.set_method(http.Post)
        |> request.set_host("api.mock.com")
        |> request.set_path("/v1/messages")
        |> request.set_body("")
      },
      parse_response: fn(_resp) {
        let count = ref_get(call_count)
        ref_set(call_count, count + 1)
        case count {
          0 ->
            Ok(mock_tool_call_response("tool-1", "add", "{\"a\": 2, \"b\": 3}"))
          _ -> Ok(mock_text_response("The sum is 5"))
        }
      },
      parse_stream_chunk: fn(_) { Error(gai.ParseError("Not implemented")) },
    )

  let ag =
    agent.new(prov)
    |> agent.with_tool(add_tool())
    |> agent.with_send(fn(_req) { Ok(response.Response(200, [], "")) })
  let messages = [gai.user_text("What is 2 + 3?")]

  let assert Ok(result) = gai_erlang.run(ag, Nil, messages)

  assert result.iterations == 2
  assert gai_response.text_content(result.response) == "The sum is 5"
}

pub fn stop_on_tool_test() {
  // Create a provider that always returns a tool call
  let final_answer_tool =
    tool.new(
      name: "final_answer",
      description: "Provide the final answer",
      schema: {
        use answer <- sextant.field("answer", sextant.string())
        sextant.success(answer)
      },
      execute: fn(_ctx, answer: String) { Ok(answer) },
    )

  let prov =
    provider.Provider(
      name: "mock",
      model: "mock-model",
      build_request: fn(_req) {
        request.new()
        |> request.set_method(http.Post)
        |> request.set_host("api.mock.com")
        |> request.set_path("/v1/messages")
        |> request.set_body("")
      },
      parse_response: fn(_resp) {
        Ok(mock_tool_call_response(
          "tool-1",
          "final_answer",
          "{\"answer\": \"42\"}",
        ))
      },
      parse_stream_chunk: fn(_) { Error(gai.ParseError("Not implemented")) },
    )

  let ag =
    agent.new(prov)
    |> agent.with_tool(final_answer_tool)
    |> agent.with_stop_condition(agent.stop_on_tool(final_answer_tool))
    |> agent.with_send(fn(_req) { Ok(response.Response(200, [], "")) })
  let messages = [gai.user_text("What is the answer?")]

  let assert Ok(result) = gai_erlang.run(ag, Nil, messages)

  // Should stop after first iteration because of HasToolCall condition
  assert result.iterations == 1
}

// FFI for mutable reference (for testing)
@external(erlang, "erlang", "make_ref")
fn erlang_ref() -> a

@external(erlang, "gai_erlang_test_ffi", "ref_get")
fn ref_get(ref: a) -> Int

@external(erlang, "gai_erlang_test_ffi", "ref_set")
fn ref_set(ref: a, value: Int) -> Nil
