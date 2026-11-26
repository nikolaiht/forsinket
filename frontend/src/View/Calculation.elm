module View.Calculation exposing (assessment, view)

{-| The calculation, shown as the service sent it: one row per step, each
with the amount that step gave. Nothing is worked out here. The app only
writes down what the rules did, so the page cannot disagree with the payout.
-}

import Claim.Calculation exposing (Assessment(..), Calculation, ExpenseAssessment(..), Handling(..), TicketValue(..))
import Departure exposing (Outcome(..))
import Html exposing (Html, dd, div, dl, dt, p, span, text)
import Html.Attributes exposing (class)
import Money
import View.Format as Format
import View.Text as Text


view : Calculation -> Html msg
view calculation =
    div [ class "receipt" ]
        [ dl [ class "receipt__rows" ]
            (List.concat
                [ [ ticketValueRow calculation.ticketValue
                  , row "Forsinkelse"
                        (Just (outcomeExplanation calculation))
                        (String.fromInt calculation.percent ++ "\u{00A0}%")
                  , row "Erstatning for billetten" Nothing (Money.format calculation.ticketCompensation)
                  ]
                , expensesRows calculation.expenses
                , [ div [ class "receipt__row receipt__row--total" ]
                        [ dt [] [ text "Sum" ]
                        , dd [] [ text (Money.format calculation.total) ]
                        ]
                  ]
                ]
            )
        , p [ class "receipt__foot" ]
            [ text ("Regnet ut etter Tindbanens reisevilkår (" ++ calculation.ruleSetVersion ++ ").") ]
        ]


ticketValueRow : TicketValue -> Html msg
ticketValueRow ticketValue =
    case ticketValue of
        FullPrice value ->
            row "Billettverdi" (Just "Hele prisen på enkeltbilletten") (Money.format value)

        PerDay { price, days, value } ->
            row "Billettverdi"
                (Just (Money.format price ++ " delt på " ++ String.fromInt days ++ " dager"))
                (Money.format value)


outcomeExplanation : Calculation -> String
outcomeExplanation calculation =
    case calculation.outcome of
        Ran delay ->
            Format.minutes delay ++ " forsinket gir " ++ String.fromInt calculation.percent ++ " % av billettverdien"

        Cancelled ->
            "Innstilt avgang gir " ++ String.fromInt calculation.percent ++ " % av billettverdien"


expensesRows : ExpenseAssessment -> List (Html msg)
expensesRows expenses =
    case expenses of
        NoneClaimed ->
            []

        NotCovered claimed ->
            [ row "Utlegg"
                (Just ("Krevd " ++ Money.format claimed ++ ". Dekkes ikke fordi forsinkelsen er for kort."))
                (Money.format Money.zero)
            ]

        PendingReview { claimed, maxCoverable } ->
            [ row "Utlegg"
                (Just
                    ("Krevd "
                        ++ Money.format claimed
                        ++ ". En saksbehandler ser på kvitteringen og kan dekke inntil "
                        ++ Money.format maxCoverable
                        ++ "."
                    )
                )
                "Ikke vurdert"
            ]

        Covered { claimed, approved } ->
            [ row "Utlegg"
                (Just ("Krevd " ++ Money.format claimed ++ ". Godkjent av saksbehandler."))
                (Money.format approved)
            ]


row : String -> Maybe String -> String -> Html msg
row label explanation value =
    div [ class "receipt__row" ]
        [ dt []
            [ span [ class "receipt__label" ] [ text label ]
            , case explanation of
                Just words ->
                    span [ class "receipt__explanation" ] [ text words ]

                Nothing ->
                    text ""
            ]
        , dd [] [ text value ]
        ]


{-| What the rules say about a claim that has not been sent yet.
-}
assessment : Assessment -> Html msg
assessment value =
    case value of
        NotEligible reason ->
            p [ class "verdict verdict--no" ] [ text ("Ingen erstatning. " ++ Text.ineligibility reason) ]

        Eligible calculation handling ->
            div []
                [ view calculation
                , p [ class "verdict" ] [ text (handlingText handling) ]
                ]


handlingText : Handling -> String
handlingText handling =
    case handling of
        AutoApprove ->
            "Kravet innvilges med en gang."

        ManualReview reasons ->
            "Kravet går til en saksbehandler fordi " ++ Text.reviewReasons reasons ++ "."
