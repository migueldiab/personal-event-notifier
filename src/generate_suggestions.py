import sys
import os
import requests
import datetime
from datetime import timedelta
from zoneinfo import ZoneInfo

# Add project root to path
sys.path.append(os.path.abspath(os.path.join(os.path.dirname(__file__), '..')))

from src.config import INTEREST_EVENTS, TELEGRAM_CHANNEL_ID
from src.utils import send_telegram_notification

def get_upcoming_suggestions():
    today = datetime.datetime.now().astimezone(ZoneInfo("America/Chicago")).date()
    limit_date = today + timedelta(days=14)
    
    suggestions = []
    seen_ids = set()

    for event_query in INTEREST_EVENTS:
        search_url = f"https://api.tvmaze.com/search/shows?q={event_query.replace(' ', '%20')}"
        try:
            r = requests.get(search_url, timeout=15)
            r.raise_for_status()
            data = r.json()
            
            for entry in data:
                show = entry.get("show")
                if not show:
                    continue
                
                # Check for next episode
                links = show.get("_links", {})
                next_ep = links.get("nextepisode")
                
                if next_ep and next_ep.get("href"):
                    resp = requests.get(next_ep["href"], timeout=15)
                    resp.raise_for_status()
                    next_data = resp.json()
                    
                    air_date_str = next_data.get("air_date")
                    if air_date_str:
                        target_date = datetime.datetime.strptime(air_date_str, "%Y-%m-%d").date()
                        
                        if today <= target_date <= limit_date:
                            show_id = show.get("id")
                            if show_id and show_id not in seen_ids:
                                suggestions.append({
                                    "name": show.get("name"),
                                    "date": air_date_str,
                                    "time": next_data.get("air_time"),
                                    "network": show.get("network", {}).get("name", "TV/Streaming"),
                                    "id": show_id
                                })
                                seen_ids.add(show_id)
        except Exception as e:
            print(f"Error fetching suggestions for {event_query}: {e}")

    return suggestions

def main():
    suggestions = get_upcoming_suggestions()
    if not suggestions:
        print("No close-in-time suggestions found.")
        return

    msg_lines = ["📅 SUGGESTIONS FOR THE NEXT 14 DAYS:", ""]
    for i, s in enumerate(suggestions, 1):
        msg_lines.append(f"{i}. {s['name']} ({s['date']})")
    
    msg_lines.append("\nReply to this message with the numbers you'd like me to add to your priority watchlist.")
    
    full_msg = "\n".join(msg_lines)
    send_telegram_notification(full_msg, TELEGRAM_CHANNEL_ID)
    print(f"Sent {len(suggestions)} suggestions.")

if __name__ == "__main__":
    main()
