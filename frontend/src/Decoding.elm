module Decoding exposing (date, enum, nonEmptyList, tagged)

{-| Four shapes the service's JSON uses again and again, so that every
decoder for them fails the same way: loudly, with the value it did not know.
-}

import Date exposing (Date)
import Json.Decode as Decode exposing (Decoder)


{-| A value that can take several shapes is an object with a `"type"` field
that says which. Each shape has its own decoder for the rest of the object.

A type that is not in the list makes the decoder fail. A new variant on the
server is then an error the user is told about, not a claim quietly shown as
something it is not.

-}
tagged : String -> List ( String, Decoder a ) -> Decoder a
tagged what variants =
    Decode.field "type" Decode.string
        |> Decode.andThen
            (\tag ->
                case lookup tag variants of
                    Just decoder ->
                        decoder

                    Nothing ->
                        Decode.fail ("Unknown type of " ++ what ++ ": \"" ++ tag ++ "\".")
            )


{-| One of a fixed set of strings.
-}
enum : String -> List ( String, a ) -> Decoder a
enum what values =
    Decode.string
        |> Decode.andThen
            (\raw ->
                case lookup raw values of
                    Just value ->
                        Decode.succeed value

                    Nothing ->
                        Decode.fail ("Unknown " ++ what ++ ": \"" ++ raw ++ "\".")
            )


{-| A list that the service promises has at least one element, as a pair of
the first and the rest. Code that gets the pair never has to ask what to do
with an empty list.
-}
nonEmptyList : Decoder a -> Decoder ( a, List a )
nonEmptyList decoder =
    Decode.list decoder
        |> Decode.andThen
            (\items ->
                case items of
                    first :: rest ->
                        Decode.succeed ( first, rest )

                    [] ->
                        Decode.fail "Expected at least one element, but the list is empty."
            )


{-| A calendar date, written `2026-11-20`.
-}
date : Decoder Date
date =
    Decode.string
        |> Decode.andThen
            (\raw ->
                case Date.fromIsoString raw of
                    Ok parsed ->
                        Decode.succeed parsed

                    Err problem ->
                        Decode.fail ("\"" ++ raw ++ "\" is not a date: " ++ problem)
            )


lookup : String -> List ( String, a ) -> Maybe a
lookup key pairs =
    List.filter (\( candidate, _ ) -> candidate == key) pairs
        |> List.head
        |> Maybe.map Tuple.second
