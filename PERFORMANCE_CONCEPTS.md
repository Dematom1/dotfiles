# Performance Engineering Concepts

Core concepts for understanding low-level performance optimization.

## Computer Architecture

### Instruction-Level Parallelism (ILP)

Multiple instructions executing simultaneously on different execution units.

```
Cycle 1: [ALU: add]  [Load: fetch]  [Store: write]  ← 3 instructions in parallel
Cycle 2: [ALU: mul]  [Load: fetch]                  ← 2 instructions in parallel
```

**Key insight:** Find independent operations that can run at the same time.

### Pipeline Stalls & Hazards

**Data hazard:** Instruction B needs the result from instruction A.

```
add r1, r2, r3    ; r1 = r2 + r3
mul r4, r1, r5    ; r4 = r1 * r5  ← must wait for add to complete
```

**Solutions:**
- Reorder instructions to hide latency
- Insert independent work between dependent operations

### VLIW vs Superscalar

| VLIW | Superscalar |
|------|-------------|
| Compiler schedules parallelism | Hardware schedules at runtime |
| Simpler hardware | Complex hardware |
| Harder to program | Easier to program |
| Predictable performance | Dynamic optimization |

**Examples:** Intel Itanium (VLIW), most modern x86 CPUs (superscalar)

## Data Parallelism

### SIMD (Single Instruction Multiple Data)

One instruction operates on multiple data elements simultaneously.

```
Scalar:  a[0] + b[0], a[1] + b[1], a[2] + b[2], a[3] + b[3]  ← 4 instructions

SIMD:    [a[0], a[1], a[2], a[3]] + [b[0], b[1], b[2], b[3]]  ← 1 instruction
```

**Real-world SIMD instruction sets:**
- x86: SSE (128-bit), AVX (256-bit), AVX-512 (512-bit)
- ARM: NEON (128-bit), SVE (scalable)
- GPUs: thousands of SIMD lanes

### Vectorization

Converting scalar loops to vector operations.

```python
# Scalar (slow)
for i in range(n):
    c[i] = a[i] + b[i]

# Vectorized (fast) - conceptually
c[0:n] = a[0:n] + b[0:n]
```

**Requirements:**
- No data dependencies between iterations
- Aligned memory access helps
- Contiguous memory layout

## Performance Optimization Techniques

### Loop Unrolling

Repeat loop body to reduce overhead and expose parallelism.

```c
// Before: 1000 iterations, 1000 loop checks
for (i = 0; i < 1000; i++) {
    process(a[i]);
}

// After: 250 iterations, 250 loop checks, more ILP opportunities
for (i = 0; i < 1000; i += 4) {
    process(a[i]);
    process(a[i+1]);
    process(a[i+2]);
    process(a[i+3]);
}
```

### Memory Hierarchy

```
Registers    ~1 cycle      bytes
L1 Cache     ~4 cycles     32-64 KB
L2 Cache     ~12 cycles    256 KB - 1 MB
L3 Cache     ~40 cycles    8-64 MB
RAM          ~100 cycles   GBs
SSD          ~10,000+      TBs
```

**Locality:**
- **Spatial:** Access nearby memory locations together
- **Temporal:** Reuse data while it's still in cache

### Latency vs Throughput

| Concept | Definition | Example |
|---------|------------|---------|
| Latency | Time for one operation | 100ns to fetch from RAM |
| Throughput | Operations per second | 10 billion ops/sec |

**Pipelining** increases throughput without reducing latency:
```
Without pipeline: [----A----][----B----][----C----]
With pipeline:    [----A----]
                     [----B----]
                        [----C----]
```

### Branch Prediction

CPUs guess which way branches will go to keep the pipeline full.

```c
if (x > 0) {    // CPU predicts: probably true
    do_a();     // speculatively executes this
} else {
    do_b();     // if wrong, throw away work (expensive!)
}
```

**Optimization:** Make branches predictable or eliminate them.

```c
// Branchy (unpredictable)
if (condition) result = a; else result = b;

// Branchless (predictable)
result = condition * a + (!condition) * b;
```

## Learning Resources

### Books
- **"Computer Architecture: A Quantitative Approach"** - Hennessy & Patterson
- **"Computer Systems: A Programmer's Perspective"** - Bryant & O'Hallaron

### Free Resources
- **"What Every Programmer Should Know About Memory"** - Ulrich Drepper (paper)
- **MIT 6.172 Performance Engineering** - full course on YouTube
- **godbolt.org** - see compiler output, experiment with assembly

### Tools
- `perf` (Linux) - CPU performance counters
- `Instruments.app` (macOS) - profiling suite
- `samply` - flamegraph profiler (see PROFILING.md)
- `hyperfine` - benchmarking (see PROFILING.md)

## Practice Projects

1. **Anthropic Performance Takehome** - VLIW/SIMD optimization challenge
   - https://github.com/anthropics/original_performance_takehome
   - Cloned to: `~/Code/original_performance_takehome/`

2. **Write a raytracer** - naturally benefits from SIMD

3. **Optimize sorting algorithms** - cache behavior, branch prediction

4. **Matrix multiplication** - tiling, vectorization, memory layout

## See Also

- [PROFILING.md](./PROFILING.md) - Practical profiling tools
- [examples/profiling/](./examples/profiling/) - Test scripts
