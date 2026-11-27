# Community Impact calendar — structure & selector recon

Verified live on **2026-11-26** (CST) against:

- <https://www.communityimpact.com/calendar/> (302/301 → <https://communityimpact.com/calendar/>)
- <https://communityimpact.com/san-antonio/calendar/> (regional variant of `satxevents.communityimpact.com`)
- <https://communityimpact.com/dallas-fort-worth/calendar/> (regional variant of `dfwevents.communityimpact.com`)
- one event detail page: <https://communityimpact.com/san-antonio/calendar/thanksgiving-day-at-hard-rock-cafe-cmwx58rgw00op6bmhmr4ddd32/>

Conclusion: **the calendar is server-rendered HTML. No headless browser is required to scrape the listing.**

---

## 1. Rendering: server-rendered (Next.js / RSC), not JS-only

Definitive evidence:

- Plain `curl -sSL https://www.communityimpact.com/calendar/` returns **379,421 bytes**, HTTP 200, `x-powered-by: Next.js`.
- The raw ( JavaScript-untouched ) response contains all 24 card links, 24 `<h3 class="line-clamp-2 ...">` title elements, 24 `"@type":"Event"` JSON-LD objects, and the pagination markup.
- Chromium `document.querySelectorAll(cardSelector).length` also returns **24** — the client adds no extra event cards.
- The page embeds Next.js flight data (`self.__next_f.push(...)`) and 8 `application/ld+json` blocks, but the event content itself is present in the initial HTML.

So a plain HTTP client + HTML parser (Nokogiri) is sufficient. A browser is only needed as a fallback if the site later introduces a challenge page.

## 2. Confirmed CSS selectors / XPath

All selectors below were executed **against the live page in Chromium** and against the raw `curl` HTML. Counts are from the master calendar (24 events).

| Field | CSS selector | XPath equivalent | Matches (master page) |
|---|---|---|---|
| Event card (link) | `a[href*="/calendar/"][class*="bg-card"]:not([href="/calendar/submit/"])` | `//a[contains(@class,'bg-card') and contains(@href,'/calendar/') and not(@href='/calendar/submit/')]` | 24 |
| Title | `h3[class*="line-clamp-2"]` | `.//h3[contains(@class,'line-clamp-2')]` | 24 |
| Time range | `svg.lucide-clock + span` | `.//*[contains(@class,'lucide-clock')]/following-sibling::span[1]` | 24 |
| Venue | `svg.lucide-map-pin + span` | `.//*[contains(@class,'lucide-map-pin')]/following-sibling::span[1]` | 22 (2 events have no venue) |
| Date note ("Through Nov. 30") | `p[class*="pl-5"]` | `.//p[contains(@class,'pl-5')]` | 10 |
| Next page link | `nav[aria-label="Pagination"] a[aria-label="Next page"]` | `//nav[@aria-label='Pagination']//a[@aria-label='Next page']` | 1 |
| Price (detail page only) | `svg.lucide-ticket + div dd.font-semibold` (or `dt.sr-only + dd.font-semibold` restricted to the ticket row) | `//*[contains(@class,'lucide-ticket')]/following-sibling::div//dd[1]` | 1 on the sampled detail page |

Always scope the field selectors to the card element, e.g.:

```css
a[href*="/calendar/"][class*="bg-card"]:not([href="/calendar/submit/"]) h3[class*="line-clamp-2"]
```

**Tailwind pitfall:** class names such as `gap-1.5` contain a dot. In Nokogiri CSS use `[class*="gap-1"]`; in XPath use `contains(@class, 'gap-1')`. Never write `.gap-1.5` as a CSS selector.

### Sample card markup (verbatim, first card)

```html
<a class="group flex h-full flex-col overflow-hidden rounded-lg border border-border bg-card transition hover:border-events/50 hover:shadow-sm"
   href="/austin/calendar/meet-megan-jaster-austin-artist-of-the-month-cmvjqfdgy0b9s01quw41kchva/">
  <div class="relative aspect-[16/9] w-full overflow-hidden bg-events-soft"> … </div>
  <div class="flex flex-1 flex-col gap-1.5 p-4">
    <h3 class="line-clamp-2 text-base font-bold leading-snug text-foreground transition group-hover:text-events-strong">Meet Megan Jaster · Austin Artist of the Month</h3>
    <p class="flex items-center gap-1.5 text-sm text-muted-foreground">
      <svg class="lucide lucide-clock h-3.5 w-3.5 shrink-0 text-events" …></svg><span>Multiple showtimes</span>
    </p>
    <p class="pl-5 text-xs text-muted-foreground">Through Nov. 30</p>
    <p class="flex min-w-0 items-center gap-1.5 text-sm text-muted-foreground">
      <svg class="lucide lucide-map-pin h-3.5 w-3.5 shrink-0 text-events" …></svg>
      <span class="truncate">Unchained.Art Contemporary Gallery</span>
    </p>
  </div>
</a>
```

