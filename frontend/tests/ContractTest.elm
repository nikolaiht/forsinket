module ContractTest exposing (suite)

{-| The Elm half of the contract. The decoders must read the hand-written
examples in `contract/examples` as the values in `Fixtures`, and the encoders
must write the request examples. The Kotlin half is
`backend/app/src/test/kotlin/ContractTest.kt`, against the same files.
-}

import Api
import Claim
import Claim.Calculation as Calculation exposing (Assessment(..), ExpenseAssessment(..), Handling(..), TicketValue(..))
import Claim.Decision as Decision
import Claim.Draft as Draft
import Claim.Reason exposing (IneligibilityReason(..), RejectionReason(..), ReviewReason(..))
import Contract.Examples as Examples
import Date
import Departure exposing (Outcome(..))
import Example
import Expect
import Fixtures
import Json.Decode as Decode exposing (Decoder)
import Json.Encode as Encode
import JsonTree
import Rules
import Status
import Test exposing (Test, describe, test)
import Time exposing (Month(..))


suite : Test
suite =
    describe "The contract with the service"
        [ describe "responses"
            [ decodes "the rule set" Rules.decoder Examples.rules Fixtures.rules
            , decodes "a day's departures" (Decode.list Departure.decoder) Examples.departures Fixtures.departures
            , describe "assessments"
                [ decodes "approved by the rules"
                    Calculation.assessmentDecoder
                    Examples.assessmentAutoApprove
                    (Eligible Fixtures.calculationA AutoApprove)
                , decodes "sent to an officer"
                    Calculation.assessmentDecoder
                    Examples.assessmentManualReview
                    (Eligible Fixtures.calculationB (ManualReview ( ExpensesClaimed, [] )))
                , decodes "not eligible"
                    Calculation.assessmentDecoder
                    Examples.assessmentNotEligible
                    (NotEligible DelayBelowThreshold)
                ]
            , describe "claims"
                [ decodes "approved automatically" Claim.decoder Examples.claimApprovedAutomatically Fixtures.approvedAutomatically
                , decodes "awaiting review" Claim.decoder Examples.claimAwaitingReview Fixtures.awaitingReview
                , decodes "approved by an officer" Claim.decoder Examples.claimApprovedByOfficer Fixtures.approvedByOfficer
                , decodes "rejected by an officer" Claim.decoder Examples.claimRejectedByOfficer Fixtures.rejectedByOfficer
                , decodes "rejected by the rules" Claim.decoder Examples.claimRejectedByRules Fixtures.rejectedByRules
                , decodes "paid out" Claim.decoder Examples.claimPaidOut Fixtures.paidOut
                ]
            , decodes "claim summaries"
                (Decode.list Claim.summaryDecoder)
                Examples.claimsSummaries
                [ { id = Fixtures.idC
                  , version = 2
                  , status = Status.Rejected
                  , submittedAt = Fixtures.time "2026-11-21T11:00:00Z"
                  , departureDate = Date.fromCalendarDate 2026 Nov 20
                  , trainNumber = "TB17"
                  , total = Nothing
                  }
                , { id = Fixtures.idB
                  , version = 2
                  , status = Status.AwaitingReview
                  , submittedAt = Fixtures.time "2026-11-21T10:00:00Z"
                  , departureDate = Date.fromCalendarDate 2026 Nov 20
                  , trainNumber = "TB14"
                  , total = Just (Fixtures.ore 2830)
                  }
                , { id = Fixtures.idA
                  , version = 2
                  , status = Status.Approved
                  , submittedAt = Fixtures.time "2026-11-21T09:15:00Z"
                  , departureDate = Date.fromCalendarDate 2026 Nov 20
                  , trainNumber = "TB16"
                  , total = Just (Fixtures.ore 17450)
                  }
                ]
            , decodes "the worked examples for the front page"
                (Decode.list Example.decoder)
                Examples.examples
                [ { ticket = Fixtures.single349
                  , expenses = Nothing
                  , outcome = Ran 45
                  , assessment = Eligible (singleTicketAt 45 25 8725) AutoApprove
                  }
                , { ticket = Fixtures.single349
                  , expenses = Nothing
                  , outcome = Ran 75
                  , assessment = Eligible (singleTicketAt 75 50 17450) AutoApprove
                  }
                , { ticket = Fixtures.period849
                  , expenses = Just Fixtures.taxi620
                  , outcome = Cancelled
                  , assessment =
                        Eligible
                            { ruleSetVersion = "v1"
                            , ticketValue = PerDay { price = Fixtures.ore 84900, days = 30, value = Fixtures.ore 2830 }
                            , outcome = Cancelled
                            , percent = 100
                            , ticketCompensation = Fixtures.ore 2830
                            , expenses = PendingReview { claimed = Fixtures.ore 62000, maxCoverable = Fixtures.ore 62000 }
                            , total = Fixtures.ore 2830
                            }
                            (ManualReview ( ExpensesClaimed, [] ))
                  }
                , { ticket = Fixtures.single349
                  , expenses = Nothing
                  , outcome = Ran 12
                  , assessment = NotEligible DelayBelowThreshold
                  }
                ]
            ]
        , describe "requests"
            [ encodes "a claim for a single ticket"
                (Draft.encode { departureId = Fixtures.tb16.id, ticket = Fixtures.single349, expenses = Nothing })
                Examples.claimRequestSingle
            , encodes "a claim for a period ticket with expenses"
                (Draft.encode { departureId = Fixtures.tb14.id, ticket = Fixtures.period849, expenses = Just Fixtures.taxi620 })
                Examples.claimRequestPeriodWithExpenses
            , encodes "an officer's approval"
                (Decision.encode 2
                    { officer = "KN"
                    , note = "Kvitteringen viser 500 kr."
                    , verdict = Decision.Approve (Fixtures.ore 50000)
                    }
                )
                Examples.decisionRequestApprove
            , encodes "an officer's rejection"
                (Decision.encode 2
                    { officer = "KN"
                    , note = "Samme reise er allerede erstattet."
                    , verdict = Decision.Reject DuplicateClaim
                    }
                )
                Examples.decisionRequestReject
            , encodes "a payout" (Api.encodePayout 2) Examples.payoutRequest
            ]
        , describe "what the decoders refuse"
            [ refuses "a status the app does not know"
                Claim.decoder
                (String.replace "\"type\":\"approved\"" "\"type\":\"escalated\"" Examples.claimApprovedAutomatically)
            , refuses "a claim sent to review for no reason"
                Claim.decoder
                (String.replace "\"reasons\":[\"expenses_claimed\"]" "\"reasons\":[]" Examples.claimAwaitingReview)
            , refuses "a ticket valid for a number of days nobody sells"
                Claim.decoder
                (String.replace "\"validityDays\":30" "\"validityDays\":14" Examples.claimAwaitingReview)
            , refuses "a claim with a field missing"
                Claim.decoder
                (String.replace "\"version\":2," "" Examples.claimAwaitingReview)
            , refuses "a date that is not a date"
                (Decode.list Departure.decoder)
                (String.replace "2026-11-20\",\"trainNumber\":\"TB11" "20.11.2026\",\"trainNumber\":\"TB11" Examples.departures)
            ]
        , test "a timestamp is read as the right instant" <|
            \_ ->
                Decode.decodeString Claim.decoder Examples.claimApprovedAutomatically
                    |> Result.map (.submittedAt >> Time.posixToMillis)
                    |> Expect.equal (Ok 1795252500000)
        ]


