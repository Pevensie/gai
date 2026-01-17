/// Completion response types and helpers.
import gai.{
  type Content, type Message, type StopReason, type Usage, Assistant, Message,
  Text, Thinking, ToolUse,
}
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/string

/// Completion response from the model
pub type CompletionResponse {
  CompletionResponse(
    id: String,
    model: String,
    content: List(Content),
    stop_reason: StopReason,
    usage: Usage,
  )
}

/// Extract all text content concatenated (excludes Thinking content)
pub fn text_content(resp: CompletionResponse) -> String {
  resp.content
  |> list.filter_map(fn(c) {
    case c {
      Text(t) -> Ok(t)
      _ -> Error(Nil)
    }
  })
  |> string.concat
}

/// Extract all tool calls from the response
pub fn tool_calls(resp: CompletionResponse) -> List(Content) {
  resp.content
  |> list.filter(fn(c) {
    case c {
      ToolUse(..) -> True
      _ -> False
    }
  })
}

/// Check if the response contains tool calls
pub fn has_tool_calls(resp: CompletionResponse) -> Bool {
  list.any(resp.content, fn(c) {
    case c {
      ToolUse(..) -> True
      _ -> False
    }
  })
}

/// Append the assistant's response to a message history.
/// Creates an Assistant message from response content and appends to end.
/// Excludes Thinking content (internal reasoning shouldn't be in conversation history).
pub fn append_response(
  messages: List(Message),
  resp: CompletionResponse,
) -> List(Message) {
  // Filter out Thinking content - it shouldn't go back to the model
  let content =
    resp.content
    |> list.filter(fn(c) {
      case c {
        Thinking(_) -> False
        _ -> True
      }
    })
  let assistant_message =
    Message(role: Assistant, content:, cache_control: None)
  list.append(messages, [assistant_message])
}

/// Extract thinking content from the response (concatenated).
/// Returns None if no thinking blocks are present.
pub fn thinking_content(resp: CompletionResponse) -> Option(String) {
  let thinking =
    resp.content
    |> list.filter_map(fn(c) {
      case c {
        Thinking(t) -> Ok(t)
        _ -> Error(Nil)
      }
    })

  case thinking {
    [] -> None
    parts -> Some(string.concat(parts))
  }
}

/// Check if the response contains thinking content.
pub fn has_thinking(resp: CompletionResponse) -> Bool {
  list.any(resp.content, fn(c) {
    case c {
      Thinking(_) -> True
      _ -> False
    }
  })
}
