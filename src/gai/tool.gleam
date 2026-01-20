/// Tool definitions with embedded executors.
///
/// Tools carry their own execution function and type safety is preserved
/// at definition time through closures.
///
/// ## Example
///
/// ```gleam
/// let weather_tool = tool.new(
///   name: "get_weather",
///   description: "Get weather for a location",
///   schema: weather_schema(),
///   execute: fn(ctx, args) {
///     // args is WeatherArgs here - fully typed!
///     Ok("Weather in " <> args.location <> ": sunny")
///   },
/// )
/// ```
import gleam/dynamic/decode
import gleam/json.{type Json}
import gleam/list
import gleam/result
import gleam/string
import sextant.{type JsonSchema}

/// An executable tool with embedded executor.
///
/// The `ctx` type parameter is the context passed to the executor.
/// The `args` type parameter represents the parsed arguments type,
/// but is erased to `ToolArgs` for storage in lists.
pub opaque type Tool(ctx) {
  Tool(
    name: String,
    description: String,
    schema_json: Json,
    /// Parses JSON args internally and executes with context
    run: fn(ctx, String) -> Result(String, ExecutionError),
  )
}

/// Tool schema information for sending to LLM APIs.
/// This is a context-free representation of a tool's metadata.
pub type Schema {
  Schema(name: String, description: String, schema: Json)
}

/// Errors that can occur during tool execution
pub type ExecutionError {
  /// Failed to parse the JSON arguments
  ParseError(message: String)
  /// The tool execution itself failed
  ToolError(message: String)
}

/// Convert an execution error to a human-readable string
pub fn describe_error(error: ExecutionError) -> String {
  case error {
    ParseError(msg) -> "Parse error: " <> msg
    ToolError(msg) -> "Execution error: " <> msg
  }
}

/// A tool call extracted from an LLM response
pub type Call {
  Call(id: String, name: String, arguments_json: String)
}

/// Result of executing a tool
pub type CallResult {
  CallResult(tool_use_id: String, content: Result(String, String))
}

/// Create a successful call result
pub fn call_ok(call: Call, content: String) -> CallResult {
  CallResult(tool_use_id: call.id, content: Ok(content))
}

/// Create a failed call result
pub fn call_error(call: Call, message: String) -> CallResult {
  CallResult(tool_use_id: call.id, content: Error(message))
}

/// Create a new executable tool with typed schema and executor.
///
/// The type parameter `args` is captured in the executor closure,
/// then erased to `ToolArgs` for storage. This allows storing
/// heterogeneous tools in a list while maintaining type safety
/// at the definition site.
///
/// ## Example
///
/// ```gleam
/// let weather_tool = tool.executable(
///   name: "get_weather",
///   description: "Get current weather",
///   schema: weather_schema(),
///   execute: fn(ctx, args) {
///     // args is fully typed as WeatherArgs
///     Ok("Sunny in " <> args.location)
///   },
/// )
/// ```
pub fn tool(
  name name: String,
  description description: String,
  schema schema: JsonSchema(args),
  execute execute: fn(ctx, args) -> Result(String, ExecutionError),
) -> Tool(ctx) {
  Tool(
    name:,
    description:,
    schema_json: sextant.to_json(schema),
    run: fn(ctx, args_json) {
      // Parse JSON to dynamic
      use dynamic <- result.try(
        json.parse(args_json, decode.dynamic)
        |> result.map_error(describe_json_decoding_error)
        |> result.map_error(ParseError),
      )
      use args <- result.try(
        sextant.run(dynamic, schema)
        |> result.map_error(describe_validation_errors)
        |> result.map_error(ParseError),
      )
      execute(ctx, args)
    },
  )
}

fn describe_json_decoding_error(error: json.DecodeError) -> String {
  case error {
    json.UnexpectedEndOfInput -> "Unexpected end of input"
    json.UnexpectedByte(_) -> "Unexpected byte"
    json.UnexpectedSequence(_) -> "Unexpected sequence"
    json.UnableToDecode(errors) ->
      "Unable to decode JSON: "
      <> list.map(errors, describe_decode_error) |> string.join("; ")
  }
  |> string.append("JSON Decoding Failed: ", _)
}

fn describe_decode_error(error: decode.DecodeError) {
  case error {
    decode.DecodeError(expected:, found:, path:) ->
      string.join(path, ".") <> " expected " <> expected <> ", got " <> found
  }
}

fn describe_validation_errors(errors: List(sextant.ValidationError)) -> String {
  errors
  |> list.map(fn(e) {
    case e {
      sextant.TypeError(path:, expected:, found:) ->
        string.join(path, ".") <> " expected " <> expected <> ", got " <> found
      sextant.MissingField(path:, field:) ->
        string.join(path, ".") <> " missing field '" <> field <> "'"
      sextant.ConstraintError(path:, violation: _) ->
        string.join(path, ".") <> " constraint violation"
      sextant.UnknownVariant(path:, value:, expected:) ->
        string.join(path, ".")
        <> " unknown variant '"
        <> value
        <> "', expected one of "
        <> string.join(expected, ", ")
      sextant.ConstMismatch(path:, expected:, actual:) ->
        string.join(path, ".")
        <> " expected const '"
        <> expected
        <> "', got '"
        <> actual
        <> "'"
    }
  })
  |> string.join("; ")
  |> string.append("Validation failed:", _)
}

/// Get the name of an executable tool
pub fn name(tool: Tool(ctx)) -> String {
  tool.name
}

/// Get the description of an executable tool
pub fn description(tool: Tool(ctx)) -> String {
  tool.description
}

/// Get the JSON Schema for sending to the LLM API
pub fn schema(tool: Tool(ctx)) -> Json {
  tool.schema_json
}

/// Execute the tool with context and JSON arguments
pub fn execute(
  tool: Tool(ctx),
  ctx: ctx,
  arguments_json: String,
) -> Result(String, ExecutionError) {
  tool.run(ctx, arguments_json)
}

/// Execute a tool call, returning a CallResult
pub fn execute_call(tool: Tool(ctx), ctx: ctx, call: Call) -> CallResult {
  case tool.run(ctx, call.arguments_json) {
    Ok(content) -> CallResult(tool_use_id: call.id, content: Ok(content))
    Error(e) ->
      CallResult(tool_use_id: call.id, content: Error(describe_error(e)))
  }
}

// ============================================================================
// Tool Schema (for requests, without executor)
// ============================================================================

/// Extract the schema information from a tool for use in requests
pub fn to_schema(tool: Tool(ctx)) -> Schema {
  Schema(
    name: tool.name,
    description: tool.description,
    schema: tool.schema_json,
  )
}
