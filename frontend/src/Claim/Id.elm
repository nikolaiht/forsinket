module Claim.Id exposing (Id, decoder, fromString, toString)

{-| The id of a claim. It is opaque so that a claim id cannot be mixed up with
any other string, and so that every `Id` in the program is known to have the
shape of one: a UUID.
-}

import Json.Decode as Decode exposing (Decoder)


type Id
    = Id String


{-| An id from text, for example from the address bar. Text that does not have
the shape of a UUID cannot be the id of a claim, so there is no point in asking
the server about it.
-}
fromString : String -> Maybe Id
fromString raw =
    let
        lower : String
        lower =
            String.toLower raw
    in
    if List.map String.length (String.split "-" lower) == [ 8, 4, 4, 4, 12 ] && String.all isHexOrDash lower then
        Just (Id lower)

    else
        Nothing


isHexOrDash : Char -> Bool
isHexOrDash char =
    Char.isHexDigit char || char == '-'


toString : Id -> String
toString (Id id) =
    id


decoder : Decoder Id
decoder =
    Decode.string
        |> Decode.andThen
            (\raw ->
                case fromString raw of
                    Just id ->
                        Decode.succeed id

                    Nothing ->
                        Decode.fail ("A claim id is a UUID, but this is \"" ++ raw ++ "\".")
            )
