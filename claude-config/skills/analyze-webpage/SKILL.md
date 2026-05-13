---
name: analyze-webpage
description: Fetches and analyzes a webpage for design patterns, copywriting, information architecture, and technical implementation signals, returning a structured report covering palette, typography, spacing, layout, interaction patterns, copy voice, and technical stack guesses. Use when the user shares a URL and asks to analyze, break down, study, or extract patterns from it; when referencing a competitor or inspiration site during a meeting; or when the user asks "what do you think of {url}". Read-only — never submits forms, follows links beyond the initial URL, or stores credentials.
argument-hint: <url>
allowed-tools: WebFetch, Read, Write
---

# /analyze-webpage

Render a webpage and report back a structured analysis.

## Invocation

`/analyze-webpage <url>` or triggered automatically when the user shares a URL and asks for analysis.

`$ARGUMENTS` is the URL. If empty and no URL in the surrounding conversation, ask.

## Auto-invocation heuristics

Unlike the other 5 command skills, this one is auto-invocable. Claude should load and use it when:

- The user shares a URL followed by "analyze", "what do you think", "break down", "what's going on with", "extract the design from"
- The user asks to study a competitor, reference site, or inspiration
- A meeting discussion references a URL as reference material

Do not auto-invoke for:
- Quick fact lookups ("what's on their homepage?") — use WebFetch directly, don't produce the full structured report
- URLs in the user's own projects (just read the files)

## Step 1 — Fetch and render

Use Playwright MCP if available (it's the default for AQNAS — see infrastructure MCP list). Capture:

1. Full-page screenshot (not just viewport)
2. Rendered HTML snapshot (after JS execution)
3. Computed styles for the first 30 visible elements
4. Network request summary (domains, asset types)
5. Any console errors or warnings

If Playwright MCP is unavailable, fall back to `WebFetch` for HTML + links only, and note in the report that visual analysis is limited.

## Step 2 — Extract design tokens

From the rendered page, identify:

- **Palette** — 3–5 dominant colors with hex values and role (background, primary, accent, text, muted)
- **Typography** — font families (heading, body, mono if present), type scale (heading size ratios)
- **Spacing** — common padding/margin values, suggesting the underlying scale (8pt, 4pt, arbitrary)
- **Corner radii** — consistent values or none
- **Shadows/elevation** — if any, the general style (subtle, pronounced, colored, none)

Report with hex/px values, not vague words.

## Step 3 — Layout and composition

- Grid system (fixed width, fluid, breakpoints observable)
- Primary layout pattern on the hero (side-by-side, centered stack, full-bleed image, etc.)
- Navigation pattern (top bar, side, hamburger, anchor, none)
- Content density (sparse, moderate, dense)
- Information hierarchy — what the eye hits first, second, third

## Step 4 — Interaction patterns

- Call-to-action style (button, text link, card, inline form)
- Form patterns if any (email capture, multi-step, etc.)
- Hover/focus treatment (color shift, elevation, underline, none)
- Animation presence (fades, reveals on scroll, hero motion, none)
- Any unusual or novel interaction worth flagging

## Step 5 — Copy analysis

- Voice — formal/informal, warm/cold, dry/enthusiastic, playful/serious
- Reading level (short sentences + concrete nouns vs. dense academic)
- Headline pattern (how many words, punctuation style)
- Use of jargon, metaphor, humor
- Specific phrases or words worth noting

## Step 6 — Technical signals

- Framework (React, Vue, Svelte, HTMX, vanilla, Webflow, Framer, Squarespace, Wix — best-guess from DOM/network)
- Hosting/CDN (Cloudflare, Vercel, Netlify, GitHub Pages, custom)
- Font delivery (Google Fonts, self-hosted, Adobe, system)
- Analytics (GA4, Plausible, Fathom, Mixpanel, none detected)
- Performance hints (image lazy loading, WebP/AVIF, preload tags)
- Accessibility signals (alt text present, heading hierarchy, form labels)

## Step 7 — Report format

```markdown
# {URL}

## Palette
- #XXXXXX — role
- #XXXXXX — role
...

## Typography
- Heading: {font}, {weight}, {size range}
- Body: {font}, {weight}, {size}
- Mono: {font} (if present)

## Spacing & shape
- Scale: {e.g. 8pt observed}
- Radius: {e.g. 6px / pill / none}
- Shadows: {style}

## Layout
- Hero pattern: {description}
- Navigation: {description}
- Density: {sparse/moderate/dense}
- Hierarchy: {what lands first, second, third}

## Interaction
- CTA style: {description}
- Forms: {description or "none visible"}
- Animation: {description or "static"}

## Copy
- Voice: {adjectives}
- Headline pattern: {observation}
- Notable phrases: "{...}", "{...}"

## Technical signals
- Stack (guess): {framework}
- Hosting: {CDN/host}
- Fonts: {delivery}
- Analytics: {tools}
- Performance: {notes}
- A11y: {notes}

## Takeaways for AQNAS
- {1–3 patterns worth studying or avoiding, in context of the AQNAS brand guide}
```

The last section is the point — everything else is setup.

## What this skill never does

- Never submits forms, clicks buttons that trigger backend actions, or logs into sites
- Never follows links beyond the initial URL unless the CEO explicitly asks
- Never stores credentials or cookies
- Never rates the site as "good" or "bad" — only describes patterns; evaluation is the CEO's call

## Failure modes

- **Playwright MCP unavailable.** Fall back to WebFetch, note the limitation in the report.
- **Paywall or login wall.** Report what's visible; don't attempt auth.
- **JS-heavy SPA that doesn't render content in HTML.** Playwright handles this; WebFetch does not. Flag the mismatch if you had to fall back.
- **Site blocked or 404.** Report and stop. Don't retry aggressively.
