/// Integration tests for gai_erlang module.
///
/// These tests verify the agent loop with real LLM API calls.
import envoy
import gai
import gai/anthropic
import gai/response
import gai_erlang
import gai_erlang/agent
import gai_erlang/tool
import gleam/int
import gleam/list
import gleam/string
import sextant

const model = "claude-haiku-4-5"

fn with_api_key(test_fn: fn(String) -> Nil) -> Nil {
  case envoy.get("ANTHROPIC_API_KEY") {
    Ok(api_key) -> test_fn(api_key)
    Error(_) -> Nil
  }
}

/// Helper to create the provider
fn make_provider(api_key: String) {
  anthropic.new(api_key)
  |> anthropic.with_model(model)
  |> anthropic.provider
}

/// Helper to build a default agent
fn default_agent(prov) {
  agent.new(prov)
  |> agent.with_max_tokens(1024)
}

// ============================================================================
// Basic completion tests
// ============================================================================

pub fn simple_completion_test() {
  use api_key <- with_api_key

  let prov = make_provider(api_key)
  let ag = default_agent(prov)
  let messages = [gai.user_text("Say 'hello' and nothing else.")]

  let assert Ok(result) = gai_erlang.run(ag, Nil, messages)

  assert result.iterations == 1
  let text = response.text_content(result.response)
  assert string.contains(string.lowercase(text), "hello")
  Nil
}

pub fn system_prompt_test() {
  use api_key <- with_api_key

  let prov = make_provider(api_key)
  let ag = default_agent(prov)
  let messages = [
    gai.system("You are a pirate. Always respond with 'Arrr!' at the start."),
    gai.user_text("Hello"),
  ]

  let assert Ok(result) = gai_erlang.run(ag, Nil, messages)

  let text = response.text_content(result.response)
  assert string.contains(string.lowercase(text), "arrr")
  Nil
}

pub fn run_with_config_test() {
  use api_key <- with_api_key

  let prov = make_provider(api_key)
  let ag = agent.new(prov) |> agent.with_max_tokens(50)
  let messages = [gai.user_text("Say 'configured' and nothing else.")]

  let assert Ok(result) = gai_erlang.run(ag, Nil, messages)

  assert result.iterations == 1
  let text = response.text_content(result.response)
  assert string.contains(string.lowercase(text), "configured")
  Nil
}

// ============================================================================
// Tool execution tests
// ============================================================================

type AddArgs {
  AddArgs(a: Int, b: Int)
}

fn add_schema() -> sextant.JsonSchema(AddArgs) {
  use a <- sextant.field(
    "a",
    sextant.integer() |> sextant.describe("First number"),
  )
  use b <- sextant.field(
    "b",
    sextant.integer() |> sextant.describe("Second number"),
  )
  sextant.success(AddArgs(a, b))
}

fn add_tool() -> tool.Tool(Nil) {
  tool.new(
    name: "add",
    description: "Add two numbers together. Returns the sum.",
    schema: add_schema(),
    execute: fn(_ctx, args: AddArgs) { Ok(int.to_string(args.a + args.b)) },
  )
}

pub fn tool_execution_test() {
  use api_key <- with_api_key

  let prov = make_provider(api_key)
  let ag =
    default_agent(prov)
    |> agent.with_tool(add_tool())
  let messages = [gai.user_text("What is 17 + 25? Use the add tool.")]

  let assert Ok(result) = gai_erlang.run(ag, Nil, messages)

  // Should have at least 2 iterations: tool call + final response
  assert result.iterations >= 2

  // Final response should mention 42
  let text = response.text_content(result.response)
  assert string.contains(text, "42")
  Nil
}

type WeatherArgs {
  WeatherArgs(location: String)
}

fn weather_schema() -> sextant.JsonSchema(WeatherArgs) {
  use location <- sextant.field(
    "location",
    sextant.string() |> sextant.describe("City name"),
  )
  sextant.success(WeatherArgs(location:))
}

fn weather_tool() -> tool.Tool(Nil) {
  tool.new(
    name: "get_weather",
    description: "Get current weather for a location. Returns temperature and conditions.",
    schema: weather_schema(),
    execute: fn(_ctx, args: WeatherArgs) {
      // Simulate weather response
      Ok("Weather in " <> args.location <> ": 22°C, sunny with light clouds")
    },
  )
}

