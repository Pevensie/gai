import gai
import gai/retry
import gleam/option.{None, Some}

pub fn default_values_test() {
  let config = retry.default()
  let assert 3 = retry.max_attempts(config)
  let assert 1000 = retry.initial_delay(config)
  let assert 60_000 = retry.max_delay(config)
  let assert 2.0 = retry.multiplier(config)
}

pub fn with_max_attempts_test() {
  let config = retry.default() |> retry.with_max_attempts(5)
  let assert 5 = retry.max_attempts(config)
  // Other values unchanged
  let assert 1000 = retry.initial_delay(config)
}

pub fn with_initial_delay_test() {
  let config = retry.default() |> retry.with_initial_delay(500)
  let assert 500 = retry.initial_delay(config)
}

pub fn with_max_delay_test() {
  let config = retry.default() |> retry.with_max_delay(120_000)
  let assert 120_000 = retry.max_delay(config)
}

pub fn with_multiplier_test() {
  let config = retry.default() |> retry.with_multiplier(1.5)
  let assert 1.5 = retry.multiplier(config)
}

pub fn builders_chainable_test() {
  let config =
    retry.default()
    |> retry.with_max_attempts(5)
    |> retry.with_initial_delay(500)
    |> retry.with_max_delay(30_000)
    |> retry.with_multiplier(3.0)

  let assert 5 = retry.max_attempts(config)
  let assert 500 = retry.initial_delay(config)
  let assert 30_000 = retry.max_delay(config)
  let assert 3.0 = retry.multiplier(config)
}

// ============================================================================
// should_retry tests
// ============================================================================

pub fn should_retry_rate_limited_test() {
  assert retry.should_retry(gai.RateLimited(Some(30)))
  assert retry.should_retry(gai.RateLimited(None))
}

pub fn should_retry_http_429_test() {
  assert retry.should_retry(gai.HttpError(status: 429, body: ""))
}

pub fn should_retry_http_server_errors_test() {
  assert retry.should_retry(gai.HttpError(status: 500, body: ""))
  assert retry.should_retry(gai.HttpError(status: 502, body: ""))
  assert retry.should_retry(gai.HttpError(status: 503, body: ""))
  assert retry.should_retry(gai.HttpError(status: 504, body: ""))
}

pub fn should_retry_http_408_timeout_test() {
  assert retry.should_retry(gai.HttpError(status: 408, body: ""))
}

pub fn should_not_retry_api_error_test() {
  let assert False =
    retry.should_retry(gai.ApiError(code: "invalid_request", message: "Bad"))
}

pub fn should_not_retry_auth_error_test() {
  let assert False = retry.should_retry(gai.AuthError("Invalid API key"))
}

pub fn should_not_retry_parse_error_test() {
  let assert False = retry.should_retry(gai.ParseError("Unexpected format"))
}

pub fn should_not_retry_json_error_test() {
  let assert False = retry.should_retry(gai.JsonError("Invalid JSON"))
}

pub fn should_not_retry_http_4xx_test() {
  let assert False = retry.should_retry(gai.HttpError(status: 400, body: ""))
  let assert False = retry.should_retry(gai.HttpError(status: 401, body: ""))
  let assert False = retry.should_retry(gai.HttpError(status: 403, body: ""))
  let assert False = retry.should_retry(gai.HttpError(status: 404, body: ""))
}

// ============================================================================
// delay_ms tests
// ============================================================================

pub fn delay_ms_attempt_0_test() {
  let config = retry.default()
  // Attempt 0: 1000 * 2^0 = 1000
  let assert 1000 = retry.delay_ms(config, 0)
}

pub fn delay_ms_attempt_1_test() {
  let config = retry.default()
  // Attempt 1: 1000 * 2^1 = 2000
  let assert 2000 = retry.delay_ms(config, 1)
}

pub fn delay_ms_attempt_2_test() {
  let config = retry.default()
  // Attempt 2: 1000 * 2^2 = 4000
  let assert 4000 = retry.delay_ms(config, 2)
}

pub fn delay_ms_capped_at_max_test() {
  let config = retry.default() |> retry.with_max_delay(5000)
  // Attempt 3: 1000 * 2^3 = 8000, but capped at 5000
  let assert 5000 = retry.delay_ms(config, 3)
}

pub fn delay_ms_custom_multiplier_test() {
  let config = retry.default() |> retry.with_multiplier(3.0)
  // Attempt 2: 1000 * 3^2 = 9000
  let assert 9000 = retry.delay_ms(config, 2)
}

// ============================================================================
// delay_for_error_ms tests
// ============================================================================

pub fn delay_for_error_rate_limited_with_retry_after_test() {
  let config = retry.default()
  let error = gai.RateLimited(Some(120))
  // Base delay for attempt 0 = 1000ms
  // retry_after = 120 seconds = 120000ms
  // Should return max(1000, 120000) = 120000
  let assert 120_000 = retry.delay_for_error_ms(config, 0, error)
}

pub fn delay_for_error_rate_limited_without_retry_after_test() {
  let config = retry.default()
  let error = gai.RateLimited(None)
  // Should return base delay
  let assert 1000 = retry.delay_for_error_ms(config, 0, error)
}

pub fn delay_for_error_other_error_test() {
  let config = retry.default()
  let error = gai.HttpError(status: 500, body: "")
  // Should return base delay for attempt 1 = 2000
  let assert 2000 = retry.delay_for_error_ms(config, 1, error)
}

// ============================================================================
// add_jitter tests
// ============================================================================

pub fn add_jitter_test() {
  let assert 1100 = retry.add_jitter(1000, 100)
  let assert 1000 = retry.add_jitter(1000, 0)
}
