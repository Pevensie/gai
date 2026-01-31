import gai
import gai/openai
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

fn get_float(data: Dynamic, field: String) -> Result(Float, Nil) {
  let decoder = {
    use value <- decode.field(field, decode.float)
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

fn get_list(data: Dynamic, field: String) -> Result(List(Dynamic), Nil) {
  let decoder = {
    use value <- decode.field(field, decode.list(decode.dynamic))
    decode.success(value)
  }
  decode.run(data, decoder) |> result.replace_error(Nil)
}

fn get_string_list(data: Dynamic, field: String) -> Result(List(String), Nil) {
  let decoder = {
    use value <- decode.field(field, decode.list(decode.string))
    decode.success(value)
  }
  decode.run(data, decoder) |> result.replace_error(Nil)
}

// Config tests

pub fn new_config_test() {
  let config = openai.new("sk-test-key")
  let req = request.new("gpt-4o", [gai.user_text("Hi")])
  let http_req = openai.build_request(config, req)

  let assert Ok("Bearer sk-test-key") =
    http_request.get_header(http_req, "authorization")
}

pub fn with_base_url_test() {
  let config =
    openai.new("sk-test")
    |> openai.with_base_url("https://my-proxy.com/v1")

  let req = request.new("gpt-4o", [gai.user_text("Hi")])
  let http_req = openai.build_request(config, req)

  let assert http_request.Request(
    host: "my-proxy.com",
    path: "/v1/chat/completions",
    ..,
  ) = http_req
}

pub fn with_organization_test() {
  let config =
    openai.new("sk-test")
    |> openai.with_organization("org-123")

  let req = request.new("gpt-4o", [gai.user_text("Hi")])
  let http_req = openai.build_request(config, req)

  let assert Ok("org-123") =
    http_request.get_header(http_req, "openai-organization")
}

// build_request tests

pub fn build_request_method_and_headers_test() {
  let config = openai.new("sk-test")
  let req = request.new("gpt-4o", [gai.user_text("Hello")])
  let http_req = openai.build_request(config, req)

  let assert http_request.Request(method: http.Post, ..) = http_req
  let assert Ok("application/json") =
    http_request.get_header(http_req, "content-type")
}

pub fn build_request_simple_message_test() {
  let config = openai.new("sk-test")
  let req =
    request.new("gpt-4o", [
      gai.system("You are helpful."),
      gai.user_text("What is 2+2?"),
    ])

  let http_req = openai.build_request(config, req)

  let assert Ok(body) = json.parse(http_req.body, decode.dynamic)
  let assert Ok("gpt-4o") = get_string(body, "model")
  let assert Ok(messages) = get_list(body, "messages")
  let assert [system_msg, user_msg] = messages

  let assert Ok("system") = get_string(system_msg, "role")
  let assert Ok("You are helpful.") = get_string(system_msg, "content")

  let assert Ok("user") = get_string(user_msg, "role")
  let assert Ok("What is 2+2?") = get_string(user_msg, "content")
}

pub fn build_request_with_options_test() {
  let config = openai.new("sk-test")
  let req =
    request.new("gpt-4o", [gai.user_text("Hi")])
    |> request.with_max_tokens(100)
    |> request.with_temperature(0.7)
    |> request.with_top_p(0.9)
    |> request.with_stop(["END"])

  let http_req = openai.build_request(config, req)
  let assert Ok(body) = json.parse(http_req.body, decode.dynamic)

  let assert Ok(100) = get_int(body, "max_completion_tokens")
  let assert Ok(0.7) = get_float(body, "temperature")
  let assert Ok(0.9) = get_float(body, "top_p")
  let assert Ok(["END"]) = get_string_list(body, "stop")
}

pub fn build_request_json_format_test() {
  let config = openai.new("sk-test")
  let req =
    request.new("gpt-4o", [gai.user_text("Give me JSON")])
    |> request.with_response_format(request.JsonFormat)

  let http_req = openai.build_request(config, req)
  let assert Ok(body) = json.parse(http_req.body, decode.dynamic)

  let assert Ok(response_format) = get_dynamic(body, "response_format")
  let assert Ok("json_object") = get_string(response_format, "type")
}

// parse_response tests

pub fn parse_response_success_test() {
  let json_body =
    "{
    \"id\": \"chatcmpl-123\",
    \"model\": \"gpt-4o-2024-05-13\",
    \"choices\": [{
      \"index\": 0,
      \"message\": {
        \"role\": \"assistant\",
        \"content\": \"4\"
      },
      \"finish_reason\": \"stop\"
    }],
    \"usage\": {
      \"prompt_tokens\": 10,
      \"completion_tokens\": 1,
      \"total_tokens\": 11
    }
  }"

  let http_resp =
    http_response.new(200)
    |> http_response.set_body(json_body)

  let assert Ok(resp) = openai.parse_response(http_resp)
  let assert response.CompletionResponse(
    id: "chatcmpl-123",
    model: "gpt-4o-2024-05-13",
    content: [gai.Text("4")],
    stop_reason: gai.EndTurn,
    usage: gai.Usage(input_tokens: 10, output_tokens: 1, ..),
  ) = resp
}

