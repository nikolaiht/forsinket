module ListPagesTest exposing (suite)

{-| The two pages that only fetch and show: the officers' list and the
passenger's view of a claim. What can go wrong in them is an answer that
arrives for something the page no longer shows.
-}

import Api
import Expect
import Fixtures
import Page.Claim as ClaimPage
import Page.Home as Home
import Page.ReviewQueue as ReviewQueue
import Remote exposing (Remote(..))
import Route exposing (Filter(..))
import Status
import Test exposing (Test, describe, test)


suite : Test
suite =
    describe "Pages that fetch and show"
        [ describe "the officers' list"
            [ test "asks for the claims its filter names" <|
                \_ ->
                    [ Only Status.AwaitingReview, Only Status.Rejected, All ]
                        |> List.map (ReviewQueue.init >> Tuple.second)
                        |> Expect.equal
                            [ [ ReviewQueue.FetchClaims (Only Status.AwaitingReview) ]
                            , [ ReviewQueue.FetchClaims (Only Status.Rejected) ]
                            , [ ReviewQueue.FetchClaims All ]
                            ]
            , test "an answer for a filter that is no longer chosen is thrown away" <|
                \_ ->
                    -- "Innvilget" was clicked, then "Avslått", and the first answer came last.
                    Tuple.first (ReviewQueue.init (Only Status.Rejected))
                        |> ReviewQueue.update (ReviewQueue.GotClaims (Only Status.Approved) (Ok []))
                        |> Tuple.first
                        |> .claims
                        |> Expect.equal Loading
            , test "an answer for the chosen filter is shown" <|
                \_ ->
                    Tuple.first (ReviewQueue.init (Only Status.Rejected))
                        |> ReviewQueue.update (ReviewQueue.GotClaims (Only Status.Rejected) (Ok []))
                        |> Tuple.first
                        |> .claims
                        |> Expect.equal (Loaded [])
            , test "a failed fetch can be tried again" <|
                \_ ->
                    Tuple.first (ReviewQueue.init All)
                        |> ReviewQueue.update (ReviewQueue.GotClaims All (Err Api.Offline))
                        |> Tuple.first
                        |> ReviewQueue.update ReviewQueue.Retried
                        |> Tuple.mapFirst .claims
                        |> Expect.equal ( Loading, [ ReviewQueue.FetchClaims All ] )
            ]
        , describe "a passenger's claim"
            [ test "is asked for by its id" <|
                \_ ->
                    Tuple.second (ClaimPage.init Fixtures.idA)
                        |> Expect.equal [ ClaimPage.FetchClaim Fixtures.idA ]
            , test "an answer about another claim is thrown away" <|
                \_ ->
                    Tuple.first (ClaimPage.init Fixtures.idB)
                        |> ClaimPage.update (ClaimPage.GotClaim Fixtures.idA (Ok Fixtures.approvedAutomatically))
                        |> Tuple.first
                        |> .claim
                        |> Expect.equal Loading
            , test "the answer about this claim is shown" <|
                \_ ->
                    Tuple.first (ClaimPage.init Fixtures.idA)
                        |> ClaimPage.update (ClaimPage.GotClaim Fixtures.idA (Ok Fixtures.approvedAutomatically))
                        |> Tuple.first
                        |> .claim
                        |> Expect.equal (Loaded Fixtures.approvedAutomatically)
            ]
        , test "the front page asks for the rules and the examples" <|
            \_ ->
                Tuple.second Home.init
                    |> Expect.equal [ Home.FetchRules, Home.FetchExamples ]
        ]
