# PII Redactor V2 Plan

## Status

The existing implementation remains the active CLI while V2 is built in small,
testable slices. Compatibility with the Python implementation and its output is
not a requirement.

An opt-in **users/usermeta vertical slice** now spans compilation, schema-aware
reads, pure mutations, transactional apply, verification, and a separate CLI.
See `TODO.md` and `V2-USERS.md` for implemented scope and test evidence. M0 safety
work and pure redaction primitives are complete; full-profile migration and MySQL
integration validation remain outstanding. The milestone checkboxes below refer
to the complete V2 migration, not just this slice.

## Goals

- Redact WordPress data completely enough for database clones and exports.
- Make repeated runs idempotent.
- Keep transformations deterministic within and, when desired, across runs.
- Make policy scope, exclusions, and optional plugin support explicit.
- Plan and report without exposing raw PII by default.
- Apply mutations atomically when the storage engines support transactions.
- Keep the code easy to load, inspect, redefine, and exercise from a Phel REPL.

## Design constraints

1. **Plain data and functions first.** Profiles are ordinary Phel maps and
   vectors. Constructors or macros are introduced only when they remove proven
   repetition without hiding the resulting data.
2. **Small public pure functions.** Value transformation and profile
   compilation must be usable without PDO, CLI contexts, or global state.
3. **No arbitrary SQL DSL.** Generalize the stable operations—reading rows,
   transforming fields, dispatching metadata keys, deleting disposable rows,
   and auditing schema matches—not SQL itself.
4. **No order-dependent replacement registry.** Keyed deterministic transforms
   provide consistency without a separate scan pass.
5. **One target owner.** Profile compilation rejects overlapping mutation rules
   instead of relying on policy order or deferred-column exceptions.
6. **Exact rules mutate; heuristics audit.** Column-name discovery is report-only
   unless a reviewed profile explicitly opts into mutation.
7. **Backend-neutral mutations.** SQL is generated only at the PDO boundary.

## Target model

A profile is a map containing entities and rules. A rule has a stable `:id`, a
source, and an action. The first implementation needs only four source/action
shapes:

- row fields in a table;
- metadata key/value rows;
- deletion of matching disposable rows;
- report-only schema matches.

Example normalized row rule:

```phel
{:id :users/profile
 :category :identity
 :source {:kind :rows
          :table :users
          :pk [:ID]
          :entity [:user :ID]}
 :fields {:user_email {:kind :email :strategy :token}
          :user_login {:kind :login :strategy :token}
          :display_name {:kind :name
                         :strategy [:constant "Anonymous"]}}}
```

Value kind and replacement strategy are separate. For example, an email may use
`:token`, `:clear`, or `[:constant value]` depending on the profile and schema.

Sources normalize database rows to data like:

```phel
{:locator {:table "site_users" :pk {:ID 12}}
 :values {:user_email "person@example.org"}
 :entity {:type :user :id 12}}
```

Pure transformation produces findings and backend-neutral mutations. Reports
receive fingerprints and counts; raw before/after values remain internal.

## Execution pipeline

1. **Catalogue**
   - Resolve logical WordPress tables from the configured prefix and site scope.
   - Read primary keys, column types/lengths, unique indexes, generated columns,
     and storage engines.
   - Detect optional plugin tables and columns.

2. **Compile profile**
   - Resolve logical names against the catalogue.
   - Apply category, rule, table, and entity exclusions centrally.
   - Reject conflicting target ownership and incompatible output shapes.
   - Produce diagnostics for missing optional schema; fail for required schema.

3. **Read and transform**
   - Page rows by primary key.
   - Canonicalize values and generate keyed HMAC tokens without a registry pass.
   - Require every transform to be idempotent.
   - Emit distinct findings and row mutations.

4. **Plan or apply**
   - `plan` is the safe default and masks values.
   - `apply` is explicit and recomputes a fresh plan inside its transaction.
   - Updates use primary keys plus old-value predicates for stale-write detection.
   - Disposable data uses transactional `DELETE`, never `TRUNCATE`.
   - Foreign-key checks remain enabled.

5. **Verify**
   - Compare expected and affected row counts.
   - Run a post-apply audit.
   - Report findings, mutations, affected rows, exemptions, and unsupported data
     separately.

## WordPress profile coverage

### Core

- `users`: email, login, nicename, display name, password, activation key.
- `usermeta`: names, biographies, URLs, messaging identifiers, sessions and
  other credentials.
- `comments`: author name, email, URL, and IP, with explicit public-content
  semantics rather than inferred matching against known users.
