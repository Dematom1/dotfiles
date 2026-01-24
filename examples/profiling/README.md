# Profiling Examples

Test scripts to practice profiling tools.

## Memory Leak Detection

```bash
cd ~/Code/dotfiles/examples/profiling

# Profile with memray (recommended)
memray run memory_leak.py
memray flamegraph memray-memory_leak.py.*.bin
open memray-flamegraph-*.html

# Live view - watch memory grow in real-time
memray run --live memory_leak.py

# macOS leaks tool
python3 memory_leak.py &
sleep 2
leaks $(pgrep -f memory_leak.py)
kill $(pgrep -f memory_leak.py)
```

## CPU Profiling

```bash
cd ~/Code/dotfiles/examples/profiling

# Benchmark slow vs fast
hyperfine 'python3 cpu_heavy.py slow' 'python3 cpu_heavy.py fast'

# Generate flamegraph
samply record -- python3 cpu_heavy.py slow
# Opens browser with interactive flamegraph

# Profile just the slow version
samply record -- python3 cpu_heavy.py
```

## What to Look For

### In Memory Flamegraphs (memray)
- Wide bars = lots of allocations
- Look for functions that allocate but never free
- Check for growing collections (lists, dicts)

### In CPU Flamegraphs (samply)
- Wide bars = time spent
- Tall stacks = deep call chains
- Look for recursive functions without memoization

### In Benchmarks (hyperfine)
- Mean time and standard deviation
- Which is faster and by how much
- Warmup effects (use --warmup)

## Cleanup

```bash
# Remove generated files
rm -f memray-*.bin memray-flamegraph-*.html
```
