/// Core types for the gai LLM library.
///
/// This module contains the foundational types for representing messages,
/// content, and metadata in LLM conversations.
import gleam/int
import gleam/list
import gleam/option.{type Option}

// ============================================================================
// Role
// ============================================================================

/// Message role in a conversation
pub type Role {
  System
  User
  Assistant
}

// ============================================================================
// Content
// ============================================================================

/// Content block within a message
pub type Content {
  Text(text: String)
  Image(source: ImageSource)
  Document(source: DocumentSource, media_type: String)
  /// Tool use with raw JSON arguments string for lossless round-tripping
  ToolUse(id: String, name: String, arguments_json: String)
  ToolResult(tool_use_id: String, content: List(Content))
  /// Extended thinking content (Claude's internal reasoning)
  Thinking(text: String)
}

/// Source for image content
pub type ImageSource {
  ImageBase64(data: String, media_type: String)
  ImageUrl(url: String)
}

/// Source for document content
pub type DocumentSource {
  DocumentBase64(data: String)
  DocumentUrl(url: String)
}

// ============================================================================
// Message
// ============================================================================

/// Cache control options for Anthropic prompt caching
pub type CacheControl {
  /// Ephemeral caching - content is cached for the session
  Ephemeral
}

/// A message in a conversation
pub type Message {
  Message(
    role: Role,
    content: List(Content),
    /// Cache control for Anthropic prompt caching (applied to last content block)
    cache_control: Option(CacheControl),
  )
}

// ============================================================================
// Response Metadata
// ============================================================================

/// Why the model stopped generating
pub type StopReason {
  EndTurn
  MaxTokens
  StopSequence
  ToolUsed
  /// Response was filtered due to safety/content policy (OpenAI, Google)
  ContentFilter
}

/// Token usage information
pub type Usage {
  Usage(
    input_tokens: Int,
    output_tokens: Int,
    /// Tokens used to create cache (Anthropic prompt caching)
    cache_creation_input_tokens: Option(Int),
    /// Tokens read from cache (Anthropic prompt caching)
    cache_read_input_tokens: Option(Int),
  )
}

/// Get cache read tokens from usage (0 if none)
pub fn cache_read_tokens(usage: Usage) -> Int {
  option.unwrap(usage.cache_read_input_tokens, 0)
}

/// Get cache creation tokens from usage (0 if none)
pub fn cache_creation_tokens(usage: Usage) -> Int {
  option.unwrap(usage.cache_creation_input_tokens, 0)
}

/// Calculate cache hit rate (read / (read + creation))
/// Returns None if no cache activity
pub fn cache_hit_rate(usage: Usage) -> Option(Float) {
  let read = cache_read_tokens(usage)
  let creation = cache_creation_tokens(usage)
  let total = read + creation
  case total {
    0 -> option.None
    _ -> option.Some(int.to_float(read) /. int.to_float(total))
  }
}

// ============================================================================
// Convenience Constructors
// ============================================================================

/// Create a system message
pub fn system(text: String) -> Message {
  Message(role: System, content: [Text(text)], cache_control: option.None)
}

/// Create a system message with caching enabled (Anthropic prompt caching)
pub fn cached_system(text: String) -> Message {
  Message(
    role: System,
    content: [Text(text)],
    cache_control: option.Some(Ephemeral),
  )
}

/// Create a user message with content list
pub fn user(content: List(Content)) -> Message {
  Message(role: User, content:, cache_control: option.None)
}

/// Create a user message with text content
pub fn user_text(text: String) -> Message {
  Message(role: User, content: [Text(text)], cache_control: option.None)
}

/// Create an assistant message with content list
pub fn assistant(content: List(Content)) -> Message {
  Message(role: Assistant, content:, cache_control: option.None)
}

/// Create an assistant message with text content
pub fn assistant_text(text: String) -> Message {
  Message(role: Assistant, content: [Text(text)], cache_control: option.None)
}

/// Add cache control to an existing message (Anthropic prompt caching)
pub fn with_cache_control(msg: Message) -> Message {
  Message(..msg, cache_control: option.Some(Ephemeral))
}

/// Create text content
pub fn text(t: String) -> Content {
  Text(t)
}

/// Create image content from URL
pub fn image_url(url: String) -> Content {
  Image(ImageUrl(url))
}

/// Create image content from base64 data
pub fn image_base64(data: String, media_type: String) -> Content {
  Image(ImageBase64(data, media_type))
}

/// Create document content from URL
pub fn document_url(url: String, media_type: String) -> Content {
  Document(DocumentUrl(url), media_type)
}

/// Create document content from base64 data
pub fn document_base64(data: String, media_type: String) -> Content {
  Document(DocumentBase64(data), media_type)
}

/// Create a tool result content block
pub fn tool_result(tool_use_id: String, result: String) -> Content {
  ToolResult(tool_use_id, [Text(result)])
}

/// Create a tool result content block indicating an error
pub fn tool_result_error(tool_use_id: String, error: String) -> Content {
  // Note: Some providers have an is_error flag - for now we just use error text
  // This can be extended when provider-specific error handling is needed
  ToolResult(tool_use_id, [Text(error)])
}

/// Create a User message containing multiple tool results
pub fn tool_results_message(results: List(#(String, String))) -> Message {
  let content =
    list.map(results, fn(pair) {
      let #(tool_use_id, result_text) = pair
      tool_result(tool_use_id, result_text)
    })
  Message(role: User, content:, cache_control: option.None)
}

// ============================================================================
// Error
// ============================================================================

/// Errors that can occur when working with LLM APIs
pub type Error {
  /// HTTP-level error (connection failed, timeout, etc.)
  HttpError(status: Int, body: String)
  /// JSON parsing error
  JsonError(message: String)
  /// API returned an error response
  ApiError(code: String, message: String)
  /// Response didn't match expected format
  ParseError(message: String)
  /// Rate limited
  RateLimited(retry_after: Option(Int))
  /// Authentication failed
  AuthError(message: String)
}

/// Convert an error to a human-readable string
pub fn error_to_string(error: Error) -> String {
  case error {
    HttpError(status:, body:) ->
      "HTTP error " <> int.to_string(status) <> ": " <> body
    JsonError(message:) -> "JSON error: " <> message
    ApiError(code:, message:) -> "API error (" <> code <> "): " <> message
    ParseError(message:) -> "Parse error: " <> message
    RateLimited(retry_after:) ->
      case retry_after {
        option.Some(seconds) ->
          "Rate limited, retry after " <> int.to_string(seconds) <> " seconds"
        option.None -> "Rate limited"
      }
    AuthError(message:) -> "Authentication error: " <> message
  }
}
