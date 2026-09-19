# Blog editing guidelines

These are the author's preferences established while editing this blog. Apply
them to future work in this repository; newer explicit user instructions take
precedence.

## Communication and scope

- Translate requested posts into English.

## Translation and editorial style

- Use natural, technically precise English. Lightly improve awkward wording and
  remove dated jokes, giggling, and unnecessary informality; keep the author's
  voice and technical argument.
- Preserve the historical perspective. Do not silently update old claims,
  examples, or APIs to describe today's C#, F#, or CLR. Keep deliberately invalid
  examples and pseudocode recognizable as such.
- Translate prose, headings, and explanatory code comments. Preserve identifiers
  and behavior unless a correction is necessary and clear from context.
- Preserve post dates, slugs, and front matter except fields that need translation
  or changes explicitly requested by the author. A public URL such as
  `/2012/06/21/generic-csharp.html` normally maps to
  `_posts/2012-06-21-generic-csharp.markdown`.
- When editing a series, keep its introductions, numbering, and cross-links
  consistent. Do not add redirects automatically when merging or reordering posts.

## Code examples

- In C#, use BSD/Allman braces for multiline bodies. Preserve the snippet's
  indentation width (commonly two spaces).
- Keep existing one-line members on one line. Do not expand empty declarations
  or compact comment-only declarations merely to apply Allman formatting.
- Write placeholder member bodies on one line using the Unicode ellipsis:
  `private int F(int x) { … }`. Do not expand a body containing only `...` over
  several lines.
- Use explicit `private` for C# members and nested types where
  accessibility would otherwise default to private. Do not add it to top-level
  types, interface declarations, or constructs where it would change semantics
  or be invalid for the language version being discussed.
- Preserve F# snippet indentation exactly. Never apply C# brace-formatting rules
  to F#.
- Start ordinary code comments with a lowercase letter and omit the final
  period. Preserve the spelling of identifiers, proper names, and abbreviations.
  XML documentation comments (including C# and F# `///` comments and C#
  `/** ... */` documentation blocks) are exempt from that style rule.

## Links, assets, and comments

- When asked to repair a lost reference, look for the original or an archived
  source. For documents preserved locally, use `assets/docs/`, record provenance
  in `assets/docs/README.md`, and link through `{{ site.baseurl }}/assets/...`.