# forsinket

A demo: passengers claim compensation for a delayed or cancelled train, and the app shows how the amount was worked out. The train operator is made up. The frontend is written in Elm and the backend in Kotlin.

![A paid-out claim: the status, the calculation set out step by step like a receipt, the journey, and the record of what has happened](docs/screenshot.png)

One claim, as the passenger sees it. The interface is in Norwegian. The train was cancelled, so the ticket is refunded in full. The passenger also claimed 620 kr for a taxi, and a claims officer (the member of staff who handles the claim) covered 500 kr of it. The page shows how the sum was reached, step by step, and everything that has happened to the claim.

*Forsinket* is Norwegian for *delayed*. Amounts are in Norwegian kroner (kr), and one krone is 100 øre.

This is a demo project. I have used Kotlin in production and I write TypeScript in a functional style, but I had not used Elm in a project before this one. I made it to show how I would write Elm, and how I would build the Kotlin side for a team that likes functional programming. It has not run in production.

I built it in a short time with an AI coding assistant, which is why the commits are large and close together. The choice of domain, the design decisions and the review are mine.

The operator, Tindbanen, is made up. The rules are made up for the demo and are not any real operator's terms. All data is synthetic. No personal data is asked for: a claim has no name, e-mail or account number. The only free text stored is an officer's initials and note.

## Run it

```bash
docker compose up --build
```

