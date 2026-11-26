module View.History exposing (view)

import Claim exposing (Claim)
import Claim.History as History exposing (Event(..))
import Html exposing (Html, blockquote, li, ol, p, text)
import Html.Attributes exposing (class, datetime)
import Money
import View.Format as Format
import View.Text as Text


{-| The claim's record, oldest first: the events the service has stored.
-}
view : Claim -> Html msg
view claim =
    ol [ class "history" ] (List.map (entry claim) claim.history)


entry : Claim -> History.Entry -> Html msg
entry claim { at, event } =
    li [ class "history__entry" ]
        (Html.time [ class "history__time", datetime (Format.machineTime at) ] [ text (Format.dateTime at) ]
            :: p [ class "history__what" ] [ text (describe claim event) ]
            :: (case note event of
                    Just words ->
                        [ blockquote [ class "history__note" ] [ text words ] ]

                    Nothing ->
                        []
               )
        )


describe : Claim -> Event -> String
describe claim event =
    case event of
        Submitted ->
            "Kravet ble mottatt."

        ApprovedAutomatically ->
            "Innvilget automatisk etter reglene."

        RejectedAutomatically reason ->
            "Avslått automatisk. " ++ Text.ineligibility reason

        SentToReview reasons ->
            "Sendt til saksbehandler fordi " ++ Text.reviewReasons reasons ++ "."

        ApprovedByOfficer { officer, approvedExpenses } ->
            "Innvilget av saksbehandler "
                ++ officer
                ++ "."
                ++ (case claim.expenses of
                        Just _ ->
                            " Godkjent utlegg: " ++ Money.format approvedExpenses ++ "."

                        Nothing ->
                            -- No expenses were claimed, so there is no approved amount to report.
                            ""
                   )

        RejectedByOfficer { officer, reason } ->
            "Avslått av saksbehandler " ++ officer ++ ". " ++ Text.rejectionReason reason ++ "."

        PayoutRecorded ->
            "Utbetalt."


{-| What the officer wrote, when an officer wrote something.
-}
note : Event -> Maybe String
note event =
    let
        ifWritten : String -> Maybe String
        ifWritten words =
            if String.isEmpty words then
                Nothing

            else
                Just words
    in
    case event of
        ApprovedByOfficer approval ->
            ifWritten approval.note

        RejectedByOfficer rejection ->
            ifWritten rejection.note

        _ ->
            Nothing
