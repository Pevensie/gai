/// Streaming support types and utilities.
import gai.{type Content, type StopReason, type Usage}
import gai/response
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/string

/// A delta from a streaming response
pub type StreamDelta {
  /// Incremental content
  ContentDelta(content: Content)
  /// Stream finished
  Done(stop_reason: StopReason, usage: Option(Usage))
  /// Keep-alive / empty event
  Ping
}

// ============================================================================
// SSE Parsing
// ============================================================================

/// Parse raw SSE text into individual event data strings.
///
/// Server-Sent Events format:
/// - Lines starting with "data:" contain the payload
/// - Lines starting with ":" are comments (ignored)
/// - Lines starting with "event:" specify event type (ignored, we just want data)
/// - Events are separated by blank lines
pub fn parse_sse(raw: String) -> List(String) {
  raw
  |> string.split("\n\n")
  |> list.filter_map(parse_sse_event)
}

fn parse_sse_event(event_block: String) -> Result(String, Nil) {
  let lines = string.split(event_block, "\n")

  // Find the data line(s) and extract content
  let data_lines =
    lines
    |> list.filter_map(fn(line) {
      case line {
        "data:" <> rest -> {
          case string.trim_start(rest) {
            "" -> Error(Nil)
            content -> Ok(content)
          }
        }
        _ -> Error(Nil)
      }
    })

  case data_lines {
    [] -> Error(Nil)
    [single] -> Ok(single)
    multiple -> Ok(string.join(multiple, "\n"))
  }
}

// ============================================================================
// Accumulator
// ============================================================================

/// Accumulates streaming deltas into a final response.
///
/// Use this to build up a complete response from streaming chunks:
/// ```gleam
/// streaming.new_accumulator()
/// |> streaming.accumulate(delta1)
/// |> streaming.accumulate(delta2)
/// |> streaming.finish()
/// ```
pub opaque type Accumulator {
  Accumulator(
    content: List(Content),
    stop_reason: Option(StopReason),
    usage: Option(Usage),
  )
}

/// Create a new empty accumulator.
pub fn new_accumulator() -> Accumulator {
  Accumulator(content: [], stop_reason: None, usage: None)
}

/// Add a delta to the accumulator.
pub fn accumulate(acc: Accumulator, delta: StreamDelta) -> Accumulator {
  case delta {
    ContentDelta(content) -> {
      // Merge consecutive text deltas
      let new_content = case content, acc.content {
        gai.Text(new_text), [gai.Text(existing_text), ..rest] -> [
          gai.Text(existing_text <> new_text),
          ..rest
        ]
        _, _ -> [content, ..acc.content]
      }
      Accumulator(..acc, content: new_content)
    }
    Done(stop_reason:, usage:) -> {
      let final_usage = case usage {
        Some(_) -> usage
        None -> acc.usage
      }
      Accumulator(..acc, stop_reason: Some(stop_reason), usage: final_usage)
    }
    Ping -> acc
  }
}

/// Finish accumulating and return the final response.
///
/// Returns an error if the stream hasn't completed (no Done delta received).
pub fn finish(
  acc: Accumulator,
) -> Result(response.CompletionResponse, gai.Error) {
  case acc.stop_reason {
    None -> Error(gai.ParseError("Stream not complete: no Done delta received"))
    Some(stop_reason) -> {
      let content = list.reverse(acc.content)
      let usage =
        option.unwrap(
          acc.usage,
          gai.Usage(
            input_tokens: 0,
            output_tokens: 0,
            cache_creation_input_tokens: option.None,
            cache_read_input_tokens: option.None,
          ),
        )

      Ok(response.CompletionResponse(
        id: "stream",
        model: "streamed",
        content:,
        stop_reason:,
        usage:,
      ))
    }
  }
}
