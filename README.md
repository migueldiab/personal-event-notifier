# Weekly Local Events Monitor

Automated monitoring system for high-interest cultural and social events (Oscars, Olympics, SXSW, etc.) with Telegram notifications.

## Features

- **Detection:** Identifies when major events are occurring.
- **Smart Info:** Fetches broadcast (TV) and streaming information.
- **Telegram Alerts:** Sends formatted notifications to your Telegram channel.
- **Multi-source:** Aggregates from Austin Chronicle, Do512, and Community Impact.
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
