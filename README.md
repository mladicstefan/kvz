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