Extracted sample row:

```json
{
  "title": "Meet Megan Jaster · Austin Artist of the Month",
  "time": "Multiple showtimes",
  "date_note": "Through Nov. 30",
  "venue": "Unchained.Art Contemporary Gallery",
  "href": "/austin/calendar/meet-megan-jaster-austin-artist-of-the-month-cmvjqfdgy0b9s01quw41kchva/"
}
```

## 3. JSON-LD — often better than DOM scraping

`script[type="application/ld+json"]` contains a `CollectionPage` whose `mainEntity` is an `ItemList` of 24 `ListItem` objects. Each `item` is an `Event` with:

- `name`, `url`, `startDate`, `endDate` (ISO-8601 UTC, e.g. `2026-11-01T05:00:00.000Z`)
- `description`, `keywords` (category), `inLanguage`
- `location` → `name` and `address`
- `offers` on 19/24 events in the sample; usually only `url` + `availability`, but one event had a full `AggregateOffer`: `{"lowPrice":14.04,"highPrice":51.65,"priceCurrency":"USD", ...}`.

This is the cleanest source for start/end timestamps, especially for all-day and recurring events whose card shows only a range like `12:00 AM – 11:59 PM`.

## 4. Pagination — classic query-string paging, no infinite scroll

- **24 events per page.**
- Next link observed: `/calendar/?from=2026-11-26&to=2026-11-26&page=2`.
- Date-range window works: `?from=2026-12-01&to=2026-12-07` returns 200 with its own `page=2` link using the same `from`/`to`.
- No scrolllistener / "load more" mechanism found; navigate with `page=N`.
- Regional pages use the same DOM: San Antonio returned 2 cards (smaller Thanksgiving-day set) and the same selectors matched 2/2 titles, times and venues.

## 5. Bot protection / login walls

- `server: cloudflare`, `cf-ray: …-DFW`, `cf-cache-status: EXPIRED` — **CDN headers only**.
- **No** Cloudflare challenge ("Just a moment…"), **no** PerimeterX, **no** CAPTCHA, and **no** 403/429 on any of the four URLs fetched.
- No login wall on calendar or event-detail pages; `/premium-signin` is for premium *news* content, not calendar data.
- Regional hosts are simple 301 redirects, not separate apps:
  - `satxevents.communityimpact.com/calendar/` → `https://communityimpact.com/san-antonio/calendar/`
  - `dfwevents.communityimpact.com/calendar/` → `https://communityimpact.com/dallas-fort-worth/calendar/`
- Practical guidance: still cap requests at ~5/min with jitter and exponential backoff on 429/503 as defensive hygiene; a headless-browser fallback is not currently needed.

## 6. Price and "Multiple showtimes" nuances

- **Listing cards never show a price** — 0 matches for `price` classes or a dollar-sign icon in the listing HTML.
- **Detail pages sometimes show a price row**: `<div><dt class="sr-only">Price</dt><dd class="font-semibold">$14 – $52</dd></div>` next to `svg.lucide-ticket`. Only fetch detail pages when price is actually required.
- `"Multiple showtimes"` on a card is a **literal string**, not a link to a list of showtimes; individual showtimes are not present in the server HTML. To expand recurring events, use the `startDate`/`endDate` from JSON-LD or the detail page's date section.
- Some cards have no venue (22/24 in sample); treat venue as optional.

---

## Verification log

```
curl -sS -L https://www.communityimpact.com/calendar/ -o calendar_main.html
  → HTTP 200, 379421 bytes, x-powered-by: Next.js
  → raw card links: 25 (24 real events after excluding the submit card)
  → raw h3.line-clamp-2: 24; raw JSON-LD Event objects: 24
Chromium on /calendar/
  → cards 24, titles 24, times 24, venues 22, date notes 10, price matches 0
  → pagination: page 2 link + "Next page" aria-label present
  → JSON-LD types: NewsMediaOrganization, WebSite, BreadcrumbList, CollectionPage
Chromium on /san-antonio/calendar/
  → cards 2; title/time/venue selectors matched 2/2/2
Chromium on detail page
  → Event JSON-LD AggregateOffer lowPrice 14.04 / highPrice 51.65 / USD
  → visible price row "$14 – $52" at svg.lucide-ticket + div dd.font-semibold
curl -sS -D - regional hosts → 301 to /san-antonio/calendar/ and /dallas-fort-worth/calendar/
```
