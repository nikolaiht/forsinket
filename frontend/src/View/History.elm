module View.History exposing (view)

import Claim.History as History exposing (Event(..))
import Html exposing (Html, blockquote, li, ol, p, text)
import Html.Attributes exposing (class)
import Money
import Time
import View.Format as Format
import View.Text as Text


{-| The claim's record, oldest first: the events the service has stored.
-}
view : Time.Zone -> List History.Entry -> Html msg
view zone entries =
    ol [ class "history" ] (List.map (entry zone) entries)


entry : Time.Zone -> History.Entry -> Html msg
entry zone { at, event } =
    li [ class "history__entry" ]
        (Html.time [ class "history__time" ] [ text (Format.dateTime zone at) ]
            :: p [ class "history__what" ] [ text (describe event) ]
            :: (case note event of
                    Just words ->
                        [ blockquote [ class "history__note" ] [ text words ] ]

                    Nothing ->
                        []
               )
        )


describe : Event -> String
describe event =
    case event of
        Submitted ->
            "Kravet ble mottatt."

        ApprovedAutomatically ->
            "Innvilget automatisk etter reglene."

        RejectedAutomatically reason ->
            "Avslått automatisk. " ++ Text.ineligibility reason

        SentToReview ( first, rest ) ->
            "Sendt til saksbehandler, fordi "
                ++ String.join " og " (List.map Text.reviewReason (first :: rest))
                ++ "."

        ApprovedByOfficer { officer, approvedExpenses } ->
            "Innvilget av saksbehandler " ++ officer ++ ". Godkjent utlegg: " ++ Money.format approvedExpenses ++ "."

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
