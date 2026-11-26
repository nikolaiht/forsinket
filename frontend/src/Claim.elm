module Claim exposing
    ( Claim, Status(..), DecidedBy(..), Rejection(..), decoder, statusName
    , Summary, summaryDecoder
    )

{-| A claim, as the service describes it.

@docs Claim, Status, DecidedBy, Rejection, decoder, statusName
@docs Summary, summaryDecoder

-}

import Claim.Calculation as Calculation exposing (Calculation)
import Claim.Expenses as Expenses exposing (Expenses)
import Claim.History as History
import Claim.Id as Id exposing (Id)
import Claim.Reason as Reason exposing (IneligibilityReason, RejectionReason, ReviewReason)
import Claim.Ticket as Ticket exposing (Ticket)
import Date exposing (Date)
import Decoding
import Departure exposing (Departure)
import Iso8601
import Json.Decode as Decode exposing (Decoder)
import Money exposing (Money)
import Status
import Time exposing (Posix)


type alias Claim =
    { id : Id
    , version : Int
    , submittedAt : Posix
    , departure : Departure
    , ticket : Ticket
    , expenses : Maybe Expenses
    , status : Status
    , history : List History.Entry
    }


{-| Where a claim stands, with the data that exists at that point and no
other.

A record with a status field and a handful of `Maybe`s could describe a
rejected claim that has a payout time, or an approved claim that nobody
approved. This type cannot. A view that has matched on `Approved` has a
calculation and a decision in its hands, and never has to ask whether they are
there.

-}
type Status
    = Received
    | AwaitingReview { calculation : Calculation, reasons : ( ReviewReason, List ReviewReason ) }
    | Approved { calculation : Calculation, by : DecidedBy, decidedAt : Posix }
    | Rejected { rejection : Rejection, decidedAt : Posix }
    | PaidOut { calculation : Calculation, by : DecidedBy, decidedAt : Posix, paidAt : Posix }


type DecidedBy
    = ByRules
    | ByOfficer { officer : String, note : String }


type Rejection
    = RejectedByRules IneligibilityReason
    | RejectedByOfficer { reason : RejectionReason, officer : String, note : String }


statusName : Status -> Status.Name
statusName status =
    case status of
        Received ->
            Status.Received

        AwaitingReview _ ->
            Status.AwaitingReview

        Approved _ ->
            Status.Approved

        Rejected _ ->
            Status.Rejected

        PaidOut _ ->
            Status.PaidOut


decoder : Decoder Claim
decoder =
    Decode.map8 Claim
        (Decode.field "id" Id.decoder)
        (Decode.field "version" Decode.int)
        (Decode.field "submittedAt" Iso8601.decoder)
        (Decode.field "departure" Departure.decoder)
        (Decode.field "ticket" Ticket.decoder)
        (Decode.field "expenses" (Decode.nullable Expenses.decoder))
        (Decode.field "status" statusDecoder)
        (Decode.field "history" (Decode.list History.decoder))


statusDecoder : Decoder Status
statusDecoder =
    Decoding.tagged "status"
        [ ( "received", Decode.succeed Received )
        , ( "awaiting_review"
          , Decode.map2 (\calculation reasons -> AwaitingReview { calculation = calculation, reasons = reasons })
                (Decode.field "calculation" Calculation.decoder)
                (Decode.field "reasons" (Decoding.nonEmptyList Reason.reviewDecoder))
          )
        , ( "approved"
          , Decode.map3 (\calculation by decidedAt -> Approved { calculation = calculation, by = by, decidedAt = decidedAt })
                (Decode.field "calculation" Calculation.decoder)
                (Decode.field "by" decidedByDecoder)
                (Decode.field "decidedAt" Iso8601.decoder)
          )
        , ( "rejected"
          , Decode.map2 (\rejection decidedAt -> Rejected { rejection = rejection, decidedAt = decidedAt })
                (Decode.field "rejection" rejectionDecoder)
                (Decode.field "decidedAt" Iso8601.decoder)
          )
        , ( "paid_out"
          , Decode.map4 (\calculation by decidedAt paidAt -> PaidOut { calculation = calculation, by = by, decidedAt = decidedAt, paidAt = paidAt })
                (Decode.field "calculation" Calculation.decoder)
                (Decode.field "by" decidedByDecoder)
                (Decode.field "decidedAt" Iso8601.decoder)
                (Decode.field "paidAt" Iso8601.decoder)
          )
        ]


decidedByDecoder : Decoder DecidedBy
decidedByDecoder =
    Decoding.tagged "decision maker"
        [ ( "rules", Decode.succeed ByRules )
        , ( "officer"
          , Decode.map2 (\officer note -> ByOfficer { officer = officer, note = note })
                (Decode.field "officer" Decode.string)
                (Decode.field "note" Decode.string)
          )
        ]


rejectionDecoder : Decoder Rejection
rejectionDecoder =
    Decoding.tagged "rejection"
        [ ( "rules", Decode.map RejectedByRules (Decode.field "reason" Reason.ineligibilityDecoder) )
        , ( "officer"
          , Decode.map3 (\reason officer note -> RejectedByOfficer { reason = reason, officer = officer, note = note })
                (Decode.field "reason" Reason.rejectionDecoder)
                (Decode.field "officer" Decode.string)
                (Decode.field "note" Decode.string)
          )
        ]



-- SUMMARY


{-| One row in the list of claims.
-}
type alias Summary =
    { id : Id
    , version : Int
    , status : Status.Name
    , submittedAt : Posix
    , departureDate : Date
    , trainNumber : String
    , total : Maybe Money
    }


summaryDecoder : Decoder Summary
summaryDecoder =
    Decode.map7 Summary
        (Decode.field "id" Id.decoder)
        (Decode.field "version" Decode.int)
        (Decode.field "status" Status.nameDecoder)
        (Decode.field "submittedAt" Iso8601.decoder)
        (Decode.field "departureDate" Decoding.date)
        (Decode.field "trainNumber" Decode.string)
        (Decode.field "total" (Decode.nullable Money.decoder))
