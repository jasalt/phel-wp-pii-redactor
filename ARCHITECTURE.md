# V2 architecture: modules and execution flow

This documents the **implemented, opt-in users/usermeta slice** entered through
`src/users.phel`, not a whole-database sanitizer or the future design in
[`PLAN.md`](PLAN.md). See [`V2-USERS.md`](V2-USERS.md) for operation and limitations.
The default `src/main.phel` still runs the separate legacy
`main.phel` → `policies.phel` / `core.phel` / `db.phel` pipeline.

Both diagrams are inline D2 source. A Markdown viewer needs D2 support to render
them; alternatively, save a block as `diagram.d2` and run
`d2 diagram.d2 diagram.svg`. Arrows in the first diagram show responsibilities
and dependencies; the second diagram shows execution order.

## Module responsibilities

Module names below are relative to `src/pii/redactor/` except the entry point.
Pure modules accept and return ordinary Phel data; they do not connect to a
 database, print reports, or keep mutable replacement registries.

```d2
entry: "src/users.phel\nEntry point: argv → phel.cli → exit code"
cli: "users_cli.phel\nIntent, secret, preflight, DB confirmation\nSafe text/JSON output; suppress error details"
config: "db.phel (shared with legacy)\nParse literal wp-config; open PDO connection"
runner: "runner.phel\nResolve linked exemptions; process bounded pages\nOwn transaction, counters and verification"
store: "store.phel\nPrefix/schema catalogue; keyset reads\nCapacity checks; guarded SQL; affected-row checks"
database: "Offline database clone\nInnoDB; SQLite for adapter tests" {
  shape: cylinder
}

pure: "Pure data and transformations" {
  wordpress: "wordpress.phel\nExact users/usermeta profile maps"
  profile: "profile.phel\nProfile diagnostics and basic rule selection"
  compiler: "compiler.phel\nValidate strategies and selectors\nResolve scope; reject overlapping mutation ownership"
  engine: "engine.phel\nNormalize row/identity; exact field dispatch\nLinked exemptions; mutation maps + safe findings"
  transforms: "transforms.phel\nCanonicalization, validation, HMAC tokens\nClear/constant strategies; idempotent value results"

  compiler -> profile: "assert-valid / enabled-rules"
  engine -> transforms: "redact / changed?"
}

entry -> cli: "run-command"
cli -> config: "open-target! → parse-wp-config / connect"
config -> database: "connect"
cli -> store: "fetch-rows!: SELECT DATABASE()"
cli -> pure.wordpress: "user-profile data"
cli -> pure.compiler: "compile-profile: preflight before connecting"
cli -> pure.transforms: "hmac-token: reject missing secret"
cli -> runner: "run!: fresh profile + secret + options"
runner -> pure.compiler: "compile-profile: validate direct callers too"
runner -> pure.transforms: "hmac-token: validate direct callers too"
runner -> store: "catalogue! / page! / validate-output! / apply-mutation!"
runner -> pure.engine: "normalize-row / transform-row"
runner -> database: "PDO beginTransaction / commit / rollBack"
store -> database: "schema reads; prepared SELECT / UPDATE"
runner -> cli: "counts only; never row values or SQL parameters"
```

`store.phel` is the V2 SQL boundary. The runner uses PDO directly only for
transaction ownership; the shared legacy config module creates the connection.
The compiler can describe broader profile kinds, but this executor accepts only
row and metadata sources. Schema audits and delete ownership in the compiler do
not imply those operations are implemented in the V2 runner.

## End-to-end call sequence

This sequence includes preflight, connection, compilation, schema checks,
exemptions, paged transformations, writes, verification, reporting and failures.
Conditional groups are alternatives, not actions all performed on one run.
Repeated pages/rules and the verification pass reuse the same functions.

