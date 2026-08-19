from flask import Flask, request, abort
import subprocess
import hmac
import hashlib
import os
from pathlib import Path

# Optional: load .env if python-dotenv is installed
try:
    from dotenv import load_dotenv
    load_dotenv()
except ImportError:
    pass

app = Flask(__name__)

WEBHOOK_SECRET = os.environ.get("WEBHOOK_SECRET")
BASE_DIR = Path(__file__).resolve().parent

def verify_signature():
    if not WEBHOOK_SECRET:
        # Prevent running if secret is unconfigured
        return False

    signature = request.headers.get("X-Hub-Signature-256")
    if not signature:
        return False

    # Compute expected SHA256 HMAC
    expected = "sha256=" + hmac.new(
        WEBHOOK_SECRET.encode(),
        request.get_data(),
        hashlib.sha256
    ).hexdigest()

    return hmac.compare_digest(signature, expected)

@app.route("/", methods=["POST"])
@app.route("/webhook", methods=["POST"])
def webhook():
    # Security check
    if not verify_signature():
        abort(401)

    # Safe JSON parsing (handles None/non-JSON gracefully)
    data = request.get_json(silent=True) or {}
    branch = data.get("ref")

    print(f"Webhook received: {branch}")

    if branch in ["refs/heads/main", "refs/heads/dev"]:
        print(f"{branch} pushed! Launching WSL popup terminal and logging...")
        script_path = BASE_DIR / "test.sh"

        # Log timestamp header to deploy.log
        with open(BASE_DIR / "deploy.log", "a", encoding="utf-8") as f:
            f.write(f"\n--- [Webhook Triggered: {branch}] ---\n")

        # Command to launch in a new visible popup window running WSL + tee to deploy.log
        wsl_cmd = (
            f"bash '{script_path.name}' 2>&1 | tee -a deploy.log; "
            f"echo ''; read -n 1 -s -r -p 'Press any key to close...'"
        )

        subprocess.Popen(
            ["cmd.exe", "/c", "start", "CI/CD Webhook Trigger", "wsl", "bash", "-c", wsl_cmd],
            cwd=str(BASE_DIR)
        )

        return {"status": "success", "message": "WSL script started in popup window"}

    return {"status": "ignored", "message": f"Ignored ref: {branch}"}

if __name__ == "__main__":
    if not WEBHOOK_SECRET:
        print("[WARNING] WEBHOOK_SECRET environment variable is not set!")
    app.run(host="0.0.0.0", port=5000)
