## Toy KV store server
Zig v0.15.2

### V1 metrics
Single threaded - no event-loop, no IO_URING, inefficient branching,no SIMD, inefficient tokenizations:

```bash
zig build run
nc localhost 25556
```
## Single threader benchmarks: 
- 1000000 inserts in 39.97s (25019 ops/sec)
on Ryzen 7 3700x
- 1000000 inserts in 31.09s (32170 ops/sec) 
on Intel Ultra 7, hybrid E/P cores
####
~ roughly 15-20% of redis performance

### V2
Work in progress ;)

### Swisstable benchmark:

==================================================
=== SwissTable ===

==================================================

--- PUT ---
Total:   103 ms
Per op:  103 ns
Size:    1000000
Cap log2: 21

--- GET (hit) ---
Total:   66 ms
Per op:  66 ns

--- GET (miss) ---
Total:   10 ms
Per op:  10 ns

--- DEL ---
Total:   62 ms
Per op:  62 ns
Size:    0

==================================================
=== std.HashMap ===

==================================================

--- PUT ---
Total:   129 ms
Per op:  129 ns
Size:    1000000

--- GET (hit) ---
Total:   67 ms
Per op:  67 ns

--- GET (miss) ---
Total:   13 ms
Per op:  13 ns

--- DEL ---
Total:   56 ms
Per op:  56 ns
Size:    0

==================================================
