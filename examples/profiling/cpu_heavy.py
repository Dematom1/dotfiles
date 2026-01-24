#!/usr/bin/env python3
"""
CPU-heavy example - demonstrates CPU profiling.

Run with samply:
    samply record -- python3 cpu_heavy.py

Run with hyperfine:
    hyperfine 'python3 cpu_heavy.py'

Compare optimized vs unoptimized:
    hyperfine 'python3 cpu_heavy.py slow' 'python3 cpu_heavy.py fast'
"""

import sys
import time

def slow_fibonacci(n: int) -> int:
    """Naive recursive fibonacci - exponential time complexity."""
    if n <= 1:
        return n
    return slow_fibonacci(n - 1) + slow_fibonacci(n - 2)

def fast_fibonacci(n: int) -> int:
    """Iterative fibonacci - linear time complexity."""
    if n <= 1:
        return n
    a, b = 0, 1
    for _ in range(2, n + 1):
        a, b = b, a + b
    return b

def slow_prime_check(n: int) -> bool:
    """Check if n is prime - naive approach."""
    if n < 2:
        return False
    for i in range(2, n):  # Could stop at sqrt(n)
        if n % i == 0:
            return False
    return True

def fast_prime_check(n: int) -> bool:
    """Check if n is prime - optimized."""
    if n < 2:
        return False
    if n == 2:
        return True
    if n % 2 == 0:
        return False
    for i in range(3, int(n ** 0.5) + 1, 2):
        if n % i == 0:
            return False
    return True

def main():
    mode = sys.argv[1] if len(sys.argv) > 1 else "slow"

    print(f"Running in {mode} mode...")
    start = time.time()

    if mode == "fast":
        # Fast versions
        for i in range(35):
            fast_fibonacci(i)
        for i in range(10000):
            fast_prime_check(i)
    else:
        # Slow versions
        for i in range(35):
            slow_fibonacci(i)
        for i in range(10000):
            slow_prime_check(i)

    elapsed = time.time() - start
    print(f"Completed in {elapsed:.2f}s")

if __name__ == "__main__":
    main()
