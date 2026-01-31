/// Tool schema types shared across runtimes.
import gleam/json.{type Json}

/// Tool schema information for sending to LLM APIs.
pub type ToolSchema {
  ToolSchema(name: String, description: String, schema_json: Json)
}

/// Errors that can occur during tool execution.
pub type ExecutionError {
  /// Failed to parse the JSON arguments.
  ParseError(message: String)
  /// The tool execution itself failed.
  ToolError(message: String)
}

/// Convert an execution error to a human-readable string.
pub fn describe_error(error: ExecutionError) -> String {
  case error {
    ParseError(msg) -> "Parse error: " <> msg
    ToolError(msg) -> "Execution error: " <> msg
  }
}
