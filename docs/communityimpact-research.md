# Community Impact calendar — recon findings

Researched 2026-11-26 against the live site. All selectors below were **confirmed against live pages** in a real browser (see [Verification](#verification)), not inferred from sample markup.

## TL;DR

| Question | Answer |
| --- | --- |
| JS-rendered or server-rendered? | **Server-rendered HTML** (Next.js App Router / React Server Components), hydrated with JS afterwards. Event cards are present in the raw HTTP response — no JS execution needed. |
| Pagination or infinite scroll? | **Classic server-side pagination**, 24 events/page. No infinite scroll, no "Load more". |
| Bot protection? | **Cloudflare is present as CDN/WAF only — no challenge active.** No PerimeterX, no CAPTCHA, no interstitial. HTTP 200 with full content. |
| Price on listing? | **None.** Also absent on event detail pages and absent from schema.org `offers`. |
| Regional variants? | 301 redirects into locale calendars on the same Next.js app, identical DOM structure. |

## URLs and redirects

| Requested URL | Final URL | Event cards (2026-11-26) |
| --- | --- | --- |
| `https://www.communityimpact.com/calendar/` | `https://communityimpact.com/calendar/` (301) | 24 (page 1), 19 (page 2) = 43 total |
| `https://satxevents.communityimpact.com/` | `https://communityimpact.com/san-antonio/calendar/` (301) | 2 |
| `https://dfwevents.communityimpact.com/` | `https://communityimpact.com/dallas-fort-worth/calendar/` (301) | 8 |

Always follow redirects and use the canonical apex host.

Relevant response headers (master calendar):

```
HTTP/2 200
content-type: text/html; charset=utf-8
server: cloudflare
cf-cache-status: EXPIRED
cf-ray: a60c8b1f1e97e68b-DFW
x-powered-by: Next.js
vary: rsc, next-router-state-tree, next-router-prefetch, ...
cache-control: public, s-maxage=300, stale-while-revalidate=86400
```

## 1. Rendering status — definitively server-rendered

Evidence:

1. A plain `curl` request (no JS, no browser) returned a 379 KB HTML document containing all 24 event cards, titles, times, venues and the full JSON-LD payload.
2. Browser DOM counts match the raw HTML counts exactly: 24 cards, 24 titles, 24 clock spans in both.
3. No XHR/fetch request supplies event data — the observed network calls are analytics/telemetry plus Next.js RSC prefetches (`?_rsc=...`) for navigation.
4. Pagination links are ordinary `<a href="/calendar/?from=...&to=...&page=2">` anchors, not JS handlers.

Conclusion: a plain HTTP fetch plus an HTML parser is sufficient. A headless browser is **not required** for the event data (only for optional JS-only widgets; none were needed here).

## 2. Confirmed selectors

All selectors below verified live on both `communityimpact.com/calendar/` and the redirected San Antonio calendar.

| Field | CSS selector (browser) | XPath (Nokogiri-safe) | Notes |
| --- | --- | --- | --- |
| Event card | `a[href*="/calendar/"][class*="bg-card"]:not([href="/calendar/submit/"])` | `//a[contains(@class,"bg-card") and contains(@href,"/calendar/") and not(@href="/calendar/submit/")]` | Exclude the "List it here for free" CTA, which shares `bg-card`. |
| Title | `h3[class*="line-clamp-2"]` | `.//h3[contains(@class,"line-clamp-2")]` | One per card. |
| Time range | `svg.lucide-clock + span` | `.//p[.//svg[contains(@class,"lucide-clock")]]/span[1]` | Text varies: `12:00 AM – 11:59 PM`, `11:00 AM`, or `Multiple showtimes`. |
| Venue | `svg.lucide-map-pin + span` | `.//p[.//svg[contains(@class,"lucide-map-pin")]]/span` | Optional — 1 of 3 sampled cards had no venue. |
| Date-span note | `p[class*="pl-5"]` | `.//p[contains(@class,"pl-5")]` | e.g. `Through Nov. 30`. Optional. |
| Detail link | card `href` | `@href` | Relative, e.g. `/austin/calendar/<slug>/`. |
| Pagination | `nav[aria-label="Pagination"] a[aria-label="Next page"]` | `//nav[@aria-label="Pagination"]//a[@aria-label="Next page"]` | Absent on last page / single-page locales. |
| Structured data | `script[type="application/ld+json"]` where `@type="CollectionPage"` | — | 4 JSON-LD blocks on the page; pick the CollectionPage. |

**Nokogiri pitfall:** Tailwind classes include dots (`gap-1.5`, `text-sm`). Never write `.gap-1.5` as CSS — `.5` becomes a class selector. Use `[class*="..."]` or the XPath `contains(@class, ...)` forms above.

### Verified extraction sample (live DOM)

```json
{
  "href": "/austin/calendar/meet-megan-jaster-austin-artist-of-the-month-cmvjqfdgy0b9s01quw41kchva/",
  "title": "Meet Megan Jaster · Austin Artist of the Month",
  "time": "Multiple showtimes",
  "venue": "Unchained.Art Contemporary Gallery",
  "date_note": "Through Nov. 30"
}
```

San Antonio page (same selectors, different locale):

```json
{
  "href": "/san-antonio/calendar/thanksgiving-day-at-hard-rock-cafe-cmwx58rgw00op6bmhmr4ddd32/",
  "title": "Thanksgiving Day at Hard Rock Cafe!",
  "time": "11:00 AM",
  "venue": "Hard Rock Cafe - San Antonio",
  "date_note": null
}
```

### Raw card markup (for reference)

```html
<a class="group flex h-full flex-col overflow-hidden rounded-lg border border-border bg-card transition hover:border-events/50 hover:shadow-sm"
   href="/austin/calendar/meet-megan-jaster-austin-artist-of-the-month-cmvjqfdgy0b9s01quw41kchva/">
  <div class="relative aspect-[16/9] w-full overflow-hidden bg-events-soft">...</div>
  <div class="flex flex-1 flex-col gap-1.5 p-4">
    <h3 class="line-clamp-2 text-base font-bold leading-snug text-foreground transition group-hover:text-events-strong">
      Meet Megan Jaster · Austin Artist of the Month
    </h3>
    <p class="flex items-center gap-1.5 text-sm text-muted-foreground">
      <svg class="lucide lucide-clock h-3.5 w-3.5 shrink-0 text-events" ...>...</svg>
      <span>Multiple showtimes</span>
    </p>
    <p class="pl-5 text-xs text-muted-foreground">Through Nov. 30</p>
    <p class="flex min-w-0 items-center gap-1.5 text-sm text-muted-foreground">
      <svg class="lucide lucide-map-pin h-3.5 w-3.5 shrink-0 text-events" ...>...</svg>
      <span class="truncate">Unchained.Art Contemporary Gallery</span>
    </p>
  </div>
</a>
```

## 3. Structured-data alternative (recommended)

The server emits a `CollectionPage` JSON-LD block with one `ListItem` per event:

```json
{
  "@type": "ListItem",
  "position": 1,
  "url": "https://communityimpact.com/austin/calendar/meet-megan-jaster-austin-artist-of-the-month-cmvjqfdgy0b9s01quw41kchva/",
  "item": {
    "@type": "Event",
    "name": "Meet Megan Jaster · Austin Artist of the Month",
    "startDate": "2026-11-01T05:00:00.000Z",
    "endDate": "2026-12-01T05:59:59.999Z",
    "description": "Austin painter Megan Jaster is November's Austin Artist of the Month ...",
    "location": {
      "@type": "Place",
      "name": "Unchained.Art Contemporary Gallery",
      "address": "311 West 7th Street, Suite 307, Austin, TX 78701"
    },
    "keywords": "Arts"
  }
}
```

`mainEntity.numberOfItems` matched the visible card count on every page tested (24 master, 2 satx, 8 dfw, 19 master page 2). This is cleaner than DOM scraping for `startDate`/`endDate`/`description`, but note the JSON-LD dates describe the **event's overall run**, not the particular day the card is shown for. The DOM time text describes the day filtered by the query. Use both if the scraper needs per-day times.

## 4. Pagination

- `<nav aria-label="Pagination">` with numbered links and `aria-label="Next page"` / `Previous`.
- Page size: **24**. Master calendar had 43 events over 2 pages.
- URL shape: `/calendar/?from=2026-11-26&to=2026-11-26&page=2`.
- `from`/`to` control the date window. Verified `?from=2026-11-26&to=2026-12-03` renders heading `Events Nov. 26 – Dec. 3` with 24 cards and page links up to `page=20`.
- Scraper strategy: iterate `page=N` until the `Next page` link disappears, or detect the last page from the numbered links.
- No infinite-scroll or lazy-loading container was found.
- Regional calendars with few events have no pagination nav at all.

## 5. Bot protection / login wall

- `server: cloudflare`, `cf-ray`, `cf-cache-status` headers are present — Cloudflare is the CDN/WAF layer.
- **No active challenge**: plain `curl` with a normal Chrome UA returned HTTP 200 with full event content. No `Just a moment...`, `Attention Required`, `cf-challenge-*`, PerimeterX/`_px*`/`px-captcha`, Turnstile or CAPTCHA markup. No HTTP 403/429 on any request.
- Browser cookies observed (`___nrbic`, `compass_uid`, `_fbp`, `_gegeo`, `_lc2_fpi`, etc.) are analytics/geolocation cookies, not bot challenges.
- Additional third-party scripts seen in network traffic: `api.communityimpact.com/v1/collect`, `events.newsroom.bi/ingest.php`, `events.newsroom.bi/data/rfv.php`, LiveConnect/liadm, `cloudflareinsights.com/cdn-cgi/rum`. These are telemetry, not data sources for the calendar.
- `/premium-signin` was referenced in earlier task notes but did **not** appear anywhere in the fetched calendar HTML, nor did any login wall trigger while reading listings or detail pages.
- Practical guidance: still keep a modest request rate (~5 req/min) out of courtesy; no stealth browser or CAPTCHA handling is required for these pages.

## 6. Price information

- No price text, `$` amounts, `Free`/`Price` labels, or `schema.org/offers` on the listing cards.
- Checked an event detail page (`beyond-brushstrokes...`): its JSON-LD `Event` has `name`, `startDate`, `endDate`, `description`, `image`, `location`, `organizer`, `keywords`, `inLanguage` — **no `offers`**, and no price text in the rendered body (the only "free" strings are the newsletter CTA).
- Set `price = nil` and do not scrape detail pages just for price.

## 7. "Multiple showtimes"

- The listing renders the literal string `Multiple showtimes` in the clock `<span>`; the detail page for such an event renders the same string. Individual showtimes are **not** present in the server HTML.
- In the Next.js RSC flight payload each card has a key shaped `<event-id>-<ISO timestamp>` (e.g. `cmvjqfdgy0b9s01quw41kchva-2026-11-26T06:00:00.000Z`) — one timestamp per visible card, not a list.
- Consequence: expanding a multi-showtime event into individual entries from these pages requires either the date-window query (`from`/`to`) with one request per day, or an external source. The `events.newsroom.bi` endpoints appear in telemetry but were **not** verified as a data API — treat as an unconfirmed lead only.

## Verification

All checks performed 2026-11-26 with live requests:

1. `curl -L -A 'Mozilla/5.0 ... Chrome/120.0' https://www.communityimpact.com/calendar/` → headers + body saved; raw HTML contains all event cards and JSON-LD.
2. `curl -L` on each regional host → 301 to locale calendar, same DOM structure confirmed by parsing.
3. Real browser (Chromium) at `https://communityimpact.com/calendar/` → `querySelectorAll` counts: 24 cards, 24 titles, 24 times, 24 venues; extraction of first 4 cards returned populated values; `nav[aria-label="Pagination"]` present with `?page=2` next link; `challengeText: false`.
4. Same probe at redirected `https://communityimpact.com/san-antonio/calendar/` → 2 cards, same selectors populated.
5. `curl` of `?from=2026-11-26&to=2026-11-26&page=2` → 19 cards, confirms 43 total; `?from=2026-11-26&to=2026-12-03` → 24 cards, pagination through page 20.
6. `curl` of two event detail pages → no price fields in HTML or JSON-LD.

## Recommendations for the scraper implementation

1. Fetch with plain HTTP + browser-like UA; follow redirects. No headless browser needed.
2. Prefer JSON-LD `CollectionPage` for title, description, overall start/end, venue and URL; use DOM selectors for the per-day time text and date note.
3. Iterate `page=N` with an explicit `from`/`to` window; stop when no `Next page` link exists.
4. Treat missing venue as nil/TBD and missing price as nil; never attempt credentialed login.
5. Keep ~5 req/min with jitter as a courtesy; do not add CAPTCHA logic unless a future check shows a real challenge.
