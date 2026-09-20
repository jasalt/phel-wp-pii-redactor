# WordPress PII Redactor (Phel)

The command-line entry point is `src/users.phel`. Run it through
[Phel](https://github.com/phel-lang/phel-lang/); no project PHP bootstrap is
needed. The implementation lives under `src/pii/redactor/`.

## Install and run

```bash
composer install

# Supply a stable secret through the environment, never an argument.
export PII_REDACTION_SECRET="$(php -r 'echo bin2hex(random_bytes(32));')"

# Planning is the default; this does not write to the database.
php vendor/bin/phel run src/users.phel \
  --config /path/to/clone/wp-config.php --prefix wp_ --json

# Apply only after reviewing a preview. The confirmation must match SELECT DATABASE().
php vendor/bin/phel run src/users.phel \
  --config /path/to/clone/wp-config.php --prefix wp_ \
  --apply --confirm-db wordpress_clone

unset PII_REDACTION_SECRET
```

If `phel` is on your `PATH`, `phel run src/users.phel ...` is equivalent. Phel
0.52 requires PHP 8.4; use `php8.4 vendor/bin/phel` when the default `php` is
older.

The command does not write unless `--apply` is present. It requires an explicit
prefix, reports counts rather than raw values, and suppresses database exception
details. Use only an offline disposable database clone.

## Customizing

### Retain a field in the profile

The profile is plain data in `src/pii/redactor/wordpress.phel`. A field is
redacted only when it is listed in a rule. For example, to retain the public
`wp_users.user_nicename` value, remove its entry from the `:users/identity`
rule:

```phel
{:id :users/identity :category :identity :source users-source
 :fields {:user_email {:kind :email :strategy :token}
          :user_login {:kind :login :strategy :token}
          :user_url {:kind :url :strategy :token}}}
```

There is no `:keep` strategy: omitting a field is what preserves it. Field-level
selection is not available as a command-line option; excluding the complete
`users/identity` rule would also preserve the email, login, and URL. Review
existing nicenames first because they can contain names or login identifiers.
After changing the profile, update any affected assertions, run
`composer test:all`, and preview the command before applying it.

### Preserve specific users

Pass the users' current `user_login` values to `--keep-users`:

```bash
php vendor/bin/phel run src/users.phel \
  --config /path/to/clone/wp-config.php --prefix wp_ \
  --keep-users local-admin,another-account --json
```

Matching is case-insensitive. Each matched user and that user's linked
`usermeta` rows are exempt from all selected rules. An unknown login makes the
command fail closed. This exemption does not extend to comments or other
linked/plugin data outside the profile. Add `--keep-users` unchanged to both the
preview and final `--apply --confirm-db ...` invocation.

## Coverage and limitations

The command uses exact rules for users/usermeta, centralized scope and exemptions,
keyed transformations, paged reads, guarded updates, and transactional
verification. **It does not sanitize a whole database.**

See [`PLAN.md`](PLAN.md) for usage, exact coverage, limitations, delivered
work, and the remaining work; [`ARCHITECTURE.md`](ARCHITECTURE.md)
contains inline D2 module and execution-flow diagrams. MySQL integration remains
unverified here; automated database tests use SQLite.

## Design

The current architecture, delivered work, and remaining work are documented in
[`PLAN.md`](PLAN.md). [`REPL-GUIDE.md`](REPL-GUIDE.md) contains the validated
interactive workflow.

Two side-effect-free, REPL-friendly namespaces provide the foundation:

- `transforms.phel` — canonicalization and keyed, idempotent value strategies.
- `profile.phel` — validation and selection for profiles represented as plain
  maps and vectors.

The command uses prepared statements for execution. Its write boundary requires
`--apply`, keeps foreign-key checks enabled, and hides preview parameters.

## Development

```bash
composer test:all   # lint + unit tests
composer build      # optional: compile into ignored out/
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
