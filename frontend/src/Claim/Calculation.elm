module Claim.Calculation exposing
    ( Calculation, TicketValue(..), ExpenseAssessment(..), decoder
    , Assessment(..), Handling(..), assessmentDecoder
    )

{-| How an amount was arrived at, and what the rules say about a claim.

The app does no arithmetic on claims. The service calculates, and sends every
step with the amount that step gave. These types hold those steps so the app
can show them.

@docs Calculation, TicketValue, ExpenseAssessment, decoder
@docs Assessment, Handling, assessmentDecoder

-}

import Claim.Reason as Reason exposing (IneligibilityReason, ReviewReason)
import Decoding
import Departure exposing (Outcome)
import Json.Decode as Decode exposing (Decoder)
import Money exposing (Money)


type alias Calculation =
    { ruleSetVersion : String
    , ticketValue : TicketValue
    , outcome : Outcome
    , percent : Int
    , ticketCompensation : Money
    , expenses : ExpenseAssessment
    , total : Money
    }


{-| What one journey on the ticket is worth: the whole price of a single
ticket, or one day's share of a period ticket.
-}
type TicketValue
    = FullPrice Money
    | PerDay { price : Money, days : Int, value : Money }


{-| Where the claimed expenses stand. Each case has only the amounts that
exist in it: there is no approved amount before an officer has approved one.
-}
type ExpenseAssessment
    = NoneClaimed
    | NotCovered Money
    | PendingReview { claimed : Money, maxCoverable : Money }
    | Covered { claimed : Money, approved : Money }


decoder : Decoder Calculation
decoder =
    Decode.map7 Calculation
        (Decode.field "ruleSetVersion" Decode.string)
        (Decode.field "ticketValue" ticketValueDecoder)
        (Decode.field "outcome" Departure.outcomeDecoder)
        (Decode.field "percent" Decode.int)
        (Decode.field "ticketCompensation" Money.decoder)
        (Decode.field "expenses" expensesDecoder)
        (Decode.field "total" Money.decoder)


ticketValueDecoder : Decoder TicketValue
ticketValueDecoder =
    Decoding.tagged "ticket value"
        [ ( "full_price", Decode.map FullPrice (Decode.field "value" Money.decoder) )
        , ( "per_day"
          , Decode.map3 (\price days value -> PerDay { price = price, days = days, value = value })
                (Decode.field "price" Money.decoder)
                (Decode.field "days" Decode.int)
                (Decode.field "value" Money.decoder)
          )
        ]


expensesDecoder : Decoder ExpenseAssessment
expensesDecoder =
    Decoding.tagged "expense assessment"
        [ ( "none_claimed", Decode.succeed NoneClaimed )
        , ( "not_covered", Decode.map NotCovered (Decode.field "claimed" Money.decoder) )
        , ( "pending_review"
          , Decode.map2 (\claimed maxCoverable -> PendingReview { claimed = claimed, maxCoverable = maxCoverable })
                (Decode.field "claimed" Money.decoder)
                (Decode.field "maxCoverable" Money.decoder)
          )
        , ( "covered"
          , Decode.map2 (\claimed approved -> Covered { claimed = claimed, approved = approved })
                (Decode.field "claimed" Money.decoder)
                (Decode.field "approved" Money.decoder)
          )
        ]



-- ASSESSMENT


{-| What the rules say about a claim before it is submitted.
-}
type Assessment
    = Eligible Calculation Handling
    | NotEligible IneligibilityReason


{-| Who would decide the claim: the rules alone, or an officer, for at least one reason.
-}
type Handling
    = AutoApprove
    | ManualReview ( ReviewReason, List ReviewReason )


assessmentDecoder : Decoder Assessment
assessmentDecoder =
    Decoding.tagged "assessment"
        [ ( "eligible"
          , Decode.map2 Eligible
                (Decode.field "calculation" decoder)
                (Decode.field "handling" handlingDecoder)
          )
        , ( "not_eligible", Decode.map NotEligible (Decode.field "reason" Reason.ineligibilityDecoder) )
        ]


handlingDecoder : Decoder Handling
handlingDecoder =
    Decoding.tagged "handling"
        [ ( "auto_approve", Decode.succeed AutoApprove )
        , ( "manual_review"
          , Decode.map ManualReview (Decode.field "reasons" (Decoding.nonEmptyList Reason.reviewDecoder))
          )
        ]
