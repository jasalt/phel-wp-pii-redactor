# PII Redactor Plan

## Current state

The current command is the users/usermeta redactor entered through
`src/users.phel`. It is not a whole-database sanitizer: comments, posts,
WooCommerce, WPML, Stream, arbitrary plugin data, heuristic auditing, and
structured-value codecs are not yet covered.

The implemented command includes plain-data profile compilation, exact rule dispatch,
keyed idempotent transforms, prefix-aware catalogue/read support, paged reads,
old-value-guarded updates, linked user exemptions, transaction ownership,
post-apply idempotence verification, and a count-only CLI. The latest
customization work deliberately leaves `user_nicename` out of the
`users/identity` rule: a field is retained by omitting it from the profile; there
is no field-level `:keep` selector.

The current tree has 293 passing automated tests under `composer test:all` and
clean lint. The latest profile customization retains `user_nicename`; its
identity and paged-count assertions were updated to cover that behavior. Tests
use isolated SQLite fixtures. This environment has PDO SQLite but no PDO MySQL
driver, so MySQL catalogue and guard SQL are implemented but have not been
live-tested. Run the command only against an offline disposable MySQL clone after
validating it there.

## Goals

- Redact WordPress data completely enough for database clones and exports.
- Make repeated runs idempotent.
- Keep transformations deterministic within and, when desired, across runs.
- Make policy scope, exclusions, and optional plugin support explicit.
- Plan and report without exposing raw PII by default.
- Apply mutations atomically when storage engines support transactions.
- Keep the code easy to load, inspect, redefine, and exercise from a Phel REPL.

## Design constraints

1. **Plain data and functions first.** Profiles are ordinary Phel maps and
   vectors. Constructors or macros are introduced only when they remove proven
   repetition without hiding the resulting data.
2. **Small public pure functions.** Value transformation and profile compilation
   must be usable without PDO, CLI contexts, or global state.
3. **No arbitrary SQL DSL.** Generalize stable operations—reading rows,
   transforming fields, dispatching metadata keys, deleting disposable rows,
   and auditing schema matches—not SQL itself.
4. **No order-dependent replacement registry.** Keyed deterministic transforms
   provide consistency without a separate scan pass.
5. **One target owner.** Profile compilation rejects overlapping mutation rules
   instead of relying on policy order or deferred-column exceptions.
6. **Exact rules mutate; heuristics audit.** Column-name discovery is report-only
   unless a reviewed profile explicitly opts into mutation.
7. **Backend-neutral mutations.** SQL is generated only at the PDO boundary.

## Current users/usermeta coverage

### Run it safely

Requirements are PHP 8.4+, Composer dependencies, and PDO MySQL for WordPress.
Supply a stable secret through the environment, not a command-line argument:

```bash
export PII_REDACTION_SECRET="$(php -r 'echo bin2hex(random_bytes(32));')"

# Preview is the default and does not write. The prefix is deliberately explicit.
php vendor/bin/phel run src/users.phel \
  --config /path/to/clone/wp-config.php --prefix wp_ --json

# Apply recomputes a fresh plan inside a transaction.
# --confirm-db must equal SELECT DATABASE().
php vendor/bin/phel run src/users.phel \
  --config /path/to/clone/wp-config.php --prefix wp_ \
  --apply --confirm-db wordpress_clone

unset PII_REDACTION_SECRET
```

`--dry-run` explicitly requests the default preview; it cannot be combined with
`--apply`. Missing secrets, unknown selectors, unknown kept users, and
unsupported schema fail closed. Apply never executes SQL saved by a preview.
The shared config reader accepts literal `DB_*` definitions only; it does not
evaluate PHP expressions or environment-based WordPress configuration. Its host
parser does not yet provide general socket/IPv6 DSN parsing.

### Exact profile coverage

| Rule | Category | Targets and behavior |
| --- | --- | --- |
| `users/identity` | `identity` | Tokenizes email, login, and HTTP(S) URL. Login tokens use the entity ID; `user_nicename` is retained. |
| `users/names` | `names` | Sets `display_name` to `Anonymous`. |
| `users/credentials` | `credentials` | Sets password hash to `*` and clears activation/reset key. |
| `usermeta/names` | `names` | Sets `first_name`, `last_name`, and `nickname` to `Anonymous`. |
| `usermeta/profile` | `identity` | Clears biography/description and messaging keys; tokenizes `user_url`. |
| `usermeta/credentials` | `credentials` | Clears `session_tokens` and `_application_passwords` wholesale, without editing serialized contents. |

There is no automatic system-email exemption. Empty values remain empty;
non-empty malformed targeted emails or URLs stop the run instead of being
silently retained. Roles, capabilities, unrelated metadata, IDs, and
`user_nicename` are preserved. Credentials are disabled unless the account is
explicitly kept.

### Scope, exemptions, and guarantees

Selectors are comma-separated names without leading colons. Include selectors
intersect; exclusions subtract; an empty include list means all. Every supplied
name must exist in the profile.

```text
--tables users,usermeta
--categories identity,names
--exclude-categories credentials
--rules users/identity,usermeta/profile
--exclude-rules usermeta/profile
--exclude-tables usermeta
--keep-users local-admin,another-account
--page-size 250
```

