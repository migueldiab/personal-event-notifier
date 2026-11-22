import datetime
import requests
import os
import difflib
from .config import INTEREST_EVENTS, TELEGRAM_CHANNEL_ID
from .utils import send_telegram_notification

class EventMonitor:
    def __init__(self):
        self.events = INTEREST_EVENTS
        self.channel_id = TELEGRAM_CHANNEL_ID

    def check_events(self):
        self.run_monitor()

    def run_monitor(self):
        print(f"--- Starting Monitor Cycle: {datetime.datetime.now()} ---")
        found_any = False
        
        for event in self.events:
            print(f"Checking {event}...")
            info = self.get_event_info(event)
            
            if info and info.get("happening"):
                dt_utc = datetime.datetime.strptime(f"{info['date']} {info['air_time']}", "%Y-%m-%d %H:%M")
                dt_utc = dt_utc.replace(tzinfo=datetime.timezone.utc)
                time_str = self.get_cst_time_str(dt_utc)
                
                msg = (
                    f"🚨 EVENTO DETECTADO: {event}!\\n"
                    f"✨ {info['show_name']}\\n"
                    f"⏰ Hora: {time_str}\\n"
                    f"📺 Ver en: {info['network']} (Link: {info['watch_url']})\\n"
                )
                
                if info.get("image_url"):
                    img_path = self.download_image(info['image_url'], f"{event.replace(' ', '_')}.jpg")
                    if img_path:
                        # Ensure we don't have double slashes like MEDIA://
                        msg += f"MEDIA:{img_path.lstrip('/')}"
                
                success, error = send_telegram_notification(msg, self.channel_id)
                if success:
                    print(f"✅ Notification sent for {event}")
                    found_any = True
                else:
                    print(f"❌ Failed to send Telegram for {event}: {error}")
            else:
                print(f"ℹ️ No upcoming occurrence found for {event}")
            
        print(f"--- Cycle Complete. Found: {found_any} ---")

    def get_cst_time_str(self, dt_utc):
        dt_cst = dt_utc.astimezone(datetime.timezone(datetime.timedelta(hours=-6)))
        return dt_cst.strftime("%d/%m/%Y a las %I:%M %p")

    def download_image(self, image_url, filename):
        try:
            import urllib.request
            local_path = os.path.join("/tmp", filename)
            urllib.request.urlretrieve(image_url, local_path)
            return local_path
        except Exception as e:
            print(f"❌ Error descargando imagen: {e}")
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

        if best_score > 0.8:
            return best_match
        return None

    def get_event_info(self, event_name):
        search_url = f"https://api.tvmaze.com/search/shows?q={event_name.replace(' ', '%20')}"
        try:
            r = requests.get(search_url, timeout=15)
            r.raise_for_status()
            data = r.json()
        except Exception as e:
            print(f"❌ Error en la búsqueda para {event_name}: {e}")
            return None

        if not data:
            return None

        match = self.find_best_match(event_name, data)
        if not match:
            return None

        show = match.get("show")
        
        # Optimization: Try to use nextAirDate directly from the show object
        # This avoids an extra network request for the schedule.
        next_air_date = show.get("nextAirDate")
        if next_air_date:
            try:
                parts = next_air_date.split(' ')
                date_part = parts[0]
                air_time = parts[1] if len(parts) > 1 else ""
                
                # Verify it's in the future
                day_dt = datetime.datetime.strptime(date_part, "%Y-%m-%d").date()
                if day_dt >= datetime.date.today():
                    return {
                        "event_name": event_name,
                        "show_name": show.get("name"),
                        "date": date_part,
                        "air_time": air_time,
                        "network": show.get("network", {}).get("name", "TV/Streaming"),
                        "watch_url": show.get("url"),
                        "image_url": show.get("image", {}).get("medium"),
                        "happening": True
                    }
            except Exception:
                pass # Fall back to schedule if parsing fails

        # Fallback: Full schedule fetch
        show_id = show.get("id")
        schedule_url = f"https://api.tvmaze.com/shows/{show_id}/schedule?page=0"
        schedule = []
        try:
            sched_r = requests.get(schedule_url, timeout=15)
            sched_r.raise_for_status()
            schedule = sched_r.json()
        except Exception:
            pass

        today = datetime.date.today()
        for day in schedule:
            day_str = day.get("date")
            if not day_str: continue
            day_dt = datetime.datetime.strptime(day_str, "%Y-%m-%d").date()
            
            if day_dt >= today:
                for episode in day.get("episodes", []):
                    return {
                        "event_name": event_name,
                        "show_name": show.get("name"),
                        "date": day_str,
                        "air_time": episode.get("air_time"),
                        "network": show.get("network", {}).get("name", "TV/Streaming"),
                        "watch_url": show.get("url"),
                        "image_url": show.get("image", {}).get("medium"),
                        "happening": True
                    }
        return None

if __name__ == "__main__":
    monitor = EventMonitor()
    monitor.run_monitor()
