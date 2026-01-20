/// Tool definitions with Sextant schema integration.
///
/// This module provides two APIs:
///
/// 1. **Legacy API** - Tools without embedded executors, for use with manual
///    tool execution via pattern matching. Uses `Tool(a)` and `UntypedTool`.
///
/// 2. **New API** - Tools with embedded executors that carry their own
///    execution logic. Uses `ExecutableTool(ctx, args)`. Type safety is
///    preserved at definition time, then erased for storage using coerce.
///
/// ## New API Example
///
/// ```gleam
/// let weather_tool = tool.executable(
///   name: "get_weather",
///   description: "Get weather for a location",
///   schema: weather_schema(),
///   execute: fn(ctx, args) {
///     // args is WeatherArgs here - fully typed!
///     Ok("Weather in " <> args.location <> ": sunny")
///   },
/// )
/// ```
import gai/internal/coerce
import gleam/dynamic/decode
import gleam/json.{type Json}
import gleam/list
import gleam/string
import sextant.{type JsonSchema}

// ============================================================================
// Legacy API (existing, for backwards compatibility)
// ============================================================================

/// Tool definition with Sextant schema.
/// The phantom type `a` represents the decoded arguments type.
pub opaque type Tool(a) {
  Tool(name: String, description: String, schema: JsonSchema(a))
}

/// Create a tool definition
pub fn new(
  name: String,
  description: String,
  parameters: JsonSchema(a),
) -> Tool(a) {
  Tool(name:, description:, schema: parameters)
}

/// Get the tool name
pub fn name(tool: Tool(a)) -> String {
  tool.name
}

/// Get the tool description
pub fn description(tool: Tool(a)) -> String {
  tool.description
}

/// Get the JSON Schema for a tool (for sending to API)
pub fn to_json_schema(tool: Tool(a)) -> Json {
  sextant.to_json(tool.schema)
}

/// Parse tool call arguments from a JSON string using the tool's schema
pub fn parse_arguments(
  tool: Tool(a),
  arguments_json: String,
) -> Result(a, List(sextant.ValidationError)) {
  case json.parse(arguments_json, decode.dynamic) {
    Ok(dynamic) -> sextant.run(dynamic, tool.schema)
    Error(_) ->
      Error([
        sextant.TypeError(
          path: [],
          expected: "valid JSON",
          found: "invalid JSON",
        ),
      ])
  }
}

/// An untyped tool for storage in lists (type erased)
pub opaque type UntypedTool {
  UntypedTool(name: String, description: String, schema_json: Json)
}

/// Erase the type parameter for storage in lists
pub fn to_untyped(tool: Tool(a)) -> UntypedTool {
  UntypedTool(
    name: tool.name,
    description: tool.description,
    schema_json: sextant.to_json(tool.schema),
  )
}

/// Get the name of an untyped tool
pub fn untyped_name(tool: UntypedTool) -> String {
  tool.name
}

/// Get the description of an untyped tool
pub fn untyped_description(tool: UntypedTool) -> String {
  tool.description
}

/// Get the JSON schema of an untyped tool
pub fn untyped_schema(tool: UntypedTool) -> Json {
  tool.schema_json
}

/// Convert an ExecutableTool to an UntypedTool for use with requests
pub fn executable_to_untyped(tool: ExecutableTool(ctx, args)) -> UntypedTool {
  UntypedTool(
    name: tool.name,
    description: tool.description,
    schema_json: tool.schema_json,
  )
}

// ============================================================================
// New API: Executable Tools with Embedded Executors
// ============================================================================

/// Opaque type representing erased tool arguments.
/// Used as a phantom type marker after coercion.
pub type ToolArgs

/// Errors that can occur during tool execution
pub type ExecutionError {
  /// Failed to parse the JSON arguments
  ParseError(message: String)
  /// The tool execution itself failed
  ToolError(message: String)
}

/// Convert an execution error to a human-readable string
pub fn execution_error_to_string(error: ExecutionError) -> String {
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

/// An executable tool with embedded executor.
///
/// The `ctx` type parameter is the context passed to the executor.
/// The `args` type parameter represents the parsed arguments type,
/// but is erased to `ToolArgs` for storage in lists.
pub opaque type ExecutableTool(ctx, args) {
  ExecutableTool(
    name: String,
    description: String,
    schema_json: Json,
    /// Parses JSON args internally and executes with context
    run: fn(ctx, String) -> Result(String, ExecutionError),
  )
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
pub fn executable(
  name name: String,
  description description: String,
  schema schema: JsonSchema(args),
  execute execute: fn(ctx, args) -> Result(String, ExecutionError),
) -> ExecutableTool(ctx, ToolArgs) {
  let tool =
    ExecutableTool(
      name:,
      description:,
      schema_json: sextant.to_json(schema),
      run: fn(ctx, args_json) {
        // Parse JSON to dynamic
        case json.parse(args_json, decode.dynamic) {
          Error(e) -> Error(ParseError("Invalid JSON: " <> string.inspect(e)))
          Ok(dynamic) -> {
            // Validate and decode using schema
            case sextant.run(dynamic, schema) {
              Error(errors) ->
                Error(ParseError(
                  "Validation failed: " <> validation_errors_to_string(errors),
                ))
              Ok(args) -> execute(ctx, args)
            }
          }
        }
      },
    )
  coerce.unsafe_coerce(tool)
}

fn validation_errors_to_string(errors: List(sextant.ValidationError)) -> String {
  errors
  |> list.map(fn(e) {
    case e {
      sextant.TypeError(path:, expected:, found:) ->
        string.join(path, ".") <> ": expected " <> expected <> ", got " <> found
      sextant.MissingField(path:, field:) ->
        string.join(path, ".") <> ": missing field " <> field
      sextant.ConstraintError(path:, violation: _) ->
        string.join(path, ".") <> ": constraint violation"
      sextant.UnknownVariant(path:, value:, expected:) ->
        string.join(path, ".")
        <> ": unknown variant '"
        <> value
        <> "', expected one of "
        <> string.join(expected, ", ")
      sextant.ConstMismatch(path:, expected:, actual:) ->
        string.join(path, ".")
        <> ": expected const '"
        <> expected
        <> "', got '"
        <> actual
        <> "'"
    }
  })
  |> string.join("; ")
}

/// Get the name of an executable tool
pub fn executable_name(tool: ExecutableTool(ctx, args)) -> String {
  tool.name
}

/// Get the description of an executable tool
pub fn executable_description(tool: ExecutableTool(ctx, args)) -> String {
  tool.description
}

/// Get the JSON Schema for sending to the LLM API
pub fn executable_schema_json(tool: ExecutableTool(ctx, args)) -> Json {
  tool.schema_json
}

/// Execute the tool with context and JSON arguments
pub fn execute(
  tool: ExecutableTool(ctx, args),
  ctx: ctx,
  arguments_json: String,
) -> Result(String, ExecutionError) {
  tool.run(ctx, arguments_json)
}

/// Execute a tool call, returning a CallResult
pub fn execute_call(
  tool: ExecutableTool(ctx, args),
  ctx: ctx,
  call: Call,
) -> CallResult {
  case tool.run(ctx, call.arguments_json) {
    Ok(content) -> CallResult(tool_use_id: call.id, content: Ok(content))
    Error(e) ->
      CallResult(
        tool_use_id: call.id,
        content: Error(execution_error_to_string(e)),
      )
  }
}
