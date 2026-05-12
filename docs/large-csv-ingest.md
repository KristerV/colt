# Large CSV ingest playbook

A field guide distilled from optimising the EE RIK elemendid ingest (3.7M rows,
294 MB CSV → Postgres `annual_reports`) on a 2 GB Fly box. We took it from
"5,000 rows in 14 minutes" to a baseline that scales linearly. This document
is what we wish we had read on day zero.

Use this whenever you ingest a multi-million-row dump into Postgres on a
resource-constrained host. Most of the lessons are not Elixir-specific but
the code shapes are.

---

## Checklist before you write a line of code

- [ ] **Source on disk fits**. Estimate: raw CSV + zip + unzipped DB rows.
  Plan to delete zips after unzip and CSVs after a successful run.
- [ ] **Same-region DB**. Cross-region network latency × round-trips × chunk
  count is often the entire cost. Check `fly status -a $DB_APP` vs the app's
  region.
- [ ] **The source data is sorted by your grouping key**. Verify with
  `cut -d';' -f1 file | uniq | wc -l` vs `sort -u | wc -l`. If equal, your
  groups are contiguous and you can stream them without a global accumulator.
- [ ] **Identify the smallest unit of work that completes**. For us:
  "one report's worth of element rows" → one `annual_reports` row. Stream
  one unit at a time; never accumulate all units in memory.
- [ ] **DB action**: is the source immutable? Use `INSERT … ON CONFLICT DO
  NOTHING` instead of `DO UPDATE`. Skipping the update path is a huge win
  when most rows already exist.

---

## Pitfalls in order of impact

### 1. Don't use Ash (or Ecto.changesets) for bulk ingest

The hottest path we hit was 500-1000× slower than raw SQL. Per-row changeset
validation, action lifecycle, identity resolution, and lifecycle callbacks
are *each* designed to be cheap, but they're not free when multiplied by a
million rows.

```elixir
# Slow: ~18-42 ms per row through Ash bulk_create
Ash.bulk_create!(rows, AnnualReport, :upsert,
  return_errors?: true, stop_on_error?: true)

# Fast: ~0.04 ms per row through raw SQL
Ecto.Adapters.SQL.query!(Repo, """
INSERT INTO annual_reports (id, company_id, year, revenue_eur, ...)
SELECT * FROM unnest($1::uuid[], $2::uuid[], $3::int[], ...)
ON CONFLICT (company_id, year) DO NOTHING
""", [ids, company_ids, years, ...])
```

The Ash action stays for general use (UI, other services). The ingest hot
path bypasses it. Keep it isolated; don't let the bypass leak.

### 2. Use `unnest(arrays)` instead of `VALUES (…), (…)`

Postgres has a 65,535-parameter limit per statement. With `VALUES` you spend
N params per row → max ~9,000 rows per insert at 7 cols. With `unnest()` you
spend **one** param per column regardless of row count: 8 params total, 50k+
rows per chunk no problem.

```elixir
sql = """
INSERT INTO annual_reports (id, company_id, year, revenue_eur, employees,
                            source, inserted_at, updated_at)
SELECT * FROM unnest(
  $1::uuid[], $2::uuid[], $3::int[], $4::numeric[],
  $5::int[],  $6::text[], $7::timestamptz[], $8::timestamptz[]
)
ON CONFLICT (company_id, year) DO NOTHING
"""

# Postgrex encodes Elixir lists → Postgres arrays directly.
Ecto.Adapters.SQL.query!(Repo, sql, [
  ids,            # [<<16-byte>>, ...]
  company_ids,    # [Ecto.UUID.dump!(id), ...]
  years,          # [int, ...]
  revenues,       # [%Decimal{} | nil, ...]
  ...
])
```

Note: use `Ecto.UUID.bingenerate/0` for new IDs (already 16-byte binary,
matches `uuid` column without casting). Use `Ecto.UUID.dump!/1` for UUIDs
that come from your DB as strings.

### 3. Stream by group, don't collect-then-emit

