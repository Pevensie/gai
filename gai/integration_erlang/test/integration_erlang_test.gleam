import envoy
import gleam/list
import gleam/string
import gleeunit
import simplifile

pub fn main() -> Nil {
  // Load .env file from project root
  load_dotenv("../.env")
  gleeunit.main()
}

fn load_dotenv(path: String) -> Nil {
  case simplifile.read(path) {
    Ok(content) -> {
      content
      |> string.split("\n")
      |> list.each(fn(line) {
        let line = string.trim(line)
        // Skip empty lines and comments
        case string.starts_with(line, "#") || line == "" {
          True -> Nil
          False -> {
            case string.split_once(line, "=") {
              Ok(#(key, value)) -> {
                let key = string.trim(key)
                let value = string.trim(value)
                // Remove surrounding quotes if present
                let value = case
                  string.starts_with(value, "\"")
                  && string.ends_with(value, "\"")
                {
                  True -> string.slice(value, 1, string.length(value) - 2)
                  False -> value
                }
                envoy.set(key, value)
              }
              Error(_) -> Nil
            }
          }
        }
      })
    }
    Error(_) -> Nil
  }
}
