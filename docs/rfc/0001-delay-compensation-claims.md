# RFC 0001: Delay compensation claims in Elm and Kotlin

- Status: accepted for the demo in this repository
- Scope: a passenger claims compensation for a delayed or cancelled train, the rules settle what they can, and a claims officer decides the rest

## Problem

A passenger whose train was late wants to know what they are owed, and to get it without a dispute. The operator wants simple claims settled without anyone looking at them, the rest decided by a claims officer, and to be able to show afterwards how every amount was arrived at.

Three things make that harder than it sounds:

- The rules must give the same answer every time, and the answer must be explainable to the person it concerns.
- A claim must never be in a state that makes no sense: paid out but rejected, or approved by nobody.
- Two people can act on the same claim at the same time.

This repository is a demo of how I would build it with Elm in the browser and functional Kotlin on the server. The operator, Tindbanen, does not exist. The rules are made up for the demo and are not any real operator's terms.

## Goals

1. Every amount is explained step by step, by the same code that decides the payout.
2. A claim can only be in a state that exists, and can only move the ways the state diagram allows.
3. What goes wrong is a value: invalid input (all of it, not just the first problem), a command that does not fit the claim's status, a conflict with another writer.
4. An Elm app whose model cannot describe a screen that should not exist.
5. One JSON contract, tested on both sides.
6. Everything runs with one command, and CI checks all of it.

Out of scope: logging in and roles (the officer pages are open), real payouts, appeals, e-mail, uploading receipts, real traffic data, real regulations, and other languages than Norwegian in the interface.

## The rules, version 1

| Rule | Value |
|---|---|
| Deadline | The claim must arrive within 90 days of the journey |
| Delay under 30 minutes | No compensation |
| 30–59 minutes | 25 % of the ticket value |
| 60–119 minutes | 50 % |
| 120 minutes or more, or cancelled | 100 % |
| Single ticket | The ticket value is its price |
| Period ticket (7 or 30 days) | The ticket value is the price divided by the number of days |
| Expenses for other transport | Covered up to 800 kr, only at 60 minutes or more, or when cancelled |
| Automatic approval | Only when no expenses need review and the ticket compensation is at most 1 000 kr |

Money is whole øre, as an integer, everywhere (one krone is 100 øre). There is one rounding function, to the nearest øre with halves up. Each step that divides or multiplies rounds, and the next step uses the rounded amount. The numbers shown are therefore exactly the numbers the calculation used, and a reader with a calculator arrives at the same sum.

The states a claim can be in, and how it moves between them:

```
submitted ─┬─► approved ────────────────────────► paid out
           ├─► rejected
           └─► awaiting review ─┬─► approved ───► paid out
                                └─► rejected
```

The first three branches are taken by the rules, the moment the claim is submitted. The two after `awaiting review` are an officer's decision.

## Design

### A core of pure functions

The Kotlin code is two Gradle modules. `domain` depends on the standard library and `arrow-core`. The build keeps Ktor, the database driver and serialization off its classpath. `app` is the shell around it.

The life of a claim is two functions in `domain`:

```kotlin
fun decide(rules: RuleSet, state: ClaimState, command: ClaimCommand): Either<ClaimError, NonEmptyList<ClaimEvent>>
fun evolve(state: ClaimState, event: ClaimEvent): ClaimState
```

`decide` looks at where a claim stands and at a command, and answers with the events that follow or the reason the command is refused. `evolve` applies one event. Neither reads a clock, makes an id or touches a database: the time is a field of the command, and the shell supplies it. That part is a convention the code keeps, not something the build can check.

`ClaimState` is a sealed type in which each state holds exactly the data that exists in it. Only `Approved` and `PaidOut` have someone who approved, only `Rejected` has a rejection, only `PaidOut` has a payout time. "Partly approved" is not a state: it follows from the approved expenses being lower than the claimed ones.

Every operation that changes a claim has the same shape (`ClaimService.execute`): load the events, fold them to a state, call `decide`, store what it returned.

### Rules as data, assessment as a function

`RuleSet` is a value, and `assess(rules, claim, submittedOn)` is a pure function from a claim to an `Assessment`: not eligible, with the reason, or eligible, with a `Calculation` and whether the rules can settle it alone. The `Calculation` holds every step and the amount that step gave. The API returns it as it is, and the Elm app shows it without doing any compensation arithmetic of its own, so the page shows the service's own numbers.

The answers in the worked examples on the front page are not hard-coded in the service or the app. `GET /api/examples` runs four inputs through `assess`.

