# Sync System — Design Notes

Part 2 of the challenge: keep local `TodoList`/`TodoItem` records in sync with an
external Todo API (see `docs/README.md` / `docs/external-api.yaml`), supporting
create, update and delete in both directions, with resilience, minimal external
calls, and clear logging.

## Overview

The sync is a **bidirectional reconciliation**: on each run it fetches the full
external snapshot, diffs it against the local state, and applies the minimal set
of changes to converge the two sides.

Conflicts are resolved with **last-write-wins (LWW)** on `updated_at`, gated by a
value **dirty-check** (we only act when values actually differ). Deletes follow a
**"the delete wins"** rule and are propagated using **tombstones** (local→external)
and pull-deletes (external→local).

The core is a plain Ruby service (`Sync::TodoSyncService`) so it can be driven by
a rake task (the POC) or an ActiveJob (`TodoSyncJob`) on Solid Queue.

## How to run

Everything works inside the dev container (`.devcontainer/`) — Ruby **3.3**
(bumped from the original 3.1 to satisfy Rails 7.1's `>= 3.2.0` requirement),
with `postCreateCommand` running `bundle install && bundle exec rake db:setup`.
This has been verified end-to-end in an actual container (not just locally):
`bundle exec rspec`, `bin/dev`, `bin/rails sync:run`, and the forwarded ports all
confirmed working from a clean `devcontainer up`.

### Dev container quick start

```bash
npm install -g @devcontainers/cli      # or use VS Code's "Dev Containers" extension
devcontainer up --workspace-folder .
devcontainer exec --workspace-folder . -- bash -lc "bundle exec rspec"
devcontainer exec --workspace-folder . -- bash -lc "bin/dev"   # web + css + worker + fake API
```

With the container up, `http://localhost:3000` (the UI) and `http://localhost:3001`
(the fake external API) are both reachable from the host — `devcontainer.json`
forwards both ports. Equivalently, open the repo in VS Code and run
**"Dev Containers: Reopen in Container"**, then use the integrated terminal.

### 0. Setup

```bash
bundle install
bin/rails db:migrate         # sync columns/tables + Solid Queue tables
```

### 1. Have an external Todo API to sync against

By default the client points at `http://localhost:3001`
(`ExternalTodoApi::Configuration`, overridable with `EXTERNAL_TODO_API_URL`). If
you don't have the real service handy, a tiny in-memory stand-in is included
(`script/fake_external_todo_api.rb`) and already listens on that same default
port — no env var needed. `bin/dev` (step 2) starts it for you automatically, so
you normally don't need to run it by hand.

Only set `EXTERNAL_TODO_API_URL` if you want to point at a real service running
somewhere else, e.g. `EXTERNAL_TODO_API_URL=http://localhost:4000 bin/rails
sync:run` — in that case, comment out (or remove) the `fake_external_api` line
in `Procfile.dev` before running `bin/dev`, so you don't have an unused fake
server sitting on `:3001`.

You can poke at the fake API directly to see it behave like the real one. Its
`id`s (`ext-1`, `ext-2`, ...) come from a counter that keeps incrementing for as
long as the process runs, so **don't hardcode them** — capture the real `id`
from each response instead (using `ruby -rjson`, always available in this
project, rather than assuming `jq` is installed):

```bash
LIST_ID=$(curl -s -X POST http://localhost:3001/todolists \
  -H 'Content-Type: application/json' \
  -d '{"source_id": null, "name": "Remote list", "items": [{"source_id": null, "description": "buy bread", "completed": false}]}' \
  | ruby -rjson -e 'puts JSON.parse(STDIN.read)["id"]')

ITEM_ID=$(curl -s http://localhost:3001/todolists \
  | ruby -rjson -e 'puts JSON.parse(STDIN.read).find { |l| l["id"] == ARGV[0] }["items"].first["id"]' "$LIST_ID")

echo "list=$LIST_ID item=$ITEM_ID"   # e.g. list=ext-2 item=ext-1 — but could be anything
```

...then update/delete using those variables:

```bash
# Update the list's name
curl -X PATCH "http://localhost:3001/todolists/$LIST_ID" \
  -H 'Content-Type: application/json' \
  -d '{"name": "Renamed remote list"}'
# => {"id":"...","source_id":null,"name":"Renamed remote list","updated_at":"...","items":[...]}

# Update an item's description/completion
curl -X PATCH "http://localhost:3001/todolists/$LIST_ID/todoitems/$ITEM_ID" \
  -H 'Content-Type: application/json' \
  -d '{"description": "buy wholegrain bread", "completed": true}'
# => {"id":"...","source_id":null,"description":"buy wholegrain bread","completed":true,"updated_at":"..."}

# Delete the item (use -i to see the status; DELETE responses have no body)
curl -i -X DELETE "http://localhost:3001/todolists/$LIST_ID/todoitems/$ITEM_ID"
# => HTTP/1.1 204 No Content

# Delete the whole list (and any remaining items)
curl -i -X DELETE "http://localhost:3001/todolists/$LIST_ID"
# => HTTP/1.1 204 No Content
```

Run `bin/rails sync:run` after any of these to see the reconciler pull the change
into the local DB: `pulled_update=1` after a `PATCH` (list or item), `deleted_local=1`
after a `DELETE` (list or item) — see `Sync::Applier`'s `pull_update_*`/`pull_delete_*`
handlers.

⚠️ **The fake API keeps its data in memory only.** Restarting it (killing and
re-running `script/fake_external_todo_api.rb`, or restarting `bin/dev`) wipes its
store back to empty. If you then run `bin/rails sync:run`, the reconciler sees an
empty external snapshot and — because of the "the delete wins" rule (see
Resilience & idempotency) — **pull-deletes every previously-synced local list and
item** (the ones that had an `external_id`). This is a quirk of the in-memory
stand-in, not of the sync logic: a real external API is expected to persist its
data across restarts, so this scenario shouldn't arise against the real service.

### 2. Run the app (web server + Solid Queue worker + fake external API)

`bin/dev` starts everything declared in `Procfile.dev` in one terminal: the
Rails server, the Tailwind watcher, the Solid Queue worker, and the fake
external Todo API:

```bash
bin/dev
```

Or start the pieces manually in separate terminals if you only need some of
them (the worker is required for the queued path and the recurring schedule in
`config/recurring.yml`, not for the inline POC below):

```bash
bin/rails server                        # web app on :3000
bin/rails solid_queue:start             # worker + recurring scheduler, or: bin/jobs
ruby script/fake_external_todo_api.rb   # fake external API on :3001 (skip if using a real service)
```

### 3. Run the sync

**POC — inline, no worker needed.** Runs one reconciliation immediately and
prints the result:

```bash
bin/rails sync:run
# => Sync result: pulled_create=1
```

Run it again against the same state and nothing changes (idempotent):

```bash
bin/rails sync:run
# => Sync result:
```

**Queued path — via the worker.** With `bin/rails solid_queue:start` (or
`bin/dev`) running, enqueue a run:

```bash
bin/rails sync:enqueue
# => Enqueued TodoSyncJob on the :sync queue.
```

The worker log will show `[Sync] ...` lines as it processes the job. Left
running, the worker also fires `TodoSyncJob` automatically every 5 minutes via
`config/recurring.yml` — no manual enqueue needed for continuous syncing.

### Tests

```bash
bundle exec rspec
```

## Architecture

The pieces are deliberately separated so the decision logic is pure and testable
and all I/O is isolated:

| Component | File | Responsibility |
|---|---|---|
| `ExternalTodoApi::Client` | `app/services/external_todo_api/client.rb` | Faraday wrapper, one method per endpoint |
| `ExternalTodoApi::ResourceError` | `.../resource_error.rb` | non-2xx / transport error, knows `#retryable?` |
| `Sync::Mapper` | `app/services/sync/mapper.rb` | field mapping, `source_id`, timestamp parsing, snapshot normalization |
| `Sync::Reconciler` | `app/services/sync/reconciler.rb` | **pure** diff engine → list of `Action`s |
| `Sync::Applier` | `app/services/sync/applier.rb` | executes actions (HTTP + AR), per-record retry |
| `Sync::TodoSyncService` | `app/services/sync/todo_sync_service.rb` | orchestrates a run, returns `Sync::Result` |
| `TodoSyncJob` | `app/jobs/todo_sync_job.rb` | ActiveJob wrapper (retries, concurrency) |

Because `Reconciler` performs no I/O, the entire decision matrix is unit-tested
without touching the network.

## A sync run — and how few calls it makes

`Sync::TodoSyncService#call` runs four phases:

1. **Fetch** — a single `GET /todolists` returns the whole external state (lists
   with nested items). This is the only read. A failed/partial fetch aborts the
   run (see Resilience).
2. **Index** — build lookup hashes for local and external records (in memory).
3. **Reconcile** — the pure `Reconciler` produces the actions.
4. **Apply** — the `Applier` performs only the necessary writes.

External calls per run: `1 (GET) + new-lists (POST) + changed-records (PATCH) +
tombstones (DELETE)`. Pull operations write locally only — **zero** external
calls. A converged state costs exactly **1 call** (the GET) and zero mutations.

## Data model & migrations

- **Timestamps on `todo_lists`** — the table had none; LWW needs `updated_at` on
  both sides (`db/migrate/*_add_timestamps_to_todo_lists.rb`).
- **`external_id` + `last_synced_at`** on `todo_lists` and `todo_items` — the link
  to the external record and the last successful reconciliation time.
- **`sync_tombstones`** — a positive record that a previously-synced record was
  deleted locally, so we can propagate the DELETE. `propagated_at` is set once the
  external DELETE succeeds (idempotency).

**Why a tombstone table instead of soft-delete?** A hard delete leaves no trace,
so "missing locally" is ambiguous (deleted vs. never existed vs. local DB reset).
A tombstone is the unambiguous "this was deleted" signal, and unlike a
`deleted_at` + `default_scope` it doesn't touch the domain models or the existing
specs (e.g. the `dependent: :destroy` test keeps passing). The tombstone is
written by the `Syncable` concern (`app/models/concerns/syncable.rb`) on
`after_destroy`, only when the record had an `external_id`.

**Why no `origin` column?** With LWW, a record absent from a *complete* snapshot
is treated as deleted, and `external_id` already distinguishes "never pushed"
(no id → push-create) from "was synced, now gone" (has id → pull-delete). So an
ownership flag isn't needed.

## Reconciliation algorithm

**Matching:** by `external_id` first; if absent, fall back to `source_id`
(`"rails-<local_id>"`). The fallback repairs a link lost to a crash between the
`POST` and saving the returned `external_id`, so we never create a duplicate.

**Decision matrix** (lists; items are identical within a matched list):

| Situation | Action |
|---|---|
| Local without `external_id`, no match | **push-create** (`POST`, items nested) |
| Both match, values differ, local newer | **push-update** (`PATCH`) |
| Both match, values differ, external newer | **pull-update** (update local) |
| Both match, values equal | no-op |
| External-only, born external (`source_id` not ours) | **pull-create** |
| Local with `external_id`, absent from snapshot | **pull-delete** (delete wins) |
| Pending tombstone | **push-delete** (delete wins) |
| External claims to be ours but no local & no tombstone | **log inconsistency** |
| New local item on an already-existing external list | **warn + skip** (API gap) |

**LWW + dirty-check:** timestamps are parsed to UTC; the newer side wins, with a
1-second epsilon breaking ties toward local. Crucially, we only act when the
mapped values differ — this is what prevents ping-pong. After a pull we also copy
the external `updated_at` onto the local row so the next run doesn't mistake it
for "locally newer".

## Field mapping & `source_id`

- `TodoList.name` ↔ external `name`.
- `TodoItem.title` ↔ external `description`; `TodoItem.complete` ↔ external `completed`.
- When we push a record we stamp `source_id = "rails-<local_id>"`. This namespaced
  value is our correlation key and lets us tell records that originated locally
  from records born on the external side (whose `source_id` is null).

## Deletes

- **Local delete → external:** `after_destroy` writes a tombstone (if the record
  had an `external_id`); the next run issues the `DELETE` and marks the tombstone
  `propagated_at`. Deleting a whole list emits only a list tombstone — the
  external `DELETE /todolists/:id` cascades to its items, so per-item tombstones
  are skipped (via `destroyed_by_association`).
- **External delete → local:** a synced record absent from a complete snapshot is
  destroyed locally (with tombstone suppression, so we don't try to re-delete it).
- **Delete vs. concurrent update — "the delete wins":** simpler and predictable,
  avoids zombie records, and doesn't require a delete timestamp from the external
  API (which it doesn't expose).

## Resilience & idempotency

- **Fetch is fatal on failure:** a failed GET propagates (nothing is applied), so
  we never act on a partial snapshot — which would otherwise cause false deletes
  or duplicate creates. A queued job retries the whole (idempotent) run later.
- **Trusting the snapshot:** a successful GET is treated as the complete external
  state (the API has no pagination), so deletes are propagated as-is. This
  deliberately favours honoring real deletes over guarding against a (rare)
  valid-but-wrong empty response; a count-based abort was rejected because it
  would also block legitimate bulk deletes. The robust fix (deferred deletes with
  a grace period, so transient glitches self-heal while real deletes still
  propagate) is noted under Future work.
- **Partial-failure isolation:** each action is applied independently; a failure
  is recorded in `Sync::Result` and the run continues.
- **Two-level retries:** the `Applier` retries transient failures per-record with
  backoff (so we don't redo already-synced records); `TodoSyncJob` additionally
  `retry_on` transient errors for the whole run and `discard_on Sync::Aborted`.
- **Idempotent by construction:** `external_id`/`source_id` matching prevents
  duplicates, `propagated_at` prevents double-deletes, and the value dirty-check
  makes redundant writes no-ops. Re-running a converged state does nothing.
- **Concurrency:** `TodoSyncJob` uses Solid Queue's `limits_concurrency key: "todo-sync", to: 1`
  so runs don't overlap.
- **Logging:** every decision is logged under the `[Sync]` tag, plus a final
  summary (`Sync::Result#to_s`).

## Performance

One GET per run (full snapshot with nested items), batched creates via the nested
`POST`, PATCH only on a real value diff, and pulls that cost no external calls.

## Assumptions

- The external API leaves `source_id` **null** for records created directly on it
  (confirmed by the create-body schema; it's what lets us tell local- vs
  external-born records apart).
- `GET /todolists` returns the complete set (the current API has no pagination).
- External `id`s are stable strings.

## Limitations & trade-offs

- **No standalone item creation on the external API.** There's no endpoint to add
  an item to an *existing* external list (items can only be created nested in the
  list `POST`). A new local item added to an already-synced list is logged and
  skipped rather than doing a destructive list recreate. New items on a *new* list
  sync fine (nested).
- **LWW drops the losing edit** and is subject to clock skew between systems (the
  epsilon mitigates ties, not genuine skew).
- **"The delete wins"** can discard a very recent edit made on the other side.
- **Solid Queue on SQLite** needed a `busy_timeout` (see Decisions log) to survive
  its dispatcher/worker/scheduler starting concurrently; fine for the POC's
  scale, but a separate queue database is the production-grade option.

## Scalability

The single full-reconcile run is correct for the app's real dataset, but it pulls
the entire external state each run — the bottleneck is the API contract
(`GET /todolists`, no `?since=`/pagination → O(total) per run). Roughly: hundreds–
low thousands are fine, tens of thousands get wasteful, millions are infeasible.

Roadmap (requires API support in most cases):
1. **Delta/incremental pull** (`updated_after`/changes feed) — the primary fix,
   O(changes) instead of O(total).
2. **Event-driven push** (`after_commit` → per-CRUD job) so the frequent path is
   O(changes) and full-reconcile becomes an infrequent safety net. The decoupled
   core makes this a drop-in addition.
3. **Webhooks from the external API** — the pull-side equivalent: react to
   created/updated/deleted events instead of polling. With (2), the whole sync
   becomes event-driven and reconciliation is only a safety net.
4. **Pagination/streaming**, **watermark cursor**, **sharding** with parallel
   workers.

Honest caveat: event-driven fixes the *push* side at scale; the *pull* side only
scales with delta sync (1).

## Decisions log

- **Bidirectional LWW** over one-way/owner-wins: honors the full brief (create
  local when detected in external + propagate local changes) without a heavy
  conflict-resolution layer, thanks to the value dirty-check.
- **Tombstone table** over soft-delete: non-invasive, keeps existing specs green.
- **Faraday** over `Net::HTTP`: declarative setup, JSON middleware, first-class
  with WebMock; all HTTP is hidden behind `ExternalTodoApi::Client`.
- **Rails 7.1 + Solid Queue** on a single SQLite DB: modern durable jobs without
  Redis; the sync core stays independent of the queue.
- **Periodic reconciliation** as the backbone (event-driven documented as future
  work).
- **`css: bin/rails tailwindcss:watch[always]`** in `Procfile.dev`, not the bare
  task: Tailwind CSS v4's CLI auto-exits its watcher when `stdin` isn't a TTY
  (the case under `foreman`/containers) — without `always`, `bin/dev` looked like
  it silently died seconds after boot. Found by actually running `bin/dev`
  inside the dev container, not just in an interactive terminal locally.
- **`timeout: 5000` in `config/database.yml`**: Solid Queue runs its dispatcher,
  worker and scheduler as separate OS processes against the same SQLite file;
  without a busy-timeout, concurrent access at boot raised
  `SQLite3::BusyException`. Rails' sqlite3 adapter maps `timeout:` directly to
  `busy_timeout()`. Also only surfaced when testing in the dev container, where
  all three processes cold-start at once.

## Testing

- `spec/services/sync/reconciler_spec.rb` — the full decision matrix, pure, no HTTP.
- `spec/services/external_todo_api/client_spec.rb` — each endpoint + error handling
  (500 retryable, 422 not, timeout, 404-on-delete), via WebMock.
- `spec/services/sync/todo_sync_service_spec.rb` — integration: push-create,
  pull-create, tombstone delete, **idempotency** (0 mutations), **partial failure**
  isolation, and **GET-abort**.
- `spec/jobs/todo_sync_job_spec.rb` — enqueue/perform + retry/discard config.
- `spec/models/sync_tombstone_spec.rb` — tombstone creation rules (incl. cascade).

All specs stub the external API with WebMock (`WebMock.disable_net_connect!`), so
the suite never hits the network.

## Future work

Delta sync; event-driven push via `after_commit`; webhooks for real-time pull; a
separate Solid Queue database; deferred deletes with a grace period (mark a
record "missing since" and only delete it after it stays absent for N runs, so a
transient empty snapshot self-heals while real deletes still propagate); and an
optional "newest wins" rule for the delete-vs-update conflict.
