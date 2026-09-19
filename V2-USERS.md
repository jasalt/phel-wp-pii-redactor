# Experimental V2: users and usermeta

**This command does not sanitize a whole WordPress database.** It is an opt-in
vertical slice of the architecture in `PLAN.md`. The default legacy command at
`src/main.phel` has not changed. Use an offline, disposable clone, with a backup.

## Run

Requirements: PHP 8.4+, Composer dependencies, and PDO MySQL for WordPress.
Supply a secret through the environment, never a command-line argument:

```bash
# Keep this same secret for related runs. Store it securely outside database dumps.
export PII_REDACTION_SECRET="$(php -r 'echo bin2hex(random_bytes(32));')"

# Preview only; no writes. Prefix is explicit, not read from wp-config.php.
php vendor/bin/phel run src/users.phel \
  --config /path/to/clone/wp-config.php --prefix wp_ --json

# Apply a fresh plan inside a transaction. Name must match SELECT DATABASE().
php vendor/bin/phel run src/users.phel \
  --config /path/to/clone/wp-config.php --prefix wp_ \
  --apply --confirm-db wordpress_clone

unset PII_REDACTION_SECRET
```

`--dry-run` explicitly requests the default preview; combining it with `--apply`
is an error. Missing secrets, unknown selectors, unknown keep-user requests, and
unsupported schema fail closed. Apply does not execute SQL saved by a preview.

The existing config reader accepts literal `DB_*` definitions. It does not execute
PHP expressions or resolve environment-based WordPress config. Its existing host
parser is not a general socket/IPv6 DSN parser. These limitations are unchanged.

## Exact coverage

| Rule | Category | Targets and behavior |
| --- | --- | --- |
| `users/identity` | `identity` | Email and HTTP(S) URL tokens; login and nicename share an entity-ID-based token. |
| `users/names` | `names` | Display name becomes `Anonymous`. |
| `users/credentials` | `credentials` | Password hash becomes `*`; activation/reset key is cleared. |
| `usermeta/names` | `names` | `first_name`, `last_name`, `nickname` become `Anonymous`. |
| `usermeta/profile` | `identity` | Clears `description`, `biography`, `description_en`, `aim`, `yim`, `jabber`; tokenizes `user_url`. |
| `usermeta/credentials` | `credentials` | Clears `session_tokens` and `_application_passwords` wholesale; does not edit serialized contents. |

Unlike the legacy planner, this profile has no automatic system-email exemption.
Non-empty malformed emails/URLs cause failure, not silent retention. Empty values
remain empty. Roles, capabilities, unrelated metadata, and user IDs are preserved.
Passwords and sessions are disabled by default; preserve a user explicitly if you
need an account for accessing the clone.

## Scope and exemptions

Selectors take comma-separated names, without leading colons. Include selectors
combine by intersection; exclusions then subtract from that selection. Empty
include lists mean all. A name that does not exist in the profile is an error.

```bash
# Add these to a preview or apply invocation:
--tables users,usermeta
--categories identity,names
--exclude-categories credentials
--rules users/identity,usermeta/profile
--exclude-rules usermeta/profile
--exclude-tables usermeta
--keep-users local-admin,another-account
--page-size 250
```

`--keep-users` resolves logins case-insensitively to user IDs before writing.
All selected fields on those users **and their linked usermeta** are preserved.
It does not preserve comments or other linked data: those are outside this slice.
Selections apply consistently to every rule, unlike the legacy `--table` flag.
For multisite, the shared user-table prefix must be supplied explicitly; automatic
network/site prefix resolution is not implemented.

## Architecture and guarantees

- `wordpress.phel`: exact, inspectable profile maps; no heuristic writes.
- `compiler.phel`: strategy validation, centralized scope, one mutation owner per
  field/key. Delete ownership is conservative; audits own no write targets.
- `engine.phel`: pure normalized row → mutations plus value-free findings.
- `store.phel`: schema catalogue, keyset readers, SQL generation and execution.
- `runner.phel`: bounded-page processing, entity exclusions, transaction ownership,
  affected-count checks and a second read/transform pass before commit.
- `users_cli.phel`: explicit intent and database confirmation; text/JSON counts only.

Targets require a single integer primary key, expected columns, supported text
field types, no generated source columns, and sufficient output capacity. Apply
requires InnoDB (or SQLite for tests). Database-enforced uniqueness violations and
write errors roll back the transaction. No foreign-key checks are disabled.
The slice does not add uniqueness constraints or prove collision freedom for
columns without an enforced unique index.

Each update has primary-key and exact old-value guards, including the metadata key
and entity reference. MySQL text guards use binary comparison to avoid collation
ambiguities. Verification requires zero further mutations for the selected rules.
This is **rule idempotence verification**, not an independent residual-PII audit.

Only counters leave the runner. `mutations` counts row updates per rule, not unique
rows across the whole profile; `affected` counts actual updates. Findings count
field results, except `exempt`, which counts skipped rows per rule. Preview has
`affected=0` and `verified=false`. No raw before/after values, usernames, secrets,
or SQL parameters appear in normal reports. Database exceptions are suppressed
at the CLI boundary, including in verbose mode; failure exits with status 1.

## Limitations and validation

- No comments, posts, order metadata/HPOS, WPML, Stream, arbitrary plugin keys,
  heuristic auditing, or general structured-value codecs yet.
- Use an offline clone with no concurrent writers or schema changes. Old-value
  guards are not a complete online synchronization protocol. Triggers with side
  effects on other/nontransactional tables are outside the rollback guarantee.
- A single transaction can be large even though application memory is paged.
- HMAC tokens are pseudonyms, not a proof of irreversible anonymization. Protect
  the secret. Existing values matching the transform's reserved output format are
  treated as already redacted.
- MySQL catalogue/guard SQL is implemented but **not live-tested in this
  environment**, which has PDO SQLite but no PDO MySQL driver. Do not treat the
  SQLite results as deployment certification. Test against a disposable MySQL
  clone before use. The legacy CLI remains the default pending broader coverage.

```bash
composer test:all
# Equivalent with the chosen PHP executable:
php vendor/bin/phel lint src tests
php vendor/bin/phel test
```

Integration tests use fresh in-memory SQLite fixtures. They cover preview safety,
custom prefixes, scoped exclusions, credential cleanup, output capacity, guarded
writes, late failures and rollback, failed post-apply verification, repeat-run
idempotence, and safe CLI reports/errors. Tests never connect to a live WordPress
installation.
