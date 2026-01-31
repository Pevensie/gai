import gai
import gai/cache
import gai/request
import gleam/json

// ============================================================================
// cache_key tests
// ============================================================================

pub fn cache_key_same_request_produces_same_key_test() {
  let req1 = request.new("gpt-4o", [gai.user_text("Hello")])
  let req2 = request.new("gpt-4o", [gai.user_text("Hello")])

  let key1 = cache.cache_key(req1) |> cache.key_to_string
  let key2 = cache.cache_key(req2) |> cache.key_to_string

  assert key1 == key2
}

pub fn cache_key_different_model_produces_different_key_test() {
  let req1 = request.new("gpt-4o", [gai.user_text("Hello")])
  let req2 = request.new("gpt-4o-mini", [gai.user_text("Hello")])

  let key1 = cache.cache_key(req1) |> cache.key_to_string
  let key2 = cache.cache_key(req2) |> cache.key_to_string

  assert key1 != key2
}

pub fn cache_key_different_message_produces_different_key_test() {
  let req1 = request.new("gpt-4o", [gai.user_text("Hello")])
  let req2 = request.new("gpt-4o", [gai.user_text("Goodbye")])

  let key1 = cache.cache_key(req1) |> cache.key_to_string
  let key2 = cache.cache_key(req2) |> cache.key_to_string

  assert key1 != key2
}

pub fn cache_key_different_max_tokens_produces_different_key_test() {
  let req1 =
    request.new("gpt-4o", [gai.user_text("Hello")])
    |> request.with_max_tokens(100)
  let req2 =
    request.new("gpt-4o", [gai.user_text("Hello")])
    |> request.with_max_tokens(200)

  let key1 = cache.cache_key(req1) |> cache.key_to_string
  let key2 = cache.cache_key(req2) |> cache.key_to_string

  assert key1 != key2
}

pub fn cache_key_different_temperature_produces_different_key_test() {
  let req1 =
    request.new("gpt-4o", [gai.user_text("Hello")])
    |> request.with_temperature(0.5)
  let req2 =
    request.new("gpt-4o", [gai.user_text("Hello")])
    |> request.with_temperature(0.7)

  let key1 = cache.cache_key(req1) |> cache.key_to_string
  let key2 = cache.cache_key(req2) |> cache.key_to_string

  assert key1 != key2
}

pub fn cache_key_is_stable_across_calls_test() {
  let req = request.new("gpt-4o", [gai.user_text("Hello")])

  let key1 = cache.cache_key(req) |> cache.key_to_string
  let key2 = cache.cache_key(req) |> cache.key_to_string
  let key3 = cache.cache_key(req) |> cache.key_to_string

  assert key1 == key2 && key2 == key3
}

pub fn cache_key_ignores_provider_options_test() {
  let req1 =
    request.new("gpt-4o", [gai.user_text("Hello")])
    |> request.with_provider_options([#("custom", json.string("value1"))])
  let req2 =
    request.new("gpt-4o", [gai.user_text("Hello")])
    |> request.with_provider_options([#("custom", json.string("value2"))])

  let key1 = cache.cache_key(req1) |> cache.key_to_string
  let key2 = cache.cache_key(req2) |> cache.key_to_string

  // Keys should be equal because provider_options are excluded
  assert key1 == key2
}

pub fn cache_key_with_multiple_messages_test() {
  let req1 =
    request.new("gpt-4o", [
      gai.system("You are helpful."),
      gai.user_text("Hello"),
      gai.assistant_text("Hi there!"),
      gai.user_text("How are you?"),
    ])
  let req2 =
    request.new("gpt-4o", [
      gai.system("You are helpful."),
      gai.user_text("Hello"),
      gai.assistant_text("Hi there!"),
      gai.user_text("How are you?"),
    ])

  let key1 = cache.cache_key(req1) |> cache.key_to_string
  let key2 = cache.cache_key(req2) |> cache.key_to_string

  assert key1 == key2
}

pub fn cache_key_with_image_content_test() {
  let req1 =
    request.new("gpt-4o", [
      gai.user([
        gai.text("Look at this"),
        gai.image_url("https://example.com/img.png"),
      ]),
    ])
  let req2 =
    request.new("gpt-4o", [
      gai.user([
        gai.text("Look at this"),
        gai.image_url("https://example.com/img.png"),
      ]),
    ])

  let key1 = cache.cache_key(req1) |> cache.key_to_string
  let key2 = cache.cache_key(req2) |> cache.key_to_string

  assert key1 == key2
}

// ============================================================================
// CacheConfig tests
// ============================================================================

pub fn default_cache_config_has_one_hour_ttl_test() {
  let config = cache.default_cache_config()
  let assert 3600 = cache.ttl_seconds(config)
}

pub fn with_ttl_sets_custom_ttl_test() {
  let config = cache.with_ttl(7200)
  let assert 7200 = cache.ttl_seconds(config)
}
