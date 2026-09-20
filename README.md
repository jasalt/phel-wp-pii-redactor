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

## Customizing

### Retain a field in the V2 profile

The V2 profile is plain data in `src/pii/redactor/wordpress.phel`. A field is
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
`composer test:all`, and preview the V2 command before applying it.

### Preserve specific users

For V2, pass the users' current `user_login` values to `--keep-users`:

```bash
php vendor/bin/phel run src/users.phel \
  --config /path/to/clone/wp-config.php --prefix wp_ \
  --keep-users local-admin,another-account --json
```

Matching is case-insensitive. Each matched user and that user's linked
`usermeta` rows are exempt from all selected V2 rules. An unknown login makes
the command fail closed. This exemption does not extend to comments or other
linked/plugin data outside the V2 profile. Add `--keep-users` unchanged to both
the preview and final `--apply --confirm-db ...` invocation.

The legacy `src/main.phel` command instead accepts
`--whitelist-users local-admin,another-account`. That option exempts the
per-user `wp_users` login/nicename/display-name/password rewrite; it is not a
blanket exemption for usermeta or other linked records.

## Experimental V2 users/usermeta slice

An opt-in exact-rule pipeline is available at `src/users.phel`. It adds centralized
scope/exemptions, keyed transformations, paged reads, guarded updates, and
transactional verification. **It does not sanitize a whole database.**

See [`V2-USERS.md`](V2-USERS.md) for usage, exact coverage, and limitations,
and [`ARCHITECTURE.md`](ARCHITECTURE.md) for inline D2 module and execution-flow
diagrams. MySQL integration remains unverified here; automated database tests use SQLite.
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
