# Profiling & Performance Tools

Quick reference for performance analysis tools.

## hyperfine - Benchmarking

Compare command execution times with statistical analysis.

```bash
# Basic comparison
hyperfine 'cmd1' 'cmd2'

# With warmup runs (recommended)
hyperfine --warmup 3 'fd .' 'find . -type f'

# Export results
hyperfine 'cmd' --export-markdown results.md

# Compare shell startup
hyperfine 'zsh -i -c exit' 'bash -i -c exit'

# Parameterized benchmarks
hyperfine -P threads 1 8 'make -j {threads}'
```

**Tips:**
- Use `--warmup` to avoid cold cache effects
- Add `--shell=none` for very fast commands (<5ms)
- Use `--runs N` to control sample size

## samply - CPU Profiler

Generate flamegraphs to visualize where time is spent.

```bash
# Profile a command (opens browser)
samply record -- nvim --headless +qa

# Profile with more detail
samply record --rate 1000 -- ./my-program

# Profile a running process
samply record --pid $(pgrep -x node)

# Save profile for later
samply record -o profile.json -- ./my-program
samply load profile.json
```

**Reading Flamegraphs:**
- Width = time spent (wider = slower)
- Stack grows upward (bottom = entry point)
- Click to zoom into a function
- Look for wide bars - those are bottlenecks

## tokei - Code Statistics

Analyze codebase composition.

```bash
# Current directory
tokei

# Specific path
tokei ~/Code/myproject

# Sort by lines
tokei --sort lines

# Exclude directories
tokei --exclude node_modules --exclude .git

# Output as JSON
tokei --output json > stats.json

# Compare two versions
tokei --output json > before.json
# ... make changes ...
tokei --output json > after.json
```

## bandwhich - Network Monitor

Real-time network usage by process.

```bash
# Monitor all interfaces (needs sudo)
sudo bandwhich

# Specific interface
sudo bandwhich -i en0
```

**Columns:**
- Process: which program
- Connections: remote addresses
- Bandwidth: current throughput

## Common Workflows

### Optimize Shell Startup

```bash
# Measure current
hyperfine 'zsh -i -c exit'

# Profile to find slow parts
samply record -- zsh -i -c exit

# After changes, compare
hyperfine 'zsh -i -c exit'  # Should be faster
```

### Profile Neovim

```bash
# Built-in timing
nvim --startuptime /tmp/startup.log +qa
sort -t: -k2 -rn /tmp/startup.log | head -20

# CPU profile with flamegraph
samply record -- nvim --headless "+Lazy sync" +qa
```

### Benchmark Before/After

```bash
# Save baseline
hyperfine 'my-command' --export-json before.json

# Make optimizations...

# Compare
hyperfine 'my-command' --export-json after.json
```

### Find Network Hogs

```bash
# What's using bandwidth right now?
sudo bandwhich

# Combined with process info
sudo bandwhich & htop
```

## Installation

```bash
brew install hyperfine samply tokei bandwhich
```

## See Also

- `htop` / `btop` - Process monitor
- `duf` - Disk usage
- `dust` - Directory sizes
- `py-spy` - Python-specific profiler
- Instruments.app - macOS native profiler
