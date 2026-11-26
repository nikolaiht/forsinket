module Claim.History exposing (Entry, Event(..), decoder)

{-| What has happened to a claim, in order. These are the events the service
stores, so the history a passenger sees is the claim's actual record, not a
summary written for display.
-}

import Claim.Reason as Reason exposing (IneligibilityReason, RejectionReason, ReviewReason)
import Decoding
import Iso8601
import Json.Decode as Decode exposing (Decoder)
import Money exposing (Money)
import Time exposing (Posix)


type alias Entry =
    { at : Posix
    , event : Event
    }


type Event
    = Submitted
    | ApprovedAutomatically
    | RejectedAutomatically IneligibilityReason
    | SentToReview ( ReviewReason, List ReviewReason )
    | ApprovedByOfficer { officer : String, approvedExpenses : Money, note : String }
    | RejectedByOfficer { officer : String, reason : RejectionReason, note : String }
    | PayoutRecorded


decoder : Decoder Entry
decoder =
    Decode.map2 Entry
        (Decode.field "at" Iso8601.decoder)
        eventDecoder


eventDecoder : Decoder Event
eventDecoder =
    Decoding.tagged "history entry"
        [ ( "submitted", Decode.succeed Submitted )
        , ( "approved_automatically", Decode.succeed ApprovedAutomatically )
        , ( "rejected_automatically"
          , Decode.map RejectedAutomatically (Decode.field "reason" Reason.ineligibilityDecoder)
          )
        , ( "sent_to_review"
          , Decode.map SentToReview (Decode.field "reasons" (Decoding.nonEmptyList Reason.reviewDecoder))
          )
        , ( "approved_by_officer"
          , Decode.map3 (\officer approvedExpenses note -> ApprovedByOfficer { officer = officer, approvedExpenses = approvedExpenses, note = note })
                (Decode.field "officer" Decode.string)
                (Decode.field "approvedExpenses" Money.decoder)
                (Decode.field "note" Decode.string)
          )
        , ( "rejected_by_officer"
          , Decode.map3 (\officer reason note -> RejectedByOfficer { officer = officer, reason = reason, note = note })
                (Decode.field "officer" Decode.string)
                (Decode.field "reason" Reason.rejectionDecoder)
                (Decode.field "note" Decode.string)
          )
        , ( "payout_recorded", Decode.succeed PayoutRecorded )
        ]
