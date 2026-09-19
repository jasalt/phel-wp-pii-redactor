# Architecture implementation tasks

## Scope

Implement the first V2 vertical slice: WordPress users and their usermeta.
Keep the legacy CLI unchanged; expose V2 as an explicit, separately documented
command. Do not imply that this slice sanitizes an entire WordPress database.
Use plain Phel data/functions, exact mutation rules, and a narrow PDO boundary.

Each numbered task is a separate implementation commit; update this checklist
and run the relevant tests before committing. Preserve the pre-existing local
change in `src/pii/redactor/profile.phel`.

- [ ] 1. Add a pure compiler with centralized selectors, field/strategy validation,
  and overlapping-target rejection. Test row, metadata, and delete conflicts.
- [ ] 2. Define exact users/usermeta profiles and a pure row-to-mutation engine.
  Apply entity exclusions to both tables; use keyed tokens without registries;
  keep raw values out of findings. Test credentials, invalid values, and repeat runs.
- [ ] 3. Add a prefix-aware schema catalogue and paged PDO readers. Validate
  required columns, primary keys, output lengths, and transactional support;
  fail closed on unsupported schema. Test with isolated SQLite fixtures.
- [ ] 4. Add transactional execution of primary-key/old-value-guarded mutations.
  Verify affected counts and post-apply idempotence before commit. Test actual
  database exclusions, rollback, stale writes, and a zero-mutation second apply.
- [ ] 5. Expose the slice through an opt-in V2 command with safe count-only reports,
  explicit apply/database confirmation, environment-supplied secret, and uniform
  rule/category/table selectors. Document scope, usage, limitations, and verification.

## Verification

- Baseline: `php vendor/bin/phel test` — 140 passed; lint clean.
- This environment has PHP 8.5 and PDO SQLite, but no PDO MySQL driver or `php8.4`
  binary. Run checks with `php vendor/bin/phel`; SQLite integration tests cannot
  establish MySQL deployment compatibility. Record that limitation explicitly.

## Later milestones (not part of this slice)

Migrate comments, exact WooCommerce metadata/HPOS, WXR imports, WPML cache and
Stream deletion; add report-only heuristic auditing and explicit structured-value
codecs; test MySQL/custom multisite deployments and independent dump scans before
switching the default CLI. See `PLAN.md` for the full V2 roadmap.
