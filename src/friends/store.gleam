//// Persistent Bluesky handle storage per authenticated user.

import gleam/dict
import gleam/dynamic/decode
import gleam/json
import gleam/list
import gleam/result
import gleam/string
import simplifile

pub type Store {
  Store(path: String, users: dict.Dict(String, List(String)))
}

pub fn open(path: String) -> Store {
  case simplifile.read(path) {
    Ok(raw) ->
      case decode_file(raw) {
        Ok(users) -> Store(path:, users:)
        Error(_) -> Store(path:, users: dict.new())
      }
    Error(_) -> Store(path:, users: dict.new())
  }
}

pub fn handles(store: Store, user_id: String) -> List(String) {
  case dict.get(store.users, user_id) {
    Ok(items) -> items
    Error(_) -> []
  }
  |> list.sort(string.compare)
}

pub fn add_handle(
  store: Store,
  user_id: String,
  handle: String,
) -> Result(#(Store, Bool), String) {
  let normalized = normalize_handle(handle)
  case valid_handle(normalized) {
    False -> Error("invalid Bluesky handle")
    True -> {
      let existing = handles(store, user_id)
      case list.contains(existing, normalized) {
        True -> Ok(#(store, False))
        False -> {
          let updated_users =
            dict.insert(store.users, user_id, [normalized, ..existing])
          let next = Store(..store, users: updated_users)
          use _ <- result.try(
            save(next)
            |> result.map_error(fn(_) { "failed to save handles" }),
          )
          Ok(#(next, True))
        }
      }
    }
  }
}

pub fn remove_handle(
  store: Store,
  user_id: String,
  handle: String,
) -> Result(#(Store, Bool), String) {
  let normalized = normalize_handle(handle)
  let existing = handles(store, user_id)
  case list.contains(existing, normalized) {
    False -> Ok(#(store, False))
    True -> {
      let remaining = list.filter(existing, fn(item) { item != normalized })
      let updated_users = dict.insert(store.users, user_id, remaining)
      let next = Store(..store, users: updated_users)
      use _ <- result.try(
        save(next)
        |> result.map_error(fn(_) { "failed to save handles" }),
      )
      Ok(#(next, True))
    }
  }
}

pub fn normalize_handle(handle: String) -> String {
  handle
  |> string.trim
  |> string.replace(each: "@", with: "")
  |> string.lowercase
}

pub fn valid_handle(handle: String) -> Bool {
  case string.split(handle, ".") {
    [] -> False
    [domain, ..rest] ->
      string.length(domain) > 0 && rest != [] && !string.contains(handle, " ")
  }
}

fn save(store: Store) -> Result(Nil, Nil) {
  let body = encode_file(store.users)
  ensure_parent_directory(store.path)
  simplifile.write(store.path, body)
  |> result.map(fn(_) { Nil })
  |> result.map_error(fn(_) { Nil })
}

fn ensure_parent_directory(path: String) -> Nil {
  case parent_directory(path) {
    "" -> Nil
    dir -> {
      let _ = simplifile.create_directory_all(dir)
      Nil
    }
  }
}

fn parent_directory(path: String) -> String {
  case list.reverse(string.split(path, "/")) {
    [_file, ..rest] -> list.reverse(rest) |> string.join("/")
    _ -> ""
  }
}

fn encode_file(users: dict.Dict(String, List(String))) -> String {
  let user_objects =
    dict.to_list(users)
    |> list.map(fn(entry) {
      let #(user_id, user_handles) = entry
      #(
        user_id,
        json.object([#("handles", json.array(user_handles, of: json.string))]),
      )
    })

  json.to_string(json.object([#("users", json.object(user_objects))]))
}

fn decode_file(raw: String) -> Result(dict.Dict(String, List(String)), Nil) {
  let user_decoder = {
    use user_handles <- decode.field("handles", decode.list(decode.string))
    decode.success(user_handles)
  }

  let decoder = {
    use users <- decode.field("users", decode.dict(decode.string, user_decoder))
    decode.success(users)
  }

  json.parse(raw, decoder)
  |> result.map_error(fn(_) { Nil })
}
