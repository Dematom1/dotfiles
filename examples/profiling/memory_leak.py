#!/usr/bin/env python3
"""
Memory leak example - demonstrates a common leak pattern.

Run with memray:
    memray run memory_leak.py
    memray flamegraph memray-memory_leak.py.*.bin
    open memray-flamegraph-*.html

Run with leaks (macOS):
    python3 memory_leak.py &
    leaks $(pgrep -f memory_leak.py)
"""

import time

# Global list that keeps growing - classic leak pattern
leaked_data = []

class DataHolder:
    """Holds some data that won't be freed."""
    def __init__(self, size: int):
        self.data = "x" * size  # Allocate memory

def leaky_function():
    """Creates objects that never get cleaned up."""
    for i in range(100):
        # These objects accumulate in the global list
        holder = DataHolder(10000)  # 10KB each
        leaked_data.append(holder)

def main():
    print("Starting memory leak demo...")
    print("Watch memory grow with: memray run --live memory_leak.py")
    print()

    for iteration in range(10):
        leaky_function()
        mb_used = len(leaked_data) * 10000 / 1024 / 1024
        print(f"Iteration {iteration + 1}: {len(leaked_data)} objects, ~{mb_used:.1f} MB leaked")
        time.sleep(0.5)

    print()
    print(f"Final: {len(leaked_data)} leaked objects")
    print("Memory was never freed!")

if __name__ == "__main__":
    main()
