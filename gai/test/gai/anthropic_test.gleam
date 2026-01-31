import gai
import gai/anthropic
import gai/request
import gai/response
import gleam/dynamic.{type Dynamic}
import gleam/dynamic/decode
import gleam/http
import gleam/http/request as http_request
import gleam/http/response as http_response
import gleam/json
import gleam/option
import gleam/result

fn test_usage(input: Int, output: Int) -> gai.Usage {
  gai.Usage(
    input_tokens: input,
    output_tokens: output,
    cache_creation_input_tokens: option.None,
    cache_read_input_tokens: option.None,
  )
}

// JSON field helpers for tests
fn get_string(data: Dynamic, field: String) -> Result(String, Nil) {
  let decoder = {
    use value <- decode.field(field, decode.string)
    decode.success(value)
  }
  decode.run(data, decoder) |> result.replace_error(Nil)
}

fn get_int(data: Dynamic, field: String) -> Result(Int, Nil) {
  let decoder = {
    use value <- decode.field(field, decode.int)
    decode.success(value)
  }
  decode.run(data, decoder) |> result.replace_error(Nil)
}

fn get_list(data: Dynamic, field: String) -> Result(List(Dynamic), Nil) {
  let decoder = {
    use value <- decode.field(field, decode.list(decode.dynamic))
    decode.success(value)
  }
  decode.run(data, decoder) |> result.replace_error(Nil)
}

fn get_dynamic(data: Dynamic, field: String) -> Result(Dynamic, Nil) {
  let decoder = {
    use value <- decode.field(field, decode.dynamic)
    decode.success(value)
  }
  decode.run(data, decoder) |> result.replace_error(Nil)
}

// Config tests

pub fn new_config_test() {
  let config = anthropic.new("sk-ant-test")
  let req = request.new("claude-3-opus-20240229", [gai.user_text("Hi")])
  let http_req = anthropic.build_request(config, req)

  let assert Ok("sk-ant-test") = http_request.get_header(http_req, "x-api-key")
  let assert Ok("2023-06-01") =
    http_request.get_header(http_req, "anthropic-version")
}

pub fn with_base_url_test() {
  let config =
    anthropic.new("sk-ant-test")
    |> anthropic.with_base_url("https://my-proxy.com/v1")

  let req = request.new("claude-3-opus-20240229", [gai.user_text("Hi")])
  let http_req = anthropic.build_request(config, req)

  let assert http_request.Request(
    host: "my-proxy.com",
    path: "/v1/messages",
    ..,
  ) = http_req
}

pub fn with_version_test() {
  let config =
    anthropic.new("sk-ant-test")
    |> anthropic.with_version("2024-01-01")

  let req = request.new("claude-3-opus-20240229", [gai.user_text("Hi")])
  let http_req = anthropic.build_request(config, req)

  let assert Ok("2024-01-01") =
    http_request.get_header(http_req, "anthropic-version")
}

// build_request tests

pub fn build_request_method_and_headers_test() {
  let config = anthropic.new("sk-ant-test")
  let req = request.new("claude-3-opus-20240229", [gai.user_text("Hello")])
  let http_req = anthropic.build_request(config, req)

  let assert http_request.Request(method: http.Post, ..) = http_req
  let assert Ok("application/json") =
    http_request.get_header(http_req, "content-type")
}

pub fn build_request_simple_message_test() {
  let config = anthropic.new("sk-ant-test")
  let req =
    request.new("claude-3-opus-20240229", [
      gai.user_text("What is 2+2?"),
    ])

  let http_req = anthropic.build_request(config, req)

  let assert Ok(body) = json.parse(http_req.body, decode.dynamic)
  let assert Ok("claude-3-opus-20240229") = get_string(body, "model")
  let assert Ok(messages) = get_list(body, "messages")
  let assert [user_msg] = messages

  let assert Ok("user") = get_string(user_msg, "role")
}

