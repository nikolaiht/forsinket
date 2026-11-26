module NewClaimTest exposing (suite)

{-| The page for a new claim, driven the way the browser drives it: one
message at a time. `update` returns the new model and the effects it wants
done, as plain values, so a test can check both what the page now shows and
what it asked for, without a browser and without a server.
-}

import Api
import Claim.Calculation exposing (Assessment(..))
import Claim.Draft exposing (ExpensesDraft(..), NewClaim)
import Claim.Expenses as Expenses
import Claim.Reason exposing (IneligibilityReason(..))
import Claim.Ticket exposing (Ticket(..))
import Date exposing (Date)
import Expect
import FieldError exposing (Field(..), Problem(..))
import Fixtures exposing (ore)
import Html
import Page.NewClaim as NewClaim exposing (Departures(..), Effect(..), Msg(..), Preview(..), Submission(..))
import Remote exposing (Remote(..))
import Test exposing (Test, describe, test)
import Test.Html.Query as Query
import Test.Html.Selector as Selector
import Time exposing (Month(..))


suite : Test
suite =
    describe "Page.NewClaim"
        [ test "opening the page asks for the rules and for today's date" <|
            \_ ->
                Tuple.second NewClaim.init
                    |> Expect.equal [ FetchRules, FetchToday ]
        , describe "departures"
            [ test "are asked for when a date is chosen" <|
                \_ ->
                    opened
                        |> NewClaim.update (DateChanged "2026-11-20")
                        |> Tuple.mapFirst .departures
                        |> Expect.equal ( For friday Loading, [ FetchDepartures friday ] )
            , test "are shown when they arrive" <|
                \_ ->
                    withDepartures
                        |> .departures
                        |> Expect.equal (For friday (Loaded Fixtures.departures))
            , test "for a date that is no longer chosen are thrown away" <|
                \_ ->
                    opened
                        |> step (DateChanged "2026-11-20")
                        |> step (DateChanged "2026-11-21")
                        |> step (GotDepartures friday (Ok Fixtures.departures))
                        |> .departures
                        |> Expect.equal (For saturday Loading)
            , test "that could not be fetched say so, and can be asked for again" <|
                \_ ->
                    opened
                        |> step (DateChanged "2026-11-20")
                        |> step (GotDepartures friday (Err Api.Offline))
                        |> Expect.all
                            [ .departures >> Expect.equal (For friday (Failed Api.Offline))
                            , effects DeparturesRetried >> Expect.equal [ FetchDepartures friday ]
                            ]
            , test "are not asked for until the date is a whole date" <|
                \_ ->
                    [ "2026-11-", "2026-11", "2026-W47-1", "i går" ]
                        |> List.map (\typed -> NewClaim.update (DateChanged typed) opened |> Tuple.mapFirst .departures)
                        |> Expect.equal (List.repeat 4 ( NoDate, [] ))
            , test "the chosen departure is dropped when the date changes" <|
                \_ ->
                    withDepartures
                        |> step (DepartureChosen Fixtures.tb16.id)
                        |> step (DateChanged "2026-11-21")
                        |> .draft
                        |> .departure
                        |> Expect.equal Nothing
            , test "today's date is filled in when the page opens" <|
                \_ ->
                    opened
                        |> NewClaim.update (GotToday friday)
                        |> Tuple.mapFirst .date
                        |> Expect.equal ( "2026-11-20", [ FetchDepartures friday ] )
            , test "but not over a date the passenger has already chosen" <|
                \_ ->
                    opened
                        |> step (DateChanged "2026-11-21")
                        |> NewClaim.update (GotToday friday)
                        |> Tuple.mapFirst .date
                        |> Expect.equal ( "2026-11-21", [] )
            ]
        , describe "the preview"
            [ test "is asked for as soon as the form is complete" <|
                \_ ->
                    withDepartures
                        |> step (DepartureChosen Fixtures.tb16.id)
                        |> NewClaim.update (PriceChanged "349")
                        |> Tuple.mapFirst .preview
                        |> Expect.equal ( PreviewFor claimA Loading, [ AskForPreview claimA ] )
            , test "is not asked for while something is missing" <|
                \_ ->
                    withDepartures
                        |> NewClaim.update (PriceChanged "349")
                        |> Tuple.mapFirst .preview
                        |> Expect.equal ( NoPreview, [] )
            , test "is shown when it arrives" <|
                \_ ->
                    complete
                        |> step (GotPreview claimA (Ok notEligible))
                        |> .preview
                        |> Expect.equal (PreviewFor claimA (Loaded notEligible))
            , test "for what the form used to say is thrown away" <|
                \_ ->
                    complete
                        |> step (PriceChanged "350")
                        |> step (GotPreview claimA (Ok notEligible))
                        |> .preview
                        |> Expect.equal (PreviewFor { claimA | ticket = Single (ore 35000) } Loading)
            , test "goes away when the form stops being complete" <|
                \_ ->
                    complete
                        |> step (GotPreview claimA (Ok notEligible))
                        |> step (PriceChanged "")
                        |> .preview
                        |> Expect.equal NoPreview
            , test "is not asked for again when nothing that matters has changed" <|
                \_ ->
                    complete
                        |> step (GotPreview claimA (Ok notEligible))
                        |> NewClaim.update (PriceChanged "349,00")
                        |> Tuple.mapFirst .preview
                        |> Expect.equal ( PreviewFor claimA (Loaded notEligible), [] )
            , test "that the service refuses puts the reason on the field, where the passenger can fix it" <|
                \_ ->
                    complete
                        |> step (GotPreview claimA (Err (Api.Invalid [ { field = DepartureField, problem = DepartureInFuture } ])))
                        |> (\model -> ( model.preview, model.errors ))
                        |> Expect.equal ( NoPreview, [ { field = DepartureField, problem = DepartureInFuture } ] )
            ]
        , describe "expenses"
            [ test "start out with nothing typed" <|
                \_ ->
                    complete
                        |> step (ExpensesToggled True)
                        |> .draft
                        |> .expenses
                        |> Expect.equal (WithExpenses { amount = "", kind = Expenses.Taxi })
            , test "what was typed is dropped when the box is unticked" <|
                \_ ->
                    complete
                        |> step (ExpensesToggled True)
                        |> step (ExpensesAmountChanged "620")
                        |> step (ExpensesToggled False)
                        |> .draft
                        |> .expenses
                        |> Expect.equal NoExpenses
            ]
        , describe "sending"
            [ test "a complete form is sent, once" <|
                \_ ->
                    complete
                        |> NewClaim.update Submitted
                        |> Tuple.mapFirst .submission
                        |> Expect.equal ( Submitting claimA, [ SendClaim claimA ] )
            , test "nothing is sent twice while the first is on its way" <|
                \_ ->
                    complete
                        |> step Submitted
                        |> effects Submitted
                        |> Expect.equal []
            , test "the form cannot be changed while the claim is on its way, so it cannot be sent again as something else" <|
                \_ ->
                    complete
                        |> step Submitted
                        |> step (PriceChanged "999")
                        |> step (DateChanged "2026-11-21")
                        |> step (ExpensesToggled True)
                        |> Expect.all
                            [ .submission >> Expect.equal (Submitting claimA)
                            , .draft >> .price >> Expect.equal "349"
                            , .date >> Expect.equal "2026-11-20"
                            , effects Submitted >> Expect.equal []
                            ]
            , test "an incomplete form is not sent, says what is missing, and moves focus to the message" <|
                \_ ->
                    withDepartures
                        |> NewClaim.update Submitted
                        |> Tuple.mapFirst (\model -> ( model.submission, model.errors ))
                        |> Expect.equal
                            ( ( NotSubmitted
                              , [ { field = DepartureField, problem = Required }
                                , { field = PriceField, problem = Required }
                                ]
                              )
                            , [ FocusErrors ]
                            )
            , test "nothing can be sent before the rules have arrived" <|
                \_ ->
                    Tuple.first NewClaim.init
                        |> NewClaim.update Submitted
                        |> Tuple.mapFirst .submission
                        |> Expect.equal ( NotSubmitted, [] )
            , test "an error goes away when its field is changed" <|
                \_ ->
                    withDepartures
                        |> step Submitted
                        |> step (PriceChanged "3")
                        |> .errors
                        |> Expect.equal [ { field = DepartureField, problem = Required } ]
            , test "when the claim is stored, the page asks to show it" <|
                \_ ->
                    complete
                        |> step Submitted
                        |> effects (GotSubmit claimA (Ok Fixtures.approvedAutomatically))
                        |> Expect.equal [ ShowClaim Fixtures.idA ]
            , test "what the service will not accept is shown on the fields" <|
                \_ ->
                    complete
                        |> step Submitted
                        |> NewClaim.update (GotSubmit claimA (Err (Api.Invalid [ { field = DepartureField, problem = DepartureInFuture } ])))
                        |> Tuple.mapFirst (\model -> ( model.submission, model.errors ))
                        |> Expect.equal
                            ( ( NotSubmitted, [ { field = DepartureField, problem = DepartureInFuture } ] )
                            , [ FocusErrors ]
                            )
            , test "a failure that is not about the fields keeps everything that was typed" <|
                \_ ->
                    complete
                        |> step Submitted
                        |> step (GotSubmit claimA (Err Api.Offline))
                        |> (\model -> ( model.submission, model.draft.price ))
                        |> Expect.equal ( SubmitFailed Api.Offline, "349" )
            , test "the failure goes away when the passenger changes something, the date included" <|
                \_ ->
                    [ PriceChanged "350", DateChanged "2026-11-21" ]
                        |> List.map
                            (\change ->
                                complete
                                    |> step Submitted
                                    |> step (GotSubmit claimA (Err Api.Offline))
                                    |> step change
                                    |> .submission
                            )
                        |> Expect.equal [ NotSubmitted, NotSubmitted ]
            , test "an answer about a claim this page did not send is ignored" <|
                \_ ->
                    -- The passenger sent a claim, left, and came back to an empty form.
                    opened
                        |> NewClaim.update (GotSubmit claimA (Err (Api.Invalid [ { field = PriceField, problem = AboveMaximum } ])))
                        |> Tuple.mapFirst .errors
                        |> Expect.equal ( [], [] )
            ]
        , describe "what the passenger sees"
            [ test "a missing departure is pointed out even when there is no list to mark" <|
                \_ ->
                    opened
                        |> step Submitted
                        |> view
                        |> Query.has [ Selector.text "Velg en avgang." ]
            , test "the fields are locked while the claim is on its way" <|
                \_ ->
                    complete
                        |> step Submitted
                        |> view
                        |> Query.find [ Selector.tag "fieldset", Selector.class "claim-form__fields" ]
                        |> Query.has [ Selector.disabled True ]
            ]
        ]


