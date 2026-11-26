module Fixtures exposing
    ( approvedAutomatically, approvedByOfficer, awaitingReview, paidOut, rejectedByOfficer, rejectedByRules
    , calculationA, calculationB
    , departures, fb14, fb16, fb17
    , idA, idB, idC, idFrom
    , period849, single349, taxi620
    , rules
    , time
    )

{-| The Elm values behind the contract examples A to E. They are written out
by hand, so a test that decodes an example compares two independent
descriptions of the same thing: the JSON file and this module.

@docs approvedAutomatically, approvedByOfficer, awaitingReview, paidOut, rejectedByOfficer, rejectedByRules
@docs calculationA, calculationB
@docs departures, fb14, fb16, fb17
@docs idA, idB, idC, idFrom
@docs period849, single349, taxi620
@docs rules
@docs time

-}

import Claim exposing (Claim, DecidedBy(..), Rejection(..), Status(..))
import Claim.Calculation exposing (Calculation, ExpenseAssessment(..), TicketValue(..))
import Claim.Expenses as Expenses exposing (Expenses)
import Claim.History as History
import Claim.Id as Id exposing (Id)
import Claim.Reason exposing (IneligibilityReason(..), RejectionReason(..), ReviewReason(..))
import Claim.Ticket exposing (Ticket(..), Validity(..))
import Date exposing (Date)
import Departure exposing (Departure, Outcome(..))
import Iso8601
import Json.Decode as Decode
import Money
import Rules exposing (Rules)
import Time exposing (Month(..), Posix)



-- THE DAY


friday : Date
friday =
    Date.fromCalendarDate 2026 Nov 20


departure : String -> String -> String -> String -> Outcome -> Departure
departure trainNumber origin destination scheduledDeparture outcome =
    { id = departureId ("2026-11-20-" ++ trainNumber)
    , date = friday
    , trainNumber = trainNumber
    , origin = origin
    , destination = destination
    , scheduledDeparture = scheduledDeparture
    , outcome = outcome
    }


departures : List Departure
departures =
    [ departure "FB11" "Fjordvik" "Storhavn" "06:12" (Ran 3)
    , departure "FB12" "Storhavn" "Fjordvik" "07:42" (Ran 0)
    , departure "FB13" "Fjordvik" "Storhavn" "09:12" (Ran 0)
    , fb14
    , departure "FB15" "Fjordvik" "Storhavn" "15:12" (Ran 0)
    , fb16
    , fb17
    , departure "FB18" "Storhavn" "Fjordvik" "21:12" (Ran 0)
    ]


fb14 : Departure
fb14 =
    departure "FB14" "Storhavn" "Fjordvik" "12:12" (Ran 130)


fb16 : Departure
fb16 =
    departure "FB16" "Storhavn" "Fjordvik" "16:42" (Ran 61)


fb17 : Departure
fb17 =
    departure "FB17" "Fjordvik" "Storhavn" "18:12" (Ran 29)



-- WHAT WAS CLAIMED


single349 : Ticket
single349 =
    Single (Money.fromOre 34900)


period849 : Ticket
period849 =
    Period (Money.fromOre 84900) ThirtyDays


taxi620 : Expenses
taxi620 =
    { amount = Money.fromOre 62000, kind = Expenses.Taxi }



-- WHAT THE RULES SAID


calculationA : Calculation
calculationA =
    { ruleSetVersion = "v1"
    , ticketValue = FullPrice (Money.fromOre 34900)
    , outcome = Ran 61
    , percent = 50
    , ticketCompensation = Money.fromOre 17450
    , expenses = NoneClaimed
    , total = Money.fromOre 17450
    }


calculationB : Calculation
calculationB =
    { ruleSetVersion = "v1"
    , ticketValue = PerDay { price = Money.fromOre 84900, days = 30, value = Money.fromOre 2830 }
    , outcome = Ran 130
    , percent = 100
    , ticketCompensation = Money.fromOre 2830
    , expenses = PendingReview { claimed = Money.fromOre 62000, maxCoverable = Money.fromOre 62000 }
    , total = Money.fromOre 2830
    }


calculationBApproved : Calculation
calculationBApproved =
    { calculationB
        | expenses = Covered { claimed = Money.fromOre 62000, approved = Money.fromOre 50000 }
        , total = Money.fromOre 52830
    }


rules : Rules
rules =
    { version = "v1"
    , claimDeadlineDays = 90
    , bands =
        [ { fromMinutes = 30, percent = 25 }
        , { fromMinutes = 60, percent = 50 }
        , { fromMinutes = 120, percent = 100 }
        ]
    , expenseMinDelayMinutes = 60
    , expenseCap = Money.fromOre 80000
    , autoApprovalLimit = Money.fromOre 100000
    , maxTicketPrice = Money.fromOre 2000000
    , maxClaimedExpenses = Money.fromOre 1000000
    }



