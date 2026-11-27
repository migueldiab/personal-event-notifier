# Do512.com Event Page Selectors — Verified DOM Structure

**Date verified:** 2026-11-26
**Base URL:** `https://www.do512.com/events?page=N`
**Platform:** DoStuff Media (same as Do312, Do206, Do713, etc.)
**Pagination:** `?page=N` (note: `/?page=2` not `/events?page=2`)

---

## ⚠️ CRITICAL FINDING: All Proposed Selectors FAIL

The site uses **DoStuff Media's `ds-` prefixed class system**. None of the originally proposed selectors (`h1.event-title`, `a.event-title`, `.event-date`, `a.venue-link`, `.price`, `.ticket-price`, `.free-badge`, `.is-free`, `a.event-link`) match any elements on the page.

---

## Verified Selectors (DoStuff Media DOM)

### Event Card Wrapper

```html
<div class="ds-listing event-card ds-event-category-variety-other"
     data-ds-ga-label="day"
     data-permalink="/events/2026/11/20/peppermint-in-the-park-tickets"
     itemprop="event" itemscope itemtype="http://schema.org/Event">
```

- **Selector:** `div.ds-listing.event-card`
- **Event ID:** `data-permalink` attribute contains the slug
- **Category:** `ds-event-category-{slug}` class (e.g., `ds-event-category-variety-other`)

---

### Title

| Proposed | Actual | Match? |
|----------|--------|--------|
| `h1.event-title` | `a.ds-listing-event-title` | ✗ NO |
| `a.event-title` | `a.ds-listing-event-title` | ✗ NO |

**Verified selector:** `a.ds-listing-event-title`

```html
<a href="/events/2026/11/20/peppermint-in-the-park-tickets"
   itemprop="url"
   class="ds-listing-event-title url summary">
  <span class="ds-byline"></span>
  <span class="ds-listing-event-title-text" itemprop="name" style="overflow-wrap: break-word;">
    Peppermint in the Park
  </span>
</a>
```

- **URL:** `a.ds-listing-event-title` (href)
- **Text:** `span.ds-listing-event-title-text` (textContent)

---

### Date / Time

| Proposed | Actual | Match? |
|----------|--------|--------|
| `.event-date` | `div.ds-event-time.dtstart` | ✗ NO |
| `time` | `div.ds-event-time.dtstart` | ✗ NO |

**Verified selectors:**

```html
<!-- Display time -->
<div class="ds-event-time dtstart">4:00PM</div>

<!-- ISO datetime (microdata) -->
<meta itemprop="startDate"
      datetime="2026-11-20T16:00-0600"
      content="2026-11-20T16:00-0600">
```

- **Display time:** `div.ds-event-time.dtstart` (textContent)
- **ISO date:** `meta[itemprop="startDate"]` (datetime attribute)

---

### Venue

| Proposed | Actual | Match? |
|----------|--------|--------|
| `a.venue-link` | `div.ds-venue-name a` | ✗ NO |

**Verified selector:** `div.ds-venue-name a`

```html
<div class="ds-venue-name" itemprop="location" itemscope itemtype="http://schema.org/Place">
  <a href="/venues/circuit-of-the-americas" itemprop="url">
    <span itemprop="name">Circuit of the Americas</span>
  </a>
  <span itemprop="address" itemscope itemtype="http://schema.org/PostalAddress">
    <meta itemprop="streetAddress" content="9201 Circuit of the Americas Blvd">
    <meta itemprop="addressLocality" content="Austin">
    <meta itemprop="addressRegion" content="TX">
    <meta itemprop="postalCode" content="78617">
  </span>
</div>
```

- **Venue link:** `div.ds-venue-name a` (href="/venues/...")
- **Venue name:** `span[itemprop="name"]` within `.ds-venue-name`
- **Address:** `span[itemprop="address"]` with microdata

---

### Price / Ticket URL

| Proposed | Actual | Match? |
|----------|--------|--------|
| `.price` | `div.ds-btn-container-buy-tix` | ✗ NO |
| `.ticket-price` | `div.ds-btn-container-buy-tix` | ✗ NO |

**Verified selector (paid events):**

```html
<div class="ds-btn-container-buy-tix">
  <span itemprop="offers" itemscope itemtype="http://schema.org/Offer">
    <meta itemprop="url" content="https://cotaland.com/peppermint-in-the-park/">
    <a href="https://cotaland.com/peppermint-in-the-park/"
       class="ds-btn ds-btn-large ds-buy-tix"
       title="BUY TICKETS">
      <span class="ds-icon ds-icon-ticket ds-icon-bg"></span>
      <span class="ds-icon-text">Buy</span>
    </a>
  </span>
</div>
```

- **Ticket URL:** `div.ds-btn-container-buy-tix a.ds-btn.ds-buy-tix` (href)
- **Vendor URL:** `meta[itemprop="url"]` within `.ds-btn-container-buy-tix`
- **Free events:** This container is **absent** — absence of `.ds-btn-container-buy-tix` = free event

---

### Free Badge

| Proposed | Actual | Match? |
|----------|--------|--------|
| `.free-badge` | `li.ds-listing-soldout span` | ✗ NO |
| `.is-free` | `li.ds-listing-soldout span` | ✗ NO |

**Verified selector:** `li.ds-listing-soldout span`

```html
<ul class="ds-listing-banners">
  <li class="ds-listing-soldout">
    <span class="ds-icon ds-icon-ticket"></span>
    <span>Free</span>
  </li>
</ul>
```

