//// Bluesky public API client.

import gleam/dynamic/decode
import gleam/http
import gleam/http/request
import gleam/httpc
import gleam/int
import gleam/json
import gleam/list
import gleam/option.{type Option}
import gleam/result
import gleam/string
import gleam/uri

pub const api_host = "public.api.bsky.app"

pub type Post {
  Post(
    uri: String,
    text: String,
    created_at: String,
    author_handle: String,
    author_name: Option(String),
    web_url: String,
  )
}

pub fn fetch_author_posts(
  handle: String,
  limit: Int,
) -> Result(List(Post), String) {
  let path =
    "/xrpc/app.bsky.feed.getAuthorFeed?actor="
    <> uri.percent_encode(handle)
    <> "&limit="
    <> int.to_string(limit)

  use body <- result.try(
    send_get(path)
    |> result.map_error(fn(_) { "failed to fetch Bluesky posts for " <> handle }),
  )

  decode_feed(body, handle)
}

fn send_get(path: String) -> Result(String, Nil) {
  let req =
    request.new()
    |> request.set_scheme(http.Https)
    |> request.set_host(api_host)
    |> request.set_path(path)
    |> request.set_header("accept", "application/json")

  use resp <- result.try(httpc.send(req) |> result.map_error(fn(_) { Nil }))
  case resp.status >= 200 && resp.status < 300 {
    True -> Ok(resp.body)
    False -> Error(Nil)
  }
}

fn decode_feed(
  body: String,
  fallback_handle: String,
) -> Result(List(Post), String) {
  let author_decoder = {
    use handle <- decode.field("handle", decode.string)
    use display_name <- decode.field(
      "displayName",
      decode.optional(decode.string),
    )
    decode.success(#(handle, display_name))
  }

  let record_decoder = {
    use text <- decode.field("text", decode.string)
    use created_at <- decode.field("createdAt", decode.string)
    decode.success(#(text, created_at))
  }

  let post_decoder = {
    use uri <- decode.field("uri", decode.string)
    use record <- decode.field("record", record_decoder)
    use author <- decode.field("author", author_decoder)
    let #(text, created_at) = record
    let #(handle, display_name) = author
    decode.success(Post(
      uri: uri,
      text: text,
      created_at: created_at,
      author_handle: handle,
      author_name: display_name,
      web_url: post_url(handle, uri),
    ))
  }

  let item_decoder = {
    use post <- decode.field("post", post_decoder)
    decode.success(post)
  }

  let decoder = {
    use feed <- decode.field("feed", decode.list(item_decoder))
    decode.success(feed)
  }

  json.parse(body, decoder)
  |> result.map_error(fn(_) {
    "failed to decode Bluesky feed for " <> fallback_handle
  })
}

fn post_url(handle: String, uri: String) -> String {
  case list.reverse(string.split(uri, "/")) {
    [rkey, "app.bsky.feed.post", ..] ->
      "https://bsky.app/profile/" <> handle <> "/post/" <> rkey
    _ -> "https://bsky.app/profile/" <> handle
  }
}
