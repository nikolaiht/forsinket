module ReviewClaimTest exposing (suite)

import Api
import Claim exposing (Claim)
import Claim.Decision as Decision exposing (Choice(..), Verdict(..))
import Claim.Reason exposing (RejectionReason(..))
import Expect
import FieldError exposing (Field(..), Problem(..))
import Fixtures exposing (ore)
import Html
import Page.ReviewClaim as ReviewClaim exposing (Effect(..), Msg(..), Saving(..))
import Remote exposing (Remote(..))
import Test exposing (Test, describe, test)
import Test.Html.Query as Query
import Test.Html.Selector as Selector


suite : Test
suite =
    describe "Page.ReviewClaim"
        [ test "opening the page asks for the claim" <|
            \_ ->
                Tuple.second (ReviewClaim.init Fixtures.idB)
                    |> Expect.equal [ FetchClaim Fixtures.idB ]
        , describe "deciding a claim that waits for an officer"
            [ test "a complete decision is sent, for the version of the claim the officer is looking at" <|
                \_ ->
                    filledIn
                        |> ReviewClaim.update DecisionSubmitted
                        |> Tuple.mapFirst .saving
                        |> Expect.equal
                            ( Saving
                            , [ SendDecision Fixtures.idB
                                    2
                                    { officer = "KN"
                                    , note = "Kvitteringen viser 500 kr."
                                    , verdict = Approve (ore 50000)
                                    }
                              ]
                            )
            , test "nothing is sent twice while the first is on its way" <|
                \_ ->
                    filledIn
                        |> step DecisionSubmitted
                        |> effects DecisionSubmitted
                        |> Expect.equal []
            , test "an incomplete decision is not sent, says what is missing, and moves focus to the message" <|
                \_ ->
                    opened Fixtures.awaitingReview
                        |> ReviewClaim.update DecisionSubmitted
                        |> Tuple.mapFirst (\model -> ( model.saving, model.errors ))
                        |> Expect.equal
                            ( ( Idle
                              , [ { field = ApprovedExpensesField, problem = Required }
                                , { field = OfficerField, problem = Required }
                                ]
                              )
                            , [ FocusErrors ]
                            )
            , test "more than the rules allow is stopped before it is sent" <|
                \_ ->
                    filledIn
                        |> step (ApprovedExpensesChanged "620,01")
                        |> ReviewClaim.update DecisionSubmitted
                        |> Tuple.mapFirst .errors
                        |> Expect.equal ( [ { field = ApprovedExpensesField, problem = AboveMaximum } ], [ FocusErrors ] )
            , test "an error goes away when its field is changed" <|
                \_ ->
                    opened Fixtures.awaitingReview
                        |> step DecisionSubmitted
                        |> step (OfficerChanged "K")
                        |> .errors
                        |> Expect.equal [ { field = ApprovedExpensesField, problem = Required } ]
            , test "changing the verdict clears the errors, which were about the other verdict's fields" <|
                \_ ->
                    opened Fixtures.awaitingReview
                        |> step (ChoiceChanged (Rejecting DuplicateClaim))
                        |> step (OfficerChanged "KN")
                        |> step DecisionSubmitted
                        |> step (ChoiceChanged Approving)
                        |> .errors
                        |> Expect.equal []
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
                        |> step (GotSaved Fixtures.idB (Ok Fixtures.approvedByOfficer))
                        |> (\model -> ( model.claim, model.draft, model.saving ))
                        |> Expect.equal ( Loaded Fixtures.approvedByOfficer, Decision.empty, Idle )
            , test "someone else got there first: nothing typed is lost, and the claim can be loaded again" <|
                \_ ->
                    filledIn
                        |> step DecisionSubmitted
                        |> step (GotSaved Fixtures.idB (Err Api.VersionConflict))
                        |> Expect.all
                            [ .saving >> Expect.equal (SaveFailed Api.VersionConflict)
                            , .draft >> .note >> Expect.equal "Kvitteringen viser 500 kr."
                            , .claim >> Expect.equal (Loaded Fixtures.awaitingReview)
                            , effects Reloaded >> Expect.equal [ FetchClaim Fixtures.idB ]
                            ]
            , test "what the service will not accept is shown on the fields" <|
                \_ ->
                    filledIn
                        |> step DecisionSubmitted
                        |> ReviewClaim.update (GotSaved Fixtures.idB (Err (Api.Invalid [ { field = ApprovedExpensesField, problem = AboveMaximum } ])))
                        |> Tuple.mapFirst (\model -> ( model.saving, model.errors ))
                        |> Expect.equal
                            ( ( Idle, [ { field = ApprovedExpensesField, problem = AboveMaximum } ] )
                            , [ FocusErrors ]
                            )
            , test "a payout the service refuses is reported, though there is no form to put it on" <|
                \_ ->
                    opened Fixtures.approvedAutomatically
                        |> step PayoutRequested
                        |> step (GotSaved Fixtures.idA (Err (Api.Invalid [])))
                        |> .saving
                        |> Expect.equal (SaveFailed (Api.Invalid []))
            , test "loading the claim again clears the failure" <|
                \_ ->
                    filledIn
                        |> step DecisionSubmitted
                        |> step (GotSaved Fixtures.idB (Err Api.VersionConflict))
                        |> step Reloaded
                        |> (\model -> ( model.saving, model.claim ))
                        |> Expect.equal ( Idle, Loading )
            ]
        , describe "answers that belong to another claim"
            [ test "a claim that arrives late for a page that now shows another claim is ignored" <|
                \_ ->
                    -- The officer opened claim A, then went straight on to claim B.
                    Tuple.first (ReviewClaim.init Fixtures.idB)
                        |> step (GotClaim Fixtures.idA (Ok Fixtures.approvedAutomatically))
                        |> .claim
                        |> Expect.equal Loading
            , test "a saved decision that arrives late for another claim is ignored" <|
                \_ ->
                    opened Fixtures.awaitingReview
                        |> step (GotSaved Fixtures.idA (Ok Fixtures.paidOut))
                        |> .claim
                        |> Expect.equal (Loaded Fixtures.awaitingReview)
            ]
        , describe "what a claim's status allows"
            [ test "an approved claim cannot be decided again" <|
                \_ ->
                    opened Fixtures.approvedAutomatically
                        |> step (OfficerChanged "KN")
                        |> effects DecisionSubmitted
                        |> Expect.equal []
            , test "an approved claim can be paid out, for the version the officer is looking at" <|
                \_ ->
                    opened Fixtures.approvedAutomatically
                        |> ReviewClaim.update PayoutRequested
                        |> Tuple.mapFirst .saving
                        |> Expect.equal ( Saving, [ SendPayout Fixtures.idA 2 ] )
            , test "the payout names the version of the claim it was made on, whatever that is" <|
                \_ ->
                    opened Fixtures.approvedByOfficer
                        |> effects PayoutRequested
                        |> Expect.equal [ SendPayout Fixtures.idB 3 ]
            , test "a claim that waits for an officer, or is rejected, cannot be paid out" <|
                \_ ->
                    [ Fixtures.awaitingReview, Fixtures.rejectedByRules, Fixtures.paidOut ]
                        |> List.map (\claim -> effects PayoutRequested (opened claim))
                        |> Expect.equal [ [], [], [] ]
            , test "nothing is sent while the claim is still loading" <|
                \_ ->
                    Tuple.first (ReviewClaim.init Fixtures.idB)
                        |> (\model -> effects DecisionSubmitted model ++ effects PayoutRequested model)
                        |> Expect.equal []
            ]
        , describe "what the officer is offered follows from the status"
            (List.map offers
                [ ( "waiting for review: the decision form", Fixtures.awaitingReview, { form = 1, payout = 0 } )
                , ( "approved: the payout button", Fixtures.approvedAutomatically, { form = 0, payout = 1 } )
                , ( "approved by an officer: the payout button", Fixtures.approvedByOfficer, { form = 0, payout = 1 } )
                , ( "rejected by the rules: nothing", Fixtures.rejectedByRules, { form = 0, payout = 0 } )
                , ( "rejected by an officer: nothing", Fixtures.rejectedByOfficer, { form = 0, payout = 0 } )
                , ( "paid out: nothing", Fixtures.paidOut, { form = 0, payout = 0 } )
                ]
            )
        ]