pub fn build_request_system_message_test() {
  let config = anthropic.new("sk-ant-test")
  let req =
    request.new("claude-3-opus-20240229", [
      gai.system("You are helpful."),
      gai.user_text("Hi"),
    ])

  let http_req = anthropic.build_request(config, req)

  let assert Ok(body) = json.parse(http_req.body, decode.dynamic)
  // System message should be extracted to top-level "system" field
  let assert Ok("You are helpful.") = get_string(body, "system")
  // Messages should not contain the system message
  let assert Ok(messages) = get_list(body, "messages")
  let assert [user_msg] = messages
  let assert Ok("user") = get_string(user_msg, "role")
}

pub fn build_request_cached_system_message_test() {
  let config = anthropic.new("sk-ant-test")
  let req =
    request.new("claude-3-opus-20240229", [
      gai.cached_system("You are helpful."),
      gai.user_text("Hi"),
    ])

  let http_req = anthropic.build_request(config, req)

  let assert Ok(body) = json.parse(http_req.body, decode.dynamic)
  // Should be an array with cache_control on last block
  let assert Ok(system) = get_list(body, "system")
  let assert [block] = system
  let assert Ok("text") = get_string(block, "type")
  let assert Ok("You are helpful.") = get_string(block, "text")
  let assert Ok(cache) = get_dynamic(block, "cache_control")
  let assert Ok("ephemeral") = get_string(cache, "type")
}

pub fn build_request_with_max_tokens_test() {
  let config = anthropic.new("sk-ant-test")
  let req =
    request.new("claude-3-opus-20240229", [gai.user_text("Hi")])
    |> request.with_max_tokens(100)

  let http_req = anthropic.build_request(config, req)
  let assert Ok(body) = json.parse(http_req.body, decode.dynamic)

  let assert Ok(100) = get_int(body, "max_tokens")
}

// parse_response tests

pub fn parse_response_success_test() {
  let json_body =
    "{
    \"id\": \"msg_123\",
    \"model\": \"claude-3-opus-20240229\",
    \"type\": \"message\",
    \"role\": \"assistant\",
    \"content\": [{\"type\": \"text\", \"text\": \"4\"}],
    \"stop_reason\": \"end_turn\",
    \"usage\": {
      \"input_tokens\": 10,
      \"output_tokens\": 1
    }
  }"

  let http_resp =
    http_response.new(200)
    |> http_response.set_body(json_body)

  let assert Ok(resp) = anthropic.parse_response(http_resp)
  let assert response.CompletionResponse(
    id: "msg_123",
    model: "claude-3-opus-20240229",
    content: [gai.Text("4")],
    stop_reason: gai.EndTurn,
    usage: gai.Usage(input_tokens: 10, output_tokens: 1, ..),
  ) = resp
}

pub fn parse_response_max_tokens_test() {
  let json_body =
    "{
    \"id\": \"msg_123\",
    \"model\": \"claude-3-opus-20240229\",
    \"content\": [{\"type\": \"text\", \"text\": \"partial...\"}],
    \"stop_reason\": \"max_tokens\",
    \"usage\": {\"input_tokens\": 10, \"output_tokens\": 100}
  }"

  let http_resp =
    http_response.new(200)
    |> http_response.set_body(json_body)

  let assert Ok(resp) = anthropic.parse_response(http_resp)
  let assert response.CompletionResponse(stop_reason: gai.MaxTokens, ..) = resp
}

pub fn parse_response_tool_use_test() {
  let json_body =
    "{
    \"id\": \"msg_123\",
    \"model\": \"claude-3-opus-20240229\",
    \"content\": [
      {\"type\": \"text\", \"text\": \"Let me check the weather.\"},
      {
        \"type\": \"tool_use\",
        \"id\": \"toolu_123\",
        \"name\": \"get_weather\",
        \"input\": {\"location\": \"London\"}
      }
    ],
    \"stop_reason\": \"tool_use\",
    \"usage\": {\"input_tokens\": 20, \"output_tokens\": 15}
  }"

  let http_resp =
    http_response.new(200)
    |> http_response.set_body(json_body)

  let assert Ok(resp) = anthropic.parse_response(http_resp)
  let assert response.CompletionResponse(stop_reason: gai.ToolUsed, ..) = resp
  assert response.has_tool_calls(resp)

  let calls = response.tool_calls(resp)
  let assert [gai.ToolUse(id: "toolu_123", name: "get_weather", ..)] = calls
}