- **Free indicator:** `li.ds-listing-soldout span` (textContent = "Free")
- **Note:** Despite class name `ds-listing-soldout`, this banner indicates **free** events (not sold out). This is a DoStuff Media naming quirk.
- **Alternative detection:** Absence of `div.ds-btn-container-buy-tix` also indicates a free event.

---

### Event URL

| Proposed | Actual | Match? |
|----------|--------|--------|
| `a.event-link` | `a.ds-listing-event-title` | ✗ NO |

**Verified selector:** `a.ds-listing-event-title`

- **URL:** `a.ds-listing-event-title` (href="/events/YYYY/MM/DD/slug")
- **Permalink:** `data-permalink` attribute on the card wrapper

---

## Pagination

| Feature | Finding |
|---------|---------|
| **Format** | `/?page=N` (e.g., `/events?page=2`) |
| **Page 1** | 54 event cards |
| **Page 2** | 44 event cards |
| **Page 3+** | 0 cards (empty page, no error) |
| **Last page** | Page 2 (no "Last" button rendered) |
| **Component** | Slick.js carousel (`.slick-nasty.slick-initialized.slick-slider`) |
| **Next button** | `<button class="slick-next" aria-label="next">Next</button>` (only on page 1) |
| **Prev button** | `<button class="slick-prev" aria-label="previous">Previous</button>` (only on page 2) |
| **Slide width** | 220px per card |
| **Cards per page** | ~10 visible (slick carousel), 54 total on page 1 |

**Pagination HTML snippet:**

```html
<div class="slick-nasty slick-initialized slick-slider">
  <div aria-live="polite" class="slick-list draggable" tabindex="0">
    <div class="slick-track" style="opacity: 1; width: 6380px; transform: translate3d(-440px, 0px, 0px);">
      <div class="slick-slide slick-cloned" style="width: 220px;" data-slick-index="-2" aria-hidden="true">
        <div class="ds-listing event-card ...">...</div>
      </div>
      <!-- ... more slides ... -->
    </div>
  </div>
  <button type="button" data-role="none" class="slick-next" aria-label="next" style="display: block;">Next</button>
</div>
```

---

## Anti-Bot Posture

| Check | Result |
|-------|--------|
| Cloudflare challenge page | ❌ None detected |
| Cloudflare beacon script | ✅ Present (`static.cloudflareinsights.com/beacon.min.js`) |
| `noscript` blocks | ✅ Present (standard) |
| Challenge divs | ❌ None |
| Response (headless Ruby) | ⚠️ **0 bytes** — Cloudflare blocks non-browser UA |
| Response (real browser) | ✅ Full HTML with all cards |

**Conclusion:** Cloudflare is present but does **not** serve a challenge page for normal requests. However, **headless Ruby/Python fetches receive 0-byte responses** — likely due to Cloudflare's JS challenge that requires browser execution. Use a real browser (Puppeteer/Playwright) or the Apify DoStuff Media actor for reliable scraping.

---

## Summary Table

| Field | Proposed Selectors | Actual Selector | Status |
|-------|-------------------|-----------------|--------|
| Title | `h1.event-title`, `a.event-title` | `a.ds-listing-event-title` | ✗ All fail |
| Date | `.event-date`, `time` | `div.ds-event-time.dtstart` + `meta[itemprop="startDate"]` | ✗ All fail |
| Venue | `a.venue-link` | `div.ds-venue-name a` | ✗ Fails |
| Price | `.price`, `.ticket-price` | `div.ds-btn-container-buy-tix a.ds-btn.ds-buy-tix` | ✗ All fail |
| URL | `a.event-link` | `a.ds-listing-event-title` | ✗ Fails |
| Free | `.free-badge`, `.is-free` | `li.ds-listing-soldout span` | ✗ All fail |
| Card | (not specified) | `div.ds-listing.event-card` | N/A |
| Pagination | `?page=N` | `?page=N` (slick carousel) | ✓ Works |

---

## Recommended Ruby Scraper Selectors

```ruby
# Event card wrapper
CARD_SELECTOR = 'div.ds-listing.event-card'

# Title
TITLE_SELECTOR = 'a.ds-listing-event-title'
TITLE_TEXT_SELECTOR = 'span.ds-listing-event-title-text'

# Date
DATE_DISPLAY_SELECTOR = 'div.ds-event-time.dtstart'
DATE_ISO_SELECTOR = 'meta[itemprop="startDate"]'

# Venue
VENUE_SELECTOR = 'div.ds-venue-name a'
VENUE_NAME_SELECTOR = 'span[itemprop="name"]'

# Ticket URL (paid events only)
TICKET_SELECTOR = 'div.ds-btn-container-buy-tix a.ds-btn.ds-buy-tix'
TICKET_URL_META_SELECTOR = 'meta[itemprop="url"]'

# Free event detection
FREE_BANNER_SELECTOR = 'li.ds-listing-soldout span'

# Pagination
PAGINATION_LINK_SELECTOR = 'a[href*="page="]'
Slick selector for next: '.slick-next'
Slick selector for prev: '.slick-prev'
```

---

## Notes

- The `data-permalink` attribute on each card contains the full event slug (e.g., `/events/2026/11/20/peppermint-in-the-park-tickets`)
- Event IDs are embedded in `data-ds-id` attributes on buttons (e.g., `data-ds-id="18039599"`)
- The site uses JSON-LD / microdata (schema.org) for structured data
- Free events may also appear in the `ds-listing-banners` list with the "Free" text
- The "Featured" section on the homepage uses a different structure (`.ds-featured-event-group`)