A claim with invalid data, such as an unknown departure or a price of zero, never becomes a claim. A claim that is too late, or for too short a delay, is a valid claim that gets a recorded rejection. The first is a validation error, the second is an event.

### Errors as values, with Arrow

Alternatives considered:

- **Exceptions for domain failures.** The compiler does not make the caller handle them, and "the officer approved too much" is not exceptional.
- **`kotlin.Result`.** Its error is a `Throwable`, so the failures would still be untyped.
- **Hand-written sealed result types.** They work, but validation that reports every problem means writing the accumulation by hand.
- **`arrow-core` (chosen).** `Either` for typed failures, `NonEmptyList` for "at least one reason" and "at least one event", and `zipOrAccumulate` for validation that collects every error. The rest of Arrow is not used.

Exceptions remain for things that are not domain outcomes:

- **A bug or corrupt data.** `evolve` throws if an event cannot follow the state it is applied to, because `decide` could not have produced that stream. Such an exception is logged, and the client gets a 500 that says nothing about what went wrong inside.
- **The framework failing to read a request body.** Ktor signals this with an exception. `StatusPages` turns a body that is not JSON into a 400 `malformed_request`, and one over 64 KB into a 413.
- **The JDK failing to parse an id or a date in an address.** The route catches it where it happens and turns it into a value: an id that is not a UUID is `not_found`, a date that is not a date is `malformed_request`.

### Ktor rather than Spring Boot

I have used Spring Boot in production, and it would have worked. Ktor was chosen because of what this demo is for. A route is an ordinary function, and the application is a function that takes what it needs as arguments (`Application.module(service, webRoot)`). There are no annotations and no container deciding what gets injected where, so the line between the pure core and the shell is visible in the code, and a test builds the same module around a service with its own clock, ids and database.

Spring Boot gives more out of the box: configuration, metrics, security, data access. In a larger service with a team that knows it, those would count for more than they do here.

### Events in PostgreSQL

```sql
claim_events    (claim_id, version, event_type, payload jsonb, occurred_at)   primary key (claim_id, version)
claim_summaries (claim_id, version, status, submitted_at, departure_date, train_number, total_ore)
```

The events are the source of truth, and they are what the claim page shows as the history. A writer says which version it built on. The service checks that against the events it loaded, and the primary key catches the case where two writers pass that check at the same moment: the second insert fails, and the failure becomes the value `VersionConflict` and a 409. A test holds one transaction open to force exactly that race.

The list of claims reads `claim_summaries`, a projection written in the same transaction as the events. A property test runs random sequences of actions through the service and checks that the projection equals what the events fold to.

An event is read for as long as its claim exists, by whatever version of the service is running then. Three things keep the stored format from changing by accident:

- One file for each kind of event, as it is stored, is checked into the tests. Each is read as the event it records and written back as the same text.
- The names that enums are stored under are pinned by a test of their own, so renaming a constant in the code does not rename it in the database.
- The reader skips fields it does not know, so a field added later does not make an older reader fail.

Alternatives considered:

- **One row per claim, updated in place.** Less code. It loses the record of what happened, which is what makes a decision possible to check afterwards.
- **A dedicated event store.** Not worth another system for one stream type.

Known limits: stored events share the JSON shapes of their values (ticket, departure, calculation) with the API, so a change to one of those shapes is also a storage format change. The tests above make such a change visible, but there is no upcasting of old events and no tool to rebuild the projection. Both would be needed before a second version of the rules or the events.

### One contract, tested on both sides

`contract/examples` holds one JSON file for every request and response, including the errors. They are written directly, not generated from either side's code, and they came before the JSON code on both sides.

- The Kotlin tests build domain values, map and serialise them, and compare with the files. They also run the whole service over HTTP against a real PostgreSQL and compare the responses with the same files.
- The Elm tests decode the same examples and compare with Elm values written out in the tests, and check that the encoders produce the request examples. Elm tests cannot read files, so a script copies the examples into an Elm module, and CI fails if the committed module is out of date.

Alternative considered: an OpenAPI document with generated clients. The generated decoders and types would replace exactly the code which this demo is meant to show, and the types would be whatever the generator emits rather than types designed to rule out invalid states.

### Elm: a plain `Browser.application`

No framework on top of The Elm Architecture. `Main` knows which page is showing and passes messages on. Each page is a module with its own `Model`, `Msg`, `update` and `view`. Frameworks such as elm-land or elm-pages would have taken over routing and page wiring, which are part of what there is to see.

The model is built so that screens that should not exist cannot be described:

