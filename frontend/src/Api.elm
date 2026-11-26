module Api exposing
    ( Error(..), errorFromResponse
    , getRules, getExamples, getDepartures, getClaim, getClaims
    , postAssessment, postClaim, postDecision, postPayout, encodePayout
    )

{-| Talking to the service.

Every request ends in a `Result Error a`. The `Error` type tells apart the
things a user can act on differently: no connection, a claim that is gone,
values the service will not accept, a claim someone else got to first.

@docs Error, errorFromResponse
@docs getRules, getExamples, getDepartures, getClaim, getClaims
@docs postAssessment, postClaim, postDecision, postPayout, encodePayout

-}

import Claim exposing (Claim)
import Claim.Calculation as Calculation exposing (Assessment)
import Claim.Decision as Decision exposing (Decision)
import Claim.Draft as Draft exposing (NewClaim)
import Claim.Id as Id exposing (Id)
import Date exposing (Date)
import Departure exposing (Departure)
import Example exposing (Example)
import FieldError exposing (FieldError)
import Http
import Json.Decode as Decode exposing (Decoder)
import Json.Encode as Encode
import Rules exposing (Rules)
import Status
import Url.Builder as Builder


type Error
    = Offline
    | Timeout
    | NotFound
    | Invalid (List FieldError)
    | VersionConflict
    | InvalidTransition
    | DemoLimitReached
    | Unexpected String


{-| What a response means.

`Http.expectJson` throws away the body of a response with a bad status, and
with it the service's own account of what went wrong. This reads the body in
both cases: as the expected value when the status is good, and as one of the
service's errors when it is not. Anything that is neither becomes
`Unexpected`, with enough detail to find out why.

-}
errorFromResponse : Decoder a -> Http.Response String -> Result Error a
errorFromResponse decoder response =
    case response of
        Http.GoodStatus_ _ body ->
            Decode.decodeString decoder body
                |> Result.mapError (Decode.errorToString >> Unexpected)

        Http.BadStatus_ metadata body ->
            Decode.decodeString errorDecoder body
                |> Result.withDefault
                    (Unexpected
                        ("The server answered "
                            ++ String.fromInt metadata.statusCode
                            ++ " "
                            ++ metadata.statusText
                            ++ "."
                        )
                    )
                |> Err

        Http.NetworkError_ ->
            Err Offline

        Http.Timeout_ ->
            Err Timeout

        Http.BadUrl_ url ->
            Err (Unexpected ("The address " ++ url ++ " is not valid."))


errorDecoder : Decoder Error
errorDecoder =
    Decode.field "type" Decode.string
        |> Decode.andThen
            (\errorType ->
                case errorType of
                    "validation" ->
                        Decode.map Invalid (Decode.field "errors" (Decode.list FieldError.decoder))

                    "not_found" ->
                        Decode.succeed NotFound

                    "version_conflict" ->
                        Decode.succeed VersionConflict

                    "invalid_transition" ->
                        Decode.succeed InvalidTransition

                    "demo_limit_reached" ->
                        Decode.succeed DemoLimitReached

                    "malformed_request" ->
                        Decode.map Unexpected (Decode.field "detail" Decode.string)

                    "internal_error" ->
                        Decode.succeed (Unexpected "The server reported an internal error.")

                    _ ->
                        Decode.fail ("Unknown type of error: \"" ++ errorType ++ "\".")
            )



-- REQUESTS


getRules : (Result Error Rules -> msg) -> Cmd msg
getRules toMsg =
    get [ "rules" ] [] Rules.decoder toMsg


getExamples : (Result Error (List Example) -> msg) -> Cmd msg
getExamples toMsg =
    get [ "examples" ] [] (Decode.list Example.decoder) toMsg


getDepartures : Date -> (Result Error (List Departure) -> msg) -> Cmd msg
getDepartures date toMsg =
    get [ "departures" ] [ Builder.string "date" (Date.toIsoString date) ] (Decode.list Departure.decoder) toMsg


getClaim : Id -> (Result Error Claim -> msg) -> Cmd msg
getClaim id toMsg =
    get [ "claims", Id.toString id ] [] Claim.decoder toMsg


{-| Summaries of the claims with a given status, or of all of them.
-}
getClaims : Maybe Status.Name -> (Result Error (List Claim.Summary) -> msg) -> Cmd msg
getClaims status toMsg =
    let
        parameters : List Builder.QueryParameter
        parameters =
            status
                |> Maybe.map (\name -> [ Builder.string "status" (Status.nameToString name) ])
                |> Maybe.withDefault []
    in
    get [ "claims" ] parameters (Decode.list Claim.summaryDecoder) toMsg


{-| Ask what the rules would say about a claim. Nothing is stored.
-}
postAssessment : NewClaim -> (Result Error Assessment -> msg) -> Cmd msg
postAssessment claim toMsg =
    post [ "assessments" ] (Draft.encode claim) Calculation.assessmentDecoder toMsg


postClaim : NewClaim -> (Result Error Claim -> msg) -> Cmd msg
postClaim claim toMsg =
    post [ "claims" ] (Draft.encode claim) Claim.decoder toMsg


{-| Every change to a claim says which version of it the change was made on.
If someone else has changed the claim since, the service answers
`VersionConflict` and nothing is overwritten.
-}
postDecision : Id -> Int -> Decision -> (Result Error Claim -> msg) -> Cmd msg
postDecision id expectedVersion decision toMsg =
    post [ "claims", Id.toString id, "decision" ] (Decision.encode expectedVersion decision) Claim.decoder toMsg


postPayout : Id -> Int -> (Result Error Claim -> msg) -> Cmd msg
postPayout id expectedVersion toMsg =
    post [ "claims", Id.toString id, "payout" ] (encodePayout expectedVersion) Claim.decoder toMsg


encodePayout : Int -> Encode.Value
encodePayout expectedVersion =
    Encode.object [ ( "expectedVersion", Encode.int expectedVersion ) ]


get : List String -> List Builder.QueryParameter -> Decoder a -> (Result Error a -> msg) -> Cmd msg
get path parameters decoder toMsg =
    request "GET" (Builder.absolute ("api" :: path) parameters) Http.emptyBody decoder toMsg


post : List String -> Encode.Value -> Decoder a -> (Result Error a -> msg) -> Cmd msg
post path body decoder toMsg =
    request "POST" (Builder.absolute ("api" :: path) []) (Http.jsonBody body) decoder toMsg


request : String -> String -> Http.Body -> Decoder a -> (Result Error a -> msg) -> Cmd msg
request method url body decoder toMsg =
    Http.request
        { method = method
        , headers = []
        , url = url
        , body = body
        , expect = Http.expectStringResponse toMsg (errorFromResponse decoder)
        , timeout = Just timeoutInMilliseconds
        , tracker = Nothing
        }


{-| Without a timeout a request that never gets an answer leaves the page
loading for ever, and `Timeout` could never happen.
-}
timeoutInMilliseconds : Float
timeoutInMilliseconds =
    15000