The naive shape is "read all rows, reduce into `%{group => acc}`, then write
the map". The map grows linearly. Every minor GC scans it on every cycle.
We saw the same parsing function go from 220 rows/s at row 5k to 25 rows/s
at row 500k — pure GC scan cost on a 500k-entry accumulator.

If the file is sorted by the grouping key (you checked this above), the fix
is `Stream.chunk_by`:

```elixir
path
|> File.stream!([:raw, {:read_ahead, 256 * 1024}, :binary], :line)
|> Stream.drop(1)                       # skip header
|> Stream.filter(&relevant?/1)
|> Stream.map(&parse_row/1)
|> Stream.reject(&is_nil/1)
|> Stream.chunk_by(& &1.group_key)      # emit groups as they complete
|> Stream.map(&reduce_group/1)          # %{revenue: ..., employees: ...}
|> Stream.flat_map(&to_db_params/1)
|> Stream.chunk_every(5_000)
|> Enum.each(&bulk_insert!/1)
```

Heap is now bounded by *one group's worth of rows* + the current chunk —
not by the whole file.

### 4. `File.stream!` defaults are slow — and `:raw` mode in `File.stream!` doesn't fix it

The default talks to a separate I/O server *process* via Erlang Ports.
Every `:io.get_line` call is a message round-trip and a scheduler hop.
Multiply by a few million lines and your process spends 95%+ of its time
**waiting for messages**, not parsing. We measured reductions/sec at 95k —
roughly 0.1% of one scheduler's capacity.

