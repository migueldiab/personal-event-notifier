# Visit Cedar Park events source recon

Target: <https://visitcedarparktexas.com/events/> ("Upcoming Events | Cedar Park | Stay for More").
Recon date: 2026-11-27 (America/Chicago). Fixture capture: `2026-11-28T00:22:26+00:00` UTC.

## Outcome

The Tourism/CVB site's HTML is behind an Akamai "Access Denied" wall, and its event
list is rendered entirely client-side by a Simpleview `layoutjs` Vue widget
(`contentRender_name_plugins_events_layout_list` / `layoutjsContainer`), so the
archived HTML and `web_extract` contain **no event entries**. The widget reads a
**live, public Simpleview REST JSON API** which *is* fetchable with a browser-like
User-Agent plus a site token. A validated 30-event capture is committed at
`spec/fixtures/visit_cedar_park_events.json`.

## Exact fetchable URL (verified 2026-11-27)

Two requests:

1. **Token** — `GET https://visitcedarparktexas.com/plugins/core/get_simple_token/`
   → plain-text token (32 hex chars). Two fetches minutes apart returned the same
   value. Fetch it at runtime; do **not** hard-code or commit the token.
2. **Events** — `GET https://visitcedarparktexas.com/includes/rest_v2/plugins_events_events_by_date/find/`
   with query parameters:

   - `json` = URL-encoded JSON:
     ```json
     {"filter":{"active":true},"options":{"limit":30,"skip":0,"count":true,"sort":{"date":1,"rank":1,"title_sort":1}}}
     ```
   - `token` = value from step 1.

   Required request headers: browser-like `User-Agent` (e.g.
   `Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0 Safari/537.36`)
   **and** `Referer: https://visitcedarparktexas.com/events/`.
   With the default `Python-urllib/3.x` UA the identical URL returns HTTP 403
   `Access Denied` (`errors.edgesuite.net`); with the browser UA it returns
   HTTP 200 `application/json; charset=utf-8`.

Response envelope: `{"docs": {"count": 5772, "docs": [ ...event objects... ]}}`.
The fixture preserves this envelope verbatim under `docs` and adds a `_meta`
object (source URL, capture time, archived recon reference, request filter/options).
Scrapers should read `payload["docs"]["docs"]` and ignore `_meta`.

## Provenance / how the endpoint was found

- Archived page: <https://web.archive.org/web/20260713162908id_/https://visitcedarparktexas.com/events/>
  — **as archived 2026-07-13**, raw `id_` capture (~150 KB). Used only to read the
  widget configuration; it contains no event records (client-side rendering).
- Archived `requirejs_config_437d02ee_690c79a4.js` (as archived 2026-07-13) mapped
  `plugins_common_custom_layoutjs` and the `plugins_core` package.
- Live JS assets remain readable even though HTML is blocked:
  - `.../core/plugins/common/virtuals/js/custom_layoutjs.js` — has a second endpoint
    `/includes/rest_v2/<model>/aggregate/` for facet counts.
  - `.../core/plugins/core/public/js/main.js` — `define(["./tokenLoader!"], ...)`.
  - `.../core/plugins/core/public/js/tokenLoader.js` — `$.get("/plugins/core/get_simple_token/")`.
- The inline widget script calls
  `/includes/rest_v2/plugins_events_events_by_date/find/?json={filter,options}&token=<core.simpleToken>`
  and maps `res.docs.count` / `res.docs.docs`.

## Field mapping

All paths are relative to one element of `docs.docs`. Coverage is from the 30-event fixture.

| Field | JSON path | Notes |
|---|---|---|
| title | `title` | Prefer over `cms_title`, which appends `(recid)`. 30/30 present. |
| date | `date` (also `dates.eventDate`, `nextDate`) | ISO-8601 UTC, `YYYY-MM-DDTHH:MM:SS.000Z`, conventionally `05:59:59Z`. 30/30. See timezone warning below. |
| time | `startTime` (`HH:MM:SS`, 24h local, 18/30) or `times` (human text e.g. `Starting: 7:00 PM`, `From: 07:00 PM to 09:30 PM`, 11/30) | Missing on recurring/all-day entries — emit all-day / no time. |
| venue | `location` (30/30), fallback `hostname` (12/30), then `"Cedar Park, TX"` | Address: `address1`, `city`, `state`, `zip`; geo: `latitude`, `longitude`. |
| url | `absoluteUrl` (30/30, absolute) or `url` (relative `/event/<slug>/<recid>/`) | Use `absoluteUrl` for the canonical link; `linkUrl` (27/30) is an external ticket/vendor link. |
| price | **No structured `price` field exists.** `admission` (22/30) is free text such as `$34.26` or `15$ per child, children under 1 get in for free...` | Store as a price note / description; parse a number only if explicitly needed. |
| category | `categories[]` → `{catName, catId}` (30/30) | `primarycatid` marks the primary category. Values include Concerts/Live Music, Austin Spurs Basketball, Holiday Festivities, Festivals/Markets, Free, etc. |
| description | `description` (HTML, 30/30) or `teaser` (HTML, truncated, 30/30) | Strip HTML tags. |
| image | `media_raw[0].mediaurl` or `_media[0].mediaurl` | |
| id | `recid` / `recId` | Stable per-event id, appears in the URL. |

