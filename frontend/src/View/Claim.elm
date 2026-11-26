module View.Claim exposing (view)

{-| A claim, laid out the same way for the passenger and for the officer:
where it stands, the journey, the calculation, and the record of what has
happened.
-}

import Claim exposing (Claim, DecidedBy(..), Rejection(..), Status(..))
import Claim.Calculation exposing (Calculation)
import Claim.Expenses exposing (Expenses)
import Html exposing (Html, blockquote, dd, div, dl, dt, h2, p, section, text)
import Html.Attributes exposing (class)
import Money
import View.Calculation
import View.Format as Format
import View.History
import View.Status
import View.Text as Text


view : Claim -> Html msg
view claim =
    div [ class "claim" ]
        [ section [ class "claim__status" ]
            (View.Status.badge (Claim.statusName claim.status) :: standing claim.status)
        , div [ class "claim__columns" ]
            (let
                journeySection : Html msg
                journeySection =
                    section []
                        [ h2 [] [ text "Reisen" ]
                        , journey claim
                        ]

                historySection : Html msg
                historySection =
                    section []
                        [ h2 [] [ text "Dette har skjedd" ]
                        , View.History.view claim
                        ]
             in
             case calculationOf claim.status of
                Just calculation ->
                    [ section []
                        [ h2 [] [ text "Slik er beløpet regnet ut" ]
                        , View.Calculation.view calculation
                        ]
                    , div [] [ journeySection, historySection ]
                    ]

                Nothing ->
                    [ journeySection, historySection ]
            )
        ]


{-| Where the claim stands, in a sentence or two. Each branch has exactly the
facts its status carries, so there is nothing here to guard against.
-}
standing : Status -> List (Html msg)
standing status =
    case status of
        Received ->
            [ p [] [ text "Kravet er mottatt og blir vurdert." ] ]

        AwaitingReview { reasons } ->
            [ p [] [ text ("Kravet venter på en saksbehandler fordi " ++ Text.reviewReasons reasons ++ ".") ] ]

        Approved { calculation, by, decidedAt } ->
            p []
                [ text
                    ("Innvilget "
                        ++ Format.dateTime decidedAt
                        ++ ". Du får "
                        ++ Money.format calculation.total
                        ++ " tilbake på betalingsmåten du brukte da du kjøpte billetten."
                    )
                ]
                :: decidedBy by

        Rejected { rejection, decidedAt } ->
            case rejection of
                RejectedByRules reason ->
                    [ p [] [ text ("Avslått " ++ Format.dateTime decidedAt ++ ". " ++ Text.ineligibility reason) ] ]

                RejectedByOfficer { reason, officer, note } ->
                    [ p []
                        [ text
                            ("Avslått "
                                ++ Format.dateTime decidedAt
                                ++ " av saksbehandler "
                                ++ officer
                                ++ ". "
                                ++ Text.rejectionReason reason
                                ++ "."
                            )
                        ]
                    , blockquote [ class "claim__note" ] [ text note ]
                    ]

        PaidOut { calculation, by, paidAt } ->
            p [] [ text (Money.format calculation.total ++ " ble utbetalt " ++ Format.dateTime paidAt ++ ".") ]
                :: decidedBy by


decidedBy : DecidedBy -> List (Html msg)
decidedBy by =
    case by of
        ByRules ->
            [ p [ class "claim__by" ] [ text "Avgjort automatisk etter reglene." ] ]

        ByOfficer { officer, note } ->
            p [ class "claim__by" ] [ text ("Avgjort av saksbehandler " ++ officer ++ ".") ]
                :: (if String.isEmpty note then
                        []

                    else
                        [ blockquote [ class "claim__note" ] [ text note ] ]
                   )


calculationOf : Status -> Maybe Calculation
calculationOf status =
    case status of
        AwaitingReview { calculation } ->
            Just calculation

        Approved { calculation } ->
            Just calculation

        PaidOut { calculation } ->
            Just calculation

        Received ->
            Nothing

        Rejected _ ->
            Nothing


journey : Claim -> Html msg
journey claim =
    dl [ class "facts" ]
        [ fact "Avgang" (claim.departure.trainNumber ++ " " ++ Format.date claim.departure.date ++ " kl. " ++ claim.departure.scheduledDeparture)
        , fact "Strekning" (claim.departure.origin ++ " – " ++ claim.departure.destination)
        , fact "Registrert" (Format.outcome claim.departure.outcome)
        , fact "Billett" (Text.ticket claim.ticket)
        , fact "Utlegg" (expensesText claim.expenses)
        ]


expensesText : Maybe Expenses -> String
expensesText expenses =
    case expenses of
        Just { amount, kind } ->
            Text.expenseKind kind ++ ", " ++ Money.format amount

        Nothing ->
            "Ingen"


fact : String -> String -> Html msg
fact label value =
    div [ class "facts__row" ]
        [ dt [] [ text label ]
        , dd [] [ text value ]
        ]