**What we tried first (didn't help):**

```elixir
# Plausible but no measurable speedup in our test:
File.stream!(path, [:raw, {:read_ahead, 256 * 1024}, :binary], :line)
```

Even with `:raw + :line` modes, Elixir's `File.stream!` wraps line reads
in a way that didn't break us out of the Port-roundtrip regime. The reds
count went up modestly but wall-clock didn't improve and we sometimes
saw it get *worse* due to binary-handling interactions.

**What worked (30-40× speedup):** a hand-rolled `Stream.resource` that
opens the file raw and reads in 256 KB chunks, splitting lines manually:

```elixir
defp raw_line_stream(path) do
  Stream.resource(
    fn ->
      {:ok, fd} = :file.open(path, [:read, :raw, :binary, {:read_ahead, 256 * 1024}])
      %{fd: fd, buffer: ""}
    end,
    fn %{fd: fd, buffer: buffer} = state ->
      case :file.read(fd, 256 * 1024) do
        {:ok, chunk} ->
          data = buffer <> chunk

          case :binary.split(data, "\n", [:global]) do
            [only] ->
              {[], %{state | buffer: only}}

            many ->
              [partial | rev_lines] = Enum.reverse(many)
              lines = rev_lines |> Enum.reverse() |> Enum.map(&(&1 <> "\n"))
              {lines, %{state | buffer: partial}}
          end

        :eof when byte_size(buffer) == 0 ->
          {:halt, state}

        :eof ->
          {[buffer], %{state | buffer: ""}}
      end
    end,
    fn %{fd: fd} -> :file.close(fd) end
  )
end
```

`:file.open(:raw)` returns a file handle Port owned directly by the
calling process. `:file.read/2` is a single BIF call into the file
driver — no Port message exchange, no scheduler hop. Each call returns
up to 256 KB; we split it on `\n` ourselves and emit all complete lines
in one Stream.resource step. The trailing partial line carries to the
next read.

Measured impact in our case (elemendid_2023, 3.7M rows):

- Before: ~21 s per 500-report chunk, sustained
- After: ~500 ms per chunk; major-GC pauses occasionally bump to 4-8 s
- Reductions/sec for the ingest process jumped from 95k to 4-10M

`NimbleCSV.parse_stream/2` uses the same `:file.open(:raw)` pattern
internally — same reason.

### 5. Sub-binary retention pins large buffers in memory

When you `:binary.split/2` a line into 5 sub-binaries, each sub-binary
keeps the original line binary alive. Combined with `read_ahead`, where a
"line" is actually a sub-binary of a 256 KB read buffer, you can pin
hundreds of MB just by holding small references in an accumulator.

Symptom: parse and fold timings inflate dramatically when you turn on
`read_ahead`; heap looks small but binary memory keeps growing.

Fix: copy fields you intend to store with `:binary.copy/1`:

```elixir
defp parse_row(line) do
  case :binary.split(line, ";", [:global]) do
    [report_id, tabel, _label, element, value_nl] ->
      %{
        report_id: :binary.copy(report_id),
        tabel:     :binary.copy(strip_quotes(tabel)),
        element:   :binary.copy(strip_quotes(element)),
        value:     :binary.copy(strip_quotes(trim_newline(value_nl)))
      }
    _ -> nil
  end
end
```

Copy cost: roughly N rows × bytes-per-field; for 4M rows × 80 bytes ≈ 300 MB
of memcpy = <1 second of wall time. Trivial vs the GC pressure you avoid.

The same trap applies to *any* function that retains binary fields from
parsed input — `parse_overview_row` style code that builds a long-lived
lookup map needs `:binary.copy` on every field that ends up in the map.

### 6. `NimbleCSV.parse_string/2` per line is slow

NimbleCSV is optimised for parsing a whole CSV stream in one pass, not
called once per line. The per-call setup cost dominates when the line is
tiny. We measured ~9 ms per call.

If your file has a fixed, known schema with no embedded separators inside
quoted fields (verify first!), bypass NimbleCSV with `:binary.split` and
positional binding:

```elixir
# Verify the assumption ONCE before relying on it:
#   awk -F';' 'NR > 1 && NF != 5 {bad++} END {print bad+0}' file.csv
#   → must print 0

defp parse_row(line) do
  case :binary.split(line, ";", [:global]) do
    [_, _, _, _, _] = fields -> bind_fields(fields)
    _ -> nil
  end
end

defp strip_quotes(<<?", rest::binary>>) when byte_size(rest) >= 1,
  do: :binary.part(rest, 0, byte_size(rest) - 1)
defp strip_quotes(s), do: s
```

`NimbleCSV.parse_stream/2` (file-level, not per-line) is still excellent
for irregular CSV files.

### 7. Delete cache files when stages finish

If you cache downloaded dumps under `priv/` and don't clean up, you'll
fill the Fly rootfs in a few runs. The OOM kill path is *exactly* the
moment when you want logs to keep flowing.

```elixir
defp cleanup_cache do
  dir = Application.fetch_env!(:my_app, :cache_dir)
  abs_dir = if Path.type(dir) == :absolute, do: dir, else: Application.app_dir(:my_app, dir)

  case File.ls(abs_dir) do
    {:ok, names} ->
      Enum.each(names, fn name -> _ = File.rm(Path.join(abs_dir, name)) end)
    _ -> :ok
  end
end
```

Run `cleanup_cache/0` only at the *end of a fully successful run* — mid-run
failures should leave cache intact so `from: N` resume works.

Also: delete the `.zip` immediately after a successful unzip. Doubles your
disk headroom and the next run will re-download cheaply (HTTP layer can
revalidate).

### 8. Map vs ETS for lookup tables

Heuristic:

- **Map**: in-process, single reader, static or rarely-mutated, fits in
  hundreds of MB. Lookups are 50-150 ns. Default choice.
- **ETS**: shared across processes *or* huge (tens of millions) *or*
  mutated while held by long-running processes. Lookups are 200-500 ns
  (BIF call + term copy out).

A 500k-entry static lookup map in one process is fine as a map. Moving it
to ETS for a "speedup" actually makes lookups slightly slower.

Where ETS *does* help on the ingest path: if your process heap is huge
because of static data, major GC scans it on every collection. ETS keeps
that data off-heap. But for tables this size the heap effect is minor.

### 9. Don't mix cache windows in scheduling

Unrelated to ingest specifically, but: schedulers (and Anthropic prompt
cache) tend to have a sweet spot. For our DB connection pool we use 5-10s
checkout timeout; the ingest holds one connection for the whole stage
with no problem. For background scheduling: either stay in cache window
(<5min between ticks) or commit to a long wait (>20min).

---

## Diagnostic recipe

When ingest is slow, **measure before changing**. Wild guesses cost hours.

Add per-chunk instrumentation that captures:

```
chunk N: P rows
  | produce Xms (filter=A parse=B fold=C params=D chunk_by=E chunk_every=F)
  | gc N colls, M MB reclaimed
  | reds N M
  | heap M MB (Δ K MB)
  | bin M MB
  | msgq N
  | db Yms
```

Implementation pattern using process dict accumulators:

```elixir
defp tick_us(key, us), do: Process.put(key, (Process.get(key) || 0) + us)
defp pop_ms(key) do
  us = Process.get(key) || 0
  Process.put(key, 0)
  div(us, 1000)
end

|> Stream.filter(fn x ->
     t = System.monotonic_time(:microsecond)
     ok? = do_filter(x)
     tick_us(:t_filter, System.monotonic_time(:microsecond) - t)
     ok?
   end)
```

Reading the numbers:

| Symptom | Interpretation |
|---|---|
| `produce` ≫ sum of named stages | I/O wait or scheduler preemption (Port latency) |
| One named stage dominates | Optimise that one — usually `parse` |
| `heap` grows linearly across chunks | Accumulator leak (Pitfall 3) |
| `bin` grows but `heap` stable | Sub-binary retention (Pitfall 5) |
| `gc` ≫ named work, `reclaimed` is small | GC churn from a large static heap |
| `reds` < 5M per chunk over 20+ seconds | Process barely runs — blocked or starved |
| `db` ≫ rest | Postgres or connection issue, not your code |

Process snapshot helper:

```elixir
defp proc_snapshot do
  {gc_count, gc_words, _} = :erlang.statistics(:garbage_collection)
  {:reductions, reds} = :erlang.process_info(self(), :reductions)
  {:total_heap_size, heap} = :erlang.process_info(self(), :total_heap_size)
  {:message_queue_len, msgq} = :erlang.process_info(self(), :message_queue_len)
  mem = :erlang.memory()
  %{gc_count: gc_count, gc_words: gc_words, reductions: reds,
    total_heap: heap, binary: Keyword.get(mem, :binary, 0), msg_queue: msgq}
end
```

`:erlang.statistics(:garbage_collection)` is **global**, not per-process —
includes Logger, LiveView, system_live ticks etc. Useful as relative
delta, noisy as absolute number.

`heap` and `gc_words` are in *words* (8 bytes on 64-bit). Multiply by 8
when printing in MB.

### Probing the DB without running the pipeline

Wrap `EXPLAIN (ANALYZE, BUFFERS)` in `BEGIN/ROLLBACK` so side effects
don't persist:

```sql
BEGIN;
EXPLAIN (ANALYZE, BUFFERS)
INSERT INTO target (...) SELECT ... FROM source LIMIT 5000
ON CONFLICT (...) DO NOTHING;
ROLLBACK;
```

If Postgres reports a small execution time but the app takes 500× longer,
the bottleneck is in app/driver/network — never in the DB itself.

### Verifying loaded code in iex

`function_exported/3` only sees public functions. For private ones (or to
confirm a hot-reload took):

```elixir
# Compile timestamp
Module.module_info(:compile)[:time]

# Local (private) functions
{:ok, {_, [{:exports, _}, {:locals, locals}]}} =
  :beam_lib.chunks(:code.which(Module), [:exports, :locals])
Enum.find(locals, fn {name, _arity} -> name == :the_private_fn end)

# Forced clean reload
:code.purge(Module)
:code.delete(Module)
r Module
```

---

## Architecture sketch

The shape that survived contact with reality:

```
┌──────────────────────────────────────────────────────────────┐
│ Stage 1: Download (cleanup .zip immediately after unzip)     │
├──────────────────────────────────────────────────────────────┤
│ Stage 2: Build lookup indexes                                │
│   - aruannete.csv → %{report_id => %{code, year}}            │
│   - companies     → %{registry_code => company}              │
│   :binary.copy retained fields                               │
├──────────────────────────────────────────────────────────────┤
│ Stage 3: Stream elemendid → DB                               │
│                                                              │
│   raw_line_stream(path)                  # Stream.resource   │
│   |> Stream.drop(1)                                          │
│   |> Stream.filter(&relevant?/1)                             │
│   |> Stream.map(&parse_row/1)            # :binary.split     │
│   |> Stream.reject(&is_nil/1)                                │
│   |> Stream.chunk_by(& &1.report_id)     # sorted → safe     │
│   |> Stream.map(&fold_group/1)                               │
│   |> Stream.flat_map(&to_params/1)                           │
│   |> Stream.chunk_every(5_000)                               │
│   |> Enum.each(&bulk_insert_ignore!/1)   # unnest + DO NOTHING│
├──────────────────────────────────────────────────────────────┤
│ Stage 4: Cleanup cache directory                             │
└──────────────────────────────────────────────────────────────┘
```

Live heap during stage 3 is bounded by:
- one report's row group (a few KB)
- one 5,000-row params chunk (a few MB)
- the two lookup maps (tens of MB each, static)

Not by the file size or row count. That's the goal.

---

## The numbers that mattered

For posterity, the speedup ladder we walked through:

| Change | reports/sec (steady state) | Notes |
|---|---|---|
| Original (Ash, byte-by-byte parser) | ~0.4 | binary heap leak in parser, accumulator GC death |
| NimbleCSV parser | ~5 | fixed parse heap leak; still O(n²) accumulator |
| Stream-by-group instead of accumulate-then-write | ~13 | bounded heap; raw SQL DB time now negligible |
| Raw SQL `INSERT ... ON CONFLICT DO NOTHING` | (same) | Ash overhead gone; revealed that the bottleneck was upstream of DB |
| `:binary.split` positional parse | (same) | parse cost dropped ~300×, but didn't show up because I/O wait dominated |
| `Stream.resource` raw file reader | **~500-1000** | reductions/sec jumped from 95k to 4-10M; Port roundtrip eliminated |

Total wall time for elemendid_2023 (3.7M rows, 255k reports):

- Before: **~5 hours**, throughput degrading
- After: **~7-9 minutes**, throughput linear except for periodic ~5-8s
  major-GC pauses scanning the in-process lookup maps (~350 MB)

The "before/after" rates are end-to-end including DB writes — once the
ingest process is running CPU-bound instead of waiting on Port replies,
everything else falls into the noise.

**What didn't help (so we don't try it again):**

- `File.stream!(path, [:raw, {:read_ahead, 256_000}, :binary], :line)` —
  no measurable improvement vs default. Whatever `File.stream!` does
  internally with `:raw + :line`, it doesn't bypass the Port-roundtrip
  cost in the way `:file.read/2` + manual splitting does. Use the
  `Stream.resource` pattern instead.
- `File.stream!(read_ahead: 256_000)` alone (non-raw) — made things
  *worse* due to sub-binary retention pinning 256 KB read buffers.
- Bumping Ash `bulk_create!` chunk size from 500 → 5000 — gave only
  marginal improvement because the cost was per-row Ash overhead, not
  per-call SQL overhead.

**Remaining lever** (not pulled yet): move `latest_by_report` and
`by_code` into ETS. They're ~350 MB combined and live in the ingest
process's heap. Every major GC scans them even though they never
change. ETS would keep them off-heap; major GC pauses would disappear.
Cost: ~100-300 ns per lookup vs ~50-150 ns for map. Only worth doing
if 7-9 minute runs aren't fast enough.

Total wall time for elemendid_2023 (3.7M rows):
- Before: ~5 hours, degrading
- After: ~target 10-30 minutes, linear