-- THE CLAIMS


submittedA : Posix
submittedA =
    time "2026-11-21T09:15:00Z"


submittedB : Posix
submittedB =
    time "2026-11-21T10:00:00Z"


submittedC : Posix
submittedC =
    time "2026-11-21T11:00:00Z"


decidedAt : Posix
decidedAt =
    time "2026-11-21T12:30:00Z"


paidAt : Posix
paidAt =
    time "2026-11-22T08:00:00Z"


claimA : Claim
claimA =
    { id = idA
    , version = 2
    , submittedAt = submittedA
    , departure = fb16
    , ticket = single349
    , expenses = Nothing
    , status = Approved { calculation = calculationA, by = ByRules, decidedAt = submittedA }
    , history =
        [ { at = submittedA, event = History.Submitted }
        , { at = submittedA, event = History.ApprovedAutomatically }
        ]
    }


claimB : Claim
claimB =
    { id = idB
    , version = 2
    , submittedAt = submittedB
    , departure = fb14
    , ticket = period849
    , expenses = Just taxi620
    , status = AwaitingReview { calculation = calculationB, reasons = ( ExpensesClaimed, [] ) }
    , history =
        [ { at = submittedB, event = History.Submitted }
        , { at = submittedB, event = History.SentToReview ( ExpensesClaimed, [] ) }
        ]
    }


approvedAutomatically : Claim
approvedAutomatically =
    claimA


paidOut : Claim
paidOut =
    { claimA
        | version = 3
        , status = PaidOut { calculation = calculationA, by = ByRules, decidedAt = submittedA, paidAt = paidAt }
        , history = claimA.history ++ [ { at = paidAt, event = History.PayoutRecorded } ]
    }


awaitingReview : Claim
awaitingReview =
    claimB


approvedByOfficer : Claim
approvedByOfficer =
    { claimB
        | version = 3
        , status =
            Approved
                { calculation = calculationBApproved
                , by = ByOfficer { officer = "KN", note = "Kvitteringen viser 500 kr." }
                , decidedAt = decidedAt
                }
        , history =
            claimB.history
                ++ [ { at = decidedAt
                     , event =
                        History.ApprovedByOfficer
                            { officer = "KN"
                            , approvedExpenses = Money.fromOre 50000
                            , note = "Kvitteringen viser 500 kr."
                            }
                     }
                   ]
    }


rejectedByOfficer : Claim
rejectedByOfficer =
    { claimB
        | version = 3
        , status =
            Rejected
                { rejection =
                    RejectedByOfficer
                        { reason = DuplicateClaim
                        , officer = "KN"
                        , note = "Samme reise er allerede erstattet."
                        }
                , decidedAt = decidedAt
                }
        , history =
            claimB.history
                ++ [ { at = decidedAt
                     , event =
                        History.RejectedByOfficer
                            { officer = "KN"
                            , reason = DuplicateClaim
                            , note = "Samme reise er allerede erstattet."
                            }
                     }
                   ]
    }


rejectedByRules : Claim
rejectedByRules =
    { id = idC
    , version = 2
    , submittedAt = submittedC
    , departure = fb17
    , ticket = single349
    , expenses = Nothing
    , status = Rejected { rejection = RejectedByRules DelayBelowThreshold, decidedAt = submittedC }
    , history =
        [ { at = submittedC, event = History.Submitted }
        , { at = submittedC, event = History.RejectedAutomatically DelayBelowThreshold }
        ]
    }



-- HELPERS


idA : Id
idA =
    idFrom "0a6f3c1e-5b7d-4e2a-9c41-7d2f8b3e6a10"


idB : Id
idB =
    idFrom "3f9d2b7a-1c4e-4f8b-a6d5-2e7c9b1f4d30"


idC : Id
idC =
    idFrom "c81e4a2d-9f6b-4d3c-8e17-5a2b6c9d0e50"


{-| An id for a test. Text that is not a UUID here is a mistake in the test itself.
-}
idFrom : String -> Id
idFrom raw =
    case Id.fromString raw of
        Just id ->
            id

        Nothing ->
            Debug.todo ("not a UUID in a test: " ++ raw)


{-| A departure id can only come from the server, so a test gets one by decoding it.
-}
departureId : String -> Departure.Id
departureId raw =
    case Decode.decodeString Departure.idDecoder ("\"" ++ raw ++ "\"") of
        Ok id ->
            id

        Err _ ->
            Debug.todo ("not a departure id in a test: " ++ raw)


{-| A point in time for a test, from ISO-8601 text.
-}
time : String -> Posix
time iso =
    case Iso8601.toTime iso of
        Ok posix ->
            posix

        Err _ ->
            Debug.todo ("not a timestamp in a test: " ++ iso)
