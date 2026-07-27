# WordPress PII Redactor (Phel)

The executable `pii-redactor.php` is a small PHP bootstrap; the implementation
is written in [Phel](https://github.com/phel-lang/phel-lang/) under
`src/pii/redactor/`.

## Install and run

```bash
composer install

./pii-redactor.php --dry-run --verbose
./pii-redactor.php --summary
```

Phel 0.49 requires PHP 8.4. The bootstrap automatically re-executes itself with
`php8.4` when the system-default PHP is older.

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
- `main.phel` — discovery, CLI, and reporting pipeline.
- `entry.phel` — guarded executable entry point.

Updates are represented as data maps (`{:sql ... :params [...]}`) until the
final PDO boundary. Prepared statements are used for execution.

## Development

```bash
composer test:all   # lint + 78 assertions + DB-backed Python/Phel parity
composer build      # compile deployable PHP into ignored out/
```

For interactive development with
[brepl](https://github.com/licht1stein/brepl/):

```bash
php8.4 vendor/bin/phel nrepl --port=7888
brepl -p 7888 <<'EOF'
(require 'pii.redactor.core)
EOF
```