pub fn parse_response_auth_error_test() {
  let json_body =
    "{
    \"type\": \"error\",
    \"error\": {
      \"type\": \"authentication_error\",
      \"message\": \"Invalid API key\"
    }
  }"

  let http_resp =
    http_response.new(401)
    |> http_response.set_body(json_body)

  let assert Error(gai.AuthError(message: "Invalid API key")) =
    anthropic.parse_response(http_resp)
}

pub fn parse_response_api_error_test() {
  let json_body =
    "{
    \"type\": \"error\",
    \"error\": {
      \"type\": \"invalid_request_error\",
      \"message\": \"Invalid model\"
    }
  }"

  let http_resp =
    http_response.new(400)
    |> http_response.set_body(json_body)

  let assert Error(gai.ApiError(
    code: "invalid_request_error",
    message: "Invalid model",
  )) = anthropic.parse_response(http_resp)
}

pub fn parse_response_rate_limited_test() {
  let json_body =
    "{
    \"type\": \"error\",
    \"error\": {
      \"type\": \"rate_limit_error\",
      \"message\": \"Rate limit exceeded\"
    }
  }"

  let http_resp =
    http_response.new(429)
    |> http_response.set_body(json_body)
    |> http_response.set_header("retry-after", "30")

  let assert Error(gai.RateLimited(retry_after: option.Some(30))) =
    anthropic.parse_response(http_resp)
}

pub fn parse_response_cache_usage_test() {
  let json_body =
    "{
    \"id\": \"msg_123\",
    \"model\": \"claude-3-5-sonnet-20241022\",
    \"content\": [{\"type\": \"text\", \"text\": \"Hello\"}],
    \"stop_reason\": \"end_turn\",
    \"usage\": {
      \"input_tokens\": 100,
      \"output_tokens\": 50,
      \"cache_creation_input_tokens\": 500,
      \"cache_read_input_tokens\": 1000
    }
  }"

  let http_resp =
    http_response.new(200)
    |> http_response.set_body(json_body)

  let assert Ok(resp) = anthropic.parse_response(http_resp)
  let assert 1000 = gai.cache_read_tokens(resp.usage)
  let assert 500 = gai.cache_creation_tokens(resp.usage)
  let assert option.Some(rate) = gai.cache_hit_rate(resp.usage)
  // 1000 / (1000 + 500) = 0.6667
  assert rate >. 0.66 && rate <. 0.67
}

pub fn parse_response_no_cache_usage_test() {
  let json_body =
    "{
    \"id\": \"msg_123\",
    \"model\": \"claude-3-5-sonnet-20241022\",
    \"content\": [{\"type\": \"text\", \"text\": \"Hello\"}],
    \"stop_reason\": \"end_turn\",
    \"usage\": {
      \"input_tokens\": 100,
      \"output_tokens\": 50
    }
  }"

  let http_resp =
    http_response.new(200)
    |> http_response.set_body(json_body)

  let assert Ok(resp) = anthropic.parse_response(http_resp)
  let assert 0 = gai.cache_read_tokens(resp.usage)
  let assert 0 = gai.cache_creation_tokens(resp.usage)
  let assert option.None = gai.cache_hit_rate(resp.usage)
}

// Provider constructor test

pub fn provider_test() {
  let config = anthropic.new("sk-ant-test")
  let provider = anthropic.provider(config)

  let assert "anthropic" = provider.name
}

// Extended thinking tests

pub fn with_thinking_includes_thinking_config_test() {
  let config = anthropic.new("sk-ant-test") |> anthropic.with_thinking(10_000)
  let req =
    request.new("claude-3-5-sonnet-20241022", [gai.user_text("Think hard")])
  let http_req = anthropic.build_request(config, req)

  let assert Ok(body) = json.parse(http_req.body, decode.dynamic)
  let assert Ok(thinking) = get_dynamic(body, "thinking")
  let assert Ok("enabled") = get_string(thinking, "type")
  let assert Ok(10_000) = get_int(thinking, "budget_tokens")
}

