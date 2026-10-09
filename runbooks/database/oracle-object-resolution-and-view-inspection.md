# Oracle Object Resolution and View Inspection

This runbook covers the common case where a query returns `ORA-00942: table or view does not exist`, even though the object exists under another schema or is a view rather than a table.

## 1. Search for the object across accessible schemas

```sql
SELECT owner, object_name, object_type
FROM all_objects
WHERE UPPER(object_name) = UPPER('CUST_BAL_ACCOUNT_INFO')
ORDER BY owner, object_type;
```

This immediately tells you whether the object is a `TABLE`, `VIEW`, `SYNONYM`, or another type.

## 2. Use the schema-qualified name

If the object is owned by another schema:

```sql
SELECT *
FROM IMAL.CUST_BAL_ACCOUNT_INFO
FETCH FIRST 10 ROWS ONLY;
```

A query such as:

```sql
SELECT * FROM CUST_BAL_ACCOUNT_INFO;
```

may fail if no synonym exists and the current user is not the owner.

## 3. Inspect columns

```sql
SELECT column_id, column_name, data_type, data_length
FROM all_tab_columns
WHERE owner = 'IMAL'
  AND table_name = 'CUST_BAL_ACCOUNT_INFO'
ORDER BY column_id;
```

`ALL_TAB_COLUMNS` works for views as well as tables.

## 4. Inspect the view definition

If the object is a view:

```sql
SELECT text
FROM all_views
WHERE owner = 'IMAL'
  AND view_name = 'CUST_BAL_ACCOUNT_INFO';
```

For longer definitions, use your SQL client's long-output settings if required.

## 5. Search data safely

For phone-number fields with inconsistent prefixes or formatting:

```sql
SELECT DISTINCT mobile_number, full_name, cif
FROM IMAL.CUST_BAL_ACCOUNT_INFO
WHERE REGEXP_REPLACE(mobile_number, '[^0-9]', '') LIKE '%123456%';
```

Normalize only when needed; avoid applying expensive regex predicates to large tables unless the result set or environment is controlled.

## 6. Check privileges when the object exists but access still fails

```sql
SELECT owner, table_name, privilege, grantor
FROM all_tab_privs
WHERE owner = 'IMAL'
  AND table_name = 'CUST_BAL_ACCOUNT_INFO';
```

## Key lesson

`ORA-00942` does not automatically mean the object is absent. Check:

- current schema
- actual owner
- object type
- synonyms
- direct privileges

before assuming the database object is missing.
