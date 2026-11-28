# Weekly Local Events Monitor

Automated monitoring system for high-interest cultural and social events (Oscars, Olympics, SXSW, etc.) with Telegram notifications.

## Features

- **Detection:** Identifies when major events are occurring.
- **Smart Info:** Fetches broadcast (TV) and streaming information.
- **Telegram Alerts:** Sends formatted notifications to your Telegram channel.
- **Multi-source:** Aggregates from Austin Chronicle, Do512, Community Impact, Eventbrite, ACL Live, Stubbs's, Paramount Austin, Visit Cedar Park, and the City of Cedar Park's public RSS calendar (`cedar_park`).
- **Weekly Digest:** Sunday 6PM CST as primary schedule; optional daily new-event alert (7AM CST) as secondary.

## Pipeline

```
Crawler Engine → Data Normalizer → Deduplication Layer → Notification Dispatcher
```

## Installation

### Prerequisites

- Ruby 3.0+
- `bundler`

### Steps

```bash
cd ~/src/ai/WeeklyLocalEvents
bundle install
```

## Configuration

Copy `.env.example` to `.env` and fill in the values:

```bash
cp .env.example .env
```

### Environment Variables

| Variable | Description |
|----------|-------------|
| `AUSTIN_EVENT_SITES` | Comma-separated list of event sites to scrape |
| `NOTIFICATION_CHANNEL_ID` | Telegram channel ID (get from @getmyid_bot) |
| `TELEGRAM_BOT_TOKEN` | Telegram bot token (get from @BotFather) |
| `EVENTBRITE_PRIVATE_TOKEN` | Eventbrite private token (get from the API Keys page, optional) |
| `EVENTBRITE_CLIENT_ID` | Eventbrite API key / OAuth client ID (optional) |
| `EVENTBRITE_CLIENT_SECRET` | Eventbrite OAuth client secret (optional) |
| `EVENTBRITE_REDIRECT_URI` | Registered OAuth redirect URI (default: `http://localhost:8080/oauth/redirect`) |
| `EVENTBRITE_TEST_EVENT_ID` | Known event ID used by the smoke test |
| `LOG_LEVEL` | `debug`, `info`, `warn`, `error`, or `fatal` (default: `info`) |

### Scraper sources

The active source names are configured in the config file the loader actually reads,
`~/.hermes/weekly_local_events/config.yml` (the YAML files under `config/` are examples
and are not loaded):

```yaml
notification_channel_id: "-1004330304115"
telegram_bot_token: "123456:ABC-DEF"
enabled_scrapers:
  - austin_chronicle
  - do512
  - community_impact
  - eventbrite_austin
  - acl_live
  - stubbss
  - paramount_austin
  - visit_cedar_park
  - cedar_park_rss
  # Authoritative live Cedar Park route; HTML/API paths are Cloudflare-blocked.
  - cedar_park
# Optional offline fallback for Akamai-blocked sources:
cached_fixture_path: /home/madrax/src/ai/WeeklyLocalEvents/spec/fixtures/vcr_cassettes/visit_cedar_park_events.yml
```

| Source name | Site | Notes |
|-------------|------|-------|
| `austin_chronicle` | austinchronicle.com | HTML calendar |
| `do512` | do512.com | HTML listings |
| `community_impact` | communityimpact.com | Recorded HTML cassette |
| `eventbrite_austin` | eventbrite.com | Requires `EVENTBRITE_PRIVATE_TOKEN` |
| `acl_live` | acllive.com | PDF/HTML calendar |
| `stubbss` | stubbs.net | HTML listings |
| `paramount_austin` | paramountaustin.com | HTML listings |
| `visit_cedar_park` | visitcedarparktexas.com | Simpleview JSON API; see caveat below |
| `cedar_park_rss` | cedarparktexas.gov | Public CivicEngage RSS feed (alternate source) |
| `cedar_park` | cedarparktexas.gov | Public CivicEngage RSS feed; primary live Cedar Park route; see caveat below |

`cedar_park_rss` reads the city's unauthenticated feed at
<https://www.cedarparktexas.gov/RSSFeed.aspx?ModID=58&CID=All-calendar.xml>
(HTTP 200, `text/xml`, 15 items, 30-second cache). Event dates and times come
from the feed's `calendarEvent` fields in `America/Chicago`; `<pubDate>` is only
publication time. Every event carries an `eid:<id>` tag and a dedupe key
`cedar_park_rss:<id>`; cancelled titles are tagged `cancelled`, and the feed has
no price. The network-free replay cassette is
`spec/fixtures/vcr_cassettes/cedar_park_calendar_rss.yml`.

Only the *archived* 2023 copy of that feed had zero items. The other
`cedarparktexas.gov` paths (`/calendar.aspx`, `/iCalendar.aspx`, `/api/...`)
remain Cloudflare-blocked, so the older Wayback HTML fixture is **fallback
only**. Details and the corrected history are in `docs/cedar_park_recon.md`.

### Cedar Park (`cedar_park`): Cloudflare caveat and cassette refresh

`cedar_park` is the authoritative live Cedar Park source. It reads the same
unauthenticated CivicEngage RSS feed (HTTP 200, `text/xml`, no credentials)
through `BaseScraper#http_get`, so the configured headers, user agent and
timeouts apply. Every event has an absolute
`https://www.cedarparktexas.gov/Calendar.aspx?EID=<id>` link, an `eid:<id>` tag
and a `cedar_park:<id>` dedupe key. Dates and times come from the namespaced
`calendarEvent` fields in `America/Chicago`; `<pubDate>` is publication time and
is never used as the event start. An event that shares a title with another
source is kept when the venue differs — the Aggregator dedupes on venue + date
+ normalized title.

