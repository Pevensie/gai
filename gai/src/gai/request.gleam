/// Completion request types and builders.
import gai.{type Message}
import gai/schema.{type Schema}
import gai/tool
import gleam/json.{type Json}
import gleam/option.{type Option, None}

/// Response format options
pub type ResponseFormat {
  TextFormat
  JsonFormat
  JsonSchemaFormat(schema: Json, name: String, strict: Bool)
}

/// Tool choice options
pub type ToolChoice {
  Auto
  ToolNone
  Required
  Specific(name: String)
}

/// Completion request configuration
pub type CompletionRequest {
  CompletionRequest(
    model: String,
    messages: List(Message),
    max_tokens: Option(Int),
    temperature: Option(Float),
    top_p: Option(Float),
    stop: Option(List(String)),
    tools: Option(List(tool.Schema)),
    tool_choice: Option(ToolChoice),
    response_format: Option(ResponseFormat),
    provider_options: Option(List(#(String, Json))),
  )
}

/// Create a new completion request
pub fn new(model: String, messages: List(Message)) -> CompletionRequest {
  CompletionRequest(
    model:,
    messages:,
    max_tokens: None,
    temperature: None,
    top_p: None,
    stop: None,
    tools: None,
    tool_choice: None,
    response_format: None,
    provider_options: None,
  )
}

/// Set maximum tokens
pub fn with_max_tokens(req: CompletionRequest, n: Int) -> CompletionRequest {
  CompletionRequest(..req, max_tokens: option.Some(n))
}

/// Set temperature
pub fn with_temperature(req: CompletionRequest, t: Float) -> CompletionRequest {
  CompletionRequest(..req, temperature: option.Some(t))
}

/// Set top_p (nucleus sampling)
pub fn with_top_p(req: CompletionRequest, p: Float) -> CompletionRequest {
  CompletionRequest(..req, top_p: option.Some(p))
}

/// Set stop sequences
pub fn with_stop(
  req: CompletionRequest,
  sequences: List(String),
) -> CompletionRequest {
  CompletionRequest(..req, stop: option.Some(sequences))
}

/// Set tools
pub fn with_tools(
  req: CompletionRequest,
  tools: List(tool.Schema),
) -> CompletionRequest {
  CompletionRequest(..req, tools: option.Some(tools))
}

/// Set tool choice
pub fn with_tool_choice(
  req: CompletionRequest,
  choice: ToolChoice,
) -> CompletionRequest {
  CompletionRequest(..req, tool_choice: option.Some(choice))
}

/// Set response format
pub fn with_response_format(
  req: CompletionRequest,
  format: ResponseFormat,
) -> CompletionRequest {
  CompletionRequest(..req, response_format: option.Some(format))
}

/// Set provider-specific options that get merged into the request body.
/// These are passed through directly to the provider's API.
///
/// ## Example
/// ```gleam
/// request.new("gpt-4o", messages)
/// |> request.with_provider_options([
///   #("reasoning_effort", json.string("low")),
///   #("presence_penalty", json.float(0.5)),
/// ])
/// ```
pub fn with_provider_options(
  req: CompletionRequest,
  options: List(#(String, Json)),
) -> CompletionRequest {
  CompletionRequest(..req, provider_options: option.Some(options))
}

/// Set a structured output schema using a Sextant schema.
/// This is a convenience wrapper around `with_response_format(JsonSchemaFormat(...))`.
///
/// Keep the schema around to parse the response with `schema.parse()`.
///
/// ## Example
/// ```gleam
/// let greeting_schema = schema.new("greeting", {
///   use message <- sextant.field("message", sextant.string())
///   sextant.success(Greeting(message))
/// })
///
/// let req = request.new("gpt-4o", messages)
///   |> request.with_schema(greeting_schema)
///
/// // Later, parse the response:
/// let assert Ok(greeting) = schema.parse(greeting_schema, response_text)
/// ```
pub fn with_schema(req: CompletionRequest, s: Schema(a)) -> CompletionRequest {
  let format =
    JsonSchemaFormat(
      schema: schema.to_json_schema(s),
      name: schema.name(s),
      strict: schema.strict(s),
    )
  CompletionRequest(..req, response_format: option.Some(format))
}
