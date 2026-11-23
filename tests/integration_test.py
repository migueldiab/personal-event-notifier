import unittest
from unittest.mock import patch, MagicMock
import sys
import os

# Add project root to path
sys.path.append(os.path.abspath(os.path.join(os.path.dirname(__file__), '..')))

from src.event_monitor import EventMonitor

class TestEventMonitorIntegration(unittest.TestCase):

    def setUp(self):
        self.monitor = EventMonitor()

    @patch('requests.get')
    def test_macy_parade_detection(self, mock_get):
        """Verify that 'Macy's Day Parade' is detected and formatted correctly."""
        # Mock responses for search and next episode
        # Structure matches actual TVMaze /search/shows output
        search_response = {
            "score": 1.2537608,
            "show": {
                "id": 22447,
                "url": "https://www.tvmaze.com/shows/22447/macys-thanksgiving-day-parade",
                "name": "Macy's Thanksgiving Day Parade",
                "network": {
                    "id": 1,
                    "name": "NBC"
                },
                "image": {
                    "medium": "https://static.tvmaze.com/uploads/images/medium_portrait/651/1628471.jpg"
                },
                "_links": {
                    "nextepisode": {
                        "href": "https://api.tvmaze.com/episodes/3440528",
                        "name": "Macy's Thanksgiving Day Parade 2026"
                    }
                }
            }
        }
        next_ep_response = {
            "air_date": "2026-11-26",
            "air_time": "12:00",
            "airstamp": "2026-11-26T12:00:00Z"
        }

        mock_get.side_effect = [
            MagicMock(status_code=200, json=lambda: [search_response]),
            MagicMock(status_code=200, json=lambda: next_ep_response)
        ]
        mock_get.return_value.raise_for_status.return_value = None

        result = self.monitor.get_event_info("Macy's Day Parade")

        self.assertIsNotNone(result)
        self.assertEqual(result["show_name"], "Macy's Thanksgiving Day Parade")
        self.assertEqual(result["network"], "NBC")
        self.assertEqual(result["watch_url"], "https://www.tvmaze.com/shows/22447/macys-thanksgiving-day-parade")

    def test_no_results_returns_none(self):
        """Verify that unknown events return None."""
        with patch('requests.get') as mock_get:
            mock_get.return_value.status_code = 200
            mock_get.return_value.json.return_value = []
            
            result = self.monitor.get_event_info("NonExistentShowXYZ123")
            self.assertIsNone(result)

if __name__ == "__main__":
    unittest.main()
