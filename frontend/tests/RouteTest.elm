module RouteTest exposing (suite)

import Claim.Id as Id exposing (Id)
import Expect
import Fuzz exposing (Fuzzer)
import Route exposing (Filter(..), Route(..))
import Status
import Test exposing (Test, describe, fuzz, test)
import Url


suite : Test
suite =
    describe "Route"
        [ describe "every page has an address"
            (List.map parsesTo
                [ ( "/", Home )
                , ( "/krav/nytt", NewClaim )
                , ( "/krav/" ++ uuid, Claim exampleId )
                , ( "/saksbehandling", ReviewQueue (Only Status.AwaitingReview) )
                , ( "/saksbehandling?status=venter", ReviewQueue (Only Status.AwaitingReview) )
                , ( "/saksbehandling?status=innvilget", ReviewQueue (Only Status.Approved) )
                , ( "/saksbehandling?status=avslatt", ReviewQueue (Only Status.Rejected) )
                , ( "/saksbehandling?status=utbetalt", ReviewQueue (Only Status.PaidOut) )
                , ( "/saksbehandling?status=mottatt", ReviewQueue (Only Status.Received) )
                , ( "/saksbehandling?status=alle", ReviewQueue All )
                , ( "/saksbehandling/" ++ uuid, ReviewClaim exampleId )
                ]
            )
        , describe "an address that is not a page is not found"
            (List.map isNotFound
                [ "/nope"
                , "/krav"
                , "/krav/not-a-uuid"
                , "/krav/" ++ uuid ++ "/extra"
                , "/saksbehandling?status=tull"
                , "/saksbehandling/nytt"
                , "/api/claims"
                ]
            )
        , test "a claim id in upper case is the same claim" <|
            \_ ->
                parse ("/krav/" ++ String.toUpper uuid)
                    |> Expect.equal (Just (Claim exampleId))
        , fuzz route "the address of a page leads back to that page" <|
            \generated ->
                parse (Route.toString generated)
                    |> Expect.equal (Just generated)
        ]


uuid : String
uuid =
    "3f9d2b7a-1c4e-4f8b-a6d5-2e7c9b1f4d30"


exampleId : Id
exampleId =
    idFrom uuid


{-| An id for a test. A string that is not a UUID would be a mistake in the test itself.
-}
idFrom : String -> Id
idFrom raw =
    case Id.fromString raw of
        Just id ->
            id

        Nothing ->
            Debug.todo ("not a UUID in a test: " ++ raw)


parse : String -> Maybe Route
parse path =
    Url.fromString ("https://forsinket.test" ++ path)
        |> Maybe.andThen Route.fromUrl


parsesTo : ( String, Route ) -> Test
parsesTo ( path, expected ) =
    test path <|
        \_ ->
            parse path
                |> Expect.equal (Just expected)


isNotFound : String -> Test
isNotFound path =
    test path <|
        \_ ->
            parse path
                |> Expect.equal Nothing


route : Fuzzer Route
route =
    Fuzz.oneOf
        [ Fuzz.constant Home
        , Fuzz.constant NewClaim
        , Fuzz.map Claim anyId
        , Fuzz.map ReviewQueue filter
        , Fuzz.map ReviewClaim anyId
        ]


filter : Fuzzer Filter
filter =
    Fuzz.oneOfValues (All :: List.map Only Status.allNames)


{-| Any UUID: 32 hexadecimal digits in groups of 8, 4, 4, 4 and 12.
-}
anyId : Fuzzer Id
anyId =
    Fuzz.listOfLength 32 (Fuzz.oneOfValues (String.toList "0123456789abcdef"))
        |> Fuzz.map
            (\digits ->
                [ List.take 8 digits
                , List.take 4 (List.drop 8 digits)
                , List.take 4 (List.drop 12 digits)
                , List.take 4 (List.drop 16 digits)
                , List.drop 20 digits
                ]
                    |> List.map String.fromList
                    |> String.join "-"
                    |> idFrom
            )
