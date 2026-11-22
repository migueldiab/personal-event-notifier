from src.event_monitor import EventMonitor
import sys

def main():
    if len(sys.argv) < 2:
        print("""
Usage: python3 main.py [events_list]
---------------------------------------
Description:
    Monitors and notifies regarding cultural/social events using TVMaze.

Mechanism:
    1. Identifies targets (from CSV input or internal config).
    2. Queries TVMaze for upcoming occurrences.
    3. Sends formatted Telegram alerts with Dates, Times, and Links.

Inputs:
    Events List (String): Comma-separated values (e.g., "The Oscars,SXSW"). 
                           If omitted, uses internal defaults.

Output:
    Console status updates and Telegram push notifications.
        """)
        sys.exit(0)

    monitor = EventMonitor()
    # Capture the first argument as the event list
    user_input = sys.argv[1]
    monitor.check_events(user_input)

if __name__ == "__main__":
    main()
