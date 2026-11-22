# AI Event Monitor

Automated monitoring system for high-interest cultural and social events.

## Features
- **Detection:** Identifies when major events (Oscars, Olympics, etc.) are occurring.
- **Smart Info:** Fetches broadcast (TV) and streaming information.
- **Telegram Alerts:** Sends formatted notifications to your Telegram channel.

## Setup

### Prerequisites
- Python 3.x
- `hermes` CLI (for Telegram notifications)

### Installation
1. Clone this repository.
2. Configure your `TELEGRAM_CHANNEL_ID` in `src/config.py`.
3. (Optional) Set `TELEGRAM_TOKEN` in your environment.

### Running the monitor
```bash
python3 main.py
```

### Running Tests
```bash
python3 -m unittest discover tests
```

## Project Structure
- `src/`: Core application logic.
- `tests/`: Unit tests.
- `main.py`: Entry point.
