#!/usr/bin/env python3
"""Execute discovery activation and inspect M87's persisted configuration."""
import json
import os
from pathlib import Path
import sqlite3
import subprocess
import sys
import tempfile

package, activation = map(Path, sys.argv[1:])
m87 = str(package / "bin/m87")
expected = {
    "owned_repos": True,
    "authored_external": True,
    "explicit_repos": "dematom-labs/alteran,dematom-labs/data-first-jobs,dematom-labs/infrastructure",
}
with tempfile.TemporaryDirectory() as directory:
    home = Path(directory)
    env = {**os.environ, "HOME": str(home), "M87_STATE_DIR": str(home / ".m87"), "DRY_RUN_CMD": ""}
    for initial in ("fresh", "missing", "configured"):
        state = home / initial
        env["M87_STATE_DIR"] = str(state)
        if initial != "fresh":
            subprocess.run([m87, "init", "--yes", "--plugin", "skip", "--no-install-service"], env=env, check=True)
        if initial == "configured":
            subprocess.run([m87, "plugin", "add", "github", "--config", "owned_repos=false", "explicit_repos=old/repo"], env=env, check=True)
            for plugin in ("gmail", "mock"):
                subprocess.run([m87, "plugin", "add", plugin], env=env, check=True)
        for _ in range(2):
            subprocess.run(["bash", "-euo", "pipefail", str(activation)], env=env, check=True)
            with sqlite3.connect(state / "m87.sqlite") as db:
                config, = db.execute("select config_json from plugins where id='github'").fetchone()
                assert json.loads(config) == expected, config
