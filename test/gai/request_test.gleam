import gai
import gai/request
import gai/schema
import gai/tool
import gleam/json
import gleam/option
import sextant

pub fn new_request_test() {
  let req =
    request.new("gpt-4o", [
      gai.system("You are helpful."),
      gai.user_text("Hello"),
    ])

  let assert request.CompletionRequest(
    model: "gpt-4o",
    messages: [_, _],
    max_tokens: option.None,
    temperature: option.None,
    top_p: option.None,
    stop: option.None,
    tools: option.None,
    tool_choice: option.None,
    response_format: option.None,
    provider_options: option.None,
  ) = req
}

pub fn with_max_tokens_test() {
  let req =
    request.new("gpt-4o", [gai.user_text("Hi")])
    |> request.with_max_tokens(100)

  let assert request.CompletionRequest(max_tokens: option.Some(100), ..) = req
}

pub fn with_temperature_test() {
  let req =
    request.new("gpt-4o", [gai.user_text("Hi")])
    |> request.with_temperature(0.7)

  let assert request.CompletionRequest(temperature: option.Some(0.7), ..) = req
}

pub fn with_top_p_test() {
  let req =
    request.new("gpt-4o", [gai.user_text("Hi")])
    |> request.with_top_p(0.9)

  let assert request.CompletionRequest(top_p: option.Some(0.9), ..) = req
}

pub fn with_stop_sequences_test() {
  let req =
    request.new("gpt-4o", [gai.user_text("Hi")])
    |> request.with_stop(["END", "STOP"])

  let assert request.CompletionRequest(stop: option.Some(["END", "STOP"]), ..) =
    req
}

pub fn with_json_format_test() {
  let req =
    request.new("gpt-4o", [gai.user_text("Hi")])
    |> request.with_response_format(request.JsonFormat)

  let assert request.CompletionRequest(
    response_format: option.Some(request.JsonFormat),
    ..,
  ) = req
}

pub fn with_json_schema_format_test() {
  let schema = json.object([#("type", json.string("object"))])
  let req =
    request.new("gpt-4o", [gai.user_text("Hi")])
    |> request.with_response_format(request.JsonSchemaFormat(
      schema:,
      name: "my_schema",
      strict: True,
    ))

  let assert request.CompletionRequest(
    response_format: option.Some(request.JsonSchemaFormat(
      name: "my_schema",
      strict: True,
      ..,
    )),
    ..,
  ) = req
}

pub fn chained_builders_test() {
  let req =
    request.new("gpt-4o", [gai.user_text("Hi")])
    |> request.with_max_tokens(500)
    |> request.with_temperature(0.5)
    |> request.with_top_p(0.8)
    |> request.with_stop(["END"])

  let assert request.CompletionRequest(
    model: "gpt-4o",
    max_tokens: option.Some(500),
    temperature: option.Some(0.5),
    top_p: option.Some(0.8),
    stop: option.Some(["END"]),
    ..,
  ) = req
}

type SearchParams {
  SearchParams(query: String)
}

pub fn with_tools_test() {
  let search_schema = {
    use query <- sextant.field("query", sextant.string())
    sextant.success(SearchParams(query:))
  }
  let search_tool =
    tool.new("search", "Search the web", search_schema)
    |> tool.to_untyped

  let req =
    request.new("gpt-4o", [gai.user_text("Search for cats")])
    |> request.with_tools([search_tool])

  let assert request.CompletionRequest(tools: option.Some([_]), ..) = req
}

pub fn with_tool_choice_test() {
  let req =
    request.new("gpt-4o", [gai.user_text("Hi")])
    |> request.with_tool_choice(request.Required)

  let assert request.CompletionRequest(
    tool_choice: option.Some(request.Required),
    ..,
  ) = req
}

pub fn with_provider_options_test() {
  let req =
    request.new("gpt-4o", [gai.user_text("Hi")])
    |> request.with_provider_options([
      #("reasoning_effort", json.string("low")),
      #("presence_penalty", json.float(0.5)),
    ])

  let assert request.CompletionRequest(
    provider_options: option.Some([
      #("reasoning_effort", _),
      #("presence_penalty", _),
    ]),
    ..,
  ) = req
}

pub type Greeting {
  Greeting(message: String)
}

pub fn with_schema_test() {
  let greeting_schema =
    schema.new("greeting", {
      use message <- sextant.field("message", sextant.string())
      sextant.success(Greeting(message))
    })

  let req =
    request.new("gpt-4o", [gai.user_text("Hi")])
    |> request.with_schema(greeting_schema)

  let assert request.CompletionRequest(
    response_format: option.Some(request.JsonSchemaFormat(
      name: "greeting",
      strict: True,
      ..,
    )),
    ..,
  ) = req
}
