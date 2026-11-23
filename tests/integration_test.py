import unittest
from unittest.mock import patch, MagicMock
import sys
import os

# Add project root to path
sys.path.append(os.path.abspath(os.path.join(os.path.dirname(__file__), "..")))

from src.event_monitor import EventMonitor

class TestEventMonitorIntegration(unittest.TestCase):
    def setUp(self):
        self.monitor = EventMonitor()

    @patch('requests.get')
    def test_macy_parade_detection(self, mock_get):
        """Verify that 'Macy's Day Parade' is detected and formatted correctly."""
        # Mock TVMaze search response
        mock_get.return_value.status_code = 200
        mock_get.return_value.json.return_value = [
            {
                "show": {
                    "name": "Macy's Thanksgiving Day Parade",
                    "nextAirDate": "2026-11-26 12:00",
                    "network": {"name": "NBC"},
                    "url": "http://macy.com",
                    "image": {"medium": "http://img.com/parade.jpg"}
                }
            }
        ]

        result = self.monitor.get_event_info("Macy's Day Parade")
        
        self.assertIsNotNone(result)
        self.assertTrue(result["happening"])
        self.assertEqual(result["show_name"], "Macy's Thanksgiving Day Parade")
        self.assertEqual(result["network"], "NBC")
        self.assertEqual(result["watch_url"], "http://macy.com")

    def test_no_results_returns_none(self):
        """Verify that unknown events return None."""
        with patch('requests.get') as mock_get:
            mock_get.return_value.status_code = 200
            mock_get.return_value.json.return_value = []
            
            result = self.monitor.get_event_info("NonExistentShowXYZ123")
            self.assertIsNone(result)

if __name__ == "__main__":
    unittest.main()
