module ReviewClaimTest exposing (suite)

import Api
import Claim exposing (Claim)
import Claim.Decision as Decision exposing (Choice(..))
import Claim.Reason exposing (RejectionReason(..))
import Expect
import FieldError exposing (Field(..), Problem(..))
import Fixtures
import Page.ReviewClaim as ReviewClaim exposing (Msg(..), Saving(..))
import Remote exposing (Remote(..))
import Test exposing (Test, describe, test)


suite : Test
suite =
    describe "Page.ReviewClaim.update"
        [ describe "deciding a claim that waits for an officer"
            [ test "a complete decision is sent" <|
                \_ ->
                    filledIn
                        |> step DecisionSubmitted
                        |> .saving
                        |> Expect.equal Saving
            , test "an incomplete decision is not sent, and says what is missing" <|
                \_ ->
                    opened Fixtures.awaitingReview
                        |> step DecisionSubmitted
                        |> (\model -> ( model.saving, model.errors ))
                        |> Expect.equal
                            ( Idle
                            , [ { field = ApprovedExpensesField, problem = Required }
                              , { field = OfficerField, problem = Required }
                              ]
                            )
            , test "more than the rules allow is stopped before it is sent" <|
                \_ ->
                    filledIn
                        |> step (ApprovedExpensesChanged "620,01")
                        |> step DecisionSubmitted
                        |> (\model -> ( model.saving, model.errors ))
                        |> Expect.equal ( Idle, [ { field = ApprovedExpensesField, problem = AboveMaximum } ] )
            , test "an error goes away when its field is changed" <|
                \_ ->
                    opened Fixtures.awaitingReview
                        |> step DecisionSubmitted
                        |> step (OfficerChanged "K")
                        |> .errors
                        |> Expect.equal [ { field = ApprovedExpensesField, problem = Required } ]
            , test "choosing to reject keeps the reason with the choice" <|
                \_ ->
                    opened Fixtures.awaitingReview
                        |> step (ChoiceChanged (Rejecting DuplicateClaim))
                        |> .draft
                        |> .choice
                        |> Expect.equal (Rejecting DuplicateClaim)
            ]
        , describe "when the answer comes back"
            [ test "the page shows the claim as it now is, and the form is cleared" <|
                \_ ->
                    filledIn
                        |> step DecisionSubmitted
                        |> step (GotSaved (Ok Fixtures.approvedByOfficer))
                        |> (\model -> ( model.claim, model.draft, model.saving ))
                        |> Expect.equal ( Loaded Fixtures.approvedByOfficer, Decision.empty, Idle )
            , test "someone else got there first: nothing typed is lost" <|
                \_ ->
                    filledIn
                        |> step DecisionSubmitted
                        |> step (GotSaved (Err Api.VersionConflict))
                        |> (\model -> ( model.saving, model.draft.note, model.claim ))
                        |> Expect.equal
                            ( SaveFailed Api.VersionConflict
                            , "Kvitteringen viser 500 kr."
                            , Loaded Fixtures.awaitingReview
                            )
            , test "what the service will not accept is shown on the fields" <|
                \_ ->
                    filledIn
                        |> step DecisionSubmitted
                        |> step (GotSaved (Err (Api.Invalid [ { field = ApprovedExpensesField, problem = AboveMaximum } ])))
                        |> (\model -> ( model.saving, model.errors ))
                        |> Expect.equal ( Idle, [ { field = ApprovedExpensesField, problem = AboveMaximum } ] )
            , test "loading the claim again clears the failure" <|
                \_ ->
                    filledIn
                        |> step DecisionSubmitted
                        |> step (GotSaved (Err Api.VersionConflict))
                        |> step Reloaded
                        |> (\model -> ( model.saving, model.claim ))
                        |> Expect.equal ( Idle, Loading )
            ]
        , describe "what a claim's status allows"
            [ test "an approved claim cannot be decided again" <|
                \_ ->
                    opened Fixtures.approvedAutomatically
                        |> step (OfficerChanged "KN")
                        |> step DecisionSubmitted
                        |> .saving
                        |> Expect.equal Idle
            , test "an approved claim can be paid out" <|
                \_ ->
                    opened Fixtures.approvedAutomatically
                        |> step PayoutRequested
                        |> .saving
                        |> Expect.equal Saving
            , test "a claim that waits for an officer cannot be paid out" <|
                \_ ->
                    opened Fixtures.awaitingReview
                        |> step PayoutRequested
                        |> .saving
                        |> Expect.equal Idle
            , test "a rejected claim cannot be paid out" <|
                \_ ->
                    opened Fixtures.rejectedByRules
                        |> step PayoutRequested
                        |> .saving
                        |> Expect.equal Idle
            , test "nothing is sent while the claim is still loading" <|
                \_ ->
                    Tuple.first (ReviewClaim.init Fixtures.idB)
                        |> step DecisionSubmitted
                        |> step PayoutRequested
                        |> .saving
                        |> Expect.equal Idle
            ]
        ]


step : Msg -> ReviewClaim.Model -> ReviewClaim.Model
step msg model =
    ReviewClaim.update msg model
        |> Tuple.first


{-| The page with a claim loaded.
-}
opened : Claim -> ReviewClaim.Model
opened claim =
    Tuple.first (ReviewClaim.init claim.id)
        |> step (GotClaim (Ok claim))


{-| The decision of example B, ready to send.
-}
filledIn : ReviewClaim.Model
filledIn =
    opened Fixtures.awaitingReview
        |> step (ApprovedExpensesChanged "500")
        |> step (NoteChanged "Kvitteringen viser 500 kr.")
        |> step (OfficerChanged "KN")
