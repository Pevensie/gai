/// Retry configuration for handling transient API failures.
///
/// Provides configurable retry behaviour with exponential backoff.
/// This module only provides configuration - actual retry execution
/// is the caller's responsibility (gai is transport-agnostic).
import gai.{
  type Error, ApiError, AuthError, HttpError, JsonError, ParseError, RateLimited,
}
import gleam/float
import gleam/int
import gleam/option

/// Configuration for retry behaviour with exponential backoff.
pub opaque type RetryConfig {
  RetryConfig(
    max_attempts: Int,
    initial_delay_ms: Int,
    max_delay_ms: Int,
    multiplier: Float,
  )
}

/// Create a RetryConfig with sensible defaults.
/// max_attempts=3, initial_delay_ms=1000, max_delay_ms=60000, multiplier=2.0
pub fn default() -> RetryConfig {
  RetryConfig(
    max_attempts: 3,
    initial_delay_ms: 1000,
    max_delay_ms: 60_000,
    multiplier: 2.0,
  )
}

/// Set the maximum number of retry attempts.
pub fn with_max_attempts(config: RetryConfig, n: Int) -> RetryConfig {
  RetryConfig(..config, max_attempts: n)
}

/// Set the initial delay in milliseconds.
pub fn with_initial_delay(config: RetryConfig, ms: Int) -> RetryConfig {
  RetryConfig(..config, initial_delay_ms: ms)
}

/// Set the maximum delay in milliseconds.
pub fn with_max_delay(config: RetryConfig, ms: Int) -> RetryConfig {
  RetryConfig(..config, max_delay_ms: ms)
}

/// Set the backoff multiplier.
pub fn with_multiplier(config: RetryConfig, m: Float) -> RetryConfig {
  RetryConfig(..config, multiplier: m)
}

/// Get the maximum number of attempts.
pub fn max_attempts(config: RetryConfig) -> Int {
  config.max_attempts
}

/// Get the initial delay in milliseconds.
pub fn initial_delay(config: RetryConfig) -> Int {
  config.initial_delay_ms
}

/// Get the maximum delay in milliseconds.
pub fn max_delay(config: RetryConfig) -> Int {
  config.max_delay_ms
}

/// Get the backoff multiplier.
pub fn multiplier(config: RetryConfig) -> Float {
  config.multiplier
}

// ============================================================================
// Retry Predicate
// ============================================================================

/// Determine if an error should be retried.
/// Returns True for transient errors (rate limits, server errors).
/// Returns False for permanent errors (auth, parse, client errors).
pub fn should_retry(error: Error) -> Bool {
  case error {
    // Rate limits are always retryable
    RateLimited(_) -> True

    // Server errors are transient
    HttpError(status: status, body: _) -> is_retryable_status(status)

    // These errors won't be fixed by retrying
    ApiError(_, _) -> False
    AuthError(_) -> False
    ParseError(_) -> False
    JsonError(_) -> False
  }
}

fn is_retryable_status(status: Int) -> Bool {
  case status {
    // Request timeout
    408 -> True
    // Rate limit
    429 -> True
    // Internal server error
    500 -> True
    // Bad gateway
    502 -> True
    // Service unavailable
    503 -> True
    // Gateway timeout
    504 -> True
    _ -> False
  }
}

// ============================================================================
// Delay Calculation
// ============================================================================

/// Calculate delay for a given attempt number (0-indexed).
/// Uses exponential backoff: initial_delay_ms * (multiplier ^ attempt)
/// Result is capped at max_delay_ms.
pub fn delay_ms(config: RetryConfig, attempt: Int) -> Int {
  let base = int.to_float(config.initial_delay_ms)
  let exponent = int.to_float(attempt)

  let result = case float.power(config.multiplier, exponent) {
    Ok(factor) -> base *. factor
    Error(_) -> base
  }

  let delay = float.truncate(result)
  int.min(delay, config.max_delay_ms)
}

/// Calculate delay for an error, respecting rate limit retry_after.
/// For RateLimited errors with retry_after, returns max(calculated_delay, retry_after * 1000).
/// For other errors, returns the calculated delay.
pub fn delay_for_error_ms(
  config: RetryConfig,
  attempt: Int,
  error: Error,
) -> Int {
  let base_delay = delay_ms(config, attempt)

  case error {
    RateLimited(retry_after) ->
      case retry_after {
        option.Some(seconds) -> int.max(base_delay, seconds * 1000)
        option.None -> base_delay
      }
    _ -> base_delay
  }
}

/// Add jitter to a delay value.
/// The jitter_amount should be a random value between 0 and max_jitter_ms.
/// This is a pure function - caller provides the random jitter amount.
///
/// Example usage with random:
///   let jitter = random.int(0, delay_ms * max_jitter_percent / 100)
///   let final_delay = add_jitter(delay_ms, jitter)
pub fn add_jitter(delay_ms: Int, jitter_amount: Int) -> Int {
  delay_ms + jitter_amount
}