**Anti-bot caveat:** the RSS feed is not blocked, but the HTML calendar and API
paths on `cedarparktexas.gov` are behind Cloudflare (403 or an interstitial body
even with HTTP 200). Do not point `cedar_park` at those paths. The archived 2026
Wayback HTML snapshot is historical fallback only, parsed by
`CedarParkCalendarScraper`, and is never presented as live. See
`docs/cedar_park_recon.md`.

The network-free replay cassettes are
`spec/fixtures/vcr_cassettes/cedar_park_calendar_rss.yml` (live feed) and
`spec/fixtures/vcr_cassettes/cedar_park_events.yml` (archived HTML). To refresh
them — the only command that performs live HTTP — run:

```bash
bundle exec ruby bin/record_vcr_cassettes
```

Cassettes carry no credentials, cookies or API keys, and the archive capture
timestamp is recorded in the cassette header so the snapshot stays auditable.

### Visit Cedar Park: Akamai and JS-shell caveat

The public Visit Cedar Park HTML sits behind an Akamai wall. Events are read from
the Simpleview REST JSON endpoint instead, using a short-lived runtime token that
is never committed. A denial can arrive with HTTP 200 as a client-side widget shell
containing `layoutjsContainer` but no `"docs"` payload; the fetcher treats that
as a block, never retries a 403, applies bounded `Retry-After` backoff to 429/503,
and falls back to a configured cached JSON file or VCR cassette rather than raising
into the digest.

To refresh the recorded response (the only command that performs live HTTP; the
runtime token is fetched outside the cassette and redacted to `TOKEN_REDACTED`):

```bash
bundle exec ruby bin/record_vcr_cassettes
```

### Eventbrite API credentials

The Eventbrite API requires an authenticated request on every call. To enable it:

1. Log in at <https://www.eventbrite.com/platform/> and choose **Get a Free API Key**.
2. On the [API Keys page](https://www.eventbrite.com/platform/api-keys/), copy the private token into `EVENTBRITE_PRIVATE_TOKEN` in `.env`. This is the simplest option for a single account.
3. For multi-user OAuth, register an app to obtain `EVENTBRITE_CLIENT_ID`, `EVENTBRITE_CLIENT_SECRET` and a redirect URI. Start the server-side flow with `WeeklyLocalEvents::EventbriteClient#authorization_url` and exchange the returned `code` with `#exchange_code`, then store the resulting private token securely.

Eventbrite does not support the `client_credentials` grant; use a private token or the authorization-code flow.

Verify the credentials with a real API call:

```bash
bin/eventbrite_smoke_test <known_event_id>
```

Never commit `.env`; only `.env.example` belongs in source control.

### Anti-bot cached fixture fallback

Scrapers that use `AntiBotFetcher` degrade gracefully behind bot walls. A 403,
429 or an interstitial body (detected by content such as "Just a moment" or
"Attention Required", even with HTTP 200) is logged as a warning and never
raises into the pipeline. With no fixture configured the scraper returns no
events for that page.

To replay a previously captured page instead, set an absolute path in the
config the loader actually reads — `~/.hermes/weekly_local_events/config.yml`:

```yaml
cached_fixture_path: /home/madrax/src/ai/WeeklyLocalEvents/spec/fixtures/cached_calendar_with_events.html
```

When every live route (primary, regional variants and the headless browser)
is blocked, the fetcher logs a warning and parses that cached HTML. Missing,
empty or interstitial-looking fixture files are rejected and yield no events.
Record provenance in the fixture header and cite archived captures with their
archive date — cached data is never presented as live.

## Usage

### Main Entry Point

```bash
# Run the full pipeline
bin/weekly_local_events

# Or using bundle exec
bundle exec ruby bin/weekly_local_events
```

### Rake Tasks

```bash
rake test      # Run all specs with documentation format
rake lint      # Run RuboCop
rake format    # Auto-fix RuboCop offenses
rake           # Default: runs tests
```

## Development

### Run Tests

```bash
rake test
```

### Run Linter

```bash
rake lint
```

### Run Linter with Auto-fix

```bash
rake format
```

### Test Coverage

Run with SimpleCov coverage:

```bash
COVERAGE=1 rake test
```

### Recorded HTTP responses (VCR)

Tests never call live sites. `spec/spec_helper.rb` configures VCR with
`record: :none`, so any request without a matching cassette raises
`VCR::Errors::UnhandledHTTPRequestError` instead of reaching the network.

Cassettes are committed under `spec/fixtures/vcr_cassettes/`. To record or
refresh them — the only command that performs live HTTP — run:

```bash
bundle exec ruby bin/record_vcr_cassettes
```

In a spec, wrap the request with `VCR.use_cassette("cassette_name") { ... }` and
feed the recorded HTML into the scraper's `parse_response`.

## Architecture

```
lib/weekly_local_events/
├── core/              # Data models (Event, Config)
├── pipeline/          # Crawler engine, normalizer
├── notifications/     # Telegram dispatcher
├── utils/             # Helpers (DateHelper)
├── aggregator.rb      # Multi-source aggregation
├── base_scraper.rb    # Base scraper class
├── notifier.rb        # Notification interface
├── scraper_registry.rb # Source registry
├── venue.rb           # Venue model
└── version.rb         # Gem version
```

## Project Structure

```
bin/                  # Executable scripts
config/               # Configuration files
db/                   # Database migrations & seeds
lib/                  # Application code
scripts/              # Utility scripts
spec/                 # RSpec tests
.env.example          # Environment template
Gemfile               # Dependencies
Rakefile              # Task definitions
```

## License

MIT License — see [LICENSE](LICENSE) for details.
