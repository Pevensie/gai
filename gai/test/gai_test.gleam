import gai
import gleam/option
import gleeunit

pub fn main() -> Nil {
  gleeunit.main()
}

// Role tests

pub fn system_role_test() {
  let msg = gai.system("You are helpful.")
  let assert gai.Message(
    role: gai.System,
    content: [gai.Text("You are helpful.")],
    ..,
  ) = msg
}

pub fn cached_system_test() {
  let msg = gai.cached_system("You are helpful.")
  let assert gai.Message(
    role: gai.System,
    content: [gai.Text("You are helpful.")],
    cache_control: option.Some(gai.Ephemeral),
  ) = msg
}

pub fn user_text_test() {
  let msg = gai.user_text("Hello")
  let assert gai.Message(role: gai.User, content: [gai.Text("Hello")], ..) = msg
}

pub fn user_with_multiple_content_test() {
  let msg =
    gai.user([
      gai.text("Look at this"),
      gai.image_url("https://example.com/img.png"),
    ])
  let assert gai.Message(
    role: gai.User,
    content: [
      gai.Text("Look at this"),
      gai.Image(gai.ImageUrl("https://example.com/img.png")),
    ],
    ..,
  ) = msg
}

pub fn assistant_message_test() {
  let msg = gai.assistant([gai.text("Here is my response")])
  let assert gai.Message(
    role: gai.Assistant,
    content: [gai.Text("Here is my response")],
    ..,
  ) = msg
}

pub fn assistant_text_test() {
  let msg = gai.assistant_text("Hello from assistant")
  let assert gai.Message(
    role: gai.Assistant,
    content: [gai.Text("Hello from assistant")],
    ..,
  ) = msg
}

// Content constructors

pub fn text_constructor_test() {
  let content = gai.text("Hello world")
  let assert gai.Text("Hello world") = content
}

pub fn image_url_constructor_test() {
  let content = gai.image_url("https://example.com/image.png")
  let assert gai.Image(gai.ImageUrl("https://example.com/image.png")) = content
}

pub fn image_base64_constructor_test() {
  let content = gai.image_base64("abc123", "image/png")
  let assert gai.Image(gai.ImageBase64("abc123", "image/png")) = content
}

pub fn document_url_constructor_test() {
  let content =
    gai.document_url("https://example.com/doc.pdf", "application/pdf")
  let assert gai.Document(
    gai.DocumentUrl("https://example.com/doc.pdf"),
    "application/pdf",
  ) = content
}

pub fn document_base64_constructor_test() {
  let content = gai.document_base64("abc123", "application/pdf")
  let assert gai.Document(gai.DocumentBase64("abc123"), "application/pdf") =
    content
}

// Usage tests

pub fn usage_test() {
  let usage =
    gai.Usage(
      input_tokens: 100,
      output_tokens: 50,
      cache_creation_input_tokens: option.None,
      cache_read_input_tokens: option.None,
    )
  let assert gai.Usage(input_tokens: 100, output_tokens: 50, ..) = usage
}

pub fn cache_read_tokens_test() {
  let usage =
    gai.Usage(
      input_tokens: 100,
      output_tokens: 50,
      cache_creation_input_tokens: option.None,
      cache_read_input_tokens: option.Some(500),
    )
  let assert 500 = gai.cache_read_tokens(usage)
}

pub fn cache_read_tokens_none_test() {
  let usage =
    gai.Usage(
      input_tokens: 100,
      output_tokens: 50,
      cache_creation_input_tokens: option.None,
      cache_read_input_tokens: option.None,
    )
  let assert 0 = gai.cache_read_tokens(usage)
}

pub fn cache_creation_tokens_test() {
  let usage =
    gai.Usage(
      input_tokens: 100,
      output_tokens: 50,
      cache_creation_input_tokens: option.Some(200),
      cache_read_input_tokens: option.None,
    )
  let assert 200 = gai.cache_creation_tokens(usage)
}

pub fn cache_hit_rate_test() {
  let usage =
    gai.Usage(
      input_tokens: 100,
      output_tokens: 50,
      cache_creation_input_tokens: option.Some(100),
      cache_read_input_tokens: option.Some(400),
    )
  // 400 / (400 + 100) = 0.8
  let assert option.Some(rate) = gai.cache_hit_rate(usage)
  assert rate >. 0.79 && rate <. 0.81
}

pub fn cache_hit_rate_no_cache_test() {
  let usage =
    gai.Usage(
      input_tokens: 100,
      output_tokens: 50,
      cache_creation_input_tokens: option.None,
      cache_read_input_tokens: option.None,
    )
  let assert option.None = gai.cache_hit_rate(usage)
}

// StopReason tests

pub fn stop_reason_variants_test() {
  let _ = gai.EndTurn
  let _ = gai.MaxTokens
  let _ = gai.StopSequence
  let _ = gai.ToolUsed
  let _ = gai.ContentFilter
}

// Tool result tests

pub fn tool_result_test() {
  let content = gai.tool_result("call_123", "Weather is sunny")
  let assert gai.ToolResult("call_123", [gai.Text("Weather is sunny")]) =
    content
}

pub fn tool_result_error_test() {
  let content = gai.tool_result_error("call_123", "Location not found")
  let assert gai.ToolResult("call_123", [gai.Text("Location not found")]) =
    content
}

pub fn tool_results_message_single_test() {
  let msg = gai.tool_results_message([#("call_1", "Result 1")])
  let assert gai.Message(
    role: gai.User,
    content: [gai.ToolResult("call_1", [gai.Text("Result 1")])],
    ..,
  ) = msg
}

pub fn tool_results_message_multiple_test() {
  let msg =
    gai.tool_results_message([#("call_1", "Result 1"), #("call_2", "Result 2")])
  let assert gai.Message(
    role: gai.User,
    content: [
      gai.ToolResult("call_1", [gai.Text("Result 1")]),
      gai.ToolResult("call_2", [gai.Text("Result 2")]),
    ],
    ..,
  ) = msg
}

pub fn tool_results_message_empty_result_test() {
  let msg = gai.tool_results_message([#("call_1", "")])
  let assert gai.Message(
    role: gai.User,
    content: [gai.ToolResult("call_1", [gai.Text("")])],
    ..,
  ) = msg
}
