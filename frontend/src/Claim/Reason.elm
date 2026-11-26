module Claim.Reason exposing
    ( IneligibilityReason(..), ineligibilityDecoder
    , ReviewReason(..), reviewDecoder
    , RejectionReason(..), rejectionDecoder, rejectionReasons, rejectionToString
    )

{-| The reasons the service gives: why the rules turned a claim down, why a
claim went to an officer, and why an officer rejected it.

@docs IneligibilityReason, ineligibilityDecoder
@docs ReviewReason, reviewDecoder
@docs RejectionReason, rejectionDecoder, rejectionReasons, rejectionToString

-}

import Decoding
import Json.Decode exposing (Decoder)


type IneligibilityReason
    = SubmittedTooLate
    | DelayBelowThreshold


ineligibilityDecoder : Decoder IneligibilityReason
ineligibilityDecoder =
    Decoding.enum "reason a claim is not eligible"
        [ ( "submitted_too_late", SubmittedTooLate )
        , ( "delay_below_threshold", DelayBelowThreshold )
        ]


type ReviewReason
    = ExpensesClaimed
    | AboveAutoApprovalLimit


reviewDecoder : Decoder ReviewReason
reviewDecoder =
    Decoding.enum "reason for review"
        [ ( "expenses_claimed", ExpensesClaimed )
        , ( "above_auto_approval_limit", AboveAutoApprovalLimit )
        ]


type RejectionReason
    = InvalidTicket
    | DuplicateClaim
    | OtherReason


{-| Every reason an officer can choose, in the order the form offers them.
-}
rejectionReasons : List RejectionReason
rejectionReasons =
    [ InvalidTicket, DuplicateClaim, OtherReason ]


{-| The reason as the API writes it.
-}
rejectionToString : RejectionReason -> String
rejectionToString reason =
    case reason of
        InvalidTicket ->
            "invalid_ticket"

        DuplicateClaim ->
            "duplicate_claim"

        OtherReason ->
            "other"


rejectionDecoder : Decoder RejectionReason
rejectionDecoder =
    Decoding.enum "rejection reason"
        (List.map (\reason -> ( rejectionToString reason, reason )) rejectionReasons)
