# The contract between the Elm app and the Kotlin service

`examples/` holds one JSON file for every request and response the API has, including the errors. The files are written directly, not generated from either side's code, and they came before the JSON code on both sides. They serve as the specification, and both sides are tested against them:

- **Kotlin** (`backend/app/src/test/kotlin/ContractTest.kt`): known domain values, mapped and serialised, must equal the response examples exactly. The request examples must parse to the expected drafts. `HttpApiTest.kt` then compares the same files with what the running service answers over HTTP.
- **Elm** (`frontend/tests/ContractTest.elm`): the decoders must turn the response examples into the expected Elm values, and the encoders must produce the request examples. Elm tests cannot read files, so `frontend/scripts/generate-contract.mjs` copies the examples into an Elm module, and CI fails if that module is out of date.

If the two sides drift apart, one of these tests fails.

## Conventions

- Money is an integer number of øre. `34900` is 349,00 kr.
- Timestamps are ISO-8601 in UTC. Dates are `YYYY-MM-DD`. Times of day are `HH:MM`.
- A value that can take several shapes is an object with a `"type"` field that says which.
- Enumerations are lower-case strings with underscores.
- Amounts are Norwegian kroner (kr). One krone is 100 øre.
- Every example is about a journey on the same fictional day, Friday 20 November 2026 on Tindbanen. The claims are submitted and decided the day after.

## Endpoints

| Method and path | Request | Success |
|---|---|---|
| `GET /api/rules` | | 200, the rule set (`rules.json`) |
| `GET /api/examples` | | 200, worked examples for the front page (`examples.json`) |
| `GET /api/departures?date=2026-11-20` | | 200, the day's departures (`departures.json`) |
| `POST /api/assessments` | `claim-request.*.json` | 200, what the rules say, nothing stored (`assessment.*.json`) |
| `POST /api/claims` | `claim-request.*.json` | 201, the claim (`claim.*.json`) |
| `GET /api/claims/{id}` | | 200, the claim |
| `GET /api/claims?status=awaiting_review` | | 200, summaries, newest first (`claims.summaries.json`) |
| `POST /api/claims/{id}/decision` | `decision-request.*.json` | 200, the claim |
| `POST /api/claims/{id}/payout` | `payout-request.json` | 200, the claim |

## Errors

Every error is an object with a `"type"` (`error.*.json`):

| Status | Type | When |
|---|---|---|
| 400 | `malformed_request` | The body or a query parameter could not be read |
| 404 | `not_found` | No such claim, or no such API path |
| 409 | `version_conflict` | The claim has changed since the client read it |
| 409 | `invalid_transition` | The claim's status does not allow this |
| 422 | `validation` | The values were read, and some are not acceptable. Lists every problem, by field |
| 413 | `malformed_request` | The body is larger than any request this API takes |
| 429 | `demo_limit_reached` | The open demo has reached its cap on stored claims |
| 500 | `internal_error` | A bug, or a database that is not there. The response says nothing more |

## The examples

| Example | What it is |
|---|---|
| A | Departure TB16, 61 minutes late. Single ticket, 349 kr. Half the price back, approved by the rules. |
| B | Departure TB14, 130 minutes late. 30-day ticket, 849 kr, and a taxi for 620 kr. Goes to an officer, who covers 500 kr. |
| C | Departure TB17, 29 minutes late. Under the threshold, rejected by the rules. |
| D | B, rejected by the officer as a duplicate. |
| E | A, paid out. |
