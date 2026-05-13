# Tuple Space in Erlang

Centralized Tuple Space implementation using Erlang/OTP based on the Linda coordination model.

## Modules

| Module | Description |
|--------|-------------|
| `ts` | Tuple Space server |
| `ts_bench` | Benchmarking and recovery tests |

## Requirements

- Erlang/OTP 26+

## How to Run

### Single node

```bash
erl -sname server -setcookie mycookie
```

```erlang
c(ts).
c(ts_bench).
```

### Create a Tuple Space

```erlang
ts:new(myts).
```

## API

### Core Operations

```erlang
ts:out(myts, {1, hello}).           % insert tuple
ts:rd(myts, {1, '_'}).              % read tuple (blocking, non-destructive)
ts:in(myts, {1, '_'}).              % consume tuple (blocking)
```

### With Timeout

```erlang
ts:in(myts, {99, '_'}, 2000).       % {ok, Tuple} or {err, timeout}
ts:rd(myts, {99, '_'}, 2000).       % {ok, Tuple} or {err, timeout}
```

### Node Visibility Management

```erlang
ts:add_node(myts, 'node2@hostname').     % add node to TS
ts:remove_node(myts, 'node2@hostname').  % remove node
ts:nodes(myts).                          % list all nodes
```

### Stop

```erlang
ts:stop(myts).
```

## Running Benchmarks

### out / rd / in latency

```erlang
ts_bench:run().
```

### Node recovery time (two terminals)

**Terminal 1:**
```bash
erl -sname server -setcookie mycookie
```
```erlang
c(ts), c(ts_bench).
ts_bench:bench_recovery().
```

**Terminal 2:**
```bash
erl -sname client1 -setcookie mycookie
```

When Terminal 1 prints `Node connected. Kill client1 now...`, press Ctrl+C twice in Terminal 2.

## Benchmark Results

| Operation | Avg Latency | Notes |
|-----------|-------------|-------|
| `out/2` | ~3 µs | end-to-end: cast + ETS insert |
| `rd/2` | ~2–3 µs | sync call + ETS lookup |
| `in/2` | ~2–3 µs | ETS lookup + deletion |
| node recovery | ~3 s | net_ticktime = 2s |

Measured with N = 10,000 operations on Erlang/OTP 26+, macOS.

## Design

- **gen_server** — serializes state access, implements blocking calls via `{noreply, State}`
- **ETS (bag)** — O(1) lookup and deletion, supports duplicate tuples
- **Waiting queue** — blocked callers stored with pattern + monitor ref, woken on matching `out`
- **Consumed flag** — ensures only one `in` caller receives a tuple when multiple are waiting
- **monitor_node** — detects node failures without crashing the server

The system preserves Linda semantics: `in` is destructive, `rd` is non-destructive, and both are blocking operations based on pattern matching.