**Illustrative input:** select only `users/names`, prefix `site_`, page size 250,
keep login `local-admin`, and apply to database `wordpress_clone`. Assume two
users: ID 12 has display name `Alice`; ID 99 has login `local-admin` and display
name `Admin`. The sequence therefore produces one update and one exempt finding.
Preview uses the same input without `--apply` and performs no updates.

Payloads use Phel notation and omit unrelated keys with `...`. All names are
invented. Raw values in the diagram illustrate **internal-only** row/value/mutation
objects, not logging or CLI output. `secret` denotes a separately supplied
`PII_REDACTION_SECRET`, never an actual value. SQL marked `...` is abbreviated,
not executable SQL.

```d2
shape: sequence_diagram

caller: "Caller / entry point"
cli: "users_cli"
compiler: "compiler / profile"
config: "db (config)"
runner: "runner"
store: "store"
engine: "engine"
values: "transforms"
pdo: "PDO / clone DB"

preflight: "1. Validate intent before connecting" {
  caller -> cli: "users-entry/run → cli/run → run-command(ctx)"
  cli -> cli: "options-from(ctx) → {:prefix \"site_\" :apply true :confirm-db \"wordpress_clone\"\n:rules [:users/names] :keep-users [\"local-admin\"] :page-size 250 ...}"
  cli -> cli: "secret-from-env() → secret"
  cli -> values: "hmac-token(secret, :preflight, \"preflight\", 1)"
  values -> cli: "Non-empty secret validated; discard token"
  cli -> compiler: "compile-profile(wordpress/user-profile, options)"
  compiler -> compiler: "profile/assert-valid(input); validate-rule! for every rule"
  compiler -> compiler: "validate-selectors!(all rules, options)"
  compiler -> compiler: "profile/enabled-rules(input, options); subtract category/table exclusions"
  compiler -> compiler: "assert-single-owner(selected rules) → target-claims / overlap?"
  compiler -> cli: "{:name :wordpress-users :rules [{:id :users/names ...}]}\nPreflight result discarded; no database I/O yet"
}

connection: "2. Open and confirm the actual target" {
  cli -> cli: "open-target!(config path)"
  cli -> config: "parse-wp-config(path) → literal DB config"
  cli -> config: "connect(config)"
  config -> pdo: "new PDO(...); configure exceptions and connection"
  config -> cli: "pdo"
  cli -> store: "fetch-rows!(pdo, \"SELECT DATABASE()\", [])"
  store -> pdo: "prepare / execute / fetchAll"
  pdo -> store: "[[\"wordpress_clone\"]]"
  store -> cli: "Actual DB name; open-target! requires config name to match"
  cli -> cli: "confirm-target!(options, {:pdo pdo :name \"wordpress_clone\"})\nApply requires exact --confirm-db match"
}

prepare: "3. Runner independently validates and resolves schema" {
  cli -> runner: "run!(pdo, wordpress/user-profile, secret, options)"
  runner -> values: "hmac-token(secret, :preflight, \"preflight\", 1)"
  runner -> pdo: "inTransaction() must be false"
  runner -> compiler: "compile-profile(input, options) again for direct-call safety"
  compiler -> runner: "Compiled selected rules"
  runner -> store: "catalogue!(pdo, compiled, \"site_\")"
  store -> store: "table-schema!(pdo, \"site_users\") → mysql-schema! / sqlite-schema!"
  store -> pdo: "fetch-rows!: table engine, columns, primary key"
  pdo -> store: "{:table \"site_users\" :engine \"InnoDB\" :pk [:ID]\n:columns {:ID {:type :integer ...} :display_name {:type :text :max-length 250 ...} ...}} (normalized)"
  store -> store: "validate-schema(rule, schema): PK, required types, no generated sources"
  store -> runner: "[{... :table \"site_users\" :schema {...}}]"
  runner -> store: "Apply only: assert-transactional!(resolved rules)"
  runner -> pdo: "beginTransaction() — preview also starts a transaction"
}

exemptions: "4. Resolve all keep-logins before writing" {
  runner -> runner: "resolve-exemptions!(pdo, prefix, options)"
  runner -> store: "table-schema! / validate-schema for ID + user_login"
  runner -> store: "page!(pdo, exemptions-rule, cursor, 250), until empty"
  store -> pdo: "Keyset SELECT ID, user_login FROM site_users ..."
  pdo -> store: "Example match: {:ID 99 :user_login \"local-admin\"}"
  store -> runner: "Pages of login rows; case-insensitive matching in runner"
  runner -> runner: "effective options: {... :keep-entities #{[:user \"99\"]}}\nUnknown requested login throws; empty requests skip this scan"
}

processing: "5. For each selected rule, for each keyset page and row" {
  runner -> runner: "process-rule!(pdo, users/names rule, secret, effective, apply?)"
  runner -> store: "page!(pdo, rule, nil, 250)"
  store -> store: "read-columns(rule) → [:ID :display_name]"
  store -> pdo: "fetch-rows!: SELECT ID, display_name FROM site_users ORDER BY ID LIMIT 250"
  pdo -> store: "[[12 \"Alice\"] [99 \"Admin\"]]"
  store -> runner: "[{:ID 12 :display_name \"Alice\"} {:ID 99 :display_name \"Admin\"}]"
  runner -> engine: "normalize-row(rule, \"site_users\", first row)"
  engine -> runner: "{:locator {:table \"site_users\" :pk {:ID 12}}\n:entity [:user \"12\"] :values {:ID 12 :display_name \"Alice\"}}"
  runner -> engine: "transform-row(secret, rule, row, effective)"
  engine -> engine: "Check :keep-entities; field-specs(rule, values)\n→ {:display_name {:kind :name :strategy [:constant \"Anonymous\"]}}"
  engine -> values: "redact(secret, :name, [:constant \"Anonymous\"], \"Alice\", {})"
  values -> values: "canonicalize / valid-value? / redacted-value? / replacement"
  values -> engine: "{:status :changed :kind :name :before \"Alice\" :after \"Anonymous\"}"
  engine -> engine: "changed?(result); collect changed fields; strip values from findings"
  engine -> runner: "{:mutations [{:rule :users/names :locator {:table \"site_users\" :pk {:ID 12}}\n:expected {:ID 12 :display_name \"Alice\"} :set {:display_name \"Anonymous\"}}]\n:findings [{:rule :users/names :field :display_name :kind :name :status :changed}]}"
  runner -> store: "validate-output!(rule, mutation): Anonymous fits VARCHAR(250)"

  write: "Apply only, for each mutation (preview skips this entire group)" {
    runner -> store: "apply-mutation!(pdo, mutation)"
    store -> pdo: "inTransaction() must be true"
    store -> store: "mutation-query(driver, mutation) → {:sql \"UPDATE ...\" :params [...]}\nWHERE guards primary key AND all expected values; MySQL uses binary comparison"
    store -> pdo: "prepare(sql) / execute(params) / rowCount()"
    pdo -> store: "1 affected row required; otherwise throw"
    store -> runner: "1"
  }

  runner -> runner: "add-findings({}, findings) → {:changed 1}; accumulate mutation/affected counts"
  runner -> engine: "normalize-row / transform-row for ID 99 (same rule)"
  engine -> runner: "{:mutations [] :findings [{:rule :users/names :status :exempt}]}\nNo value transform or write for a kept entity"
  runner -> runner: "add-findings({:changed 1}, exempt findings) → {:changed 1 :exempt 1}"
  runner -> store: "page!(pdo, rule, 99, 250): cursor is last PK, never OFFSET"
  store -> pdo: "SELECT ... WHERE ID > ? ORDER BY ID LIMIT 250; params [99]"
  pdo -> store: "[]"
  store -> runner: "[] ends this rule; process-rule! returns counts only"
}

apply_finish: "6a. Apply: re-read and verify before commit" {
  runner -> runner: "process-rule!(pdo, each rule, secret, effective, false)\nRepeat page! → normalize-row → transform-row → validate-output!; never write"
  runner -> store: "page!: read current values inside the SAME transaction"
  store -> pdo: "SELECT ... → display_name is now Anonymous"
  store -> runner: "Current keyword-keyed rows"
  runner -> engine: "normalize-row / transform-row on current rows"
  engine -> values: "redact(secret, :name, [:constant \"Anonymous\"], \"Anonymous\", {})"
  values -> engine: "{:status :unchanged :reason :same-value ...}"
  engine -> runner: "No mutations; kept ID 99 still :exempt"
  runner -> runner: "Require original mutations = affected AND verification mutations = 0 for every rule"
  runner -> pdo: "commit()"
  runner -> cli: "{:mode :apply :profile :wordpress-users :mutations 1 :affected 1 :verified true\n:rules [{:rule :users/names :mutations 1 :affected 1 :findings {:changed 1 :exempt 1}}]}"
}

preview_finish: "6b. Alternative: preview, no writes or verification pass" {
  runner -> pdo: "rollBack() — close the read-only planning transaction"
  runner -> cli: "{:mode :plan :profile :wordpress-users :mutations 1 :affected 0 :verified false\n:rules [{:rule :users/names :mutations 1 :affected 0 :findings {:changed 1 :exempt 1}}]}"
}

success: "7. Successful output (either mode)" {
  cli -> cli: "render-report(report, json?) → count-only JSON/text"
  cli -> caller: "cli/writeln(ctx, output); return 0 → entry exits 0"
}

failure: "Alternative failure path, not after a successful commit" {
  runner -> pdo: "On an error inside transaction: rollBack() if still active"
  runner -> cli: "Rethrow; no success report"
  cli -> caller: "Catch Throwable, including preflight/connection failures\nWrite fixed failure-message (or JSON error); return/exit 1\nNever expose PDO details, row values, secret or verbose trace"
}
```

