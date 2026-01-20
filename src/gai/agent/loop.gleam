/// Tool loop for agent execution.
///
/// The tool loop orchestrates LLM calls with automatic tool execution:
/// 1. Send messages to the LLM
/// 2. If the response contains tool calls, execute them
/// 3. Append tool results and repeat
/// 4. Return when no more tool calls or max iterations reached
///
/// ## Example
///
/// ```gleam
/// let result = loop.run(agent, ctx, messages, runtime)
/// case result {
///   Ok(run_result) -> {
///     io.println(response.text_content(run_result.response))
///   }
///   Error(err) -> {
///     io.println("Error: " <> gai.error_to_string(err))
///   }
/// }
/// ```
import gai.{type Error, type Message}
import gai/agent.{type Agent}
import gai/provider
import gai/request
import gai/response.{type CompletionResponse}
import gai/runtime.{type Runtime}
import gai/tool.{type Call, type CallResult}
import gleam/list
import gleam/option.{None, Some}
import gleam/result

/// Result of running the agent
pub type RunResult {
  RunResult(
    /// The final completion response
    response: CompletionResponse,
    /// Full message history including tool calls and results
    messages: List(Message),
    /// Number of iterations (LLM calls) made
    iterations: Int,
  )
}

/// Run the agent with automatic tool loop.
///
/// This function:
/// 1. Prepends the system prompt (if set)
/// 2. Sends messages to the LLM
/// 3. If tool calls are returned, executes them and loops
/// 4. Returns when complete or max iterations reached
pub fn run(
  agent: Agent(ctx),
  ctx: ctx,
  messages: List(Message),
  http_runtime: Runtime,
) -> Result(RunResult, Error) {
  // Prepend system prompt if set
  let messages = case agent.system_prompt(agent) {
    None -> messages
    Some(prompt) -> [gai.system(prompt), ..messages]
  }

  run_loop(agent, ctx, messages, http_runtime, 0)
}

fn run_loop(
  agent: Agent(ctx),
  ctx: ctx,
  messages: List(Message),
  http_runtime: Runtime,
  iteration: Int,
) -> Result(RunResult, Error) {
  // Check iteration limit
  case iteration >= agent.max_iterations(agent) {
    True ->
      Error(gai.ApiError(
        "max_iterations",
        "Tool loop exceeded maximum iterations",
      ))
    False -> {
      // Build request
      let req = build_request(agent, messages)

      // Build HTTP request using provider
      let http_req = provider.build_request(agent.provider(agent), req)

      // Send via runtime
      use http_resp <- result.try(runtime.send(http_runtime, http_req))

      // Parse response
      use completion <- result.try(provider.parse_response(
        agent.provider(agent),
        http_resp,
      ))

      // Check for tool calls
      case response.has_tool_calls(completion) {
        False -> {
          // No tools, we're done
          let final_messages = response.append_response(messages, completion)
          Ok(RunResult(
            response: completion,
            messages: final_messages,
            iterations: iteration + 1,
          ))
        }
        True -> {
          // Execute tools
          let tool_calls = extract_tool_calls(completion)
          let results = execute_tools(agent, ctx, tool_calls)

          // Append assistant response and tool results to history
          let messages = response.append_response(messages, completion)
          let messages = append_tool_results(messages, results)

          // Continue loop
          run_loop(agent, ctx, messages, http_runtime, iteration + 1)
        }
      }
    }
  }
}

fn build_request(
  agent: Agent(ctx),
  messages: List(Message),
) -> request.CompletionRequest {
  let base_req = request.new(provider.name(agent.provider(agent)), messages)

  // Add tools if any
  let req = case agent.has_tools(agent) {
    False -> base_req
    True -> {
      let tool_schemas =
        agent.tools(agent)
        |> list.map(tool.to_schema)
      request.with_tools(base_req, tool_schemas)
    }
  }

  // Add max_tokens if set
  let req = case agent.max_tokens(agent) {
    None -> req
    Some(n) -> request.with_max_tokens(req, n)
  }

  // Add temperature if set
  let req = case agent.temperature(agent) {
    None -> req
    Some(t) -> request.with_temperature(req, t)
  }

  req
}

fn extract_tool_calls(resp: CompletionResponse) -> List(Call) {
  response.tool_calls(resp)
  |> list.filter_map(fn(content) {
    case content {
      gai.ToolUse(id, name, args_json) ->
        Ok(tool.Call(id:, name:, arguments_json: args_json))
      _ -> Error(Nil)
    }
  })
}

fn execute_tools(
  agent: Agent(ctx),
  ctx: ctx,
  calls: List(Call),
) -> List(CallResult) {
  list.map(calls, fn(call) { execute_single_tool(agent, ctx, call) })
}

fn execute_single_tool(agent: Agent(ctx), ctx: ctx, call: Call) -> CallResult {
  case agent.find_tool(agent, call.name) {
    None -> tool.call_error(call, "Unknown tool: " <> call.name)
    Some(t) -> tool.execute_call(t, ctx, call)
  }
}

fn append_tool_results(
  messages: List(Message),
  results: List(CallResult),
) -> List(Message) {
  let content =
    list.map(results, fn(r) {
      case r.content {
        Ok(text) -> gai.tool_result(r.tool_use_id, text)
        Error(err) -> gai.tool_result_error(r.tool_use_id, err)
      }
    })
  list.append(messages, [gai.Message(gai.User, content, None)])
}
