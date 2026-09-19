# Architecture implementation tasks

## Scope

Implement the first V2 vertical slice: WordPress users and their usermeta.
Keep the legacy CLI unchanged; expose V2 as an explicit, separately documented
command. Do not imply that this slice sanitizes an entire WordPress database.
Use plain Phel data/functions, exact mutation rules, and a narrow PDO boundary.

Each numbered task is a separate implementation commit; update this checklist
and run the relevant tests before committing. Preserve the pre-existing local
change in `src/pii/redactor/profile.phel`.

- [x] 1. Add a pure compiler with centralized selectors, field/strategy validation,
  and overlapping-target rejection. Test row, metadata, and delete conflicts.
- [x] 2. Define exact users/usermeta profiles and a pure row-to-mutation engine.
  Apply entity exclusions to both tables; use keyed tokens without registries;
  keep raw values out of findings. Test credentials, invalid values, and repeat runs.
- [x] 3. Add a prefix-aware schema catalogue and paged PDO readers. Validate
  required columns, primary keys, output lengths, and transactional support;
  fail closed on unsupported schema. Test with isolated SQLite fixtures.
- [x] 4. Add transactional execution of primary-key/old-value-guarded mutations.
  Verify affected counts and post-apply idempotence before commit. Test actual
  database exclusions, rollback, stale writes, and a zero-mutation second apply.
- [ ] 5. Expose the slice through an opt-in V2 command with safe count-only reports,
  explicit apply/database confirmation, environment-supplied secret, and uniform
  rule/category/table selectors. Document scope, usage, limitations, and verification.

- [x] Prerequisite discovered during clean-checkout verification: fix the existing
  invalid exception constructor in committed `profile.phel`. Commit the equivalent
  `(new InvalidArgumentException ...)` form while preserving the user's working-tree
  shorthand `(InvalidArgumentException. ...)` byte-for-byte and uncommitted.

## Verification

- Baseline: `php vendor/bin/phel test` — 140 passed; lint clean.
- Task 1: 152 tests passed; lint clean. Compiler rejects duplicate row/metadata
  targets, conservative delete overlaps, unknown selectors, and invalid strategies.
- Task 2: 184 tests passed; lint clean. Tests exercise all six rules, linked
  exclusions, exact metadata transformations, credential clearing, and idempotence.
- Task 3: 204 tests passed; lint clean. SQLite integration covers prefix resolution,
  primary-key pagination, exact metadata reads, missing tables, output capacity,
  schema rejection, and identifier safety. MySQL catalogue queries are not live-tested.
- Task 4: 246 tests passed; lint clean. Real SQLite updates prove linked exclusions,
  no-write preview, rollback after late write/capacity failures, rollback on failed
  verification, null/case-sensitive CAS guards, and a zero-change second apply.
- Clean committed-tree verification initially exposed the pre-existing profile
  compile error hidden by the local edit. With the independent prerequisite fix,
  an isolated export passes all 246 tests for tasks 1–4 and lint.
- This environment has PHP 8.5 and PDO SQLite, but no PDO MySQL driver or `php8.4`
  binary. Run checks with `php vendor/bin/phel`; SQLite integration tests cannot
  establish MySQL deployment compatibility. Record that limitation explicitly.

## Later milestones (not part of this slice)

Migrate comments, exact WooCommerce metadata/HPOS, WXR imports, WPML cache and
Stream deletion; add report-only heuristic auditing and explicit structured-value
codecs; test MySQL/custom multisite deployments and independent dump scans before
switching the default CLI. See `PLAN.md` for the full V2 roadmap.