`--keep-users` resolves current `user_login` values case-insensitively before
writing. It preserves every selected field on the matched users and their linked
usermeta, but does not extend to comments or plugin data. For multisite,
supply the intended shared user-table prefix; network/site prefix discovery is
not implemented.

The runner reports only counts: no raw before/after values, usernames, secrets,
SQL parameters, or database exception details are emitted by normal text or JSON
reports. `mutations` counts row updates per rule; `affected` counts executed
updates; findings count field results except `exempt`, which counts skipped rows
per rule. Preview reports `affected=0` and `verified=false`.

Each update is guarded by the primary key and the exact old value; metadata
updates also guard its key and entity reference. MySQL text guards use binary
comparison. Apply requires InnoDB (SQLite is accepted for tests), keeps
foreign-key checks enabled, verifies affected counts, then re-reads inside the
same transaction and requires zero further selected-rule mutations before
commit. This proves rule idempotence, not an independent residual-PII audit.

Use an offline clone with no concurrent writers or schema changes. A transaction
can still be large despite paged application, and triggers affecting other or
nontransactional tables are outside its rollback guarantee. HMAC tokens are
pseudonyms rather than proof of irreversible anonymization; protect the secret.
Values already matching a reserved output format are treated as redacted.

### Delivered implementation and validation

- [x] **M0 — safety/foundation:** planning is the default; writes require
      `--apply`; preview parameters are hidden; Stream uses transactional
      `DELETE`; WPML caches are deleted safely; pure keyed idempotent transforms
      and a documented nREPL workflow exist; Python parity is no longer required.
- [x] **M1 — profiles/compiler:** minimal plain-map schema, path-oriented
      diagnostics, selector resolution, overlap detection, and REPL examples.
- [x] **M2 — catalogue/readers:** prefix-aware SQLite/MySQL
      catalogue support, required-column/type/output-capacity checks, keyset
      readers, optional/schema failure handling, and identifier safety tests.
- [x] **M3 — mutation engine:** normalized row-to-mutation and
      value-free findings, linked keep-user exemptions, guarded prepared updates,
      transactional execution, affected-count checks, rollback tests, and
      post-apply verification.
- [x] **M4 — CLI/reporting:** uniform selectors, safe text/JSON
      reports, explicit apply/database confirmation, environment secret, and
      separate planned versus affected counts.

The automated progression for the completed work was: 140 baseline tests; 152
after compiler work; 184 after exact profile/engine work; 204 after catalogue and
reader work; 246 after transactional execution; and 283 after the CLI, including
an isolated clean-export check. Coverage includes preview safety, custom prefixes,
scoped exclusions, credential cleanup, capacity and schema rejection, guarded
writes, late failures/rollback, failed verification, repeat-run idempotence, and
safe CLI errors. It does not certify a live MySQL deployment.

## Remaining work

### M1 follow-up — expand reviewed profile data

- [ ] Define the remaining initial core WordPress profile and exact metadata-key
      maps beyond the delivered users/usermeta rules.
- [ ] Establish explicit public-content semantics rather than inferring comments
      from known users.

### M2 follow-up — catalogue and readers

- [ ] Parse or override `$table_prefix`; support ports, sockets, and IPv6 hosts.
- [ ] Complete logical-to-physical table catalogue support for multisite and
      optional plugin tables.
- [ ] Add readers for comments, posts, delete targets, and reviewed structured
      values/codecs.

### M3 follow-up — mutation engine

- [ ] Add entity-wide keep rules across users, usermeta, comments, and future
      linked data.
- [ ] Support transactional deletes for reviewed disposable caches/logs.
- [ ] Validate generated-value uniqueness and all remaining output shapes.
- [ ] Refuse atomic mode whenever any touched table is nontransactional.

### M4 follow-up — coverage and reports

- [ ] Add comments with explicit public-content policy; keep posts report-only by
      default and require an explicit draft/private-content policy.
- [ ] Add exact WooCommerce billing/shipping metadata and separate HPOS module.
- [ ] Add WXR import-slug handling with opaque-placeholder fallback.
- [ ] Add WPML translator-cache and Stream audit deletion to the profile.
- [ ] Add report-only heuristic auditing and explicit structured-value codecs;
      never blindly replace text inside PHP serialization.

### M5 — validation and cutover

- [ ] Apply twice and require a zero-mutation second plan for every profile.
- [ ] Prove rollback with failure injection for all touched transactional tables.
- [ ] Test disposable MySQL clones, custom prefixes, multisite, missing plugins,
      non-InnoDB tables, and independent dump scans.
- [ ] Prove normal reports never reveal raw PII and exact metadata fixtures retain
      no configured PII after apply.
- [ ] Expand the entry point only after broader coverage and deployment
      validation.

## Acceptance criteria

The redactor is ready for broader production use only when all profile rules are
inspectable plain data; required use cases are represented without
policy-order dependencies; a second application is a no-op; absent optional
plugins are non-fatal; planning cannot write or reveal raw values by default;
transaction failure leaves touched transactional tables unchanged; configured
metadata fixtures contain no residual PII after apply; an independent dump scan
has been run against representative data; and ordinary control flow remains
understandable through direct REPL calls without macro expansion or a framework
lifecycle.
