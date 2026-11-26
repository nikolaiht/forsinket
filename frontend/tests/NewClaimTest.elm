module NewClaimTest exposing (suite)

{-| The page for a new claim, driven the way the browser drives it: one
message at a time. No browser is needed, because `update` is a function from a
message and a model to a model.
-}

import Api
import Claim.Calculation exposing (Assessment(..))
import Claim.Draft exposing (ExpensesDraft(..), NewClaim)
import Claim.Expenses as Expenses
import Claim.Reason exposing (IneligibilityReason(..))
import Claim.Ticket
import Date exposing (Date)
import Expect
import FieldError exposing (Field(..), Problem(..))
import Fixtures
import Money
import Page.NewClaim as NewClaim exposing (Departures(..), Msg(..), Preview(..), Submission(..))
import Remote exposing (Remote(..))
import Test exposing (Test, describe, test)
import Time exposing (Month(..))


suite : Test
suite =
    describe "Page.NewClaim.update"
        [ describe "departures"
            [ test "are asked for when a date is chosen" <|
                \_ ->
                    opened
                        |> step (DateChanged "2026-11-20")
                        |> .departures
                        |> Expect.equal (For friday Loading)
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
            , test "that could not be fetched say so" <|
                \_ ->
                    opened
                        |> step (DateChanged "2026-11-20")
                        |> step (GotDepartures friday (Err Api.Offline))
                        |> .departures
                        |> Expect.equal (For friday (Failed Api.Offline))
            , test "are not asked for until the date is a date" <|
                \_ ->
                    opened
                        |> step (DateChanged "2026-11-")
                        |> .departures
                        |> Expect.equal NoDate
            , test "the chosen departure is dropped when the date changes" <|
                \_ ->
                    withDepartures
                        |> step (DepartureChosen Fixtures.fb16.id)
                        |> step (DateChanged "2026-11-21")
                        |> .draft
                        |> .departure
                        |> Expect.equal Nothing
            , test "today's date is filled in when the page opens" <|
                \_ ->
                    opened
                        |> step (GotToday friday)
                        |> (\model -> ( model.draft.date, model.departures ))
                        |> Expect.equal ( "2026-11-20", For friday Loading )
            , test "but not over a date the passenger has already chosen" <|
                \_ ->
                    opened
                        |> step (DateChanged "2026-11-21")
                        |> step (GotToday friday)
                        |> .draft
                        |> .date
                        |> Expect.equal "2026-11-21"
            ]
        , describe "the preview"
            [ test "is asked for as soon as the form is complete" <|
                \_ ->
                    complete
                        |> .preview
                        |> Expect.equal (PreviewFor claimA Loading)
            , test "is not asked for while something is missing" <|
                \_ ->
                    withDepartures
                        |> step (PriceChanged "349")
                        |> .preview
                        |> Expect.equal NoPreview
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
                        |> Expect.equal (PreviewFor { claimA | ticket = single 35000 } Loading)
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
                        |> step (PriceChanged "349,00")
                        |> .preview
                        |> Expect.equal (PreviewFor claimA (Loaded notEligible))
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
            [ test "a complete form is sent" <|
                \_ ->
                    complete
                        |> step Submitted
                        |> .submission
                        |> Expect.equal Submitting
            , test "an incomplete form is not sent, and says what is missing" <|
                \_ ->
                    withDepartures
                        |> step Submitted
                        |> (\model -> ( model.submission, model.errors ))
                        |> Expect.equal
                            ( NotSubmitted
                            , [ { field = DepartureField, problem = Required }
                              , { field = PriceField, problem = Required }
                              ]
                            )
            , test "an error goes away when its field is changed" <|
                \_ ->
                    withDepartures
                        |> step Submitted
                        |> step (PriceChanged "3")
                        |> .errors
                        |> Expect.equal [ { field = DepartureField, problem = Required } ]
            , test "what the service will not accept is shown on the fields" <|
                \_ ->
                    complete
                        |> step Submitted
                        |> step (GotSubmit (Err (Api.Invalid [ { field = DepartureField, problem = DepartureInFuture } ])))
                        |> (\model -> ( model.submission, model.errors ))
                        |> Expect.equal ( NotSubmitted, [ { field = DepartureField, problem = DepartureInFuture } ] )
            , test "a failure that is not about the fields keeps everything that was typed" <|
                \_ ->
                    complete
                        |> step Submitted
                        |> step (GotSubmit (Err Api.Offline))
                        |> (\model -> ( model.submission, model.draft.price ))
                        |> Expect.equal ( SubmitFailed Api.Offline, "349" )
            , test "nothing is sent twice while the first is on its way" <|
                \_ ->
                    complete
                        |> step Submitted
                        |> step Submitted
                        |> .submission
                        |> Expect.equal Submitting
            ]
        , test "the form cannot be used until the rules have arrived" <|
            \_ ->
                Tuple.first NewClaim.init
                    |> .rules
                    |> Expect.equal Loading
        ]


friday : Date
friday =
    Date.fromCalendarDate 2026 Nov 20


saturday : Date
saturday =
    Date.fromCalendarDate 2026 Nov 21


single : Int -> Claim.Ticket.Ticket
single ore =
    Claim.Ticket.Single (Money.fromOre ore)


claimA : NewClaim
claimA =
    { departureId = Fixtures.fb16.id
    , ticket = Fixtures.single349
    , expenses = Nothing
    }


notEligible : Assessment
notEligible =
    NotEligible DelayBelowThreshold


{-| One message, with a navigation that goes nowhere.
-}
step : Msg -> NewClaim.Model -> NewClaim.Model
step msg model =
    NewClaim.update (\_ -> Cmd.none) msg model
        |> Tuple.first


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
        |> step (DepartureChosen Fixtures.fb16.id)
        |> step (PriceChanged "349")