offers : ( String, Claim, { form : Int, payout : Int } ) -> Test
offers ( name, claim, expected ) =
    test name <|
        \_ ->
            Query.fromHtml (Html.div [] (ReviewClaim.view (opened claim)).body)
                |> Expect.all
                    [ Query.findAll [ Selector.tag "form" ] >> Query.count (Expect.equal expected.form)
                    , Query.findAll [ Selector.tag "button", Selector.containing [ Selector.text "Registrer utbetaling" ] ]
                        >> Query.count (Expect.equal expected.payout)
                    ]


step : Msg -> ReviewClaim.Model -> ReviewClaim.Model
step msg model =
    ReviewClaim.update msg model
        |> Tuple.first


effects : Msg -> ReviewClaim.Model -> List Effect
effects msg model =
    ReviewClaim.update msg model
        |> Tuple.second


{-| The page with a claim loaded.
-}
opened : Claim -> ReviewClaim.Model
opened claim =
    Tuple.first (ReviewClaim.init claim.id)
        |> step (GotClaim claim.id (Ok claim))


{-| The decision of example B, ready to send.
-}
filledIn : ReviewClaim.Model
filledIn =
    opened Fixtures.awaitingReview
        |> step (ApprovedExpensesChanged "500")
        |> step (NoteChanged "Kvitteringen viser 500 kr.")
        |> step (OfficerChanged "KN")
