---
name: hyperview-patterns
description: Defines Hyperview/HXML conventions for AQNAS mobile clients, covering the `/m/` route prefix for mobile endpoints, the `application/vnd.hyperview+xml` Content-Type, screen structure (`<doc>` root with `<screen>` and `<body>` children), server-driven UI primitives (`<view>`, `<text>`, `<form>`, `<text-field>`, `<list>`, `<item>`), behaviors (`behavior trigger="press" action="navigate" href="..."` and action="replace", "reload", "dispatch-event"), styling via `<styles>` with attribute matching (not CSS), and the React Native thin-shell client in `mobile-client/` that renders these screens. Use when generating or reviewing HXML templates (.hxml.jinja2), adding a mobile route to `app/routes/mobile.py`, debugging why a mobile screen doesn't render or behaviors don't fire, deciding whether a feature should be web-only or mobile-aware, or when the user asks about Hyperview, HXML, server-driven UI, React Native + Hyperview, or the mobile-client shell. Contains examples/ with reference HXML templates for a list screen, detail screen, and form.
---

# hyperview-patterns

Server-driven mobile UI via Hyperview.

## What Hyperview is

Hyperview is "hypermedia for native." Server sends XML (HXML); a React Native client parses it and renders native components. The client is a thin shell — all screens, flows, and logic are defined server-side. Same philosophy as HTMX, applied to mobile.

The AQNAS mobile stack: `mobile-client/` is a minimal Expo app that loads an initial HXML URL and navigates between screens via behaviors. Every screen is a server template.

## Route conventions

- **All mobile endpoints live under `/m/`.** Never collide with web routes (`/users` is web, `/m/users` is mobile).
- **Handler module:** `app/routes/mobile.py`
- **Response Content-Type:** `application/vnd.hyperview+xml` — not `application/xml`, not `text/html`. The mobile client will ignore the response if the Content-Type is wrong.
- **Template extension:** `.hxml.jinja2`. Keep in `templates/mobile/`.
- **Shared fragments** (used by both web and mobile): `templates/components/` with the appropriate extension per fragment.

## Screen structure

Every HXML screen is wrapped in `<doc>`:

```xml
<doc xmlns="https://hyperview.org/hyperview">
  <screen>
    <styles>
      <!-- style definitions -->
    </styles>
    <body style="body">
      <!-- content -->
    </body>
  </screen>
</doc>
```

Key elements:

| Element | Purpose |
|---|---|
| `<doc>` | Required root. Always has the xmlns. |
| `<screen>` | One per document. Wraps styles and body. |
| `<styles>` | Style definitions, referenced by name via `style="..."` attributes. |
| `<body>` | The visible screen. |
| `<view>` | Container, like `<div>`. Stacks children (flex-column by default). |
| `<text>` | Text node, like `<span>` or `<p>`. |
| `<form>` | Group of inputs submitted together. |
| `<text-field>` | Single-line text input. |
| `<select-single>` / `<select-multiple>` | Dropdown-style pickers. |
| `<list>` + `<item>` | Scrollable list. `<item>` is each row. |
| `<image>` | Image. Use `source="{url}"`. |
| `<spinner>` | Loading indicator. |

## Behaviors

Behaviors are how screens react to user input. Attach one or more `<behavior>` elements as children of an interactive element:

```xml
<item>
  <behavior
    trigger="press"
    action="navigate"
    href="/m/posts/42"
  />
  <text>View post 42</text>
</item>
```

### Triggers

| Trigger | Fires when |
|---|---|
| `press` | Element tapped |
| `longPress` | Element held |
| `visible` | Element scrolls into view (load-more patterns) |
| `refresh` | Pull-to-refresh gesture |
| `load` | Screen finishes loading |
| `on-event` | A named event is dispatched elsewhere |

### Actions

| Action | Effect |
|---|---|
| `navigate` | Push a new screen onto the stack |
| `new` | Present a modal (full-screen overlay) |
| `back` | Pop the current screen |
| `close` | Dismiss a modal |
| `replace` | Replace current screen without animation |
| `replace-inner` | Swap inner content of a target element (like HTMX `hx-swap="innerHTML"`) |
| `append` / `prepend` | Add fetched content to a target |
| `reload` | Re-fetch the current screen |
| `dispatch-event` | Fire a named event to trigger other behaviors |

### Common pattern: replace-inner for partial updates

