import subprocess

def send_telegram_notification(message, channel_id):
    """Sends a message to a Telegram channel via the hermes command."""
    cmd = f'hermes send -t telegram "{message}"'
    result = subprocess.run(cmd, shell=True, capture_output=True, text=True)
    if result.returncode == 0:
        return True, "Success"
    else:
        return False, result.stderr
