module Claim.Expenses exposing (Expenses, Kind(..), decoder, encode, kinds)

{-| What the passenger paid to get there another way.
-}

import Decoding
import Json.Decode as Decode exposing (Decoder)
import Json.Encode as Encode
import Money exposing (Money)


type alias Expenses =
    { amount : Money
    , kind : Kind
    }


type Kind
    = Taxi
    | Bus
    | Other


{-| Every kind, in the order the form offers them.
-}
kinds : List Kind
kinds =
    [ Taxi, Bus, Other ]


kindToString : Kind -> String
kindToString kind =
    case kind of
        Taxi ->
            "taxi"

        Bus ->
            "bus"

        Other ->
            "other"


decoder : Decoder Expenses
decoder =
    Decode.map2 Expenses
        (Decode.field "amount" Money.decoder)
        (Decode.field "kind" (Decoding.enum "kind of expense" (List.map (\kind -> ( kindToString kind, kind )) kinds)))


encode : Expenses -> Encode.Value
encode expenses =
    Encode.object
        [ ( "amount", Money.encode expenses.amount )
        , ( "kind", Encode.string (kindToString expenses.kind) )
        ]
