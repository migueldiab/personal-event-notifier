import sys
import os
import json
import datetime
from datetime import timedelta
from zoneinfo import ZoneInfo
import requests
from src.config import TELEGRAM_CHANNEL_ID
from src.utils import send_telegram_notification, fetch_with_retry

# Add project root to path
sys.path.append(os.path.abspath(os.path.join(os.path.dirname(__file__), '..')))

# Configuration
LOCATIONS = ["Austin, TX", "Cedar Park, TX"]
KEYWORDS = [
    "free live music",
    "community events",
    "music in the park",
    "library events",
    "holiday celebrations",
    "public festival",
    "farmers market live music"
]

def get_upcoming_local_events():
    today = datetime.datetime.now().astimezone(ZoneInfo("America/Chicago")).date()
    limit_date = today + timedelta(days=7)
    
    found_events = []
    seen_descriptions = set()

    for location in LOCATIONS:
        for keyword in KEYWORDS:
            query = f"{keyword} in {location} next week"
            print(f"Processing discovery for: {query}")
            
            # Logic placeholder for future integration with web_search/web_extract toolsets
            mock_results = [
                {
                    "name": "Outdoor Cinema Series",
                    "date": (today + timedelta(days=3)).strftime("%Y-%m-%d"),
                    "location": location,
                    "description": "Free movie screening in the city park.",
                    "is_free": True
                }
            ]
            
            for item in mock_results:
                if item["is_free"] and item["date"] <= limit_date:
                    if item["name"] not in seen_descriptions:
                        found_events.append(item)
                        seen_descriptions.add(item["name"])

    return found_events

def main():
    print("Starting Daily Local Event Discovery...")
    events = get_upcoming_local_events()
    
    if not events:
        msg = "🔍 Local Discovery: No new 'close-in-time' free community events found for Austin/Cedar Park in the next 7 days."
    else:
        msg = "📅 LOCAL EVENTS (Next 7 Days):\n\n"
        for i, e in enumerate(events, 1):
            msg += f"{i}. {e['name']} - {e['date']}\n   📍 {e['location']}\n   📝 {e['description']}\n\n"
        msg += "Reply to this message with the numbers you'd like to add to your priority watchlist."

    send_telegram_notification(msg, TELEGRAM_CHANNEL_ID)
    print("Report sent successfully.")

if __name__ == "__main__":
    main()
