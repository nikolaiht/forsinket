module Money exposing
    ( Money, zero, fromOre, toOre
    , ParseError(..), parse, format
    , decoder, encode
    )

{-| An amount of money in whole øre.

The type is opaque, so the only ways to get a `Money` are the ones below, and
none of them gives a negative amount or a fraction of an øre. Code that has a
`Money` does not have to check it again.

@docs Money, zero, fromOre, toOre
@docs ParseError, parse, format
@docs decoder, encode

-}

import Json.Decode as Decode exposing (Decoder)
import Json.Encode as Encode


type Money
    = Money Int


zero : Money
zero =
    Money 0


{-| An amount from a number of øre, when there is such an amount: a negative
number is not one.
-}
fromOre : Int -> Maybe Money
fromOre ore =
    if ore < 0 then
        Nothing

    else
        Just (Money ore)


toOre : Money -> Int
toOre (Money ore) =
    ore



-- TEXT


type ParseError
    = Empty
    | NotAnAmount


{-| Read an amount the way people type it: `349`, `349,50`, `349.50`,
`1 234,50`, `349 kr`, `kr 349` or `349,-`.

Spaces are ignored, so is `kr` before or after, and both comma and full stop
work as the decimal sign. Anything else is not an amount: a sign, letters, more
than two decimals, or more digits than any ticket could cost.

-}
parse : String -> Result ParseError Money
parse input =
    let
        withoutSpaces : String
        withoutSpaces =
            String.filter (not << isSpace) input
    in
    if String.isEmpty withoutSpaces then
        Err Empty

    else
        case String.split "," (String.replace "." "," (withoutUnit withoutSpaces)) of
            [ kroner ] ->
                fromParts kroner "00"

            [ kroner, "-" ] ->
                -- "349,-" is how a price in whole kroner is written on a ticket.
                fromParts kroner "00"

            [ kroner, ore ] ->
                if String.isEmpty ore then
                    -- "5," has a decimal sign and nothing after it.
                    Err NotAnAmount

                else
                    fromParts kroner (String.padRight 2 '0' ore)

            _ ->
                Err NotAnAmount


fromParts : String -> String -> Result ParseError Money
fromParts kroner ore =
    if isDigits kroner && String.length kroner <= maxKronerDigits && isDigits ore && String.length ore == 2 then
        Maybe.map2 (\k o -> Money (k * 100 + o)) (String.toInt kroner) (String.toInt ore)
            |> Result.fromMaybe NotAnAmount

    else
        Err NotAnAmount


{-| Nine digits of kroner is far more than any ticket, and far less than the
largest whole number JavaScript can hold exactly.
-}
maxKronerDigits : Int
maxKronerDigits =
    9


{-| `String.toInt` would accept "+5" and "-5", and `Char.isDigit` only accepts
0 to 9, so this is the check that keeps signs and other scripts' digits out.
-}
isDigits : String -> Bool
isDigits text =
    not (String.isEmpty text) && String.all Char.isDigit text


isSpace : Char -> Bool
isSpace char =
    char == ' ' || char == nonBreakingSpace || char == '\t' || char == '\u{202F}'


{-| `kr` in front or behind, but not both.
-}
withoutUnit : String -> String
withoutUnit text =
    let
        lower : String
        lower =
            String.toLower text
    in
    if String.startsWith "kr" lower then
        String.dropLeft 2 text

    else if String.endsWith "kr" lower then
        String.dropRight 2 text

    else
        text


{-| Write an amount the Norwegian way: `1 234,50 kr`. The spaces are
non-breaking, so an amount is never split across two lines.
-}
format : Money -> String
format (Money ore) =
    let
        kroner : String
        kroner =
            String.fromInt (ore // 100)

        decimals : String
        decimals =
            String.padLeft 2 '0' (String.fromInt (modBy 100 ore))
    in
    groupThousands kroner ++ "," ++ decimals ++ String.fromChar nonBreakingSpace ++ "kr"


groupThousands : String -> String
groupThousands digits =
    if String.length digits <= 3 then
        digits

    else
        groupThousands (String.dropRight 3 digits)
            ++ String.fromChar nonBreakingSpace
            ++ String.right 3 digits


nonBreakingSpace : Char
nonBreakingSpace =
    '\u{00A0}'



-- JSON


{-| On the wire an amount is a whole, non-negative number of øre.
-}
decoder : Decoder Money
decoder =
    Decode.int
        |> Decode.andThen
            (\ore ->
                if ore < 0 then
                    Decode.fail ("An amount cannot be negative, but this one is " ++ String.fromInt ore ++ " øre.")

                else
                    Decode.succeed (Money ore)
            )


encode : Money -> Encode.Value
encode (Money ore) =
    Encode.int ore