friday : Date
friday =
    Date.fromCalendarDate 2026 Nov 20


saturday : Date
saturday =
    Date.fromCalendarDate 2026 Nov 21


claimA : NewClaim
claimA =
    { departureId = Fixtures.tb16.id
    , ticket = Fixtures.single349
    , expenses = Nothing
    }


notEligible : Assessment
notEligible =
    NotEligible DelayBelowThreshold


step : Msg -> NewClaim.Model -> NewClaim.Model
step msg model =
    NewClaim.update msg model
        |> Tuple.first


effects : Msg -> NewClaim.Model -> List Effect
effects msg model =
    NewClaim.update msg model
        |> Tuple.second


view : NewClaim.Model -> Query.Single Msg
view model =
    Query.fromHtml (Html.div [] (NewClaim.view model).body)


{-| The page with the rules loaded.
-}
opened : NewClaim.Model
opened =
    Tuple.first NewClaim.init
        |> step (GotRules (Ok Fixtures.rules))


{-| Friday chosen, and its departures loaded.
-}
withDepartures : NewClaim.Model
withDepartures =
    opened
        |> step (DateChanged "2026-11-20")
        |> step (GotDepartures friday (Ok Fixtures.departures))


{-| The form filled in as example A.
-}
complete : NewClaim.Model
complete =
    withDepartures
        |> step (DepartureChosen Fixtures.tb16.id)
        |> step (PriceChanged "349")
