module Departure exposing (Departure, Id, Outcome(..), decoder, encodeId, idDecoder, idToString, outcomeDecoder)

{-| A departure, and what happened to it.
-}

import Date exposing (Date)
import Decoding
import Json.Decode as Decode exposing (Decoder)
import Json.Encode as Encode


type alias Departure =
    { id : Id
    , date : Date
    , trainNumber : String
    , origin : String
    , destination : String
    , scheduledDeparture : String
    , outcome : Outcome
    }


{-| The id of a departure. The app never makes one up: every `Id` it holds was
decoded from an answer from the service, which is the only way to get one.
-}
type Id
    = Id String


idToString : Id -> String
idToString (Id id) =
    id


idDecoder : Decoder Id
idDecoder =
    Decode.map Id Decode.string


encodeId : Id -> Encode.Value
encodeId (Id id) =
    Encode.string id


{-| A departure either ran, some minutes late or on time, or it was cancelled.
A cancelled departure has no delay, so it has no number of minutes.
-}
type Outcome
    = Ran Int
    | Cancelled


decoder : Decoder Departure
decoder =
    Decode.map7 Departure
        (Decode.field "id" idDecoder)
        (Decode.field "date" Decoding.date)
        (Decode.field "trainNumber" Decode.string)
        (Decode.field "origin" Decode.string)
        (Decode.field "destination" Decode.string)
        (Decode.field "scheduledDeparture" Decode.string)
        (Decode.field "outcome" outcomeDecoder)


outcomeDecoder : Decoder Outcome
outcomeDecoder =
    Decoding.tagged "outcome"
        [ ( "ran", Decode.map Ran (Decode.field "delayMinutes" Decode.int) )
        , ( "cancelled", Decode.succeed Cancelled )
        ]
