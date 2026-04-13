# Toy KV Store Server

A toy key-value store server written in **Zig nightly**, built as a learning project to teach myself SIMD and low-level performance optimization.

> **⚠️ Important caveat:** Network latency — the primary bottleneck for real-world databases — is not simulated in these benchmarks. This is a fun toy project, not a production system, and I've probably made many mistakes along the way. Take all comparisons with a grain of salt.

---

## V1 — Naive Implementation

Single-threaded with no event loop, no `io_uring`, inefficient branching, no SIMD, and inefficient tokenization.

```bash
zig build run
nc localhost 25556
```

### Benchmarks

| Machine | Result | Throughput |
|---|---|---|
| Ryzen 7 3700X | 1,000,000 inserts in 39.97s | ~25,019 ops/sec |
| Intel Ultra 7 (hybrid E/P cores) | 1,000,000 inserts in 31.09s | ~32,170 ops/sec |

Roughly **15–20%** of Redis performance.

---

## V2 — SIMD & Cache-Friendly Redesign

```
1,000,000 inserts in 2.04s (489,721 ops/sec)
```

According to my (very unscientific) benchmark, V2 is approximately **3× faster than Redis**. The core hashmap and parser are faster thanks to being cache-friendly and using SIMD. Performance should improve further once Zig 0.16 lands `std.Io.Uring` socket support, which is currently not implemented.

### Disclaimers

- V2 **is not thread-safe** and probably isn't memory safe
- Only supports a small subset of actual Redis functionality (no persistence, etc.)
- The socket approach is likely much slower than Redis in real-world conditions
- Benchmark methodology is identical to V1 — take the Redis comparison lightly
