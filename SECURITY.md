# Security policy

## Credentials

Do not ship Token Factory or Tavily API keys inside client applications. The `.apiKey` modes exist for local development and simulator testing. Production apps should use `.proxied` with relays that store provider credentials server-side, authenticate callers, validate request scope, and enforce per-user quotas and budgets.

Both HTTP clients require HTTPS and refuse to forward credentials across origins during redirects. A relay must apply the same rule when following upstream redirects.

## Retrieved web content

Search results, extracted pages, crawls, site maps, and research reports are untrusted external input. The Tavily tools label their output accordingly and bound the text returned to the language model. Applications should additionally:

- Keep tool descriptions and instructions explicit about ignoring commands found in retrieved content.
- Restrict domains, paths, crawl depth, breadth, page count, and output size for the product's use case.
- Validate links before presenting them as trusted or actionable.
- Require confirmation before using retrieved content to trigger side effects.
- Avoid placing private URLs, intranet hosts, signed links, credentials, or personal files in model-generated tool arguments.

## Reporting a vulnerability

Until the repository has a dedicated private advisory channel, do not open a public issue containing a live credential, user prompt, response payload, retrieved private content, or exploit details. Contact the repository owner privately and rotate any credential that may have been disclosed.
