module ApiTest exposing (suite)

{-| What the app makes of every kind of answer the service, or the network,
can give. The user sees a message for each of these, so each has to be told
apart from the others.
-}

import Api exposing (Error(..))
import Contract.Examples as Examples
import Dict
import Expect
import FieldError exposing (Field(..), Problem(..))
import Http
import Rules
import Test exposing (Test, describe, test)


suite : Test
suite =
    describe "Api.errorFromResponse"
        [ describe "the request never got an answer"
            [ test "no connection" <|
                \_ ->
                    read Http.NetworkError_
                        |> Expect.equal (Err Offline)
            , test "the answer took too long" <|
                \_ ->
                    read Http.Timeout_
                        |> Expect.equal (Err Timeout)
            ]
        , describe "the service said no"
            [ test "not found" <|
                \_ ->
                    read (badStatus 404 Examples.errorNotFound)
                        |> Expect.equal (Err NotFound)
            , test "validation errors keep their field and their problem" <|
                \_ ->
                    read (badStatus 422 Examples.errorValidation)
                        |> Expect.equal
                            (Err
                                (Invalid
                                    [ { field = DepartureField, problem = UnknownDeparture }
                                    , { field = PriceField, problem = MustBePositive }
                                    , { field = ValidityField, problem = UnsupportedValidity }
                                    , { field = ExpensesKindField, problem = UnknownValue }
                                    ]
                                )
                            )
            , test "a field or a problem the app does not know is kept, not dropped" <|
                \_ ->
                    read (badStatus 422 """{"type":"validation","errors":[{"field":"ticket.zone","code":"not_served"}]}""")
                        |> Expect.equal
                            (Err (Invalid [ { field = OtherField "ticket.zone", problem = OtherProblem "not_served" } ]))
            , test "every field the service can name has a place in the forms" <|
                \_ ->
                    read
                        (badStatus 422
                            ("""{"type":"validation","errors":["""
                                ++ String.join ","
                                    (List.map (\field -> "{\"field\":\"" ++ field ++ "\",\"code\":\"required\"}")
                                        [ "departureId"
                                        , "ticket.price"
                                        , "ticket.validityDays"
                                        , "expenses.amount"
                                        , "expenses.kind"
                                        , "officer"
                                        , "note"
                                        , "decision.reason"
                                        , "decision.approvedExpenses"
                                        ]
                                    )
                                ++ "]}"
                            )
                        )
                        |> Result.mapError
                            (\error ->
                                case error of
                                    Invalid errors ->
                                        List.map .field errors

                                    _ ->
                                        []
                            )
                        |> Expect.equal
                            (Err
                                [ DepartureField
                                , PriceField
                                , ValidityField
                                , ExpensesAmountField
                                , ExpensesKindField
                                , OfficerField
                                , NoteField
                                , ReasonField
                                , ApprovedExpensesField
                                ]
                            )
            , test "someone else changed the claim first" <|
                \_ ->
                    read (badStatus 409 Examples.errorVersionConflict)
                        |> Expect.equal (Err (VersionConflict 3))
            , test "the claim's status does not allow it" <|
                \_ ->
                    read (badStatus 409 Examples.errorInvalidTransition)
                        |> Expect.equal (Err InvalidTransition)
            , test "the demo is full" <|
                \_ ->
                    read (badStatus 429 Examples.errorDemoLimitReached)
                        |> Expect.equal (Err DemoLimitReached)
            , test "a request the service could not read is a fault in the app, and says so" <|
                \_ ->
                    read (badStatus 400 Examples.errorMalformedRequest)
                        |> Expect.equal
                            (Err (Unexpected "The request body could not be read as the JSON this endpoint expects."))
            ]
        , describe "the answer was not what the app expected"
            [ test "an error page from something in between, not from the service" <|
                \_ ->
                    read (badStatus 502 "<html><body><h1>502 Bad Gateway</h1></body></html>")
                        |> Expect.equal (Err (Unexpected "The server answered 502 Bad Gateway."))
            , test "an error the service has but the app does not know" <|
                \_ ->
                    read (badStatus 418 """{"type":"teapot"}""")
                        |> Expect.equal (Err (Unexpected "The server answered 418 I'm a teapot."))
            , test "a good status with a body that is not what was asked for" <|
                \_ ->
                    read (Http.GoodStatus_ (metadata 200) """{"version":"v1"}""")
                        |> Result.mapError isUnexpected
                        |> Expect.equal (Err True)
            , test "a good status with a body that is not JSON at all" <|
                \_ ->
                    read (Http.GoodStatus_ (metadata 200) "<!doctype html><title>forsinket</title>")
                        |> Result.mapError isUnexpected
                        |> Expect.equal (Err True)
            , test "an address the browser refuses" <|
                \_ ->
                    read (Http.BadUrl_ "htp:/nope")
                        |> Expect.equal (Err (Unexpected "The address htp:/nope is not valid."))
            ]
        , test "a good answer is decoded" <|
            \_ ->
                read (Http.GoodStatus_ (metadata 200) Examples.rules)
                    |> Result.map .version
                    |> Expect.equal (Ok "v1")
        ]


read : Http.Response String -> Result Error Rules.Rules
read =
    Api.errorFromResponse Rules.decoder


badStatus : Int -> String -> Http.Response String
badStatus statusCode body =
    Http.BadStatus_ (metadata statusCode) body


metadata : Int -> Http.Metadata
metadata statusCode =
    { url = "https://forsinket.test/api/rules"
    , statusCode = statusCode
    , statusText =
        Dict.fromList
            [ ( 200, "OK" )
            , ( 400, "Bad Request" )
            , ( 404, "Not Found" )
            , ( 409, "Conflict" )
            , ( 418, "I'm a teapot" )
            , ( 422, "Unprocessable Entity" )
            , ( 429, "Too Many Requests" )
            , ( 502, "Bad Gateway" )
            ]
            |> Dict.get statusCode
            |> Maybe.withDefault ""
    , headers = Dict.empty
    }


isUnexpected : Error -> Bool
isUnexpected error =
    case error of
        Unexpected _ ->
            True

        _ ->
            False