```xml
<view id="comments">
  <!-- initial comment list -->
</view>

<view>
  <behavior
    trigger="press"
    action="replace-inner"
    target="comments"
    href="/m/posts/42/comments"
  />
  <text>Refresh comments</text>
</view>
```

The fetched HXML must be a fragment (no `<doc>` wrapper) when used with `replace-inner`, `append`, or `prepend`.

## Forms

```xml
<form>
  <text-field name="title" placeholder="Title" />
  <text-field name="body" placeholder="Body" multiline="true" />
  <view>
    <behavior
      trigger="press"
      action="navigate"
      href="/m/posts"
      verb="post"
    />
    <text>Submit</text>
  </view>
</form>
```

`verb="post"` (or `"put"`, `"delete"`) sends the form fields as `application/x-www-form-urlencoded`. FastAPI handles this natively — same as web form POST.

## Styling

HXML styles are attribute bags referenced by name. Not CSS.

```xml
<styles>
  <style id="body" flex="1" backgroundColor="#F8FAFC" padding="16" />
  <style id="heading" fontSize="24" fontWeight="700" color="#0F172A" />
  <style id="button" padding="12" backgroundColor="#E34234" borderRadius="6" />
  <style id="buttonText" color="#F8FAFC" fontWeight="700" textAlign="center" />
</styles>

<body style="body">
  <text style="heading">Hello</text>
  <view style="button">
    <text style="buttonText">Tap me</text>
  </view>
</body>
```

Multiple styles can be composed: `style="heading heading-large"`.

Real projects define their palette and type scale in a project-scope color/typography skill, then reference those tokens here. The colors above are placeholders for the example — swap for the project's actual palette.

## Jinja2 integration

HXML templates use Jinja2 like HTML templates. Switch the environment per handler:

```python
@app.get("/m/posts", response_class=Response)
async def mobile_posts(request: Request) -> Response:
    posts = await services.posts.list_all()
    return templates_mobile.TemplateResponse(
        request=request,
        name="posts_list.hxml.jinja2",
        context={"posts": posts},
        media_type="application/vnd.hyperview+xml",
    )
```

Always set `media_type` explicitly — FastAPI's default for `Response` is `text/plain`, which the Hyperview client ignores.

## Fragment vs full screen

A handler that returns a full screen returns a `<doc>`-wrapped document. A handler that returns a fragment (for `replace-inner`, etc.) returns children only, no `<doc>` wrapper.

Route them separately when the same data appears in both contexts:

- `/m/posts` — returns the full posts list screen (with `<doc>`)
- `/m/posts/fragment` — returns just the list body (no `<doc>`)

Or use a single handler with a `?fragment=true` query param and branch the template selection. Both patterns work; pick one per project and stick with it.

## Examples

See `${CLAUDE_SKILL_DIR}/examples/`:

- `list_screen.hxml.jinja2` — scrollable list with pull-to-refresh and tap-to-navigate
- `detail_screen.hxml.jinja2` — single-record detail view with back navigation
- `create_form.hxml.jinja2` — form with fields and submit behavior

## What not to do

- Don't return HTML from `/m/` routes. The mobile client can't parse it.
- Don't mix HTMX attributes (`hx-get`, `hx-post`) into HXML. They're ignored.
- Don't nest `<doc>` inside `<doc>`. One document per response.
- Don't use inline styles (`style="color: red"` as CSS). HXML styles are referenced by id, not inline declarations.
- Don't assume browser globals (window, document, fetch). There is no JavaScript runtime — the client is native React Native.
- Don't put secrets in HXML templates. They're delivered to untrusted clients, same as HTML.

## Failure modes

- **Screen renders blank.** Check `Content-Type` header on the response. If not `application/vnd.hyperview+xml`, the client silently drops the response.
- **Behavior doesn't fire.** Confirm the trigger is one of the supported values (typos fail silently). Confirm the action URL is reachable and returns HXML.
- **Styles not applied.** Style `id` must match `style` attribute exactly, case-sensitive. A style referenced but not defined is ignored, not errored.
- **Form submit does nothing.** Missing `verb="post"` — the default is GET, which won't send form data. Or the endpoint expects JSON but the client sends URL-encoded.
- **Fragment response has `<doc>` wrapper.** `replace-inner` and friends expect children only. Remove the wrapper or route to a fragment-specific endpoint.
- **Infinite refresh loop.** A `trigger="load"` behavior that causes the screen to reload will loop. Use `trigger="visible"` with a one-shot pattern or gate with state.
