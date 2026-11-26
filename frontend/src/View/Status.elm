module View.Status exposing (badge)

import Html exposing (Html, span, text)
import Html.Attributes exposing (class)
import Status
import View.Text as Text


badge : Status.Name -> Html msg
badge name =
    span [ class ("status status--" ++ modifier name) ] [ text (Text.status name) ]


modifier : Status.Name -> String
modifier name =
    case name of
        Status.Received ->
            "received"

        Status.AwaitingReview ->
            "awaiting"

        Status.Approved ->
            "approved"

        Status.Rejected ->
            "rejected"

        Status.PaidOut ->
            "paid"
