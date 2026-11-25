# Weekly Local Events Monitor

Automated monitoring system for high-interest cultural and social events.

## Features

- **Detection:** Identifies when major events (Oscars, Olympics, etc.) are occurring.
- **Smart Info:** Fetches broadcast (TV) and streaming information.
- **Telegram Alerts:** Sends formatted notifications to your Telegram channel.
- **Multi-source:** Aggregates from Austin Chronicle, Do512, and Community Impact.

## Pipeline

```
Crawler Engine → Data Normalizer → Deduplication Layer → Notification Dispatcher
```

## Setup

### Prerequisites

- Ruby 3.3+
- `bundler`

### Installation

```bash
cd ~/src/ai/WeeklyLocalEvents
bundle install
```

### Configuration

Set environment variables:

```bash
export TELEGRAM_CHANNEL_ID="-1004330304115"
export TELEGRAM_TOKEN="your-bot-token"
```

### Running

```bash
bundle exec ruby bin/run
```

### Running Tests

```bash
bundle exec rspec
```

## Project Structure

```
lib/weekly_local_events/
├── core/          # Data models (Event, Config)
├── engines/       # Source-specific crawlers
├── pipeline/      # Crawler, Normalizer, Dedup
├── notifications/ # Telegram dispatcher
├── utils/         # Helpers (DateHelper)
└── version.rb     # Gem version
spec/              # RSpec tests
bin/               # Executable scripts
config/            # Configuration files
db/                # Database migrations & seeds
scripts/           # Utility scripts
```