- `posts`: report public content by default; allow an explicit policy for
  drafts/private content.

### Metadata and plugins

- WooCommerce billing/shipping metadata maps every exact key to a value kind;
  names, addresses, and phones must not be treated as email-only fields.
- WXR import slugs use an email transform with an opaque-placeholder fallback.
- WPML translator cache rows are deleted rather than edited as serialized text.
- Stream audit rows are transactionally deleted when the optional table exists.
- Newer WooCommerce HPOS tables are a separate composable profile module.

Structured values are decoded and re-encoded with an explicit codec. Disposable
caches should be deleted. Blind replacement inside PHP serialization is never
allowed.

## REPL-driven development

Every pure namespace should be useful independently:

```phel
(require 'pii.redactor.transforms)

(pii.redactor.transforms/redact
 "development-secret"
 :email
 :token
 "Person@Example.org")
```

Development rules:

- Keep namespace loading free of database connections and other side effects.
- Prefer named public functions over deeply nested anonymous callbacks.
- Return inspectable maps rather than opaque objects.
- Keep I/O at narrow functions suffixed with `!` where practical.
- Add examples to docstrings for key public functions.
- Test pure functions directly; use database fixtures only for the adapter.
- Use `with-redefs` at the REPL rather than service containers or dependency
  injection frameworks.

A `defprofile` macro is deliberately deferred. If introduced, it may only add
name/source metadata and invoke profile validation; its expansion must remain an
ordinary profile map and have macro-expansion tests.

## Implementation milestones

### M0 — immediate safety and foundation

- [x] Architecture review and replacement plan.
- [x] Make plan/preview the CLI default and require `--apply` for writes.
- [x] Hide query parameter values unless explicitly requested.
- [x] Replace Stream `TRUNCATE` with transactional `DELETE`.
- [x] Delete WPML cache rows safely and honor `--redact-options`.
- [x] Add pure keyed, idempotent transform primitives and tests.
- [x] Remove Python parity from the required test suite.
- [x] Validate the edit/reload/evaluate workflow against a live nREPL and
      document it in `REPL-GUIDE.md`.

### M1 — profile data and pure compiler

- [x] Define the minimal plain-map profile schema.
- [x] Add validation with useful path-oriented diagnostics.
- [x] Resolve category, table, and rule selection without database access.
- [x] Detect conflicting target ownership without database access.
- [ ] Define the initial core WordPress profile and exact metadata key maps.
- [x] Add REPL examples for validating and inspecting a profile.

### M2 — catalogue and readers

- [ ] Parse or override `$table_prefix`; support ports, sockets, and IPv6 hosts.
- [ ] Build a logical-to-physical table catalogue.
- [ ] Add optional-table and schema compatibility checks.
- [ ] Implement paged row, metadata, and delete-target readers.

### M3 — mutation engine

- [ ] Transform normalized rows into findings and mutations.
- [ ] Add entity-wide keep rules for users and linked rows.
- [ ] Validate lengths and generated-value uniqueness.
- [ ] Compile prepared CAS updates and transactional deletes.
- [ ] Refuse atomic mode for touched nontransactional tables.

### M4 — CLI and reporting

- [ ] Replace negative feature flags with uniform include/exclude selectors.
- [ ] Add safe text and JSON plan reports.
- [ ] Require an explicit apply confirmation tied to the database name.
- [ ] Report planned mutations separately from affected rows.
- [ ] Add post-apply verification.

### M5 — validation and cutover

- [ ] Apply twice; the second run must plan zero mutations.
- [ ] Failure-injection test proves complete rollback.
- [ ] Test custom prefixes, multisite, missing plugins, and non-InnoDB tables.
- [ ] Test exclusion scope across users, usermeta, and comments.
- [ ] Verify serialized caches are deleted or codec-round-tripped correctly.
- [ ] Prove normal reports never reveal raw PII.
- [ ] Run the independent dump scanner against representative fixtures.
- [ ] Switch the entry point to V2 and remove the legacy planner.

## Acceptance criteria

V2 is ready to replace the current implementation when:

- all profile rules are inspectable as plain data;
- all current use cases are represented without policy-order dependencies;
- a second application is a no-op;
- optional plugin absence is non-fatal;
- dry planning cannot modify the database or reveal raw values by default;
- transaction failure leaves all touched transactional tables unchanged;
- exact metadata fixtures contain no residual configured PII after apply; and
- the implementation remains understandable through direct REPL calls without
  requiring a macro-expansion or framework lifecycle to follow normal control
  flow.