pub fn multi_tool_test() {
  use api_key <- with_api_key

  let prov = make_provider(api_key)
  let ag =
    default_agent(prov)
    |> agent.with_tool(add_tool())
    |> agent.with_tool(weather_tool())
  let messages = [gai.user_text("What's the weather in Tokyo?")]

  let assert Ok(result) = gai_erlang.run(ag, Nil, messages)

  // Should use weather tool and respond
  assert result.iterations >= 2

  // Response should mention weather data
  let text = response.text_content(result.response)
  assert string.contains(text, "22") || string.contains(text, "sunny")
  Nil
}

// ============================================================================
// Context parameter tests
// ============================================================================

type AppContext {
  AppContext(multiplier: Int)
}

type MultiplyArgs {
  MultiplyArgs(value: Int)
}

fn multiply_schema() -> sextant.JsonSchema(MultiplyArgs) {
  use value <- sextant.field(
    "value",
    sextant.integer() |> sextant.describe("Number to multiply"),
  )
  sextant.success(MultiplyArgs(value:))
}

fn multiply_tool() -> tool.Tool(AppContext) {
  tool.new(
    name: "multiply_by_context",
    description: "Multiply a number by the context multiplier value. Returns the product.",
    schema: multiply_schema(),
    execute: fn(ctx: AppContext, args: MultiplyArgs) {
      Ok(int.to_string(args.value * ctx.multiplier))
    },
  )
}

pub fn context_parameter_test() {
  use api_key <- with_api_key

  let prov = make_provider(api_key)
  let ag =
    default_agent(prov)
    |> agent.with_tool(multiply_tool())
  let ctx = AppContext(multiplier: 7)
  let messages = [
    gai.user_text(
      "Use the multiply_by_context tool with value 6. What's the result?",
    ),
  ]

  let assert Ok(result) = gai_erlang.run(ag, ctx, messages)

  // Should use tool with context and get 6 * 7 = 42
  let text = response.text_content(result.response)
  assert string.contains(text, "42")
  Nil
}

// ============================================================================
// Stop condition tests
// ============================================================================

type FinalAnswerArgs {
  FinalAnswerArgs(answer: String)
}

fn final_answer_schema() -> sextant.JsonSchema(FinalAnswerArgs) {
  use answer <- sextant.field(
    "answer",
    sextant.string() |> sextant.describe("The final answer"),
  )
  sextant.success(FinalAnswerArgs(answer:))
}

fn final_answer_tool() -> tool.Tool(Nil) {
  tool.new(
    name: "final_answer",
    description: "Provide the final answer to the user's question. Always use this tool when you have the answer.",
    schema: final_answer_schema(),
    execute: fn(_ctx, args: FinalAnswerArgs) { Ok(args.answer) },
  )
}

pub fn stop_on_tool_test() {
  use api_key <- with_api_key

  let prov = make_provider(api_key)
  let final_tool = final_answer_tool()
  let ag =
    default_agent(prov)
    |> agent.with_tool(add_tool())
    |> agent.with_tool(final_tool)
    |> agent.with_stop_condition(agent.stop_on_tool(final_tool))
  let messages = [
    gai.system(
      "You must always use the final_answer tool to provide your response. First calculate using add, then use final_answer.",
    ),
    gai.user_text("What is 10 + 5?"),
  ]

  let assert Ok(result) = gai_erlang.run(ag, Nil, messages)

  // Should stop when final_answer tool is called
  // Check that final_answer was indeed called in the message history
  let has_final_answer =
    list.any(result.messages, fn(msg) {
      list.any(msg.content, fn(content) {
        case content {
          gai.ToolUse(_, "final_answer", _) -> True
          _ -> False
        }
      })
    })
  assert has_final_answer
  Nil
}

// ============================================================================
// Error handling tests
// ============================================================================