- **`Remote error value = Loading | Failed error | Loaded value`** for everything fetched. It has no "not asked" case. Where a page really has not asked yet, the type around it says so: the departures are `NoDate` until a date is chosen, and the preview is `NoPreview` until the form is complete.
- **`Claim.Status`** is a custom type with the data of each status inside the variant. What an officer can do follows from pattern matching on it: the decision form exists for `AwaitingReview`, the payout button for `Approved`. There is no boolean to keep in step with the status.
- **A form is a parser.** `Claim.Draft.Draft` is what is in the form, as text. `validate : Rules -> Draft -> Result (List FieldError) NewClaim` gives a claim that can be sent, or every problem at once. There is no "is valid" flag: either there is a `NewClaim` or there is a list of what is wrong. `Validation.andMap` does on this side what `zipOrAccumulate` does in Kotlin.
- **`Money`, `Claim.Id` and `Departure.Id` are opaque.** An amount cannot be negative: `Money.fromOre` returns a `Maybe`. An id cannot be confused with other text.
- **Answers that arrive late are recognised.** Every answer says what it is about. The departures in the model belong to a date (`For date remote`), a preview belongs to the claim it was asked about (`PreviewFor claim remote`), a claim to its id, a list to its filter. An answer about something the user has moved on from is dropped, by comparing values, not by cancelling requests.
- **A claim on its way locks the form.** `Submitting claim` remembers which claim was sent. Until the answer about that claim comes, nothing in the form can be changed and nothing is sent again.

**Effects as values.** A page's `update` has the type `Msg -> Model -> ( Model, List Effect )`, where `Effect` is the page's own type: `FetchDepartures date`, `SendClaim claim`, `SendDecision id version decision`. `update` never builds a command. `perform : Effect -> Cmd Msg` is the only place an effect becomes one. The tests run a page message by message without a browser, and check what it asked for as well as what it shows.

`Api.Error` separates what a user can act on differently: no connection, timeout, not found, values the service refuses, a claim someone else changed first, and an answer the app did not expect. Requests use `Http.expectStringResponse`, because `Http.expectJson` discards the body of a failed request, and with it the service's field errors. Errors from the service land on the same fields, in the same words, as the errors the form finds itself.

Decoders fail on a variant they do not know. A status added on the server becomes a visible "unexpected answer", not a claim quietly shown as something else. The one exception is a field error: a field or a code the app does not know is kept and shown as a general problem, so the user is still told that something is wrong.

**No ports and no flags.** The app needs two things that are not HTTP: the time now, and the rules of the Oslo time zone. The first is Elm's own `Time.now`. The second is data in an Elm package (`justinmimbs/timezone-data`), because `Time.here` only gives the offset that applies today, and would show a time on the other side of a clock change wrong by an hour. Times are therefore shown in Oslo time whatever the reader's own time zone is, which is also the zone the deadlines are counted in. There is no local storage and no JavaScript beyond the line that starts the program.

**Focus.** When the page changes, focus moves to the new page's content, so a keyboard or screen reader user starts where the new page starts. When a form is refused, focus moves to the message that says why.

Styling is one hand-written CSS file. elm-ui or elm-css would have moved layout into Elm, which is a matter of taste. Plain CSS keeps the views about structure.

### Synthetic traffic data

The claims service needs to know how late a train was. In a real operator that is another system, so the service only sees a port, `TrafficData`. The implementation here is a pure function of the date: a fixed timetable of eight departures a day, with delays in a seven-day cycle that hits both sides of every limit in the rules. The demo therefore has fresh departures on whatever day it runs, and a test can name a date and know what happened on it. A departure can be claimed for once its scheduled time has passed.

### An open demo

The app is built to stand open on the internet without a login:

- Every input has a limit: ticket price, claimed expenses, the length of an officer's note, and 64 KB for a request body.
- Elm renders text as text. Nothing a user types is treated as HTML.
- With `DEMO_MODE=true` the service seeds six claims through the normal `submit` and `decide` path, caps the number of stored claims, and can start over from the seed data at an interval. A reset that fails is logged, and the next one is still tried.
- The time of the last reset is stored in the database, and a service that starts checks whether one is due. A timer inside the service is not enough on its own: it starts from nothing every time the service is restarted, and on a host that stops the service between visits it never fires at all.
- More than one instance of the service can start at the same moment. The store takes a lock while it decides whether to empty itself, so only one of them does. Seeding leaves a claim that is already there as it is, so two instances that seed at the same moment do not get in each other's way, and a seeding that was cut short is finished the next time the service starts.
- No personal data is asked for. A claim has no name, e-mail or account number. The only free text stored is an officer's initials and note.

### Where the hosted copy runs

