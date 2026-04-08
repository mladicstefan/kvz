## Toy KV store server
Zig v0.15.2

```bash
zig build
./zig-out/bin/kvz
nc localhost 25556
```
## Single threader benchmarks: 
1000000 inserts in 39.97s (25019 ops/sec)
