//// One-time post-OAuth login tickets stored on disk.

import filepath
import friends/session.{type UserSession, UserSession}
import gleam/bit_array
import gleam/dynamic/decode
import gleam/json
import gleam/option.{None, Some}
import gleam/result
import gleam/string
import simplifile

pub const ticket_max_age_seconds = 600

pub fn directory(data_path: String) -> String {
  filepath.join(filepath.directory_name(data_path), "pending")
}

pub fn issue(data_path: String, user: UserSession) -> Result(String, String) {
  let dir = directory(data_path)
  use _ <- result.try(
    simplifile.create_directory_all(dir)
    |> result.map_error(fn(_) { "failed to create pending login directory" }),
  )

  let ticket = new_ticket()
  let expiry = unix_seconds() + ticket_max_age_seconds
  let body = encode(user, expiry)
  let path = ticket_path(dir, ticket)

  simplifile.write(to: path, contents: body)
  |> result.map_error(fn(_) { "failed to persist pending login" })
  |> result.replace(ticket)
}

pub fn take(data_path: String, ticket: String) -> Result(UserSession, String) {
  use _ <- result.try(validate_ticket_name(ticket))
  let path = ticket_path(directory(data_path), ticket)

  use raw <- result.try(
    simplifile.read(path)
    |> result.map_error(fn(_) { "sign-in ticket expired or already used" }),
  )
  let _ = simplifile.delete(path)

  use #(user, expiry) <- result.try(decode_ticket(raw))
  case unix_seconds() <= expiry {
    True -> Ok(user)
    False -> Error("sign-in ticket expired; try signing in again")
  }
}

fn ticket_path(dir: String, ticket: String) -> String {
  filepath.join(dir, ticket <> ".json")
}

fn validate_ticket_name(ticket: String) -> Result(Nil, String) {
  case string.length(ticket) >= 20 && string.length(ticket) <= 80 {
    False -> Error("invalid sign-in ticket")
    True -> {
      case string.to_graphemes(ticket) |> list_all_ticket_chars {
        True -> Ok(Nil)
        False -> Error("invalid sign-in ticket")
      }
    }
  }
}

fn list_all_ticket_chars(chars: List(String)) -> Bool {
  case chars {
    [] -> True
    [char, ..rest] ->
      case is_ticket_char(char) {
        True -> list_all_ticket_chars(rest)
        False -> False
      }
  }
}

fn is_ticket_char(char: String) -> Bool {
  case char {
    "A"
    | "B"
    | "C"
    | "D"
    | "E"
    | "F"
    | "G"
    | "H"
    | "I"
    | "J"
    | "K"
    | "L"
    | "M"
    | "N"
    | "O"
    | "P"
    | "Q"
    | "R"
    | "S"
    | "T"
    | "U"
    | "V"
    | "W"
    | "X"
    | "Y"
    | "Z"
    | "a"
    | "b"
    | "c"
    | "d"
    | "e"
    | "f"
    | "g"
    | "h"
    | "i"
    | "j"
    | "k"
    | "l"
    | "m"
    | "n"
    | "o"
    | "p"
    | "q"
    | "r"
    | "s"
    | "t"
    | "u"
    | "v"
    | "w"
    | "x"
    | "y"
    | "z"
    | "0"
    | "1"
    | "2"
    | "3"
    | "4"
    | "5"
    | "6"
    | "7"
    | "8"
    | "9"
    | "-"
    | "_" -> True
    _ -> False
  }
}

fn encode(user: UserSession, expiry: Int) -> String {
  let name = case user.name {
    Some(value) -> json.string(value)
    None -> json.null()
  }

  json.to_string(
    json.object([
      #("sub", json.string(user.sub)),
      #("name", name),
      #("exp", json.int(expiry)),
    ]),
  )
}

fn decode_ticket(raw: String) -> Result(#(UserSession, Int), String) {
  let decoder = {
    use sub <- decode.field("sub", decode.string)
    use name <- decode.optional_field(
      "name",
      None,
      decode.optional(decode.string),
    )
    use exp <- decode.field("exp", decode.int)
    decode.success(#(UserSession(sub:, name:), exp))
  }

  json.parse(raw, decoder)
  |> result.map_error(fn(_) { "corrupt sign-in ticket" })
}

fn new_ticket() -> String {
  strong_rand_bytes(24)
  |> bit_array.base64_encode(False)
  |> string.replace(each: "+", with: "-")
  |> string.replace(each: "/", with: "_")
  |> string.replace(each: "=", with: "")
}

@external(erlang, "crypto", "strong_rand_bytes")
fn strong_rand_bytes(count: Int) -> BitArray

@external(erlang, "friends_ffi", "unix_seconds")
fn unix_seconds() -> Int
