import unittest
from unittest.mock import patch, MagicMock
import datetime
import sys
import os

# Add the project root to sys.path
sys.path.append(os.path.abspath(os.path.join(os.path.dirname(__file__), '..')))

from src.event_monitor import EventMonitor

class TestEventMonitor(unittest.TestCase):

    def setUp(self):
        self.monitor = EventMonitor()

    def test_get_cst_details(self):
        dt_utc = datetime.datetime(2026, 11, 22, 12, 0, 0, tzinfo=datetime.timezone.utc)
        date_str, time_str = self.monitor.get_cst_details(dt_utc)
        self.assertEqual(date_str, "22/11/2026")
        self.assertEqual(time_str, "06:00 AM")

    def test_download_image_success(self):
        with patch('urllib.request.urlretrieve') as mock_retrieve:
            url = "http://example.com/image.jpg"
            filename = "test_img.jpg"
            with patch('os.path.join', return_value="/tmp/test_img.jpg"):
                result = self.monitor.download_image(url, filename)
                self.assertEqual(result, "/tmp/test_img.jpg")
                mock_retrieve.assert_called_once_with(url, "/tmp/test_img.jpg")

    def test_download_image_failure(self):
        with patch('urllib.request.urlretrieve', side_effect=Exception("Fail")):
            result = self.monitor.download_image("http://example.com/bad.jpg", "bad.jpg")
            self.assertIsNone(result)

    def test_find_best_match_exact(self):
        event_name = "The Oscars"
        results = [
            {"show": {"name": "30 Rock"}},
            {"show": {"name": "The Oscars"}},
        ]
        match = self.monitor.find_best_match(event_name, results)
        self.assertIsNotNone(match)
        self.assertEqual(match['show']['name'], "The Oscars")

    def test_find_best_match_no_substring_match(self):
        event_name = "Rock and Roll Hall of Fame"
        results = [
            {"show": {"name": "30 Rock"}},
            {"show": {"name": "Rock"}},
        ]
        match = self.monitor.find_best_match(event_name, results)
        self.assertIsNone(match)

    def test_find_best_match_none(self):
        event_name = "The Oscars"
        results = [
            {"show": {"name": "Cooking Show"}},
        ]
        match = self.monitor.find_best_match(event_name, results)
        self.assertIsNone(match)

    def test_find_best_match_low_similarity(self):
        event_name = "Macy's Day Parade"
        results = [
            {"show": {"name": "Macy's Thanksgiving Day Parade"}},
            {"show": {"name": "Cedar Park Parade"}},
            {"show": {"name": "30 Rock"}},
            {"show": {"name": "Rock"}},
        ]
        match = self.monitor.find_best_match(event_name, results)
        self.assertIsNotNone(match)
        self.assertEqual(match['show']['name'], "Macy's Thanksgiving Day Parade")

    def test_get_event_info_no_matches(self):
        with patch('src.event_monitor.requests.get') as mock_get:
            mock_get.return_value.json.return_value = []
            match = self.monitor.get_event_info("NonExistentEvent")
            self.assertIsNone(match)

    def test_get_event_info_no_schedule(self):
        with patch('src.event_monitor.requests.get') as mock_get:
            mock_get.side_effect = [
                MagicMock(json=lambda: [{"show": {"name": "Test Show", "id": "123"}}]),
                MagicMock(json=lambda: [])
            ]
            mock_get.return_value.raise_for_status.return_value = None
            match = self.monitor.get_event_info("Test Show")
            self.assertIsNone(match)

    def test_run_monitor_success_flow(self):
        """Test a full successful detection and notification flow."""
        mock_info = {
            "event_name": "The Oscars",
            "show_name": "The Oscars",
            "date": "2026-11-23",
            "air_time": "20:00",
            "network": "ABC",
            "watch_url": "http://oscars.com",
            "image_url": "http://img.com/oscars.jpg",
            "happening": True
        }

        def side_effect_get_info(name):
            if name == "The Oscars":
                return mock_info
            return None

        with patch('src.event_monitor.requests.get'), \
             patch('src.event_monitor.EventMonitor.get_event_info', side_effect=side_effect_get_info) as mock_get_info, \
             patch('src.event_monitor.EventMonitor.download_image') as mock_download, \
             patch('src.event_monitor.send_telegram_notification') as mock_send_tg, \
             patch('src.event_monitor.EventMonitor.get_cst_details') as mock_get_cst_details:
            
            mock_get_cst_details.return_value = ("23/11/2026", "08:00 PM")
            mock_download.return_value = "/tmp/oscars.jpg"
            mock_send_tg.return_value = (True, None)
            
            self.monitor.run_monitor()
            
            mock_get_info.assert_called()
            mock_send_tg.assert_called_once()
            
            args, _ = mock_send_tg.call_args
            msg = args[0]
            self.assertIn("🚨 EVENTO DETECTADO: The Oscars!", msg)
            self.assertIn("✨ The Oscars", msg)
            self.assertIn("📅 Fecha: 23/11/2026", msg)
            self.assertIn("⏰ Hora: 08:00 PM", msg)
            self.assertIn("📺 Ver en: ABC", msg)
            self.assertIn("MEDIA:tmp/oscars.jpg", msg)

    @patch('src.event_monitor.requests.get')
    @patch('src.event_monitor.EventMonitor.get_event_info')
    @patch('src.event_monitor.datetime.date')
    @patch('src.event_monitor.datetime.datetime')
    def test_run_monitor_fallback_info(self, mock_datetime, mock_date, mock_get_info, mock_get_req):
        mock_date.today.return_value = datetime.date(2026, 11, 22)
        mock_datetime.strptime.return_value = datetime.datetime(2026, 11, 23, 20, 0, 0)
        mock_datetime.now.return_value = datetime.datetime(2026, 11, 22, 12, 0, 0)
        
        mock_get_info.return_value = {
            "event_name": "SXSW",
            "show_name": "SXSW",
            "date": "2026-11-23",
            "air_time": "20:00",
            "network": "TV/Streaming",
            "watch_url": "http://sxsw.com",
            "image_url": None,
            "happening": False
        }
        
        self.monitor.run_monitor()
        self.assertTrue(mock_get_info.called)

    @patch('src.event_monitor.requests.get')
    @patch('src.event_monitor.EventMonitor.get_event_info')
    @patch('src.event_monitor.EventMonitor.download_image')
    @patch('src.event_monitor.datetime.date')
    @patch('src.event_monitor.datetime.datetime')
    @patch('src.event_monitor.send_telegram_notification')
    def test_run_monitor_image_failure(self, mock_send_tg, mock_datetime, mock_date, mock_download, mock_get_info, mock_get_req):
        mock_date.today.return_value = datetime.date(2026, 11, 22)
        mock_datetime.strptime.return_value = datetime.datetime(2026, 11, 23, 20, 0, 0)
        mock_datetime.now.return_value = datetime.datetime(2026, 11, 22, 12, 0, 0)
        
        mock_get_info.return_value = {
            "event_name": "The Oscars",
            "show_name": "The Oscars",
            "date": "2026-11-23",
            "air_time": "20:00",
            "network": "ABC",
            "watch_url": "http://url.com",
            "image_url": "http://img.com/img.jpg",
            "happening": True
        }
        
        mock_download.return_value = None
        mock_send_tg.return_value = (True, None)
        
        self.monitor.run_monitor()
        self.assertTrue(mock_send_tg.called)

    @patch('src.event_monitor.requests.get')
    def test_get_event_info_nextepisode_success(self, mock_get):
        # Mock first request: Search Shows
        search_response = MagicMock()
        search_response.json.return_value = [
            {
                "show": {
                    "name": "Oscars",
                    "id": "123",
                    "nextepisode": {
                        "href": "https://api.tvmaze.com/shows/123/episodes/456"
                    },
                    "url": "http://oscars.com",
                    "image": {"medium": "http://img.com/med.jpg"},
                    "network": {"name": "HBO"}
                }
            }
        ]
        
        # Mock second request: Nextepisode Details
        next_ep_response = MagicMock()
        next_ep_response.json.return_value = {
            "air_date": "2026-11-23",
            "air_time": "20:00"
        }
        next_ep_response.raise_for_status.return_value = None
        
        mock_get.side_effect = [search_response, next_ep_response]
        
        result = self.monitor.get_event_info("Oscars")
        
        self.assertIsNotNone(result)
        self.assertEqual(result["show_name"], "Oscars")
        self.assertEqual(result["date"], "2026-11-23")
        self.assertEqual(result["air_time"], "20:00")
        self.assertEqual(result["network"], "HBO")
