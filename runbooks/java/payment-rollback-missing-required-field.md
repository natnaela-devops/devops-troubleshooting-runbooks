# Trace Java payment rollback to a missing required request field

## Problem
A Java payment request failed inside an application server with a transaction rollback and a resilience fallback, making the incident initially look like a remote-service or circuit-breaker problem.

## Evidence
The stack trace contained the more specific exception:

```text
IllegalArgumentException: phoneNumber is required
```

The exception originated while preparing a validation request, then propagated through the payment service and caused the surrounding transaction to roll back.

## Investigation
Start from the deepest specific exception, not the outer fallback wrapper.

```bash
grep -nE 'IllegalArgumentException|phoneNumber|rollback|fallback|CircuitBreaker' application.log
```

Correlate the failing request with the method chain shown in the stack trace and inspect the inbound payload/configuration that should populate the required field.

Typical questions:
- Was the field absent in the incoming request?
- Was it present but mapped to a different DTO/property name?
- Did an earlier transformation replace it with `null`?
- Is validation happening only after the transaction begins?

## Root cause pattern
The circuit breaker/fallback was a secondary effect. The actionable failure was local request validation: a required phone-number field was missing/null before the external validation call could be prepared.

## Fix pattern
Validate required inputs at the API/service boundary and return a clear client validation response before entering the transactional downstream flow.

## Verification
Repeat the request with:
1. a valid populated field and verify normal processing,
2. an intentionally missing field and verify a controlled validation response rather than an EJB transaction rollback.

## Lesson
Framework wrappers such as Resilience4j fallbacks and transaction rollback exceptions can obscure the first useful exception. Troubleshoot from the deepest specific cause outward.