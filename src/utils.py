import subprocess
import logging
import requests
import datetime
import shlex
from urllib.parse import quote
from typing import Dict, Any, Optional

logging.basicConfig(level=logging.INFO, format='%(levelname)s: %(message)s')
logger = logging.getLogger(__name__)

def send_telegram_notification(message, channel_id):
    args = ["hermes", "send", "-t", "telegram", message]
    res = subprocess.run(args, shell=False, capture_output=True, text=True)
    if res.returncode == 0:
        return True, "Success"
    return False, res.stderr

def build_tvmaze_query_url(query: str) -> str:
    base_url = "https://api.tvmaze.com/search/shows?q="
    return base_url + quote(query)

def parse_date(date_str: str) -> Optional[datetime.date]:
    try:
        return datetime.datetime.strptime(date_str, "%Y-%m-%d").date()
    except (ValueError, TypeError):
        return None

def fetch_with_retry(url: str, timeout: int = 15, retries: int = 3) -> requests.Response:
    for i in range(retries):
        try:
            resp = requests.get(url, timeout=timeout)
            resp.raise_for_status()
            return resp
        except requests.RequestException as e:
            if i == retries - 1:
                raise e
    raise Exception("Fetch failed")
