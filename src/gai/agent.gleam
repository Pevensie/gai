/// Agent configuration for tool-enabled LLM interactions.
///
/// An Agent bundles a provider, system prompt, and executable tools
/// together for use with the tool loop. It focuses on agentic-specific
/// concerns, leaving request-level config (max_tokens, temperature, etc.)
/// to be passed separately.
///
/// ## Example
///
/// ```gleam
/// let my_agent = agent.new(provider)
///   |> agent.with_system_prompt("You are a helpful assistant.")
///   |> agent.with_tool(weather_tool)
///   |> agent.with_tool(search_tool)
///   |> agent.with_max_iterations(5)
/// ```
import gai/provider.{type Provider}
import gai/tool.{type Tool}
import gleam/list
import gleam/option.{type Option, None, Some}

/// Agent configuration with context type parameter.
///
/// The `ctx` type represents the context passed to tool executors.
pub opaque type Agent(ctx) {
  Agent(
    provider: Provider,
    system_prompt: Option(String),
    tools: List(Tool(ctx)),
    max_iterations: Int,
  )
}

/// Create a new agent with a provider
pub fn new(provider: Provider) -> Agent(ctx) {
  Agent(provider:, system_prompt: None, tools: [], max_iterations: 10)
}

/// Set the system prompt
pub fn with_system_prompt(agent: Agent(ctx), prompt: String) -> Agent(ctx) {
  Agent(..agent, system_prompt: Some(prompt))
}

/// Add a tool to the agent
pub fn with_tool(agent: Agent(ctx), tool: Tool(ctx)) -> Agent(ctx) {
  Agent(..agent, tools: [tool, ..agent.tools])
}

/// Add multiple tools to the agent
pub fn with_tools(agent: Agent(ctx), tools: List(Tool(ctx))) -> Agent(ctx) {
  Agent(..agent, tools: list.append(tools, agent.tools))
}

/// Set maximum tool loop iterations (safety limit)
pub fn with_max_iterations(agent: Agent(ctx), n: Int) -> Agent(ctx) {
  Agent(..agent, max_iterations: n)
}

/// Get the provider
pub fn provider(agent: Agent(ctx)) -> Provider {
  agent.provider
}

/// Get the system prompt
pub fn system_prompt(agent: Agent(ctx)) -> Option(String) {
  agent.system_prompt
}

/// Get tools as a list
pub fn tools(agent: Agent(ctx)) -> List(Tool(ctx)) {
  agent.tools
}

/// Get max iterations setting
pub fn max_iterations(agent: Agent(ctx)) -> Int {
  agent.max_iterations
}

/// Find a tool by name
pub fn find_tool(agent: Agent(ctx), name: String) -> Option(Tool(ctx)) {
  agent.tools
  |> list.find(fn(t) { tool.name(t) == name })
  |> option.from_result
}

/// Check if the agent has any tools
pub fn has_tools(agent: Agent(ctx)) -> Bool {
  !list.is_empty(agent.tools)
}

/// Get the number of tools
pub fn tool_count(agent: Agent(ctx)) -> Int {
  list.length(agent.tools)
}
