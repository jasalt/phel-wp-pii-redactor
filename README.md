# WordPress PII Redactor

Scrubs personally identifiable information from WordPress database for development purposes.

Requires per project modifications to take into account data stored by plugins, but attempts to provide a simplified (WIP) API for facilitating that.

Written in [Phel](https://github.com/phel-lang/phel-lang/), a Clojure dialect.

## Features

- Safe-by-default preview; writes require `--apply`.
- Deterministic, idempotent HMAC tokens for identifiers and URLs.
- Paged reads, primary-key/old-value guarded updates, and transactional apply
  with post-apply verification.
- Exact profile rules, table/category/rule selectors, and linked user/usermeta
  exemptions through `--keep-users`.
- Count-only text or JSON reports that do not expose source values, tokens,
  secrets, SQL parameters, or database exception details.

### Information redacted

Rules are currently hard-coded while designed to be customizable.

| Location | Information |
| --- | --- |
| `wp_users` | Email, login, and HTTP(S) URL are tokenized; display name becomes `Anonymous`; password hash is replaced and activation/reset key is cleared. |
| `wp_usermeta` | First name, last name, and nickname become `Anonymous`; biography, description, and messaging identifiers are cleared; profile URL is tokenized. |
| `wp_usermeta` credentials | Session tokens and application passwords are cleared as whole values, without editing serialized data. |

`user_nicename`, roles, capabilities, user IDs, and metadata not named by an
exact profile rule are retained. Comments, posts, WooCommerce, plugins, and
other database tables are not yet redacted.

## Install and run
Phel requires PHP 8.5 and Composer. The command-line entry point is `src/main.phel`.

Running in local WordPress dev environment public html root directory:

```bash
git clone <repo url>
cd phel-wp-pii-redactor
composer install

# Planning is the default; this does not write to the database.
vendor/bin/phel run src/main.phel --config ../wp-config.php

# Apply only after reviewing the plan; preserve the admin account.
vendor/bin/phel run src/main.phel \
  --config ../wp-config.php --apply --whitelist-users admin
```

The command does not write unless `--apply` is present. It reports counts rather
than raw values and suppresses database exception details. Use only an offline
disposable database clone.


## Coverage and limitations

The command uses exact rules for users/usermeta, centralized scope and exemptions,
keyed transformations, paged reads, guarded updates, and transactional
verification. **It does not sanitize a whole database.**

See [`PLAN.md`](PLAN.md) for usage, exact coverage, limitations, delivered
work, and the remaining work; [`ARCHITECTURE.md`](ARCHITECTURE.md)
contains inline D2 module and execution-flow diagrams. MySQL integration remains
unverified here; automated database tests use SQLite.

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
preview and final `--apply` invocation.


## Design

The current architecture, delivered work, and remaining work are documented in
[`PLAN.md`](PLAN.md). [`REPL-GUIDE.md`](REPL-GUIDE.md) contains the validated
interactive workflow.

The implementation lives under `src/pii/redactor/`. Two side-effect-free, REPL-friendly namespaces provide the foundation:

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