The hosted copy is one small machine at Fly.io that is always on (`fly.toml`). It runs the image that `docker compose` and CI run, unchanged, so it serves both the Elm app and the API. The database is PostgreSQL 18 at Neon. Both are in Frankfurt. A new version goes out with `fly deploy`.

Measured on 26 November 2026:

| What | Time |
|---|---|
| The page, or its script | 0.2 s |
| A request that does not need the database | 0.15 s |
| The first request that reads claims after 16 minutes without one | 0.8 s |
| Requests that read claims after that | 0.2 s |

The machine uses about 200 MB of its 512 MB.

The database goes to sleep when it has not been used for five minutes, and wakes for the next query. That is the 0.8 seconds. The connection pool keeps no connection open for its own sake, because an idle pool that checks its connections every other minute would keep the database awake day and night. Only pages that read or write claims wait for it: the rules, the examples, the departures and the preview are all computed, so the front page and the claim form up to the point of sending do not touch the database.

**What was tried first.** The first hosted copy ran on a platform that stops a service when it has had no traffic for five minutes, and starts it again for the next visitor (Vercel's container runtime, in beta at the time). A demo that is seldom visited then costs nothing to keep. The price is the wait for that next visitor, measured after eight minutes without traffic:

| What | Time |
|---|---|
| The first request to the service | 6.0 s |
| Requests after that | 0.2 s |

The service logs where its own part of that goes. About 1.9 s passed before the JVM started at all. Opening the first database connection took 1.4 s, the migration check 0.6 s, getting the demo ready 0.4 s, and starting Ktor 0.8 s. The rest was the JVM itself.

Serving the Elm app as static files from the platform's CDN made the page appear at once, and it said that it was fetching, which is what the `Loading` state in the Elm model is for. The numbers still took six seconds. A JVM service is built to be left running. On a platform built around stopping it, the choice was between that wait and a scheduled request every few minutes to keep it awake. A machine that is always on needs neither, for a few dollars a month.

Three things in the code came out of that attempt and are kept, because they make the service safe to restart at any time and to run as more than one instance. The time of the last reset is stored. Seeding can be repeated. And a database address is read in the form a host hands out: one `postgresql://` address with the user and the password in it. Where a host gives a direct address beside one that goes through its connection pooler, the direct one is used, since the service keeps its own small pool.

## Testing

- **Kotlin, domain:** unit tests of the rules, the validation and the decider. Property tests: compensation never exceeds the ticket value, a longer delay never pays less, random command sequences only ever move along the state diagram, nothing happens to a claim in a final state, and no officer can make a claim pay more for expenses than was claimed or the rules allow.
- **Kotlin, app:** the contract tests, a JSON round trip for every event, the stored-event files, the store against PostgreSQL in Testcontainers (including the forced race), the HTTP API end to end against the same database, and the projection property test.
- **Elm:** the contract tests, fuzz tests (an amount formatted and parsed gives the same amount, a route written as an address and parsed gives the same route, any acceptable claim typed into the form validates back to itself), and the mapping of every kind of HTTP outcome to an `Api.Error`. The two pages with forms are tested message by message through `update`: what they show, what they ask for, and late answers. The pages that only fetch and show are tested for dropping an answer about something else. What an officer is offered is tested against the rendered page, for every status.
- **Together:** CI builds the image, starts it with its database and walks two claims through it with `curl`.

## Risks and simplifications

- **A departure's outcome is known from its scheduled departure time.** In reality the delay is known when the train arrives.
- **No authentication.** Anyone can open the officer pages, and an officer's initials are whatever was typed.
- **Submitting a claim is not idempotent.** The form locks while a claim is on its way, but a request that is sent again by something in between, after the first one was stored, makes a second claim. A real service would take an idempotency key.
- **The demo's cap on stored claims is soft.** Two submissions at the same moment can both get in under it.
- **The preview is asked for on every change that leaves the form complete.** There is no debounce. Late answers are dropped, so the result is right, but a slow connection sends more requests than it needs.
- **The first request that reads claims after a quiet spell waits for the database to wake**, 0.8 seconds as measured above. Keeping the database awake costs more than the machine does.
- **A new version reaches the hosted copy when someone runs `fly deploy`**, not when it is pushed.
- **A ticket under 45 øre can give a compensation of zero**, which is then approved. No real ticket is that cheap, so there is no minimum payout rule yet.

## Open questions

- Which rule set applies when the rules change: the one in force on the day of travel, or on the day of the claim? Every calculation records its version, but there is only one version so far.
- Should a period ticket count two journeys a day rather than one?
- Is an appeal a new state after `Rejected`, or a new claim that refers to the old one?
