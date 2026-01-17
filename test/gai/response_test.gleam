import gai
import gai/response
import gleam/option

fn test_usage(input: Int, output: Int) -> gai.Usage {
  gai.Usage(
    input_tokens: input,
    output_tokens: output,
    cache_creation_input_tokens: option.None,
    cache_read_input_tokens: option.None,
  )
}

pub fn text_content_single_test() {
  let resp =
    response.CompletionResponse(
      id: "chatcmpl-123",
      model: "gpt-4o",
      content: [gai.Text("Hello, world!")],
      stop_reason: gai.EndTurn,
      usage: test_usage(10, 5),
    )

  response.text_content(resp)
  |> should_equal("Hello, world!")
}

pub fn text_content_multiple_test() {
  let resp =
    response.CompletionResponse(
      id: "chatcmpl-123",
      model: "gpt-4o",
      content: [gai.Text("Hello"), gai.Text(" world")],
      stop_reason: gai.EndTurn,
      usage: test_usage(10, 5),
    )

  response.text_content(resp)
  |> should_equal("Hello world")
}

pub fn text_content_skips_non_text_test() {
  let resp =
    response.CompletionResponse(
      id: "chatcmpl-123",
      model: "gpt-4o",
      content: [
        gai.Text("Before"),
        gai.Image(gai.ImageUrl("https://example.com/img.png")),
        gai.Text("After"),
      ],
      stop_reason: gai.EndTurn,
      usage: test_usage(10, 5),
    )

  response.text_content(resp)
  |> should_equal("BeforeAfter")
}

pub fn tool_calls_extracts_tool_use_test() {
  let resp =
    response.CompletionResponse(
      id: "chatcmpl-123",
      model: "gpt-4o",
      content: [
        gai.Text("Let me check the weather."),
        gai.ToolUse(
          id: "call_123",
          name: "get_weather",
          arguments_json: "{\"location\":\"London\"}",
        ),
      ],
      stop_reason: gai.ToolUsed,
      usage: test_usage(20, 15),
    )

  let calls = response.tool_calls(resp)
  let assert [gai.ToolUse(id: "call_123", name: "get_weather", ..)] = calls
}

pub fn tool_calls_empty_when_no_tools_test() {
  let resp =
    response.CompletionResponse(
      id: "chatcmpl-123",
      model: "gpt-4o",
      content: [gai.Text("Just text")],
      stop_reason: gai.EndTurn,
      usage: test_usage(10, 5),
    )

  response.tool_calls(resp)
  |> should_equal([])
}

pub fn has_tool_calls_true_test() {
  let resp =
    response.CompletionResponse(
      id: "chatcmpl-123",
      model: "gpt-4o",
      content: [
        gai.ToolUse(id: "call_123", name: "get_weather", arguments_json: "{}"),
      ],
      stop_reason: gai.ToolUsed,
      usage: test_usage(20, 15),
    )

  response.has_tool_calls(resp)
  |> should_equal(True)
}

pub fn has_tool_calls_false_test() {
  let resp =
    response.CompletionResponse(
      id: "chatcmpl-123",
      model: "gpt-4o",
      content: [gai.Text("No tools")],
      stop_reason: gai.EndTurn,
      usage: test_usage(10, 5),
    )

  response.has_tool_calls(resp)
  |> should_equal(False)
}

// ============================================================================
// append_response tests
// ============================================================================

pub fn append_response_text_only_test() {
  let messages = [gai.user_text("Hello")]
  let resp =
    response.CompletionResponse(
      id: "chatcmpl-123",
      model: "gpt-4o",
      content: [gai.Text("Hi there!")],
      stop_reason: gai.EndTurn,
      usage: test_usage(10, 5),
    )

  let result = response.append_response(messages, resp)

  let assert [
    gai.Message(role: gai.User, content: [gai.Text("Hello")], ..),
    gai.Message(role: gai.Assistant, content: [gai.Text("Hi there!")], ..),
  ] = result
}

pub fn append_response_tool_only_test() {
  let messages = [gai.user_text("What's the weather?")]
  let resp =
    response.CompletionResponse(
      id: "chatcmpl-123",
      model: "gpt-4o",
      content: [
        gai.ToolUse(id: "call_1", name: "get_weather", arguments_json: "{}"),
      ],
      stop_reason: gai.ToolUsed,
      usage: test_usage(10, 5),
    )

  let result = response.append_response(messages, resp)

  let assert [
    gai.Message(role: gai.User, ..),
    gai.Message(
      role: gai.Assistant,
      content: [gai.ToolUse(id: "call_1", ..)],
      ..,
    ),
  ] = result
}

pub fn append_response_mixed_content_test() {
  let messages = [gai.user_text("What's the weather?")]
  let resp =
    response.CompletionResponse(
      id: "chatcmpl-123",
      model: "gpt-4o",
      content: [
        gai.Text("Let me check."),
        gai.ToolUse(id: "call_1", name: "get_weather", arguments_json: "{}"),
      ],
      stop_reason: gai.ToolUsed,
      usage: test_usage(10, 15),
    )

  let result = response.append_response(messages, resp)

  let assert [
    gai.Message(role: gai.User, ..),
    gai.Message(
      role: gai.Assistant,
      content: [gai.Text("Let me check."), gai.ToolUse(id: "call_1", ..)],
      ..,
    ),
  ] = result
}

pub fn append_response_empty_content_test() {
  let messages = [gai.user_text("Hello")]
  let resp =
    response.CompletionResponse(
      id: "chatcmpl-123",
      model: "gpt-4o",
      content: [],
      stop_reason: gai.EndTurn,
      usage: test_usage(10, 0),
    )

  let result = response.append_response(messages, resp)

  let assert [
    gai.Message(role: gai.User, ..),
    gai.Message(role: gai.Assistant, content: [], ..),
  ] = result
}

// Helper for assertions
fn should_equal(actual: a, expected: a) -> Nil {
  assert actual == expected
}
