import gai
import gai/usage
import gleam/option.{None, Some}

fn test_usage(input: Int, output: Int) -> gai.Usage {
  gai.Usage(
    input_tokens: input,
    output_tokens: output,
    cache_creation_input_tokens: None,
    cache_read_input_tokens: None,
  )
}

pub fn new_starts_at_zero_test() {
  let conv = usage.new()
  usage.input_tokens(conv) |> should_equal(0)
  usage.output_tokens(conv) |> should_equal(0)
  usage.total_tokens(conv) |> should_equal(0)
  usage.turns(conv) |> should_equal(0)
}

pub fn add_accumulates_tokens_test() {
  let conv =
    usage.new()
    |> usage.add(test_usage(100, 50))

  usage.input_tokens(conv) |> should_equal(100)
  usage.output_tokens(conv) |> should_equal(50)
  usage.total_tokens(conv) |> should_equal(150)
  usage.turns(conv) |> should_equal(1)
}

pub fn add_multiple_accumulates_test() {
  let conv =
    usage.new()
    |> usage.add(test_usage(100, 50))
    |> usage.add(test_usage(200, 75))
    |> usage.add(test_usage(50, 25))

  usage.input_tokens(conv) |> should_equal(350)
  usage.output_tokens(conv) |> should_equal(150)
  usage.total_tokens(conv) |> should_equal(500)
  usage.turns(conv) |> should_equal(3)
}

pub fn getters_return_correct_values_test() {
  let conv =
    usage.new()
    |> usage.add(test_usage(1000, 500))

  // Verify each getter individually
  assert usage.input_tokens(conv) == 1000
  assert usage.output_tokens(conv) == 500
  assert usage.total_tokens(conv) == 1500
  assert usage.turns(conv) == 1
}

// ============================================================================
// Context limit tests
// ============================================================================

pub fn context_limit_openai_gpt4o_test() {
  usage.context_limit("openai", "gpt-4o") |> should_equal(Some(128_000))
  usage.context_limit("openai", "gpt-4o-2024-08-06")
  |> should_equal(Some(128_000))
}

pub fn context_limit_anthropic_claude_test() {
  usage.context_limit("anthropic", "claude-3-5-sonnet-20241022")
  |> should_equal(Some(200_000))
}

pub fn context_limit_google_gemini_test() {
  usage.context_limit("google", "gemini-1.5-pro")
  |> should_equal(Some(2_000_000))
  usage.context_limit("google", "gemini-2.0-flash")
  |> should_equal(Some(1_000_000))
}

pub fn context_limit_unknown_model_test() {
  usage.context_limit("openai", "unknown-model") |> should_equal(None)
  usage.context_limit("unknown-provider", "gpt-4o") |> should_equal(None)
}

pub fn context_limit_case_insensitive_test() {
  usage.context_limit("OpenAI", "gpt-4o") |> should_equal(Some(128_000))
  usage.context_limit("ANTHROPIC", "claude-3-5-sonnet")
  |> should_equal(Some(200_000))
}

pub fn output_limit_openai_test() {
  usage.output_limit("openai", "gpt-4o") |> should_equal(Some(16_000))
  usage.output_limit("openai", "gpt-4-turbo") |> should_equal(Some(4000))
}

pub fn output_limit_anthropic_test() {
  usage.output_limit("anthropic", "claude-3-5-sonnet")
  |> should_equal(Some(8000))
  usage.output_limit("anthropic", "claude-3-opus") |> should_equal(Some(4000))
}

pub fn output_limit_google_test() {
  usage.output_limit("google", "gemini-1.5-pro") |> should_equal(Some(8000))
}

pub fn output_limit_unknown_test() {
  usage.output_limit("openai", "unknown") |> should_equal(None)
}

// Helper for assertions
fn should_equal(actual: a, expected: a) -> Nil {
  assert actual == expected
}
