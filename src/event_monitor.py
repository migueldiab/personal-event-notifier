from .config import INTEREST_EVENTS, TELEGRAM_CHANNEL_ID
from .utils import send_telegram_notification
from datetime import datetime, timedelta
from zoneinfo import ZoneInfo
import difflib
import os
import requests
import json

class EventMonitor:
    def __init__(self):
        self.events = INTEREST_EVENTS
        self.channel_id = TELEGRAM_CHANNEL_ID

    def check_events(self, events_input=None):
        self.run_monitor(events_input)

    def run_monitor(self, events_input=None):
        print(f"--- Starting Monitor Cycle: {datetime.now()} ---")
        found_any = False
        
        # Load priority watchlist
        try:
            with open('src/watchlist.json', 'r') as f:
                data = json.load(f)
                watchlist = list(data) if isinstance(data, (dict, list)) else []
        except (FileNotFoundError, json.JSONDecodeError):
            watchlist = []
        
        if events_input:
            targets = [e.strip() for e in events_input.split(',') if e.strip()]
        else:
            # Priority: Watchlist first, then standard interests
            combined = list(dict.fromkeys(watchlist + self.events))
            targets = combined

        today = datetime.now().astimezone(ZoneInfo("America/Chicago")).date()
        limit_date = today + timedelta(days=7)
        
        for event in targets:
            info = self.get_event_info(event)
            
            if info:
                show_date_str = info.get("air_date")
                if show_date_str:
                    try:
                        target_date = datetime.strptime(show_date_str, "%Y-%m-%d").date()
                        if target_date > limit_date:
                            continue
                    except ValueError:
                        pass
                
                show_name = info.get("show_name", "Desconocido")
                network = info.get("network", "S/N")
                watch_url = info.get("watch_url", "#")
                show_date = show_date_str
                show_time = info.get("air_time")
                
                msg = (
                    f"🚨 EVENTO DETECTADO: {event}!\n"
                    f"✨ {show_name}\n"
                    f"📅 Fecha: {show_date}\n"
                    f"⏰ Hora: {show_time}\n"
                    f"📺 Ver en: {network} (Link: {watch_url})\n"
                    f"\nMEDIA:{info.get('image_url')}"
                )
                
                success, error = send_telegram_notification(msg, self.channel_id)
                if success:
                    print(f"✅ Success: Notification sent for {event}")
                    found_any = True
                else:
                    print(f"❌ Failure: Failed to send Telegram for {event}: {error}")
            else:
                print(f"ℹ️ Status: No upcoming occurrence found for {event}. Data: {info}")
            
        print(f"--- Cycle Complete. Hits: {found_any} ---")

    def download_image(self, image_url, filename):
        try:
            import urllib.request
            local_path = os.path.join("/tmp", filename)
            urllib.request.urlretrieve(image_url, local_path)
            return local_path
        except Exception as e:
            print(f"❌ Image Download Error: {e}")
            return None

    def find_best_match(self, event_name, data):
        event_name_lower = event_name.lower()
        best_score = 0
        best_match = None

        for entry in data:
            show = entry.get("show")
            if not show:
                continue
            show_name = show.get("name", "").lower()

            if show_name == event_name_lower:
                return entry

            score = difflib.SequenceMatcher(None, event_name_lower, show_name).ratio()
            if score > best_score:
                best_score = score
                best_match = entry
        
        if best_score > 0.6:
            return best_match
        return None

    def get_event_info(self, event_name):
        search_url = f"https://api.tvmaze.com/search/shows?q={event_name.replace(' ', '%20')}"
        try:
            r = requests.get(search_url, timeout=15)
            r.raise_for_status()
            data = r.json()
        except Exception as e:
            print(f"❌ Search Error for {event_name}: {e}")
            return None

        if not data:
            return None

        match = self.find_best_match(event_name, data)
        if not match:
            return None

        show = match.get("show")
        
        nextepisode = show.get("_links").get("nextepisode")
        if nextepisode and nextepisode.get("href"):
            try:
                resp = requests.get(nextepisode["href"], timeout=15)
                resp.raise_for_status()
                next_ep_data = resp.json()
                dt_cst = datetime.fromisoformat(next_ep_data.get("airstamp")).astimezone(ZoneInfo("America/Chicago"))
                
                return {
                    "event_name": event_name,
                    "show_name": show.get("name"),
                    "air_date": dt_cst.date().strftime("%Y-%m-%d"),
                    "air_time": dt_cst.time().strftime("%I:%M:%S %p %Z"),
                    "network": show.get("network", {}).get("name", "TV/Streaming"),
                    "watch_url": show.get("url"),
                    "image_url": show.get("image", {}).get("medium"),
                }
            except Exception as e:
                print(f"⚠️ Error fetching nextepisode from {nextepisode['href']}: {e}")

        return None
