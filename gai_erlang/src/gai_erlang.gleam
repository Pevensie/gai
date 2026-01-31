//// Erlang runtime for gai.
////
//// Loop lives in this module. Agent and Tool remain in submodules.

import gai.{type Error, type Message, ToolUsed}
import gai/agent as gai_agent
import gai/provider
import gai/request as gai_request
import gai/response as gai_response
import gai_erlang/agent as erlang_agent
import gai_erlang/tool
import gleam/erlang/process
import gleam/list
import gleam/option
import gleam/order

// ==========================================================================
// Types
// ==========================================================================

/// Result of running the agent loop successfully.
pub type RunResult {
  RunResult(
    /// The final completion response.
    response: gai_response.CompletionResponse,
    /// Full message history including tool calls and results.
    messages: List(Message),
    /// Number of iterations (LLM calls) made.
    iterations: Int,
  )
}

/// Error from the agent loop, preserving partial state.
pub type LoopError {
  LoopError(
    /// The error that occurred.
    error: Error,
    /// Partial message history up to the point of failure.
    messages: List(Message),
    /// Number of iterations completed before failure.
    iterations: Int,
  )
}

// ==========================================================================
// Public API
// ==========================================================================

/// Run the agent with automatic tool loop.
pub fn run(
  agent: erlang_agent.Agent(ctx),
  ctx: ctx,
  messages: List(Message),
) -> Result(RunResult, LoopError) {
  run_loop(agent, ctx, messages, 0)
}

// ==========================================================================
// Internal
// ==========================================================================

fn run_loop(
  agent: erlang_agent.Agent(ctx),
  ctx: ctx,
  messages: List(Message),
  iteration: Int,
) -> Result(RunResult, LoopError) {
  let max_iterations = erlang_agent.max_iterations(agent)
  case iteration >= max_iterations {
    True ->
      Error(LoopError(
        error: gai.ApiError(
          "max_iterations",
          "Tool loop exceeded maximum iterations",
        ),
        messages:,
        iterations: iteration,
      ))
    False -> {
      let model = provider.model(erlang_agent.provider(agent))
      case model == "" {
        True ->
          Error(LoopError(
            error: gai.ApiError(
              "missing_model",
              "Provider model not configured",
            ),
            messages:,
            iterations: iteration,
          ))
        False -> {
          let req = build_request(agent, model, messages)
          let http_req =
            provider.build_request(erlang_agent.provider(agent), req)
          case erlang_agent.send(agent)(http_req) {
            Error(error) ->
              Error(LoopError(error:, messages:, iterations: iteration))
            Ok(http_resp) -> {
              case
                provider.parse_response(erlang_agent.provider(agent), http_resp)
              {
                Error(error) ->
                  Error(LoopError(error:, messages:, iterations: iteration))
                Ok(completion) ->
                  handle_completion(agent, ctx, messages, iteration, completion)
              }
            }
          }
        }
      }
    }
  }
}

fn handle_completion(
  agent: erlang_agent.Agent(ctx),
  ctx: ctx,
  messages: List(Message),
  iteration: Int,
  completion: gai_response.CompletionResponse,
) -> Result(RunResult, LoopError) {
  case
    completion.stop_reason == ToolUsed
    && gai_response.has_tool_calls(completion)
  {
    False -> {
      let final_messages = gai_response.append_response(messages, completion)
      Ok(RunResult(
        response: completion,
        messages: final_messages,
        iterations: iteration + 1,
      ))
    }
    True -> {
      let tool_calls = extract_tool_calls(completion)
      let results = execute_tools_parallel(agent, ctx, tool_calls)

      let should_stop =
        should_stop_on_tool(erlang_agent.stop_conditions(agent), tool_calls)

      let messages = gai_response.append_response(messages, completion)
      let messages = append_tool_results(messages, results)

      case should_stop {
        True ->
          Ok(RunResult(
            response: completion,
            messages:,
            iterations: iteration + 1,
          ))
        False -> run_loop(agent, ctx, messages, iteration + 1)
      }
    }
  }
}

fn build_request(
  agent: erlang_agent.Agent(ctx),
  model: String,
  messages: List(Message),
) -> gai_request.CompletionRequest {
  let base_req = gai_request.new(model, messages)

  let req = case erlang_agent.max_tokens(agent) {
    option.None -> base_req
    option.Some(max) -> gai_request.with_max_tokens(base_req, max)
  }

  let req = case erlang_agent.temperature(agent) {
    option.None -> req
    option.Some(temp) -> gai_request.with_temperature(req, temp)
  }

  case erlang_agent.has_tools(agent) {
    False -> req
    True -> {
      let tool_schemas =
        erlang_agent.tools(agent)
        |> list.map(tool.schema)
      gai_request.with_tools(req, tool_schemas)
    }
  }
}

type Call {
  Call(id: String, name: String, arguments_json: String)
}

fn extract_tool_calls(resp: gai_response.CompletionResponse) -> List(Call) {
  gai_response.tool_calls(resp)
  |> list.filter_map(fn(content) {
    case content {
      gai.ToolUse(id, name, args_json) ->
        Ok(Call(id:, name:, arguments_json: args_json))
      _ -> Error(Nil)
    }
  })
}

fn execute_tools_parallel(
  agent: erlang_agent.Agent(ctx),
  ctx: ctx,
  calls: List(Call),
) -> List(gai.Content) {
  case calls {
    [] -> []
    [single] -> [execute_single_tool(agent, ctx, single)]
    _ -> {
      let subject = process.new_subject()

      list.index_map(calls, fn(call, index) {
        process.spawn(fn() {
          let result = execute_single_tool(agent, ctx, call)
          process.send(subject, #(index, result))
        })
      })

      collect_results(subject, list.length(calls), [])
      |> list.sort(fn(a, b) { int_compare(a.0, b.0) })
      |> list.map(fn(pair) { pair.1 })
    }
  }
}

fn collect_results(
  subject: process.Subject(#(Int, gai.Content)),
  remaining: Int,
  acc: List(#(Int, gai.Content)),
) -> List(#(Int, gai.Content)) {
  case remaining {
    0 -> acc
    _ -> {
      let result = process.receive_forever(subject)
      collect_results(subject, remaining - 1, [result, ..acc])
    }
  }
}

fn int_compare(a: Int, b: Int) -> order.Order {
  case a < b {
    True -> order.Lt
    False ->
      case a > b {
        True -> order.Gt
        False -> order.Eq
      }
  }
}

fn execute_single_tool(
  agent: erlang_agent.Agent(ctx),
  ctx: ctx,
  call: Call,
) -> gai.Content {
  case erlang_agent.find_tool(agent, call.name) {
    option.None -> gai.tool_result_error(call.id, "Unknown tool: " <> call.name)
    option.Some(t) -> tool.execute(t, ctx, call.id, call.arguments_json)
  }
}

fn append_tool_results(
  messages: List(Message),
  results: List(gai.Content),
) -> List(Message) {
  list.append(messages, [gai.user(results)])
}

fn should_stop_on_tool(
  conditions: List(gai_agent.StopCondition),
  calls: List(Call),
) -> Bool {
  let called_names = list.map(calls, fn(call) { call.name })

  list.any(conditions, fn(cond) {
    case cond {
      gai_agent.HasToolCall(schema) -> list.contains(called_names, schema.name)
      gai_agent.MaxIterations(_) -> False
    }
  })
}
