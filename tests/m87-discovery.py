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
    "explicit_repos": "dematom-labs/alteran,dematom-labs/data-first-jobs,dematom-labs/infrastructure,dematom-labs/hekera",
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
            npm = home / ".local/lib/node_modules/@kunchenguid/m87"
            npm.mkdir(parents=True)
            nix_root = package / "libexec/m87/node_modules/@kunchenguid/m87"
            with sqlite3.connect(state / "m87.sqlite") as db:
                original = db.execute("select * from plugins order by id").fetchall()
                for plugin_id, binary in db.execute("select id, binary_path from plugins").fetchall():
                    legacy = npm / Path(binary).relative_to(nix_root)
                    db.execute("update plugins set binary_path=? where id=?", (str(legacy), plugin_id))
            subprocess.run([
                sys.executable, str(Path(__file__).resolve().parents[1] / "scripts/m87-remove-npm-daemon.py"),
                str(nix_root),
            ], env=env, check=True)
            assert not npm.exists()
            with sqlite3.connect(state / "m87.sqlite") as db:
                assert db.execute("select * from plugins order by id").fetchall() == original
        for _ in range(2):
            subprocess.run(["bash", "-euo", "pipefail", str(activation)], env=env, check=True)
            with sqlite3.connect(state / "m87.sqlite") as db:
                config, = db.execute("select config_json from plugins where id='github'").fetchone()
                assert json.loads(config) == expected, config
