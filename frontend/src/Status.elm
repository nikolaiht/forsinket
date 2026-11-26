module Status exposing (Name(..), allNames, nameDecoder, nameToString)

{-| The name of a claim's status, on its own.

A claim's full status carries data that differs from status to status, and
lives in `Claim`. This is just the name, for the places that only need that:
the list of claims, and the filter in its address.

-}

import Json.Decode as Decode exposing (Decoder)


type Name
    = Received
    | AwaitingReview
    | Approved
    | Rejected
    | PaidOut


allNames : List Name
allNames =
    [ Received, AwaitingReview, Approved, Rejected, PaidOut ]


{-| The name as the API writes it.
-}
nameToString : Name -> String
nameToString name =
    case name of
        Received ->
            "received"

        AwaitingReview ->
            "awaiting_review"

        Approved ->
            "approved"

        Rejected ->
            "rejected"

        PaidOut ->
            "paid_out"


nameDecoder : Decoder Name
nameDecoder =
    Decode.string
        |> Decode.andThen
            (\raw ->
                case List.filter (\name -> nameToString name == raw) allNames of
                    name :: _ ->
                        Decode.succeed name

                    [] ->
                        Decode.fail ("Unknown status \"" ++ raw ++ "\".")
            )
