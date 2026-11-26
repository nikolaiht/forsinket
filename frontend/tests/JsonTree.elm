module JsonTree exposing (JsonTree, fromString, fromValue)

{-| JSON as a plain Elm value, so two pieces of JSON can be compared with
`Expect.equal` whatever order their fields were written in.
-}

import Dict exposing (Dict)
import Json.Decode as Decode exposing (Decoder)
import Json.Encode as Encode


type JsonTree
    = Null
    | Boolean Bool
    | Number Float
    | Text String
    | Array (List JsonTree)
    | Object (Dict String JsonTree)


fromString : String -> Result String JsonTree
fromString json =
    Decode.decodeString decoder json
        |> Result.mapError Decode.errorToString


fromValue : Encode.Value -> Result String JsonTree
fromValue value =
    Decode.decodeValue decoder value
        |> Result.mapError Decode.errorToString


decoder : Decoder JsonTree
decoder =
    Decode.oneOf
        [ Decode.null Null
        , Decode.map Boolean Decode.bool
        , Decode.map Number Decode.float
        , Decode.map Text Decode.string
        , Decode.map Array (Decode.list (Decode.lazy (\_ -> decoder)))
        , Decode.map Object (Decode.dict (Decode.lazy (\_ -> decoder)))
        ]
