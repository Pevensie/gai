import envoy
import gai
import gai/anthropic
import gai/request
import gai/response
import gai/schema
import gai/tool
import gleam/httpc
import gleam/json
import gleam/string
import sextant

const model = "claude-haiku-4-5"

fn with_api_key(test_fn: fn(String) -> Nil) -> Nil {
  case envoy.get("ANTHROPIC_API_KEY") {
    Ok(api_key) -> test_fn(api_key)
    Error(_) -> Nil
  }
}

pub fn basic_completion_test() {
  use api_key <- with_api_key

  let config = anthropic.new(api_key)
  let req =
    request.new(model, [gai.user_text("Say 'hello' and nothing else.")])
    |> request.with_max_tokens(10)

  let http_req = anthropic.build_request(config, req)
  let assert Ok(http_resp) = httpc.send(http_req)
  let assert Ok(completion) = anthropic.parse_response(http_resp)

  let text = response.text_content(completion)
  assert string.contains(string.lowercase(text), "hello")
}

type WeatherParams {
  WeatherParams(location: String)
}

fn weather_schema() -> sextant.JsonSchema(WeatherParams) {
  use location <- sextant.field(
    "location",
    sextant.string() |> sextant.describe("City name"),
  )
  sextant.success(WeatherParams(location:))
}

fn weather_tool() -> tool.UntypedTool {
  tool.new(
    "get_weather",
    "Get current weather for a location",
    weather_schema(),
  )
  |> tool.to_untyped
}

pub fn tool_call_test() {
  use api_key <- with_api_key

  let config = anthropic.new(api_key)
  let req =
    request.new(model, [gai.user_text("What's the weather in London?")])
    |> request.with_max_tokens(100)
    |> request.with_tools([weather_tool()])
    |> request.with_tool_choice(request.Required)

  let http_req = anthropic.build_request(config, req)
  let assert Ok(http_resp) = httpc.send(http_req)
  let assert Ok(completion) = anthropic.parse_response(http_resp)

  assert response.has_tool_calls(completion)
  let assert [gai.ToolUse(name: "get_weather", ..)] =
    response.tool_calls(completion)
  Nil
}

pub fn invalid_model_test() {
  use api_key <- with_api_key

  let config = anthropic.new(api_key)
  let req =
    request.new("claude-nonexistent-model-12345", [gai.user_text("Hi")])
    |> request.with_max_tokens(10)

  let http_req = anthropic.build_request(config, req)
  let assert Ok(http_resp) = httpc.send(http_req)
  let assert Error(gai.ApiError(..)) = anthropic.parse_response(http_resp)
  Nil
}

pub fn json_schema_test() {
  use api_key <- with_api_key

  let schema =
    json.object([
      #("type", json.string("object")),
      #(
        "properties",
        json.object([
          #("greeting", json.object([#("type", json.string("string"))])),
        ]),
      ),
      #("required", json.preprocessed_array([json.string("greeting")])),
      #("additionalProperties", json.bool(False)),
    ])

  let config = anthropic.new(api_key)
  let req =
    request.new(model, [gai.user_text("Generate a greeting message.")])
    |> request.with_max_tokens(50)
    |> request.with_response_format(request.JsonSchemaFormat(
      schema: schema,
      name: "greeting_response",
      strict: True,
    ))

  let http_req = anthropic.build_request(config, req)
  let assert Ok(http_resp) = httpc.send(http_req)
  let assert Ok(completion) = anthropic.parse_response(http_resp)

  let text = response.text_content(completion)
  assert string.contains(text, "greeting")
}

pub type GreetingResponse {
  GreetingResponse(greeting: String)
}

pub fn typed_schema_test() {
  use api_key <- with_api_key

  let greeting_schema =
    schema.new("greeting_response", {
      use greeting <- sextant.field("greeting", sextant.string())
      sextant.success(GreetingResponse(greeting))
    })

  let config = anthropic.new(api_key)
  let req =
    request.new(model, [gai.user_text("Say hello to the user.")])
    |> request.with_max_tokens(50)
    |> request.with_schema(greeting_schema)

  let http_req = anthropic.build_request(config, req)
  let assert Ok(http_resp) = httpc.send(http_req)
  let assert Ok(completion) = anthropic.parse_response(http_resp)

  let text = response.text_content(completion)
  let assert Ok(GreetingResponse(greeting)) =
    schema.parse(greeting_schema, text)
  assert greeting != ""
}