pub fn with_thinking_includes_beta_header_test() {
  let config = anthropic.new("sk-ant-test") |> anthropic.with_thinking(5000)
  let req = request.new("claude-3-5-sonnet-20241022", [gai.user_text("Think")])
  let http_req = anthropic.build_request(config, req)

  let assert Ok("interleaved-thinking-2025-05-14") =
    http_request.get_header(http_req, "anthropic-beta")
}

pub fn without_thinking_no_thinking_config_test() {
  let config = anthropic.new("sk-ant-test")
  let req = request.new("claude-3-5-sonnet-20241022", [gai.user_text("Normal")])
  let http_req = anthropic.build_request(config, req)

  let assert Ok(body) = json.parse(http_req.body, decode.dynamic)
  // Thinking field should not be present
  let assert Error(_) = get_dynamic(body, "thinking")
}

pub fn without_thinking_no_beta_header_test() {
  let config = anthropic.new("sk-ant-test")
  let req = request.new("claude-3-5-sonnet-20241022", [gai.user_text("Normal")])
  let http_req = anthropic.build_request(config, req)

  // No beta header without special features
  let assert Error(_) = http_request.get_header(http_req, "anthropic-beta")
}

// Extended thinking response parsing tests

pub fn parse_response_with_thinking_test() {
  let json_body =
    "{
    \"id\": \"msg_123\",
    \"model\": \"claude-3-5-sonnet-20241022\",
    \"content\": [
      {\"type\": \"thinking\", \"thinking\": \"Let me think about this...\"},
      {\"type\": \"text\", \"text\": \"The answer is 4.\"}
    ],
    \"stop_reason\": \"end_turn\",
    \"usage\": {\"input_tokens\": 10, \"output_tokens\": 20}
  }"

  let http_resp =
    http_response.new(200)
    |> http_response.set_body(json_body)

  let assert Ok(resp) = anthropic.parse_response(http_resp)

  // Should have both thinking and text content
  let assert [
    gai.Thinking("Let me think about this..."),
    gai.Text("The answer is 4."),
  ] = resp.content

  // text_content should exclude thinking
  let assert "The answer is 4." = response.text_content(resp)

  // thinking_content should extract thinking
  let assert option.Some("Let me think about this...") =
    response.thinking_content(resp)

  // has_thinking should return True
  assert response.has_thinking(resp)
}

pub fn append_response_excludes_thinking_test() {
  let messages = [gai.user_text("What is 2+2?")]
  let resp =
    response.CompletionResponse(
      id: "msg_123",
      model: "claude-3-5-sonnet-20241022",
      content: [gai.Thinking("Calculating..."), gai.Text("4")],
      stop_reason: gai.EndTurn,
      usage: test_usage(10, 5),
    )

  let result = response.append_response(messages, resp)

  // The assistant message should NOT contain thinking
  let assert [
    gai.Message(role: gai.User, ..),
    gai.Message(role: gai.Assistant, content: [gai.Text("4")], ..),
  ] = result
}

// Port handling tests

pub fn with_base_url_port_test() {
  let config =
    anthropic.new("sk-ant-test")
    |> anthropic.with_base_url("http://localhost:8080/v1")

  let req = request.new("claude-3-opus-20240229", [gai.user_text("Hi")])
  let http_req = anthropic.build_request(config, req)

  let assert http_request.Request(
    host: "localhost",
    port: option.Some(8080),
    scheme: http.Http,
    path: "/v1/messages",
    ..,
  ) = http_req
}

pub fn with_base_url_no_port_test() {
  let config =
    anthropic.new("sk-ant-test")
    |> anthropic.with_base_url("https://api.anthropic.com/v1")

  let req = request.new("claude-3-opus-20240229", [gai.user_text("Hi")])
  let http_req = anthropic.build_request(config, req)

  let assert http_request.Request(
    host: "api.anthropic.com",
    port: option.None,
    scheme: http.Https,
    path: "/v1/messages",
    ..,
  ) = http_req
}
