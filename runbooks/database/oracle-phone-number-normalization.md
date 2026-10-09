# Oracle Phone-Number Normalization for Customer Lookup Troubleshooting

## Problem

A customer lookup by mobile number returns no row even though the customer exists. The same number may be stored with international prefixes, leading zeros, punctuation, or other formatting differences.

## Start by inspecting stored values

Search by a distinctive suffix instead of immediately forcing one normalized format:

```sql
SELECT DISTINCT mobile_number, full_name, cif
FROM <schema>.<view_or_table>
WHERE REGEXP_REPLACE(mobile_number, '[^0-9]', '') LIKE '%<last_digits>%';
```

This reveals how numbers are actually stored.

## Normalize for comparison

A generalized pattern for numbers that may start with a country code or a domestic zero is:

```sql
SELECT DISTINCT
    account_number,
    current_balance,
    TO_CHAR(cif) AS cif,
    full_name,
    mobile_number
FROM <schema>.<view_or_table>
WHERE REGEXP_REPLACE(
        REGEXP_REPLACE(mobile_number, '[^0-9]', ''),
        '^(<country_code>|0)',
        ''
      ) = '<national_number_without_prefix>'
ORDER BY account_number;
```

## Important edge case

Legacy systems sometimes store international values with extra leading zeros, for example `00<country-code>...`. A normalization rule that removes only `<country-code>` or `0` may still fail.

Inspect representative stored values before deciding the canonical rule.

## Validate uniqueness

A suffix search can match multiple customers. Do not treat a suffix-only result as a unique identity check.

```sql
SELECT COUNT(*)
FROM <schema>.<view_or_table>
WHERE REGEXP_REPLACE(mobile_number, '[^0-9]', '') LIKE '%<last_digits>%';
```

## Lesson

When data comes from legacy or integrated banking systems, lookup failure may be a data-normalization problem rather than a missing customer record.