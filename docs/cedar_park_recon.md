# Cedar Park events source — recon findings

**Task:** find a reliably fetchable source for <https://www.cedarparktexas.gov/177/Events> and
capture a real fixture.

## Decision

The requested page is **not a data source**. Its only archived copy (as archived 2025-10-25)
contains an intro paragraph, a "4th of July" graphic link and a Parks sponsorship form —
**zero event records**. The data-bearing page is the CivicEngage city calendar at
<https://www.cedarparktexas.gov/calendar.aspx>, which renders a month grid of real events with
schema.org microdata.

The live host is 100% behind Cloudflare. The only reliably fetchable source found is a
Wayback **raw (`id_`) snapshot** of the calendar page, as archived **2026-02-07**.

- Fixture: `spec/fixtures/cedar_park_events.html`
- Snapshot provenance: **archived snapshot, as archived 2026-02-07 — not the live page.**
- The fixture's 107 events are February 2026 events relative to that capture date. Do not
  present them as current/upcoming as of today.

## Recovery ladder — what was tried

| Route | Target | Result | Verdict |
|-------|--------|--------|---------|
| Live fetch (curl, browser) | `/177/Events`, apex + `www`, http + https, `?output=1` | HTTP 403, 5,661-byte Cloudflare "Attention Required" interstitial | blocked |
| Live API-first pivot | `/api/`, `/api/calendar/events`, `/api/Calendar/GetEvents`, `/Calendar/GetEvents`, `/calendar.aspx`, `/rss.aspx`, `/sitemap.xml`, `/robots.txt` | all HTTP 403, same Cloudflare body | blocked — WAF covers the whole host, not just HTML |
| Wayback availability API | `/177/Events` | one snapshot, `20251025171036` | fetched; no events in body |
| Wayback `id_` snapshot | `/calendar.aspx` `20260207030455` | HTTP 200, 343,638-byte HTML, 107 event entries | **accepted** |
| Wayback `id_` snapshot | `calendar.aspx?CID=24` `20251024145945` | HTTP 200, one event (NightMarket.Fun) | usable but too thin |
| Wayback RSS feed | `RSSFeed.aspx?ModID=58&CID=All-calendar.xml` `20230204052436` | valid RSS but **0 `<item>` elements** | rejected |
| archive.today rotation (`archive.ph/.md/.li/.is`) | `/177/Events` | HTTP 200 + ~59 KB each, but title `archive.ph`, body "One more step / security check / CAPTCHA" | **rejected — fake 200** |
| Jina Reader | — | skipped, `JINA_API_KEY` is unset | not attempted |
| CDX enumeration | several queries | 2 of 4 returned Internet Archive "Temporarily Offline" | not retried (per skill) |

## Exact fetchable URL

```bash
curl -sL --compressed --max-time 90 \
  'https://web.archive.org/web/20260207030455id_/https://www.cedarparktexas.gov/calendar.aspx' \
  -o cedar_park_calendar.html
```

The `id_` form returns the original captured bytes (gzip-encoded, hence `--compressed`;
`gzip -dc` also works on the raw download). The non-`id_` replay URL injects Wayback chrome;
the `id_` body contains **zero** `web.archive.org` references.

## Fixture validation

- 343,638 bytes of original HTML; Nokogiri parses it cleanly.
- **107** `div[itemscope][itemtype="http://schema.org/Event"]` entries (≫ 3 required).
- No interstitial title, no meta-refresh/JS redirect stub, no rate-limit body; no
  `Attention Required`, `Just a moment`, or `One more step` text.
- Example entries (all as archived 2026-02-07): `BASKETBALL (1 COURT)` 2026-02-01T13:00,
  `VOLLEYBALL (1 COURT)` 2026-02-01T15:00, `City Council Meeting`,
  `CANCELLED: Flashback Friday: 90s Arcade and Skate Night` 2026-02-06T18:00.
- Reproduce with: `bundle exec ruby` on a Nokogiri script selecting the containers below.

## Field mapping (CSS selectors)

