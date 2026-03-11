-- HF SQL Validation Template
-- Purpose: Validate database hotfix SQL safely in staging/production-like environments.
-- Default behavior is ROLLBACK (dry run). Switch to COMMIT only after review.
--
-- Dialect: PostgreSQL-oriented SQL.
-- For MySQL, adapt TEMP table syntax and EXPLAIN ANALYZE usage.

/* ============================================================================
   0) EDIT THESE PLACEHOLDERS
   ----------------------------------------------------------------------------
   - Replace <schema.table>, <pk_column>, and validation predicates.
   - Paste your hotfix SQL in section (2).
   ============================================================================ */

BEGIN;

-- Optional safety guard (PostgreSQL):
-- SET LOCAL statement_timeout = '5min';
-- SET LOCAL lock_timeout = '10s';

/* ============================================================================
   1) BASELINE SNAPSHOT (before hotfix)
   ============================================================================ */

-- Example baseline row count for impacted scope:
DROP TABLE IF EXISTS tmp_hf_baseline_counts;
CREATE TEMP TABLE tmp_hf_baseline_counts AS
SELECT
  COUNT(*)::bigint AS total_rows
FROM <schema.table>
WHERE <scope_predicate>;

-- Example baseline aggregate:
DROP TABLE IF EXISTS tmp_hf_baseline_agg;
CREATE TEMP TABLE tmp_hf_baseline_agg AS
SELECT
  COALESCE(SUM(<numeric_column>), 0)::numeric AS total_amount
FROM <schema.table>
WHERE <scope_predicate>;

/* ============================================================================
   2) APPLY HOTFIX SQL (paste your statements below)
   ============================================================================ */

-- Example:
-- UPDATE <schema.table>
--    SET <target_column> = <new_value>
--  WHERE <scope_predicate>
--    AND <fix_predicate>;

-- Optionally capture changed PKs to validate exact impact:
-- DROP TABLE IF EXISTS tmp_hf_changed_ids;
-- CREATE TEMP TABLE tmp_hf_changed_ids AS
-- SELECT <pk_column>
-- FROM <schema.table>
-- WHERE <scope_predicate> AND <expected_post_fix_predicate>;

/* ============================================================================
   3) VALIDATION CHECKS
   ============================================================================ */

-- 3.1 Row count drift check (expected usually 0 for UPDATE-only fixes)
WITH after_counts AS (
  SELECT COUNT(*)::bigint AS total_rows_after
  FROM <schema.table>
  WHERE <scope_predicate>
)
SELECT
  b.total_rows          AS total_rows_before,
  a.total_rows_after    AS total_rows_after,
  (a.total_rows_after - b.total_rows) AS row_delta
FROM tmp_hf_baseline_counts b
CROSS JOIN after_counts a;

-- 3.2 Duplicate PK check (must return 0 rows)
SELECT <pk_column>, COUNT(*) AS dup_count
FROM <schema.table>
GROUP BY <pk_column>
HAVING COUNT(*) > 1;

-- 3.3 Null/invalid value check (adjust columns and constraints; should be 0)
SELECT COUNT(*) AS invalid_rows
FROM <schema.table>
WHERE <scope_predicate>
  AND (
    <required_column> IS NULL
    OR <numeric_column> < 0
  );

-- 3.4 Business reconciliation check (example total comparison)
WITH after_agg AS (
  SELECT COALESCE(SUM(<numeric_column>), 0)::numeric AS total_amount_after
  FROM <schema.table>
  WHERE <scope_predicate>
)
SELECT
  b.total_amount      AS total_amount_before,
  a.total_amount_after
FROM tmp_hf_baseline_agg b
CROSS JOIN after_agg a;

-- 3.5 Spot-check sampled records
SELECT *
FROM <schema.table>
WHERE <scope_predicate>
ORDER BY <pk_column>
LIMIT 50;

/* ============================================================================
   4) IDEMPOTENCY CHECK (run hotfix logic again; should affect 0 rows)
   ============================================================================ */

-- Re-run ONLY the hotfix predicate as a SELECT first:
SELECT COUNT(*) AS would_change_again
FROM <schema.table>
WHERE <scope_predicate>
  AND <fix_predicate_that_should_now_be_false>;

-- If would_change_again > 0, hotfix may not be idempotent.

/* ============================================================================
   5) PERFORMANCE CHECKS (staging preferred)
   ============================================================================ */

-- EXPLAIN <your critical SELECT>;
-- EXPLAIN ANALYZE <your critical SELECT>;  -- staging only

/* ============================================================================
   6) FINALIZE
   ============================================================================ */

-- Default safe path:
ROLLBACK;

-- When fully validated and approved, use:
-- COMMIT;
