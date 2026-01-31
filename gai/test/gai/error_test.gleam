import gai
import gleam/option
import gleeunit/should

pub fn http_error_to_string_test() {
  gai.HttpError(status: 500, body: "Internal Server Error")
  |> gai.error_to_string
  |> should.equal("HTTP error 500: Internal Server Error")
}

pub fn json_error_to_string_test() {
  gai.JsonError(message: "Expected object, got array")
  |> gai.error_to_string
  |> should.equal("JSON error: Expected object, got array")
}

pub fn api_error_to_string_test() {
  gai.ApiError(code: "invalid_api_key", message: "Invalid API key provided")
  |> gai.error_to_string
  |> should.equal("API error (invalid_api_key): Invalid API key provided")
}

pub fn parse_error_to_string_test() {
  gai.ParseError(message: "Missing 'content' field")
  |> gai.error_to_string
  |> should.equal("Parse error: Missing 'content' field")
}

pub fn rate_limited_with_retry_test() {
  gai.RateLimited(retry_after: option.Some(30))
  |> gai.error_to_string
  |> should.equal("Rate limited, retry after 30 seconds")
}

pub fn rate_limited_without_retry_test() {
  gai.RateLimited(retry_after: option.None)
  |> gai.error_to_string
  |> should.equal("Rate limited")
}

pub fn auth_error_to_string_test() {
  gai.AuthError(message: "Invalid credentials")
  |> gai.error_to_string
  |> should.equal("Authentication error: Invalid credentials")
}