{-| A single ticket of 349 kr and no expenses, at a given delay.
-}
singleTicketAt : Int -> Int -> Int -> Calculation.Calculation
singleTicketAt delayMinutes percent compensation =
    { ruleSetVersion = "v1"
    , ticketValue = FullPrice (Fixtures.ore 34900)
    , outcome = Ran delayMinutes
    , percent = percent
    , ticketCompensation = Fixtures.ore compensation
    , expenses = NoneClaimed
    , total = Fixtures.ore compensation
    }


decodes : String -> Decoder a -> String -> a -> Test
decodes name decoder json expected =
    test name <|
        \_ ->
            Decode.decodeString decoder json
                |> Result.mapError Decode.errorToString
                |> Expect.equal (Ok expected)


{-| What an encoder writes is compared with the example as JSON, not as text,
so the order of the fields does not matter.
-}
encodes : String -> Encode.Value -> String -> Test
encodes name value example =
    test name <|
        \_ ->
            JsonTree.fromValue value
                |> Expect.equal (JsonTree.fromString example)


{-| The replacement must have changed something, or the test would pass for the wrong reason.
-}
refuses : String -> Decoder a -> String -> Test
refuses name decoder json =
    test name <|
        \_ ->
            Decode.decodeString decoder json
                |> Expect.err
