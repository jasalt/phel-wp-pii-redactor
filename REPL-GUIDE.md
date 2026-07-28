# REPL Development Guide

This project is developed in small pieces against a live Phel nREPL. Profile
maps and transformation functions are intentionally independent from PDO and the
CLI so they can be evaluated without a WordPress database.

Use synthetic values only. REPL history and terminal scrollback are not safe
places for production PII or redaction secrets.

## Start the server

Run the server from the project root so project source paths and relative
`load-file` paths resolve correctly:

```bash
php8.4 vendor/bin/phel nrepl --port=7888
```

In another terminal, verify the connection:

```bash
brepl -p 7888 <<'EOF'
(println :nrepl-ready)
EOF
```

Expected result:

```text
:nrepl-ready
nil
```

The trailing `nil` is the result of `println` and is normal.

## Load project namespaces

On a fresh server, require namespaces normally:

```bash
brepl -p 7888 <<'EOF'
(require 'pii.redactor.transforms)
(require 'pii.redactor.profile)
EOF
```

During development, re-evaluate an edited namespace without restarting the
server:

```bash
brepl -p 7888 <<'EOF'
(load-file "src/pii/redactor/transforms.phel")
(load-file "src/pii/redactor/profile.phel")
EOF
```

This workflow has been validated with the current Phel nREPL. `load-file` also
handles a namespace created after the server started, when the initial
`require` cannot yet find it. Load dependencies first, then dependants.

Keep each submitted expression balanced and complete. A here-document is the
least error-prone way to send multiline forms through `brepl`.

## Explore transformations

The public value API is `pii.redactor.transforms/redact`:

```bash
brepl -p 7888 <<'EOF'
(let [result
      (pii.redactor.transforms/redact
       "development-only-secret"
       :email
       :token
       "Person@Example.org")]
  (println result)
  (println
   (pii.redactor.transforms/redact
    "development-only-secret"
    :email
    :token
    (:after result))))
EOF
```

The first call returns inspectable data similar to:

```phel
{:status :changed
 :kind :email
 :before "Person@Example.org"
 :after "anon-...@redacted.example.invalid"}
```

The second call must return `:status :unchanged` with
`:reason :already-redacted`. This is the quickest interactive idempotence check.

Useful focused calls:

```phel
(pii.redactor.transforms/canonicalize :email " Person@Example.ORG ")
(pii.redactor.transforms/valid-value? :ip "2001:db8::1")
(pii.redactor.transforms/hmac-token
 "development-only-secret" :email "person@example.org" 12)
(pii.redactor.transforms/redact
 "development-only-secret" :name [:constant "Anonymous"] "Person")
```

To correlate a token with an entity rather than the original value, pass a
context map:

```phel
(pii.redactor.transforms/redact
 "development-only-secret"
 :login
 :token
 "person"
 {:namespace :wordpress-user :seed 42})
```

Do not put a real secret in source, shell history, tests, or REPL history.

## Develop a profile as plain data

Profiles do not need a macro or constructor. Define a small map and inspect it:

```bash
brepl -p 7888 <<'EOF'
(def scratch-profile
  {:name :wordpress
   :rules
   [{:id :users/profile
     :category :identity
     :source {:kind :rows :table :users :pk [:ID]}
     :fields
     {:user_email {:kind :email :strategy :token}
      :display_name {:kind :name
                     :strategy [:constant "Anonymous"]}}}

    {:id :stream/logs
     :category :logs
     :source {:kind :delete :table :stream}
     :where :all}]})

(println (pii.redactor.profile/diagnostics scratch-profile))
(println (pii.redactor.profile/summary scratch-profile))
EOF
```

A valid profile returns `[]` diagnostics. `summary` provides a compact view that
is easier to scan than generated SQL or callback closures.

Introduce a mistake and inspect its exact path:

```bash
brepl -p 7888 <<'EOF'
(println
 (pii.redactor.profile/diagnostics
  (assoc-in
   scratch-profile
   [:rules 0 :fields :user_email :kind]
   :unknown)))
EOF
```

Expected diagnostic shape:

```phel
[{:path [:rules 0 :fields :user_email :kind]
  :message "Field must declare a supported :kind"}]
```

Select an effective rule subset without involving CLI state:

```phel
(pii.redactor.profile/enabled-rules
 scratch-profile
 {:categories [:logs]})

(pii.redactor.profile/enabled-rules
 scratch-profile
 {:exclude-rules [:stream/logs]})

(pii.redactor.profile/rule-by-id scratch-profile :users/profile)
```

Use `diagnostics` while editing because it accumulates errors and does not throw.
Use `assert-valid` only at an application boundary where malformed configuration
must stop execution.

## Recommended edit/evaluate loop

1. Add or change one pure function or one profile rule.
2. Save the file.
3. Reload only that namespace with `load-file`.
4. Evaluate a normal case, an invalid case, and an idempotence/no-op case.
5. Move the accepted examples into `phel.test` tests.
6. Run formatting, lint, and tests before committing:

```bash
composer format
composer lint
composer test
```

The REPL shortens feedback time; it does not replace repeatable tests.

## REPL-friendly code rules

- Namespace loading must not connect to a database or execute a plan.
- Keep transformation/profile functions public when they are useful exploration
  points; hide only implementation details with `defn-`.
- Accept and return Phel values rather than PHP arrays or service objects.
- Keep functions deterministic unless their name clearly marks I/O with `!`.
- Prefer a short named function over an anonymous callback embedded in profile
  data.
- Keep profile rules inspectable after evaluation.
- Avoid macros until ordinary data has demonstrated repetitive syntax. Any
  future profile macro must expand to the same plain map shape documented here.
- Reload dependencies before dependants after changing namespace-level vars or
  function signatures.

## Database adapter development

Pure profile work should not require a database. When catalogue/read/apply
functions are added, keep the boundary narrow:

1. Capture a small synthetic row from a fixture, not production.
2. Exercise the pure row transformation at the REPL.
3. Exercise SQL compilation against the resulting mutation map.
4. Use an isolated disposable database for `!` functions.
5. Verify rollback and affected-row checks with automated integration tests.

Never run the active redactor against a live database merely to test a pure
profile change.
