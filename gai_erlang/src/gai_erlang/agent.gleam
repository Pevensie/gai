/// Agent configuration for tool-enabled LLM interactions.
import gai.{type Error}
import gai/agent as gai_agent
import gai/provider.{type Provider}
import gai_erlang/tool
import gleam/http/request
import gleam/http/response
import gleam/httpc
import gleam/list
import gleam/option
import gleam/result

/// HTTP send function type.
pub type Send =
  fn(request.Request(String)) -> Result(response.Response(String), Error)

fn default_send(
  req: request.Request(String),
) -> Result(response.Response(String), Error) {
  httpc.send(req)
  |> result.map_error(fn(_) { gai.HttpError(0, "HTTP request failed") })
}

/// Agent configuration with context type parameter.
///
/// The `ctx` type represents the context passed to tool executors.
pub opaque type Agent(ctx) {
  Agent(
    provider: Provider,
    tools: List(tool.Tool(ctx)),
    stop_conditions: List(gai_agent.StopCondition),
    max_tokens: option.Option(Int),
    temperature: option.Option(Float),
    send: Send,
  )
}

/// Create a new agent with a provider.
pub fn new(provider: Provider) -> Agent(ctx) {
  Agent(
    provider:,
    tools: [],
    stop_conditions: [gai_agent.MaxIterations(10)],
    max_tokens: option.None,
    temperature: option.None,
    send: default_send,
  )
}

/// Add a tool to the agent.
pub fn with_tool(agent: Agent(ctx), tool: tool.Tool(ctx)) -> Agent(ctx) {
  Agent(..agent, tools: [tool, ..agent.tools])
}

/// Add multiple tools to the agent.
pub fn with_tools(agent: Agent(ctx), tools: List(tool.Tool(ctx))) -> Agent(ctx) {
  Agent(..agent, tools: list.append(tools, agent.tools))
}

/// Add a stop condition to the agent.
pub fn with_stop_condition(
  agent: Agent(ctx),
  condition: gai_agent.StopCondition,
) -> Agent(ctx) {
  Agent(..agent, stop_conditions: [condition, ..agent.stop_conditions])
}

/// Set maximum tool loop iterations (safety limit).
pub fn with_max_iterations(agent: Agent(ctx), max: Int) -> Agent(ctx) {
  let stop_conditions =
    agent.stop_conditions
    |> list.filter(fn(cond) {
      case cond {
        gai_agent.MaxIterations(_) -> False
        _ -> True
      }
    })
  Agent(..agent, stop_conditions: [
    gai_agent.MaxIterations(max),
    ..stop_conditions
  ])
}

/// Set max tokens on requests.
pub fn with_max_tokens(agent: Agent(ctx), max: Int) -> Agent(ctx) {
  Agent(..agent, max_tokens: option.Some(max))
}

/// Set temperature on requests.
pub fn with_temperature(agent: Agent(ctx), temp: Float) -> Agent(ctx) {
  Agent(..agent, temperature: option.Some(temp))
}

/// Set a custom send function.
pub fn with_send(agent: Agent(ctx), send: Send) -> Agent(ctx) {
  Agent(..agent, send: send)
}

/// Convenience helper to create a HasToolCall stop condition.
pub fn stop_on_tool(tool: tool.Tool(ctx)) -> gai_agent.StopCondition {
  gai_agent.HasToolCall(tool.schema(tool))
}

/// Get the provider.
pub fn provider(agent: Agent(ctx)) -> Provider {
  agent.provider
}

/// Get tools as a list.
pub fn tools(agent: Agent(ctx)) -> List(tool.Tool(ctx)) {
  agent.tools
}

/// Get stop conditions.
pub fn stop_conditions(agent: Agent(ctx)) -> List(gai_agent.StopCondition) {
  agent.stop_conditions
}

/// Get max tokens.
pub fn max_tokens(agent: Agent(ctx)) -> option.Option(Int) {
  agent.max_tokens
}

/// Get temperature.
pub fn temperature(agent: Agent(ctx)) -> option.Option(Float) {
  agent.temperature
}

/// Get send function.
pub fn send(agent: Agent(ctx)) -> Send {
  agent.send
}

/// Get max iterations.
pub fn max_iterations(agent: Agent(ctx)) -> Int {
  case
    list.find(agent.stop_conditions, fn(cond) {
      case cond {
        gai_agent.MaxIterations(_) -> True
        _ -> False
      }
    })
  {
    Ok(gai_agent.MaxIterations(n)) -> n
    _ -> 10
  }
}

/// Find a tool by name.
pub fn find_tool(
  agent: Agent(ctx),
  name: String,
) -> option.Option(tool.Tool(ctx)) {
  agent.tools
  |> list.find(fn(t) { tool.name(t) == name })
  |> option.from_result
}

/// Check if the agent has any tools.
pub fn has_tools(agent: Agent(ctx)) -> Bool {
  case agent.tools {
    [] -> False
    _ -> True
  }
}

/// Get the number of tools.
pub fn tool_count(agent: Agent(ctx)) -> Int {
  list.length(agent.tools)
}