That is all it needs: Docker. The app is then on [http://localhost:8080](http://localhost:8080), with six demo claims in it. It is not hosted anywhere yet, so this is the way to see it. There are three places to start:

- **[The front page](http://localhost:8080/)** says what a passenger is owed, with four worked examples.
- **[Meld krav](http://localhost:8080/krav/nytt)** is the claim form. Pick a departure and a ticket, and the calculation appears before the claim is submitted.
- **[Saksbehandling](http://localhost:8080/saksbehandling)** is the officers' list. Open a claim that is waiting, decide it, and record the payout.

## What it does

- **Looks up the delay.** The passenger picks the departure they travelled on. How late it was is already recorded, so nobody types in a delay.
- **Calculates, and shows its work.** 25 % of the ticket value from 30 minutes, 50 % from 60, all of it from 120 or when the train is cancelled. A period ticket counts as its price divided by its days. Every step is returned with the amount that step gave, and the app shows those steps as they are.
- **Settles what it can.** A claim with no expenses to review and a ticket compensation of at most 1 000 kr is approved or rejected the moment it is submitted. The rest wait for an officer.
- **Lets an officer decide, within the rules.** The officer sets how much of the expenses to cover, up to what the rules allow, or rejects the claim with a reason. The ticket compensation follows from the rules and is not theirs to change.
- **Keeps the record.** Every claim is stored as the list of things that happened to it. The history on the page is that list.
- **Handles two officers at once.** Whoever decides second is told the claim has changed, and nothing is overwritten.

The rules, the design decisions and the alternatives are in [RFC 0001](docs/rfc/0001-delay-compensation-claims.md).

```
Elm app ──── JSON over HTTP ────► Ktor: routes, JSON, clock, ids          (the shell)
  ▲                                 │
  │                                 ├─► assess · decide · evolve          (pure functions)
  └── contract/examples ──┐         │
      tested on both sides┘         └─► PostgreSQL: an append-only event log per claim
```

## What to look at in the Elm code

Elm 0.19.3, a plain `Browser.application`, no framework, no ports and no flags.

- **A status carries only its own data.** [`Claim.Status`](frontend/src/Claim.elm) is a custom type with the data of each status inside its variant. A rejected claim has no payout time, because `Rejected` has no field for one. What an officer can do is decided by pattern matching on it in [`Page.ReviewClaim`](frontend/src/Page/ReviewClaim.elm): the decision form exists for `AwaitingReview`, the payout button for `Approved`.
- **No booleans to keep in step.** [`Remote`](frontend/src/Remote.elm) is loading, failed or loaded, never two of them. In [`Page.NewClaim`](frontend/src/Page/NewClaim.elm) a claim on its way is `Submitting claim`, and while it is, the form is locked.
- **Late answers are recognised.** Every answer from the service says what it is about: the date of the departures, the claim a preview was asked for, the id of a claim, the filter of a list. An answer about something the page has moved on from is dropped, by comparing values.
- **Effects are values.** A page's `update` returns the new model and a list of its own `Effect` type, such as `SendDecision id version decision`. Only `perform` turns them into commands. The [tests](frontend/tests/ReviewClaimTest.elm) can therefore check what a page asked for, not only what it shows: that a decision is sent for the version of the claim the officer is looking at, and that nothing is sent twice.
- **A form is a parser.** [`Claim.Draft`](frontend/src/Claim/Draft.elm) holds what is typed, as text. `validate` turns it into a `NewClaim` that can be sent, or into every problem at once. [`Validation.andMap`](frontend/src/Validation.elm) collects the errors instead of stopping at the first.
- **Opaque types.** A [`Money`](frontend/src/Money.elm) is never negative and never a fraction of an øre. It parses what people type (`349`, `349,50`, `1 234,50 kr`, `349,-`) and formats the Norwegian way.
- **JSON decoded by hand, strictly.** Decoders fail on a variant they do not know ([`Decoding.tagged`](frontend/src/Decoding.elm)), so a status added on the server becomes a visible error, not a claim shown as something it is not.
- **Errors the user can act on.** [`Api.Error`](frontend/src/Api.elm) tells apart no connection, a timeout, a missing claim, values the service refuses, and a claim someone else changed first. The service's validation errors land on the same fields, in the same words, as the form's own.
- **No compensation arithmetic in the browser.** The preview is a request to the service, so the page shows the service's own numbers.
- **Focus follows the user.** When the page changes, focus moves to the new page's content. When a form is refused, focus moves to the message that says why.

## What to look at in the Kotlin code

Kotlin 2.4 on JDK 25, Ktor, `arrow-core`, PostgreSQL.

- **A pure core.** The build keeps Ktor, the database driver and serialization off the classpath of [`backend/domain`](backend/domain): it depends on the standard library and `arrow-core` only. That it reads no clock and makes no ids is a convention the code keeps: the time is a field of the command.
- **Two functions.** [`decide`](backend/domain/src/main/kotlin/Decider.kt) takes a state and a command and returns the events that follow, or the reason the command is refused. `evolve` applies one event to a state. [`ClaimState`](backend/domain/src/main/kotlin/Claim.kt) is a sealed type where each state holds only the data that exists in it.
- **Rules as data.** [`assess`](backend/domain/src/main/kotlin/Assessment.kt) is a pure function from a rule set and a claim to an assessment, with every step of the calculation in the result.
- **Errors as values.** [`validateClaim`](backend/domain/src/main/kotlin/Validation.kt) returns every problem with a claim, using Arrow's `zipOrAccumulate`. An exception means a bug or corrupt data, never something a passenger or an officer did.
- **A thin shell.** [`ClaimService`](backend/app/src/main/kotlin/ClaimService.kt) does the same four things for every change: load the events, fold them to a state, call `decide`, store what it returned. The [Ktor module](backend/app/src/main/kotlin/http/Module.kt) is a function that takes the service as an argument, with no annotations and no container.
- **An event log with optimistic concurrency.** [`PostgresClaimStore`](backend/app/src/main/kotlin/store/PostgresClaimStore.kt) appends events under a `(claim_id, version)` primary key, in plain SQL. Two writers on the same version collide in the database, and the loser gets a value back, not an exception.
- **A stored format that does not change by accident.** [One file for each kind of stored event](backend/app/src/test/resources/stored-events) is read and written in a test, so renaming a field or an enum constant fails a test before it makes old rows unreadable.

## The contract between them

[`contract/examples`](contract/examples) has one JSON file for every request and response, including the errors. They are written directly, not generated from either side's code, and both sides are tested against the same files:

- [`ContractTest.kt`](backend/app/src/test/kotlin/ContractTest.kt) checks that the service's own types serialise to exactly these documents, and [`HttpApiTest.kt`](backend/app/src/test/kotlin/HttpApiTest.kt) checks it again over HTTP against a real database.
- [`ContractTest.elm`](frontend/tests/ContractTest.elm) checks that the decoders read them as the expected Elm values, and that the encoders write the request examples.

If the two sides drift apart, one of these tests fails.

## Tests

```bash
make test     # needs JDK 25, Node 22, and Docker for the PostgreSQL the tests start
```

- **Kotlin:** unit tests for the rules, the validation and the decider. Property tests with Kotest: a longer delay never pays less, random sequences of commands only ever move a claim the ways the rules allow, nothing more happens to a rejected or paid claim, no officer can make a claim pay more for expenses than was claimed or the rules allow, and whatever is done to a claim, its line in the officers' list is what its events add up to. Integration tests run the store and the whole HTTP API against PostgreSQL in Testcontainers, including a test that forces two writers to race.
- **Elm:** elm-test, with fuzz tests where a round trip must hold: an amount formatted and parsed again, a route written as an address and parsed again, and any acceptable claim typed into the form and validated. The two pages with forms are tested message by message through `update`: what they show, what they ask for, and answers that arrive late. The pages that only fetch and show are tested for dropping an answer about something else. What an officer is offered is tested against the rendered page, for every status. elm-review and elm-format report no problems.
- **Together:** CI builds the Docker image, starts it with its database, and [`scripts/smoke.sh`](scripts/smoke.sh) walks two claims through it.

## Layout

```
frontend/                 the Elm app
  src/Claim.elm             a claim and its status
  src/Claim/                ticket, expenses, calculation, history, the two forms
  src/Page/                 one module per page: model, update, effects, view
  src/View/                 shared views: the calculation, the history, form fields, texts
  src/Api.elm               requests, and what every kind of answer means
  src/Route.elm             the pages and their addresses
  tests/                    elm-test, including the Elm half of the contract tests
backend/
  domain/                   rules, validation, decide and evolve. No I/O
  app/                      Ktor, JSON, PostgreSQL, configuration, demo data
contract/examples/        the JSON both sides are tested against
docs/rfc/                 the design, and the alternatives
scripts/smoke.sh          two claims through the running app
```

## Development

```bash
make up          # the whole thing in Docker, on http://localhost:8080
make test        # every check CI runs, except the Docker smoke test
make dev         # the service outside Docker, with a development build of the Elm app
make contract    # copy contract/examples into the Elm test module
make smoke       # walk two claims through the running app
```

The service is configured with environment variables: `PORT`, `DATABASE_URL`, `DATABASE_USER`, `DATABASE_PASSWORD`, `WEB_ROOT`, and for an open demo `DEMO_MODE`, `DEMO_MAX_CLAIMS` and `DEMO_RESET_MINUTES`. The database password in `docker-compose.yml` and the `Makefile` is for the local setup only.

## License

MIT. See [LICENSE](LICENSE).