### Date/timezone warning (important for the scraper)

`date`, `dates.eventDate` and `nextDate` are end-of-local-day instants expressed in
UTC as `...T05:59:59.000Z`. Example: `2026-11-28T05:59:59.000Z` is
`2026-11-27 23:59:59 America/Chicago`. Taking `date[0, 10]` naively is **off by one
day**. Convert to `America/Chicago` first, then take the calendar date.
`startDate` is local midnight encoded as `...T06:00:00.000Z` (CST) and is a good
cross-check. `startTime` is a separate local wall-clock string. Recurring events
can have a much older `startDate` (e.g. `2026-07-02`) with a current `nextDate`.
Use `date`/`nextDate` for the occurrence being listed.

## Pagination

- `options.skip` is a zero-based offset, `options.limit` the page size; `docs.count`
  is the total number of matching documents (5772 for `{"active":true}`).
- Advance with `skip += limit`; stop when `skip >= count` or a page returns no docs.
- The public widget defaults: `custom_items_per_page = 12`, `defaultRange = "month"`,
  `defaultSort/ sort = "date"`, sort object `{date: 1, rank: 1, title_sort: 1}`,
  date range from today to +1 month, and a category whitelist. The scraper may
  keep it simpler (`{"active": true}`) since the source already returns upcoming
  occurrences first.
- Optional narrowing: `filter.date_range = {start: {"$date": "<ISO>"}, end: {"$date": "<ISO>"}}`.

## Anti-bot posture

- HTML `/events/` and `/event/rss/`: Akamai HTTP 403 "Access Denied", ~384–391 bytes,
  referencing `errors.edgesuite.net`. Do not retry-loop these URLs.
- REST API with default `Python-urllib` UA: 403 access-denied body. With browser
  UA + Referer but no `token`: HTTP 200 body `Invalid credentials` (19 bytes) —
  a fake success; treat it as a failure.
- Token endpoint and REST API are reachable with the browser UA; JS assets and
  `requirejs_config` are readable without special treatment.
- Wayback: many HTML snapshots (2019–2026) exist but none of `/includes/rest_v2/*`;
  `/event/rss/` has no snapshot. archive.today was unnecessary once the live API
  was found; Jina Reader was skipped (`JINA_API_KEY` unset).
- Detection markers for rejection: `Access Denied`, `errors.edgesuite.net`,
  `Invalid credentials`, `Just a moment`, `Attention Required`, `Redirecting`,
  or a body that is only the `layoutjsContainer` shell with no `docs.docs`.

## Validation performed

- Fixture contains **30 real upcoming events** dated 2026-11-28 → 2026-11-30
  (all after the 2026-11-27 recon date), well above the 3-event minimum.
- 30/30 docs have `title`, `date`, `location`, `absoluteUrl`, `categories`, `description`;
  18/30 have `startTime`; 11/30 have `times`; 22/30 have `admission` price text.
- Zero occurrences of access-denied / interstitial / redirect-stub markers.
- No token value or credential is stored in the fixture; `_meta` records only URLs.

## Follow-up stories (already on the board, in dependency order)

1. `t_f9e77cb1` — SCRAPER: `lib/weekly_local_events/scrapers/visit_cedar_park_scraper.rb`
   plus spec; `SOURCE_NAME = "visit_cedar_park"`; token + API fetches through
   `BaseScraper#fetch`; parse `docs.docs`; `America/Chicago` date normalization.
2. `t_68233efa` — REGISTRY: add `visit_cedar_park` to `KNOWN_SCRAPERS` /
   `DEFAULT_SCRAPERS`, require the file, enable it in both config files; keep distinct
   from `cedar_park` (the city CivicEngage source).
3. `t_d87715d7` — VCR: record `visit_cedar_park_events` cassette from the Simpleview
   JSON endpoint (never an access-denied page) and add a replay spec.
4. `t_41a07ff8` — ANTI-BOT: graceful 403 / JS-shell fallback and cached-fixture path.
5. `t_ed9ce921` — VERIFY: end-to-end digest with both Cedar Park sources, dedupe,
   JSON links, README/config updates.

Suggested extra follow-up (not yet a card): periodically re-verify that
`/plugins/core/get_simple_token/` still returns a usable token and that the API's
`docs.count` remains non-zero; alert if the source starts returning denials.
