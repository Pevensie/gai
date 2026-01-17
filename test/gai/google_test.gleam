import gai
import gai/google
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
import gleam/string

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

// Config tests

pub fn new_config_test() {
  let config = google.new("test-api-key")
  let req = request.new("gemini-1.5-pro", [gai.user_text("Hi")])
  let http_req = google.build_request(config, req)

  // API key should be in query string
  let assert option.Some(query) = http_req.query
  assert string.contains(query, "key=test-api-key")
}

pub fn with_base_url_test() {
  let config =
    google.new("test-key")
    |> google.with_base_url("https://my-proxy.com/v1beta")

  let req = request.new("gemini-1.5-pro", [gai.user_text("Hi")])
  let http_req = google.build_request(config, req)

  let assert http_request.Request(host: "my-proxy.com", ..) = http_req
}

// build_request tests

pub fn build_request_method_and_headers_test() {
  let config = google.new("test-key")
  let req = request.new("gemini-1.5-pro", [gai.user_text("Hello")])
  let http_req = google.build_request(config, req)

  let assert http_request.Request(method: http.Post, ..) = http_req
  let assert Ok("application/json") =
    http_request.get_header(http_req, "content-type")
}

pub fn build_request_path_includes_model_test() {
  let config = google.new("test-key")
  let req = request.new("gemini-1.5-pro", [gai.user_text("Hello")])
  let http_req = google.build_request(config, req)

  assert string.contains(
    http_req.path,
    "/models/gemini-1.5-pro:generateContent",
  )
}

pub fn build_request_simple_message_test() {
  let config = google.new("test-key")
  let req =
    request.new("gemini-1.5-pro", [
      gai.user_text("What is 2+2?"),
    ])

  let http_req = google.build_request(config, req)

  let assert Ok(body) = json.parse(http_req.body, decode.dynamic)
  let assert Ok(contents) = get_list(body, "contents")
  let assert [user_content] = contents

  let assert Ok("user") = get_string(user_content, "role")
}

pub fn build_request_system_message_test() {
  let config = google.new("test-key")
  let req =
    request.new("gemini-1.5-pro", [
      gai.system("You are helpful."),
      gai.user_text("Hi"),
    ])

  let http_req = google.build_request(config, req)

  let assert Ok(body) = json.parse(http_req.body, decode.dynamic)
  // System message should be in systemInstruction
  let assert Ok(system_instruction) = get_dynamic(body, "systemInstruction")
  let assert Ok(parts) = get_list(system_instruction, "parts")
  let assert [part] = parts
  let assert Ok("You are helpful.") = get_string(part, "text")
}

pub fn build_request_with_max_tokens_test() {
  let config = google.new("test-key")
  let req =
    request.new("gemini-1.5-pro", [gai.user_text("Hi")])
    |> request.with_max_tokens(100)

  let http_req = google.build_request(config, req)
  let assert Ok(body) = json.parse(http_req.body, decode.dynamic)
  let assert Ok(generation_config) = get_dynamic(body, "generationConfig")
  let assert Ok(100) = get_int(generation_config, "maxOutputTokens")
}

// parse_response tests

pub fn parse_response_success_test() {
  let json_body =
    "{
    \"candidates\": [{
      \"content\": {
        \"parts\": [{\"text\": \"4\"}],
        \"role\": \"model\"
      },
      \"finishReason\": \"STOP\"
    }],
    \"usageMetadata\": {
      \"promptTokenCount\": 10,
      \"candidatesTokenCount\": 1
    }
  }"

  let http_resp =
    http_response.new(200)
    |> http_response.set_body(json_body)

  let assert Ok(resp) = google.parse_response(http_resp)
  let assert response.CompletionResponse(
    content: [gai.Text("4")],
    stop_reason: gai.EndTurn,
    usage: gai.Usage(input_tokens: 10, output_tokens: 1, ..),
    ..,
  ) = resp
}

pub fn parse_response_max_tokens_test() {
  let json_body =
    "{
    \"candidates\": [{
      \"content\": {
        \"parts\": [{\"text\": \"partial...\"}],
        \"role\": \"model\"
      },
      \"finishReason\": \"MAX_TOKENS\"
    }],
    \"usageMetadata\": {\"promptTokenCount\": 10, \"candidatesTokenCount\": 100}
  }"

  let http_resp =
    http_response.new(200)
    |> http_response.set_body(json_body)

  let assert Ok(resp) = google.parse_response(http_resp)
  let assert response.CompletionResponse(stop_reason: gai.MaxTokens, ..) = resp
}

pub fn parse_response_function_call_test() {
  let json_body =
    "{
    \"candidates\": [{
      \"content\": {
        \"parts\": [{
          \"functionCall\": {
            \"name\": \"get_weather\",
            \"args\": {\"location\": \"London\"}
          }
        }],
        \"role\": \"model\"
      },
      \"finishReason\": \"STOP\"
    }],
    \"usageMetadata\": {\"promptTokenCount\": 20, \"candidatesTokenCount\": 15}
  }"

  let http_resp =
    http_response.new(200)
    |> http_response.set_body(json_body)

  let assert Ok(resp) = google.parse_response(http_resp)
  assert response.has_tool_calls(resp)

  let calls = response.tool_calls(resp)
  let assert [gai.ToolUse(name: "get_weather", ..)] = calls
}

pub fn parse_response_auth_error_test() {
  let json_body =
    "{
    \"error\": {
      \"code\": 401,
      \"message\": \"API key not valid\",
      \"status\": \"UNAUTHENTICATED\"
    }
  }"

  let http_resp =
    http_response.new(401)
    |> http_response.set_body(json_body)

  let assert Error(gai.AuthError(message: "API key not valid")) =
    google.parse_response(http_resp)
}

pub fn parse_response_api_error_test() {
  let json_body =
    "{
    \"error\": {
      \"code\": 400,
      \"message\": \"Invalid model\",
      \"status\": \"INVALID_ARGUMENT\"
    }
  }"

  let http_resp =
    http_response.new(400)
    |> http_response.set_body(json_body)

  let assert Error(gai.ApiError(
    code: "INVALID_ARGUMENT",
    message: "Invalid model",
  )) = google.parse_response(http_resp)
}

pub fn parse_response_rate_limited_test() {
  let json_body =
    "{
    \"error\": {
      \"code\": 429,
      \"message\": \"Rate limit exceeded\",
      \"status\": \"RESOURCE_EXHAUSTED\"
    }
  }"

  let http_resp =
    http_response.new(429)
    |> http_response.set_body(json_body)
    |> http_response.set_header("retry-after", "30")

  let assert Error(gai.RateLimited(retry_after: option.Some(30))) =
    google.parse_response(http_resp)
}

// Provider constructor test

pub fn provider_test() {
  let config = google.new("test-key")
  let provider = google.provider(config)

  let assert "google" = provider.name
}
