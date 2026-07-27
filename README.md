# WordPress PII Redactor (Phel)

The native executable entry point is `src/main.phel`. Run it through
[Phel](https://github.com/phel-lang/phel-lang/); no project PHP bootstrap is
needed. The implementation lives under `src/pii/redactor/`.

## Install and run

```bash
composer install

# Use the path to the target WordPress installation's wp-config.php.
vendor/bin/phel run src/main.phel --config /path/to/wp-config.php --dry-run --verbose
vendor/bin/phel run src/main.phel --config /path/to/wp-config.php --summary
```

If `phel` is on your `PATH`, `phel run src/main.phel ...` is equivalent. Phel
0.49 requires PHP 8.4; use `php8.4 vendor/bin/phel` when the default `php` is
older.

Always inspect a dry run before running without `--dry-run`.

## Design

- `core.phel` — pure validation, deterministic replacement registries, and
  immutable query-plan transformations.
- `db.phel` — WordPress config parsing and the PDO interpreter for query plans.
- `policies.phel` — table-specific handling policies as data. Each descriptor
  declares an optional registry pre-pass (`:scan`), a read model (`:load`), a
  pure plan transformation (`:plan`), and report messages (`:report`); generic
  interpreters thread one immutable plan through the ordered vector. Adding a
  new table concern means appending one descriptor to `table-policies`.
- `src/pii/redactor/main.phel` — discovery, CLI, and reporting pipeline.
- `src/main.phel` — native Phel executable entry point.

Updates are represented as data maps (`{:sql ... :params [...]}`) until the
final PDO boundary. Prepared statements are used for execution.

## Development

```bash
composer test:all   # lint + 78 assertions + DB-backed Python/Phel parity
composer build      # optional: compile a deployable PHP artifact into ignored out/
```

For interactive development with
[brepl](https://github.com/licht1stein/brepl/):

```bash
php8.4 vendor/bin/phel nrepl --port=7888
brepl -p 7888 <<'EOF'
(require 'pii.redactor.core)
EOF
```
