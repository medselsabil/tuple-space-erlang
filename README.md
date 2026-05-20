# Tuple Space in Erlang

Centralized Tuple Space implementation using Erlang/OTP based on the Linda coordination model.

## Modules

| Module | Description |
|--------|-------------|
| `ts` | Tuple Space server (gen_server + ETS) |
| `ts_bench` | Benchmarking and recovery tests |

## Requirements

- Erlang/OTP 26+
- Same cookie on all nodes

---

## Setup

**Terminal 1 — Server (do this first):**
```bash
erl -sname server -setcookie mycookie
```
```erlang
c(ts).
c(ts_bench).
ts:new(myts).
```

**Terminal 2 — Client:**
```bash
erl -sname client1 -setcookie mycookie
```
```erlang
net_adm:ping('server@Selssabils-MacBook').
```

**Back on Terminal 1 — Server (after client is connected):**
```erlang
ts:add_node(myts, 'client1@Selssabils-MacBook').
ts:nodes(myts).
```

---

## API

```erlang
ts:out(myts, {1, hello}).
ts:rd(myts, {1, '_'}).
ts:in(myts, {1, '_'}).

ts:in(myts, {99, '_'}, 2000).
ts:rd(myts, {99, '_'}, 2000).

ts:remove_node(myts, 'client1@Selssabils-MacBook').
ts:nodes(myts).
ts:add_node(myts, 'client1@Selssabils-MacBook').
```

---

## Blocking Behavior

From client, start a blocking call:
```erlang
ts:in(myts, {99, '_'}).
```

From server, insert the matching tuple:
```erlang
ts:out(myts, {99, found}).
```

The blocked call returns immediately with `{ok, {99, found}}`.

---

## Benchmarks

### Latency
```erlang
ts_bench:run().
```

### Node Recovery

On server:
```erlang
ts_bench:bench_recovery().
```

When it prints `Node connected. Kill client1 now...`, press `Ctrl+C` twice on Terminal 2.

### Results

| Operation | Avg Latency | Notes |
|-----------|-------------|-------|
| `out/2` | ~3 µs | end-to-end: cast + ETS insert |
| `rd/2` | ~2–3 µs | sync call + ETS lookup |
| `in/2` | ~2–3 µs | ETS lookup + deletion |
| node recovery | ~6–7 s | net_ticktime = 2s |

Measured with N = 10,000 operations on Erlang/OTP 26+, macOS.


