#!/usr/bin/env node

const { spawn } = require("node:child_process");

const child = spawn(
  "npx",
  [
    "-y",
    "chrome-devtools-mcp@latest",
    "--no-usage-statistics",
    ...process.argv.slice(2),
  ],
  {
    stdio: "inherit",
    env: {
      ...process.env,
      CHROME_DEVTOOLS_MCP_NO_USAGE_STATISTICS: "1",
    },
  },
);

const forwardedSignals = ["SIGINT", "SIGTERM", "SIGHUP"];
for (const signal of forwardedSignals) {
  process.on(signal, () => {
    if (child.exitCode === null && child.signalCode === null) {
      child.kill(signal);
    }
  });
}

child.on("error", (error) => {
  console.error(`Failed to launch chrome-devtools-mcp: ${error.message}`);
  process.exit(1);
});

child.on("exit", (code, signal) => {
  if (signal !== null) {
    process.removeAllListeners(signal);
    process.kill(process.pid, signal);
    return;
  }

  process.exit(code ?? 1);
});