pub fn parse_response_max_tokens_test() {
  let json_body =
    "{
    \"id\": \"chatcmpl-123\",
    \"model\": \"gpt-4o\",
    \"choices\": [{
      \"message\": {\"role\": \"assistant\", \"content\": \"partial...\"},
      \"finish_reason\": \"length\"
    }],
    \"usage\": {\"prompt_tokens\": 10, \"completion_tokens\": 100}
  }"

  let http_resp =
    http_response.new(200)
    |> http_response.set_body(json_body)

  let assert Ok(resp) = openai.parse_response(http_resp)
  let assert response.CompletionResponse(stop_reason: gai.MaxTokens, ..) = resp
}

pub fn parse_response_tool_calls_test() {
  let json_body =
    "{
    \"id\": \"chatcmpl-123\",
    \"model\": \"gpt-4o\",
    \"choices\": [{
      \"message\": {
        \"role\": \"assistant\",
        \"content\": null,
        \"tool_calls\": [{
          \"id\": \"call_abc123\",
          \"type\": \"function\",
          \"function\": {
            \"name\": \"get_weather\",
            \"arguments\": \"{\\\"location\\\": \\\"London\\\"}\"
          }
        }]
      },
      \"finish_reason\": \"tool_calls\"
    }],
    \"usage\": {\"prompt_tokens\": 20, \"completion_tokens\": 15}
  }"

  let http_resp =
    http_response.new(200)
    |> http_response.set_body(json_body)

  let assert Ok(resp) = openai.parse_response(http_resp)
  let assert response.CompletionResponse(stop_reason: gai.ToolUsed, ..) = resp
  assert response.has_tool_calls(resp)

  let calls = response.tool_calls(resp)
  let assert [gai.ToolUse(id: "call_abc123", name: "get_weather", ..)] = calls
}

pub fn parse_response_auth_error_test() {
  let json_body =
    "{
    \"error\": {
      \"message\": \"Invalid API key\",
      \"type\": \"invalid_request_error\",
      \"code\": \"invalid_api_key\"
    }
  }"

  let http_resp =
    http_response.new(401)
    |> http_response.set_body(json_body)

  let assert Error(gai.AuthError(message: "Invalid API key")) =
    openai.parse_response(http_resp)
}

pub fn parse_response_api_error_test() {
  let json_body =
    "{
    \"error\": {
      \"message\": \"Invalid model\",
      \"type\": \"invalid_request_error\",
      \"code\": \"invalid_model\"
    }
  }"

  let http_resp =
    http_response.new(400)
    |> http_response.set_body(json_body)

  let assert Error(gai.ApiError(code: "invalid_model", message: "Invalid model")) =
    openai.parse_response(http_resp)
}

pub fn parse_response_rate_limited_test() {
  let json_body =
    "{
    \"error\": {
      \"message\": \"Rate limit exceeded\",
      \"type\": \"rate_limit_error\",
      \"code\": \"rate_limit_exceeded\"
    }
  }"

  let http_resp =
    http_response.new(429)
    |> http_response.set_body(json_body)
    |> http_response.set_header("retry-after", "30")

  let assert Error(gai.RateLimited(retry_after: option.Some(30))) =
    openai.parse_response(http_resp)
}

// Provider constructor test

pub fn provider_test() {
  let config = openai.new("sk-test")
  let provider = openai.provider(config)

  let assert "openai" = provider.name
}

// Convenience constructors

pub fn openrouter_test() {
  let config = openai.openrouter("or-test-key")
  let req = request.new("anthropic/claude-3", [gai.user_text("Hi")])
  let http_req = openai.build_request(config, req)

  let assert http_request.Request(
    host: "openrouter.ai",
    path: "/api/v1/chat/completions",
    ..,
  ) = http_req
}

pub fn xai_test() {
  let config = openai.xai("xai-test-key")
  let req = request.new("grok-beta", [gai.user_text("Hi")])
  let http_req = openai.build_request(config, req)

  let assert http_request.Request(
    host: "api.x.ai",
    path: "/v1/chat/completions",
    ..,
  ) = http_req
}
