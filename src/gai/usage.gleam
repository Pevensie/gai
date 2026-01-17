/// Token tracking for conversations.
///
/// Provides cumulative token usage tracking across multi-turn conversations.
import gai.{type Usage}
import gleam/option.{type Option, None, Some}
import gleam/string

/// Cumulative token usage across a conversation.
/// Opaque to allow future extension (e.g., cache tokens).
pub opaque type ConversationUsage {
  ConversationUsage(
    total_input_tokens: Int,
    total_output_tokens: Int,
    turn_count: Int,
  )
}

/// Create a new ConversationUsage with all values at zero.
pub fn new() -> ConversationUsage {
  ConversationUsage(
    total_input_tokens: 0,
    total_output_tokens: 0,
    turn_count: 0,
  )
}

/// Add usage from a response to the cumulative total.
pub fn add(conv: ConversationUsage, resp_usage: Usage) -> ConversationUsage {
  ConversationUsage(
    total_input_tokens: conv.total_input_tokens + resp_usage.input_tokens,
    total_output_tokens: conv.total_output_tokens + resp_usage.output_tokens,
    turn_count: conv.turn_count + 1,
  )
}

/// Get total tokens (input + output).
pub fn total_tokens(conv: ConversationUsage) -> Int {
  conv.total_input_tokens + conv.total_output_tokens
}

/// Get total input tokens.
pub fn input_tokens(conv: ConversationUsage) -> Int {
  conv.total_input_tokens
}

/// Get total output tokens.
pub fn output_tokens(conv: ConversationUsage) -> Int {
  conv.total_output_tokens
}

/// Get the number of turns (API calls) made.
pub fn turns(conv: ConversationUsage) -> Int {
  conv.turn_count
}

// ============================================================================
// Model Context Limits
// ============================================================================

/// Get the context window limit for a model.
/// Returns None for unknown models.
/// Provider matching is case-insensitive.
/// Model matching uses starts_with for version flexibility.
pub fn context_limit(provider: String, model: String) -> Option(Int) {
  let provider_lower = string.lowercase(provider)
  let model_lower = string.lowercase(model)

  case provider_lower {
    "openai" -> openai_context_limit(model_lower)
    "anthropic" -> anthropic_context_limit(model_lower)
    "google" -> google_context_limit(model_lower)
    _ -> None
  }
}

/// Get the maximum output tokens for a model.
/// Returns None for unknown models.
pub fn output_limit(provider: String, model: String) -> Option(Int) {
  let provider_lower = string.lowercase(provider)
  let model_lower = string.lowercase(model)

  case provider_lower {
    "openai" -> openai_output_limit(model_lower)
    "anthropic" -> anthropic_output_limit(model_lower)
    "google" -> google_output_limit(model_lower)
    _ -> None
  }
}

fn openai_context_limit(model: String) -> Option(Int) {
  case
    string.starts_with(model, "gpt-4o"),
    string.starts_with(model, "gpt-4-turbo"),
    string.starts_with(model, "gpt-3.5-turbo"),
    string.starts_with(model, "o1"),
    string.starts_with(model, "o3")
  {
    True, _, _, _, _ -> Some(128_000)
    _, True, _, _, _ -> Some(128_000)
    _, _, True, _, _ -> Some(16_000)
    _, _, _, True, _ -> Some(200_000)
    _, _, _, _, True -> Some(200_000)
    _, _, _, _, _ -> None
  }
}

fn openai_output_limit(model: String) -> Option(Int) {
  case
    string.starts_with(model, "gpt-4o"),
    string.starts_with(model, "gpt-4-turbo"),
    string.starts_with(model, "gpt-3.5-turbo"),
    string.starts_with(model, "o1"),
    string.starts_with(model, "o3")
  {
    True, _, _, _, _ -> Some(16_000)
    _, True, _, _, _ -> Some(4000)
    _, _, True, _, _ -> Some(4000)
    _, _, _, True, _ -> Some(100_000)
    _, _, _, _, True -> Some(100_000)
    _, _, _, _, _ -> None
  }
}

fn anthropic_context_limit(model: String) -> Option(Int) {
  case
    string.starts_with(model, "claude-3-5-sonnet"),
    string.starts_with(model, "claude-3-5-haiku"),
    string.starts_with(model, "claude-3-opus"),
    string.starts_with(model, "claude-sonnet-4"),
    string.starts_with(model, "claude-opus-4")
  {
    True, _, _, _, _ -> Some(200_000)
    _, True, _, _, _ -> Some(200_000)
    _, _, True, _, _ -> Some(200_000)
    _, _, _, True, _ -> Some(200_000)
    _, _, _, _, True -> Some(200_000)
    _, _, _, _, _ -> None
  }
}

fn anthropic_output_limit(model: String) -> Option(Int) {
  case
    string.starts_with(model, "claude-3-5-sonnet"),
    string.starts_with(model, "claude-3-5-haiku"),
    string.starts_with(model, "claude-3-opus"),
    string.starts_with(model, "claude-sonnet-4"),
    string.starts_with(model, "claude-opus-4")
  {
    True, _, _, _, _ -> Some(8000)
    _, True, _, _, _ -> Some(8000)
    _, _, True, _, _ -> Some(4000)
    _, _, _, True, _ -> Some(64_000)
    _, _, _, _, True -> Some(32_000)
    _, _, _, _, _ -> None
  }
}

fn google_context_limit(model: String) -> Option(Int) {
  case
    string.starts_with(model, "gemini-1.5-pro"),
    string.starts_with(model, "gemini-1.5-flash"),
    string.starts_with(model, "gemini-2.0-flash"),
    string.starts_with(model, "gemini-2.5-pro")
  {
    True, _, _, _ -> Some(2_000_000)
    _, True, _, _ -> Some(1_000_000)
    _, _, True, _ -> Some(1_000_000)
    _, _, _, True -> Some(1_000_000)
    _, _, _, _ -> None
  }
}

fn google_output_limit(model: String) -> Option(Int) {
  case
    string.starts_with(model, "gemini-1.5-pro"),
    string.starts_with(model, "gemini-1.5-flash"),
    string.starts_with(model, "gemini-2.0-flash"),
    string.starts_with(model, "gemini-2.5-pro")
  {
    True, _, _, _ -> Some(8000)
    _, True, _, _ -> Some(8000)
    _, _, True, _ -> Some(8000)
    _, _, _, True -> Some(64_000)
    _, _, _, _ -> None
  }
}