### How the other rules use the same flow

- **Metadata:** `page!` adds `meta_key IN (...)` for the rule's exact cases.
  `normalize-row` uses `{:pk {:umeta_id 7}}` and `:entity [:user "12"]` from
  `user_id`. `field-specs` dispatches by `meta_key`; for example `jabber` maps
  `meta_value` to `{:kind :text :strategy :clear}`. The mutation's `:expected`
  includes `umeta_id`, `user_id`, `meta_key` and `meta_value`, guarding against a
  changed key or entity link as well as a changed value. The same kept-user IDs
  exempt linked usermeta rows.
- **Token strategies:** `redact` calls `replacement` → `token-replacement` →
  `hmac-token`. Email/URL tokens derive from canonical values. Login and nicename
  use `{:namespace :user-login :seed "12"}` to correlate the entity's outputs.
  Reserved token shapes are recognized on later runs.
- **Empty/already-redacted fields:** findings record skipped/unchanged results,
  but no mutation is generated. Invalid targeted values throw in the engine;
  they do not become a successful report claiming complete redaction.

### Boundaries and guarantees

- Only effective rules reach the schema catalogue and processing loop. Compilation
  validates the full profile and all selector values before narrowing scope;
  ownership conflicts are checked on the selected rules.
- Schema reads happen **before** `beginTransaction`; data reads, exemption
  resolution, transformations and verification happen **inside** it. Use an
  offline clone without concurrent writers or schema changes.
- Verification proves a second pass of the **selected rules** proposes no further
  mutations. It is not a residual-PII audit. Success reports retain first-pass
  findings, not verification findings.
- Raw values exist in database rows, transform results, mutations and bound SQL
  parameters only within processing. The runner returns counters. `mutations`
  counts row updates per rule, not distinct database rows; ordinary findings count
  fields, while `exempt` counts skipped rows per rule.
- MySQL SQL generation is implemented, but local integration coverage uses SQLite.
  Transaction guarantees do not cover external writers or trigger side effects on
  nontransactional tables. See `V2-USERS.md` for the full limitations.
