import os, sys, tarfile, time
from datetime import datetime
from huggingface_hub import HfApi, hf_hub_download
from huggingface_hub.utils import disable_progress_bars

disable_progress_bars()

api = HfApi()
repo_id = os.getenv("HF_DATASET")
token = os.getenv("HF_TOKEN")
FILENAME = "latest_backup.tar.gz"
LOCK_FILE = "/root/.openclaw/.backup_last_time"
MIN_INTERVAL = 600

def log(msg):
    print(f"[{datetime.now().strftime('%Y-%m-%d %H:%M:%S')}] {msg}", flush=True)

def restore():
    try:
        if not repo_id or not token:
            log("Skip Restore: HF_DATASET or HF_TOKEN not set")
            return
        log(f"Downloading {FILENAME} from {repo_id}...")
        path = hf_hub_download(repo_id=repo_id, filename=FILENAME, repo_type="dataset", token=token)
        with tarfile.open(path, "r:gz") as tar:
            tar.extractall(path="/root/.openclaw/")
        log(f"Restore Success: {FILENAME}")
        return True
    except Exception as e:
        log(f"Restore Note: No backup found or error: {e}")

def backup(force=False):
    try:
        if not repo_id or not token:
            log("Skip Backup: HF_DATASET or HF_TOKEN not set")
            return

        if not force and os.path.exists(LOCK_FILE):
            try:
                last = float(open(LOCK_FILE).read().strip())
                elapsed = time.time() - last
                if elapsed < MIN_INTERVAL:
                    return
            except Exception:
                pass

        with tarfile.open(FILENAME, "w:gz") as tar:
            paths_to_backup = [
                "/root/.openclaw/sessions",
                "/root/.openclaw/agents",
                "/root/.openclaw/skills",
                "/root/.openclaw/plugins",
                "/root/.openclaw/extensions",
                "/root/.openclaw/credentials",
                "/root/.openclaw/workspace",
            ]
            for p in paths_to_backup:
                if os.path.exists(p):
                    arcname = p.replace("/root/.openclaw/", "")
                    tar.add(p, arcname=arcname)

        api.upload_file(
            path_or_fileobj=FILENAME,
            path_in_repo=FILENAME,
            repo_id=repo_id,
            repo_type="dataset",
            token=token
        )
        open(LOCK_FILE, "w").write(str(time.time()))
        log(f"Backup Success: {FILENAME} updated.")
    except Exception as e:
        log(f"Backup Error: {e}")

if __name__ == "__main__":
    if len(sys.argv) > 1 and sys.argv == "backup":
        backup(force="--force" in sys.argv)
    else:
        restore()