| Field | Selector / rule | Example |
|-------|-----------------|---------|
| Event container | `div[itemscope][itemtype="http://schema.org/Event"]` | one per event |
| Title | `span[itemprop="name"]` | `BASKETBALL (1 COURT)` |
| Start (ISO) | `span[itemprop="startDate"]` | `2026-02-01T13:00:00` — local `America/Chicago`, **no offset** |
| Start/end (human) | `.subHeader .date` | `February 1, 2026, 1:00 PM - 6:00 PM` (`&nbsp;`/`&thinsp;` separators) |
| Time range | `div.detailsTooltip dl > dt[text()='When:'] + dd` | `1:00 PM - 6:00 PM` or `All Day` |
| Venue | `span[itemprop="location"] span[itemprop="name"]` | `Recreation Center` |
| Address | `span[itemprop="address"]` → `streetAddress`, `addressLocality`, `addressRegion`, `postalCode` | `1435 Main Street`, `Cedar Park`, `TX`, `78613` |
| Detail URL | `div.detailsTooltip a.button[href^="/Calendar.aspx?EID="]` — prefix origin `https://www.cedarparktexas.gov` | `/Calendar.aspx?EID=3428&month=2&year=2026&day=1&calType=0` |
| Event id | `EID` query param of detail URL (also `a[id^="calendarEvent"]`) | `3428` |
| Category | `div.monthItem > a > span.visuallyHidden`, strip leading `Category: ` | `Gym Court Schedule` |
| Description | `p[itemprop="description"]` | **empty in all 107 entries**; only the detail page carries prose |
| Price | *absent* | no price field anywhere in the markup; treat as `nil`/unknown |

JSON paths: none — the reliable source is HTML microdata, not JSON. The archived RSS feed is
empty; no JSON endpoint was found (all `/api/...` probes were Cloudflare-blocked).

## Pagination rule

- The month grid shows one calendar month. UI navigation is JS-only:
  `changeDate(2026, 1, 'month', '0', 'prevMonth')` / `nextMonth` — there is **no crawlable
  `href`** for adjacent months, so a scraper must construct the URL itself.
- URL shape inferred from the detail links and archived month-param captures:
  `calendar.aspx?month=<1-12>&year=<YYYY>`; detail links additionally carry `&day=<D>&calType=0`.
  **Verify this live once Cloudflare access is available** — no archived month-param page was
  found to confirm it.
- Category filter: `CID` CSV, e.g. `/calendar.aspx?CID=14,26&showPastEvents=false`.
  Known CIDs: `14` Events, `24` Parks, `26` Meetings, `30` Cedar Park Popup, `31` Mental Health,
  `32` Gym Court Schedule, `25` Police Training.
- Several events span multiple days (one EID appears on consecutive day cells), so
  deduplicate on `EID` after collecting a range of months.

## Date format

- `startDate`: `YYYY-MM-DDTHH:MM:SS`, naive local time (`America/Chicago`); no timezone suffix.
- Human date: `Month D, YYYY, h:mm AM - h:mm PM` with thin/non-breaking spaces.
- Time-only can be `All Day`. Treat naive times as `America/Chicago` when building `Event`s.

## Anti-bot posture

- Cloudflare challenge on **every** path of `www.cedarparktexas.gov` and the apex domain,
  including static assets/feeds, for plain curl, browser automation and API-looking paths.
  Browser automation is not a workaround.
- Archive copies are the practical route. Wayback `id_` is the only one that yielded a
  content-bearing body; archive.today returns a CAPTCHA page with HTTP 200 — validate the
  body, never the status code.
- Wayback availability and CDX are intermittently rate-limited ("Temporarily Offline"); do
  not retry-hammer. Fetch the specific timestamp URL once.
- Snapshots are stale by construction. For production, either arrange authorized access to
  the live CivicEngage calendar or use a different fetchable source; **do not** point the
  scheduled digest at a snapshot as if it were live.

## Follow-up stories (explicitly named)

1. **Implement `CedarParkCalendarScraper` that parses the CivicEngage month grid**
   — use the selectors above; emit one `Event` per `EID` with category, venue and absolute URL;
   skip `CANCELLED:` prefixed events or flag them explicitly.
2. **Add a fixture-based spec for the Cedar Park scraper**
   — assert ≥3 parsed events, ISO date parsing in `America/Chicago`, dedupe by `EID`, and that
   an interstitial/rate-limit body yields zero events (rejection test).
3. **Add a shared archived-snapshot fetch helper with body validation**
   — reuse the recovery ladder; reject HTTP-200 CAPTCHA/interstitial/redirect-stub bodies;
   record source URL + snapshot timestamp in a header comment for every captured fixture.
4. **Register the Cedar Park source in config and the scraper registry, gated behind an opt-in**
   — default off until a live fetch path is proven; document the Cloudflare block in config.
5. **Investigate an authorized live route for Cedar Park events**
   — City's CivicEngage iCalendar subscription (`/iCalendar.aspx`) or an official API key;
   replace the archived fixture with a recorded live cassette when available.
