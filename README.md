## Toy KV store server
Zig nightly

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
```
1000000 inserts in 2.04s (489721 ops/sec)
```
Now acording to my very shady benchmark, (same as benchmark for v1) I am approximately 3x faster than redis. Of course my implementation is only a subset of the functionality of Redis and doesn't support persistence, regardless this was a fun project. It can and will be even faster when Zig 0.16 ```std.Io.Uring``` drops the support for sockets, which is currently, not implemented.
Disclaimer: V2 isn't thread safe, probably isn't memory safe, and works only on a small subset of actual redis functionality, the core HASHMAP & Parser is faster (Due to being cache-friendly and using SIMD), although the socket approach is probably much slower.
