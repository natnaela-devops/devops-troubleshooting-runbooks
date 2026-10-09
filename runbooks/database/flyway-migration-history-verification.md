# Verify Flyway Migration History Before Debugging the Application

## Problem

An application starts with unexpected schema behavior, missing objects, or a migration-related failure. It is unclear which migrations actually executed in the target database.

## Inspect Flyway history

Connect to the target database and query the application's Flyway history table. The table name may be customized.

```sql
SELECT
    installed_rank,
    version,
    description,
    type,
    script,
    checksum,
    installed_by,
    installed_on,
    execution_time,
    success
FROM public.flyway_schema_history
ORDER BY installed_rank;
```

If the application uses a custom history table, query that table instead.

## What to check

- Are all expected versions present?
- Is `success` true for every installed migration?
- Is the version order correct?
- Did an unexpected user install the migration?
- Does the recorded script name match the artifact you expected to deploy?
- Did the same version receive a different checksum after being edited?

## Check current schema objects

For PostgreSQL-compatible databases:

```sql
SELECT table_schema, table_name
FROM information_schema.tables
WHERE table_schema NOT IN ('pg_catalog','information_schema')
ORDER BY table_schema, table_name;
```

## Avoid the wrong fix

Do not immediately edit the Flyway history table to make the application start. First determine whether the migration file, database state, or deployment artifact is wrong.

Manual history edits can hide drift and make later migrations less predictable.

## Verification

After the application successfully starts, query the history again and confirm the expected migration was recorded exactly once and with `success = true`.

## Lesson

The migration history table is evidence. Check it before assuming the application applied the schema you intended.