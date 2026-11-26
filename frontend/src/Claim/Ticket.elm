module Claim.Ticket exposing (Ticket(..), Validity(..), decoder, encode, validityDays)

{-| What the passenger travelled on.

A single ticket has a price. A period ticket has a price and a validity. There
is no ticket with a validity and no price, and no single ticket with a
validity, because the type has no way to write one.

-}

import Decoding
import Json.Decode as Decode exposing (Decoder)
import Json.Encode as Encode
import Money exposing (Money)


type Ticket
    = Single Money
    | Period Money Validity


type Validity
    = SevenDays
    | ThirtyDays


validityDays : Validity -> Int
validityDays validity =
    case validity of
        SevenDays ->
            7

        ThirtyDays ->
            30


decoder : Decoder Ticket
decoder =
    Decoding.tagged "ticket"
        [ ( "single", Decode.map Single (Decode.field "price" Money.decoder) )
        , ( "period"
          , Decode.map2 Period
                (Decode.field "price" Money.decoder)
                (Decode.field "validityDays" validityDecoder)
          )
        ]


validityDecoder : Decoder Validity
validityDecoder =
    Decode.int
        |> Decode.andThen
            (\days ->
                case List.filter (\validity -> validityDays validity == days) [ SevenDays, ThirtyDays ] of
                    validity :: _ ->
                        Decode.succeed validity

                    [] ->
                        Decode.fail ("No ticket is valid for " ++ String.fromInt days ++ " days.")
            )


encode : Ticket -> Encode.Value
encode ticket =
    case ticket of
        Single price ->
            Encode.object
                [ ( "type", Encode.string "single" )
                , ( "price", Money.encode price )
                ]

        Period price validity ->
            Encode.object
                [ ( "type", Encode.string "period" )
                , ( "price", Money.encode price )
                , ( "validityDays", Encode.int (validityDays validity) )
                ]
