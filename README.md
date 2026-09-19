# WordPress PII Redactor (Phel)

The native executable entry point is `src/main.phel`. Run it through
[Phel](https://github.com/phel-lang/phel-lang/); no project PHP bootstrap is
needed. The implementation lives under `src/pii/redactor/`.

## Install and run

```bash
composer install

# Planning is the default; this does not write to the database.
vendor/bin/phel run src/main.phel --config /path/to/wp-config.php --verbose
vendor/bin/phel run src/main.phel --config /path/to/wp-config.php --summary

# Apply only after reviewing the plan.
vendor/bin/phel run src/main.phel --config /path/to/wp-config.php --apply
```

If `phel` is on your `PATH`, `phel run src/main.phel ...` is equivalent. Phel
0.49 requires PHP 8.4; use `php8.4 vendor/bin/phel` when the default `php` is
older.

The command does not write unless `--apply` is present. Plan parameters are
hidden because they can contain raw PII; `--show-values` is an explicit unsafe
diagnostic option.

## Experimental V2 users/usermeta slice

An opt-in exact-rule pipeline is available at `src/users.phel`. It adds centralized
scope/exemptions, keyed transformations, paged reads, guarded updates, and
transactional verification. **It does not sanitize a whole database.**

See [`V2-USERS.md`](V2-USERS.md) for usage, exact coverage, and limitations.
MySQL integration remains unverified here; automated database tests use SQLite.
The legacy `src/main.phel` command remains unchanged.

## Design

The replacement architecture and migration milestones are documented in
[`PLAN.md`](PLAN.md). [`REPL-GUIDE.md`](REPL-GUIDE.md) contains the validated
interactive workflow.

V2 foundations include two side-effect-free, REPL-friendly namespaces:

- `transforms.phel` — canonicalization and keyed, idempotent value strategies.
- `profile.phel` — validation and selection for profiles represented as plain
  maps and vectors.

The default CLI still uses the legacy `core.phel`, `db.phel`, and
`policies.phel` pipeline during migration. Its immediate write boundary has
been hardened: writes require `--apply`, WPML cache payloads are deleted rather
than rewritten, Stream cleanup uses transactional `DELETE`, foreign-key checks
remain enabled, and preview parameters are hidden.

Prepared statements are used for execution.

## Development

```bash
composer test:all   # lint + unit tests
composer build      # optional: compile the legacy entry point into ignored out/
```

Composer scripts use Composer's PHP executable (`@php`), rather than requiring a
binary specifically named `php8.4`.

For the complete interactive workflow, see [`REPL-GUIDE.md`](REPL-GUIDE.md).
A minimal [brepl](https://github.com/licht1stein/brepl/) session is:

```bash
php8.4 vendor/bin/phel nrepl --port=7888
brepl -p 7888 <<'EOF'
(require 'pii.redactor.transforms)
(require 'pii.redactor.profile)
EOF
```
