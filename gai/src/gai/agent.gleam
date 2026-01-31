/// Stop conditions for agent loops.
import gai/tool.{type ToolSchema}

/// Conditions that can cause the agent loop to stop.
pub type StopCondition {
  /// Stop when maximum iterations are reached.
  MaxIterations(Int)
  /// Stop when the specified tool is called.
  /// The tool is still executed before stopping.
  HasToolCall(ToolSchema)
}
