import gai
import gai/response
import gai/streaming
import gleam/option

fn test_usage(input: Int, output: Int) -> gai.Usage {
  gai.Usage(
    input_tokens: input,
    output_tokens: output,
    cache_creation_input_tokens: option.None,
    cache_read_input_tokens: option.None,
  )
}

// parse_sse tests

pub fn parse_sse_single_event_test() {
  let raw = "data: {\"content\": \"hello\"}\n\n"
  let events = streaming.parse_sse(raw)

  let assert ["{\"content\": \"hello\"}"] = events
}

pub fn parse_sse_multiple_events_test() {
  let raw =
    "data: {\"content\": \"hello\"}\n\ndata: {\"content\": \"world\"}\n\n"
  let events = streaming.parse_sse(raw)

  let assert ["{\"content\": \"hello\"}", "{\"content\": \"world\"}"] = events
}

pub fn parse_sse_with_empty_data_test() {
  let raw = "data: {\"text\": \"a\"}\n\ndata:\n\ndata: {\"text\": \"b\"}\n\n"
  let events = streaming.parse_sse(raw)

  let assert ["{\"text\": \"a\"}", "{\"text\": \"b\"}"] = events
}

pub fn parse_sse_with_done_test() {
  let raw = "data: {\"content\": \"hi\"}\n\ndata: [DONE]\n\n"
  let events = streaming.parse_sse(raw)

  let assert ["{\"content\": \"hi\"}", "[DONE]"] = events
}

pub fn parse_sse_ignores_comments_test() {
  let raw = ": keep-alive\n\ndata: {\"text\": \"hi\"}\n\n"
  let events = streaming.parse_sse(raw)

  let assert ["{\"text\": \"hi\"}"] = events
}

pub fn parse_sse_with_event_type_test() {
  // Anthropic uses event: prefix before data:
  let raw =
    "event: content_block_delta\ndata: {\"delta\": {\"text\": \"hi\"}}\n\n"
  let events = streaming.parse_sse(raw)

  let assert ["{\"delta\": {\"text\": \"hi\"}}"] = events
}

// Accumulator tests

pub fn new_accumulator_test() {
  let _acc = streaming.new_accumulator()
  // Just verify it creates without error
  Nil
}

pub fn accumulate_text_deltas_test() {
  let acc =
    streaming.new_accumulator()
    |> streaming.accumulate(streaming.ContentDelta(gai.Text("Hello")))
    |> streaming.accumulate(streaming.ContentDelta(gai.Text(" ")))
    |> streaming.accumulate(streaming.ContentDelta(gai.Text("world")))
    |> streaming.accumulate(streaming.Done(
      stop_reason: gai.EndTurn,
      usage: option.Some(test_usage(10, 3)),
    ))

  let assert Ok(resp) = streaming.finish(acc)
  let assert "Hello world" = response.text_content(resp)
  let assert response.CompletionResponse(
    stop_reason: gai.EndTurn,
    usage: gai.Usage(input_tokens: 10, output_tokens: 3, ..),
    ..,
  ) = resp
}

pub fn accumulate_ignores_ping_test() {
  let acc =
    streaming.new_accumulator()
    |> streaming.accumulate(streaming.ContentDelta(gai.Text("Hi")))
    |> streaming.accumulate(streaming.Ping)
    |> streaming.accumulate(streaming.Ping)
    |> streaming.accumulate(streaming.Done(
      stop_reason: gai.EndTurn,
      usage: option.None,
    ))

  let assert Ok(resp) = streaming.finish(acc)
  let assert "Hi" = response.text_content(resp)
}

pub fn finish_without_done_returns_error_test() {
  let acc =
    streaming.new_accumulator()
    |> streaming.accumulate(streaming.ContentDelta(gai.Text("incomplete")))

  let assert Error(gai.ParseError(_)) = streaming.finish(acc)
}

pub fn accumulate_tool_use_test() {
  let acc =
    streaming.new_accumulator()
    |> streaming.accumulate(
      streaming.ContentDelta(gai.Text("Let me check that.")),
    )
    |> streaming.accumulate(
      streaming.ContentDelta(gai.ToolUse(
        id: "call_123",
        name: "get_weather",
        arguments_json: "{\"location\":\"London\"}",
      )),
    )
    |> streaming.accumulate(streaming.Done(
      stop_reason: gai.ToolUsed,
      usage: option.None,
    ))

  let assert Ok(resp) = streaming.finish(acc)
  assert response.has_tool_calls(resp)
  let assert response.CompletionResponse(stop_reason: gai.ToolUsed, ..) = resp
}
