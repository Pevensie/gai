import gai/agent
import gai/tool
import gleam/json

pub fn stop_condition_variants_test() {
  let schema = json.object([#("type", json.string("object"))])
  let tool_schema =
    tool.ToolSchema(
      name: "final_answer",
      description: "Final answer",
      schema_json: schema,
    )

  let _ = agent.MaxIterations(5)
  let _ = agent.HasToolCall(tool_schema)
}
