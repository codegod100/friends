//// Home page rendering.

import friends/config.{type Config}
import friends/html
import friends/session.{type UserSession, display_name}
import friends/store.{type Store, handles}
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/string

pub fn render(
  config: Config,
  user: Option(UserSession),
  store: Store,
  flash: Option(String),
) -> String {
  let body = case user {
    None -> render_guest(config)
    Some(current_user) -> render_dashboard(config, current_user, store, flash)
  }

  html.page("Friends", body)
}

fn render_guest(config: Config) -> String {
  "<header><h1>Friends</h1></header>"
  <> "<p>Sign in with Pocket ID to curate a unified Atom feed from your favorite Bluesky accounts.</p>"
  <> "<p><a class=\"btn\" href=\"/auth/login\">Sign in with Pocket ID</a></p>"
  <> "<p class=\"meta\">Identity provider: "
  <> html.escape_text(config.oidc_issuer)
  <> "</p>"
}

fn render_dashboard(
  config: Config,
  user: UserSession,
  store: Store,
  flash: Option(String),
) -> String {
  let user_handles = handles(store, user.sub)
  let flash_html = case flash {
    None -> ""
    Some(message) ->
      "<div class=\"flash\">" <> html.escape_text(message) <> "</div>"
  }

  "<header><h1>Friends</h1>"
  <> "<div>"
  <> "<span class=\"meta\">Signed in as "
  <> html.escape_text(display_name(user))
  <> "</span> "
  <> "<a class=\"btn secondary\" href=\"/auth/logout\">Sign out</a>"
  <> "</div></header>"
  <> flash_html
  <> "<section>"
  <> "<h2>Bluesky handles</h2>"
  <> "<p class=\"meta\">Add public Bluesky handles to merge their posts into one Atom feed.</p>"
  <> "<form method=\"post\" action=\"/handles\">"
  <> "<input type=\"text\" name=\"handle\" placeholder=\"name.bsky.social\" required>"
  <> "<button type=\"submit\">Add handle</button>"
  <> "</form>"
  <> render_handle_list(user_handles)
  <> "</section>"
  <> "<section>"
  <> "<h2>Your feed</h2>"
  <> "<p>Subscribe in any Atom reader:</p>"
  <> "<p><a class=\"btn\" href=\"/feed.atom\">"
  <> html.escape_text(config.base_url <> "/feed.atom")
  <> "</a></p>"
  <> "</section>"
}

fn render_handle_list(user_handles: List(String)) -> String {
  case user_handles {
    [] -> "<p class=\"meta\">No handles yet. Add one above to get started.</p>"
    _ ->
      "<ul class=\"handles\">"
      <> {
        user_handles
        |> list.map(fn(handle) {
          "<li class=\"handle\"><span>@"
          <> html.escape_text(handle)
          <> "</span>"
          <> "<form method=\"post\" action=\"/handles/"
          <> html.escape_attr(handle)
          <> "/delete\">"
          <> "<button type=\"submit\" class=\"secondary\">Remove</button>"
          <> "</form></li>"
        })
        |> string.join("")
      }
      <> "</ul>"
  }
}