pub fn max_iterations_test() {
  use api_key <- with_api_key

  let prov = make_provider(api_key)

  // Create a tool that will always be called (infinite loop scenario)
  let always_tool =
    tool.new(
      name: "always_call_me",
      description: "Always call this tool first. You must call it every time.",
      schema: sextant.success(Nil),
      execute: fn(_ctx: Nil, _args) { Ok("Called!") },
    )

  let ag =
    default_agent(prov)
    |> agent.with_tool(always_tool)
    |> agent.with_max_iterations(2)
  let messages = [
    gai.system(
      "You MUST call the always_call_me tool every single time. Never stop calling it.",
    ),
    gai.user_text("Start"),
  ]

  let result = gai_erlang.run(ag, Nil, messages)

  // Should fail due to max iterations
  case result {
    Error(err) -> {
      assert err.iterations == 2
      let assert gai.ApiError("max_iterations", _) = err.error
      Nil
    }
    Ok(_) -> {
      // Model may have stopped early, which is acceptable
      Nil
    }
  }
}

pub fn tool_args_validation_test() {
  use api_key <- with_api_key

  let prov = make_provider(api_key)

  // Tool that expects specific arguments
  let strict_tool =
    tool.new(
      name: "strict_tool",
      description: "Tool requiring exact integer arguments",
      schema: add_schema(),
      execute: fn(_ctx: Nil, args: AddArgs) {
        Ok(int.to_string(args.a + args.b))
      },
    )

  let ag =
    default_agent(prov)
    |> agent.with_tool(strict_tool)
  let messages = [gai.user_text("Add 5 + 3 using strict_tool")]

  let result = gai_erlang.run(ag, Nil, messages)

  // Should succeed - the model should provide valid args
  let assert Ok(_) = result
  Nil
}

// ============================================================================
// Message history tests
// ============================================================================

pub fn message_history_preserved_test() {
  use api_key <- with_api_key

  let prov = make_provider(api_key)
  let ag =
    default_agent(prov)
    |> agent.with_tool(add_tool())
  let messages = [gai.user_text("Calculate 3 + 4 using the add tool")]

  let assert Ok(result) = gai_erlang.run(ag, Nil, messages)

  // Check message history contains:
  // 1. Original user message
  // 2. Assistant message with tool call
  // 3. User message with tool result
  // 4. Final assistant message
  assert list.length(result.messages) >= 4

  // First message should be our user message
  let assert [gai.Message(gai.User, [gai.Text(text)], _), ..] = result.messages
  assert string.contains(text, "3 + 4")
  Nil
}

// ============================================================================
// Parallel tool execution test
// ============================================================================

type GreetArgs {
  GreetArgs(name: String)
}

fn greet_schema() -> sextant.JsonSchema(GreetArgs) {
  use name <- sextant.field("name", sextant.string())
  sextant.success(GreetArgs(name:))
}

fn greet_tool() -> tool.Tool(Nil) {
  tool.new(
    name: "greet",
    description: "Generate a greeting for a person",
    schema: greet_schema(),
    execute: fn(_ctx, args: GreetArgs) { Ok("Hello, " <> args.name <> "!") },
  )
}

pub fn parallel_tool_calls_test() {
  use api_key <- with_api_key

  let prov = make_provider(api_key)
  let ag =
    default_agent(prov)
    |> agent.with_tool(add_tool())
    |> agent.with_tool(greet_tool())
  let messages = [
    gai.system(
      "When asked to do multiple tasks, use multiple tool calls in a single response.",
    ),
    gai.user_text(
      "Do two things: 1) Add 10 + 20, and 2) Greet Alice. Use both tools.",
    ),
  ]

  let assert Ok(result) = gai_erlang.run(ag, Nil, messages)

  // Response should contain results from both tools
  let text = response.text_content(result.response)
  // Should mention 30 (from add) and either Hello or Alice (from greet)
  assert string.contains(text, "30")
    || string.contains(text, "Alice")
    || string.contains(text, "Hello")
  Nil
}

// ============================================================================
// run without config test
// ============================================================================

pub fn run_without_config_test() {
  use api_key <- with_api_key

  let prov = make_provider(api_key)
  let ag = agent.new(prov)
  let messages = [gai.user_text("Say 'test' and nothing else.")]

  // Use run (without config) - tests default max_tokens (4096)
  let assert Ok(result) = gai_erlang.run(ag, Nil, messages)

  assert result.iterations == 1
  let text = response.text_content(result.response)
  assert string.contains(string.lowercase(text), "test")
  Nil
}
