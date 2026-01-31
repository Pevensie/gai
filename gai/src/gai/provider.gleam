/// Provider abstraction for framework use.
///
/// The Provider type bundles request building and response parsing functions,
/// enabling frameworks to work with any LLM provider polymorphically.
import gai.{type Error}
import gai/request as gai_request
import gai/response as gai_response
import gai/streaming.{type StreamDelta}
import gleam/http/request.{type Request}
import gleam/http/response.{type Response}

/// A provider bundles request building and response parsing.
/// Use this for building frameworks/abstractions over multiple providers.
pub type Provider {
  Provider(
    /// Provider name (e.g., "openai", "anthropic")
    name: String,
    /// Build an HTTP request from a completion request
    build_request: fn(gai_request.CompletionRequest) -> Request(String),
    /// Parse an HTTP response into a completion response
    parse_response: fn(Response(String)) ->
      Result(gai_response.CompletionResponse, Error),
    /// Parse a streaming chunk (SSE data line)
    parse_stream_chunk: fn(String) -> Result(StreamDelta, Error),
  )
}

/// Get the provider name
pub fn name(provider: Provider) -> String {
  provider.name
}

/// Build an HTTP request using the provider
pub fn build_request(
  provider: Provider,
  req: gai_request.CompletionRequest,
) -> Request(String) {
  provider.build_request(req)
}

/// Parse an HTTP response using the provider
pub fn parse_response(
  provider: Provider,
  resp: Response(String),
) -> Result(gai_response.CompletionResponse, Error) {
  provider.parse_response(resp)
}

/// Parse a streaming chunk using the provider
pub fn parse_stream_chunk(
  provider: Provider,
  chunk: String,
) -> Result(StreamDelta, Error) {
  provider.parse_stream_chunk(chunk)
}
