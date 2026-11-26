module Page.NewClaim exposing (Departures(..), Model, Msg(..), Preview(..), Submission(..), init, update, view)

{-| The form a passenger makes a claim with.

The model has no flags. Whether the departures are loading, whether there is a
preview, whether the claim is on its way: each is a type with one value per
situation, so the page cannot be in two of them at once.

-}

import Api
import Claim exposing (Claim)
import Claim.Calculation exposing (Assessment)
import Claim.Draft as Draft exposing (Draft, ExpensesDraft(..), NewClaim, TicketKind(..))
import Claim.Expenses as Expenses
import Claim.Ticket exposing (Validity(..))
import Date exposing (Date)
import Departure exposing (Departure, Outcome(..))
import FieldError exposing (Field(..), FieldError)
import Html exposing (Html, button, div, fieldset, form, h1, h2, input, label, legend, p, section, span, text)
import Html.Attributes exposing (attribute, checked, class, disabled, for, id, name, novalidate, type_, value)
import Html.Events exposing (onCheck, onInput, onSubmit)
import Money
import Remote exposing (Remote(..))
import Route exposing (Route)
import Rules exposing (Rules)
import Task
import View.Calculation
import View.Form
import View.Format as Format
import View.Layout
import View.Problem
import View.Text as Text


type alias Model =
    { rules : Remote Api.Error Rules
    , draft : Draft
    , departures : Departures
    , preview : Preview
    , submission : Submission
    , errors : List FieldError
    }


{-| The departures to choose from belong to a date. Remembering which date is
what makes it possible to recognise an answer that arrives for a date the
passenger has already moved on from.
-}
type Departures
    = NoDate
    | For Date (Remote Api.Error (List Departure))


{-| What the rules would say about the form as it stands, and the claim that
was asked about, for the same reason: an answer about an older version of the
form must not be shown next to a newer one.
-}
type Preview
    = NoPreview
    | PreviewFor NewClaim (Remote Api.Error Assessment)


type Submission
    = NotSubmitted
    | Submitting
    | SubmitFailed Api.Error


init : ( Model, Cmd Msg )
init =
    ( { rules = Loading
      , draft = Draft.empty
      , departures = NoDate
      , preview = NoPreview
      , submission = NotSubmitted
      , errors = []
      }
    , Cmd.batch
        [ Api.getRules GotRules
        , Task.perform GotToday Date.today
        ]
    )



-- UPDATE


type Msg
    = GotRules (Result Api.Error Rules)
    | RulesRetried
    | GotToday Date
    | DateChanged String
    | GotDepartures Date (Result Api.Error (List Departure))
    | DeparturesRetried
    | DepartureChosen Departure.Id
    | TicketKindChosen TicketKind
    | PriceChanged String
    | ExpensesToggled Bool
    | ExpensesAmountChanged String
    | ExpensesKindChosen Expenses.Kind
    | GotPreview NewClaim (Result Api.Error Assessment)
    | PreviewRetried
    | Submitted
    | GotSubmit (Result Api.Error Claim)


{-| `navigate` is how the page asks to go somewhere else. It is passed in, so
this function can be run in a test without a browser.
-}
update : (Route -> Cmd Msg) -> Msg -> Model -> ( Model, Cmd Msg )
update navigate msg model =
    case msg of
        GotRules result ->
            refreshPreview { model | rules = Remote.fromResult result }

        RulesRetried ->
            ( { model | rules = Loading }, Api.getRules GotRules )

        GotToday today ->
            if String.isEmpty model.draft.date then
                chooseDate (Date.toIsoString today) model

            else
                ( model, Cmd.none )

        DateChanged date ->
            chooseDate date model

        GotDepartures date result ->
            case model.departures of
                For chosen _ ->
                    if chosen == date then
                        ( { model | departures = For date (Remote.fromResult result) }, Cmd.none )

                    else
                        ( model, Cmd.none )

                NoDate ->
                    ( model, Cmd.none )

        DeparturesRetried ->
            chooseDate model.draft.date model

        DepartureChosen departure ->
            edit DepartureField (\draft -> { draft | departure = Just departure }) model

        TicketKindChosen kind ->
            edit ValidityField (\draft -> { draft | ticketKind = kind }) model

        PriceChanged price ->
            edit PriceField (\draft -> { draft | price = price }) model

        ExpensesToggled True ->
            edit ExpensesAmountField
                (\draft -> { draft | expenses = WithExpenses { amount = "", kind = Expenses.Taxi } })
                model

        ExpensesToggled False ->
            edit ExpensesAmountField (\draft -> { draft | expenses = NoExpenses }) model

        ExpensesAmountChanged amount ->
            edit ExpensesAmountField (changeExpenses (\expenses -> { expenses | amount = amount })) model

        ExpensesKindChosen kind ->
            edit ExpensesKindField (changeExpenses (\expenses -> { expenses | kind = kind })) model

        GotPreview claim result ->
            case model.preview of
                PreviewFor asked _ ->
                    if asked == claim then
                        ( { model | preview = PreviewFor claim (Remote.fromResult result) }, Cmd.none )

                    else
                        ( model, Cmd.none )

                NoPreview ->
                    ( model, Cmd.none )

        PreviewRetried ->
            refreshPreview { model | preview = NoPreview }

        Submitted ->
            case ( model.submission, model.rules ) of
                ( Submitting, _ ) ->
                    ( model, Cmd.none )

                ( _, Loaded rules ) ->
                    case Draft.validate rules model.draft of
                        Ok claim ->
                            ( { model | submission = Submitting, errors = [] }, Api.postClaim claim GotSubmit )

                        Err errors ->
                            ( { model | submission = NotSubmitted, errors = errors }, Cmd.none )

                _ ->
                    ( model, Cmd.none )

        GotSubmit (Ok claim) ->
            ( model, navigate (Route.Claim claim.id) )

        GotSubmit (Err (Api.Invalid errors)) ->
            ( { model | submission = NotSubmitted, errors = errors }, Cmd.none )

        GotSubmit (Err error) ->
            ( { model | submission = SubmitFailed error }, Cmd.none )


{-| A new date means new departures, so whatever departure was chosen no
longer applies.
-}
chooseDate : String -> Model -> ( Model, Cmd Msg )
chooseDate raw model =
    let
        draft : Draft
        draft =
            model.draft

        withDate : Model
        withDate =
            { model
                | draft = { draft | date = raw, departure = Nothing }
                , errors = List.filter (\error -> error.field /= DepartureField) model.errors
            }
    in
    case parseDate raw of
        Just date ->
            refreshPreview { withDate | departures = For date Loading }
                |> Tuple.mapSecond (\cmd -> Cmd.batch [ cmd, Api.getDepartures date (GotDepartures date) ])

        Nothing ->
            refreshPreview { withDate | departures = NoDate }


{-| `Date.fromIsoString` also reads `2026-11` and `2026-W47`. A date field
gives a full date or nothing, so only a full date counts.
-}
parseDate : String -> Maybe Date
parseDate raw =
    if String.length raw == 10 then
        Result.toMaybe (Date.fromIsoString raw)

    else
        Nothing


{-| Change one field. Its errors are about what it used to say, so they go,
and the preview is asked for again if the form now says something else.
-}
edit : Field -> (Draft -> Draft) -> Model -> ( Model, Cmd Msg )
edit field change model =
    refreshPreview
        { model
            | draft = change model.draft
            , errors = List.filter (\error -> error.field /= field) model.errors
            , submission = NotSubmitted
        }


changeExpenses : ({ amount : String, kind : Expenses.Kind } -> { amount : String, kind : Expenses.Kind }) -> Draft -> Draft
changeExpenses change draft =
    case draft.expenses of
        WithExpenses expenses ->
            { draft | expenses = WithExpenses (change expenses) }

        NoExpenses ->
            draft


{-| Ask what the rules would say, if the form is complete and says something
it has not already been asked about.
-}
refreshPreview : Model -> ( Model, Cmd Msg )
refreshPreview model =
    case model.rules of
        Loaded rules ->
            case ( Draft.validate rules model.draft, model.preview ) of
                ( Ok claim, PreviewFor asked _ ) ->
                    if asked == claim then
                        ( model, Cmd.none )

                    else
                        askFor claim model

                ( Ok claim, NoPreview ) ->
                    askFor claim model

                ( Err _, _ ) ->
                    ( { model | preview = NoPreview }, Cmd.none )

        _ ->
            ( { model | preview = NoPreview }, Cmd.none )


askFor : NewClaim -> Model -> ( Model, Cmd Msg )
askFor claim model =
    ( { model | preview = PreviewFor claim Loading }, Api.postAssessment claim (GotPreview claim) )



-- VIEW


view : Model -> { title : String, body : List (Html Msg) }
view model =
    { title = "Meld krav"
    , body =
        [ h1 [] [ text "Meld krav om erstatning" ]
        , p [ class "lead" ]
            [ text "Velg avgangen du reiste med, og oppgi billetten. Du ser hva du kan forvente før du sender kravet." ]
        , case model.rules of
            Loading ->
                View.Layout.loading

            Failed error ->
                View.Problem.view { retry = Just ( "Prøv igjen", RulesRetried ) } error

            Loaded rules ->
                viewForm rules model
        ]
    }


viewForm : Rules -> Model -> Html Msg
viewForm rules model =
    let
        problems : Field -> Maybe String -> List String
        problems field limit =
            FieldError.for field model.errors
                |> List.map (View.Problem.field { limit = limit })
    in
    form [ class "claim-form", onSubmit Submitted, novalidate True ]
        [ section []
            [ h2 [] [ text "Reisen" ]
            , div [ class "field" ]
                [ label [ for "reisedato", class "field__label" ] [ text "Reisedato" ]
                , input
                    [ type_ "date"
                    , id "reisedato"
                    , class "field__input field__input--date"
                    , value model.draft.date
                    , onInput DateChanged
                    ]
                    []
                ]
            , viewDepartures (problems DepartureField Nothing) model
            ]
        , section []
            [ h2 [] [ text "Billetten" ]
            , View.Form.choice
                { name = "billettype"
                , legend = "Hva slags billett hadde du?"
                , options =
                    [ ( "Enkeltbillett", SingleKind )
                    , ( "Periodebillett, 7 dager", PeriodKind SevenDays )
                    , ( "Periodebillett, 30 dager", PeriodKind ThirtyDays )
                    ]
                , chosen = Just model.draft.ticketKind
                , onChoose = TicketKindChosen
                , problems = problems ValidityField Nothing
                }
            , View.Form.textField "decimal"
                { id = "pris"
                , label = "Hva kostet billetten?"
                , hint = Just "Hele prisen i kroner, for eksempel 349 eller 349,50."
                , value = model.draft.price
                , onInput = PriceChanged
                , problems = problems PriceField (Just (Money.format rules.maxTicketPrice))
                }
            ]
        , section []
            (h2 [] [ text "Utlegg" ]
                :: label [ class "choice__option" ]
                    [ input
                        [ type_ "checkbox"
                        , checked (model.draft.expenses /= NoExpenses)
                        , onCheck ExpensesToggled
                        ]
                        []
                    , span [] [ text "Jeg betalte selv for annen transport, for eksempel taxi eller buss" ]
                    ]
                :: (case model.draft.expenses of
                        NoExpenses ->
                            []

                        WithExpenses expenses ->
                            [ View.Form.textField "decimal"
                                { id = "utlegg"
                                , label = "Hvor mye betalte du?"
                                , hint =
                                    Just
                                        ("Utlegg dekkes med inntil "
                                            ++ Money.format rules.expenseCap
                                            ++ " når toget er innstilt eller minst "
                                            ++ Format.minutes rules.expenseMinDelayMinutes
                                            ++ " forsinket. En saksbehandler ser på kvitteringen."
                                        )
                                , value = expenses.amount
                                , onInput = ExpensesAmountChanged
                                , problems = problems ExpensesAmountField (Just (Money.format rules.maxClaimedExpenses))
                                }
                            , View.Form.choice
                                { name = "utleggstype"
                                , legend = "Hva betalte du for?"
                                , options = List.map (\kind -> ( Text.expenseKind kind, kind )) Expenses.kinds
                                , chosen = Just expenses.kind
                                , onChoose = ExpensesKindChosen
                                , problems = problems ExpensesKindField Nothing
                                }
                            ]
                   )
            )
        , section [ class "preview", attribute "aria-live" "polite" ]
            [ h2 [] [ text "Dette kan du forvente" ]
            , viewPreview model.preview
            ]
        , View.Problem.formErrors "Kravet er ikke sendt. Rett opp det som er markert, og send på nytt." model.errors
        , case model.submission of
            SubmitFailed error ->
                View.Problem.view { retry = Nothing } error

            _ ->
                text ""
        , button [ type_ "submit", class "button", disabled (model.submission == Submitting) ]
            [ text
                (if model.submission == Submitting then
                    "Sender kravet …"

                 else
                    "Send kravet"
                )
            ]
        ]


viewDepartures : List String -> Model -> Html Msg
viewDepartures problems model =
    case model.departures of
        NoDate ->
            p [ class "hint" ] [ text "Velg en dato for å se avgangene." ]

        For _ Loading ->
            View.Layout.loading

        For _ (Failed error) ->
            View.Problem.view { retry = Just ( "Prøv igjen", DeparturesRetried ) } error

        For _ (Loaded []) ->
            p [ class "hint" ]
                [ text "Ingen avganger har gått denne dagen ennå. Du kan melde krav fra toget skulle ha gått." ]

        For _ (Loaded departures) ->
            fieldset
                (class "departures"
                    :: (if List.isEmpty problems then
                            []

                        else
                            [ attribute "aria-describedby" "avgang-problems" ]
                       )
                )
                (legend [ class "field__label" ] [ text "Hvilken avgang reiste du med?" ]
                    :: List.map (viewDeparture model.draft.departure) departures
                    ++ [ if List.isEmpty problems then
                            text ""

                         else
                            div [ id "avgang-problems", class "field__problems" ]
                                (List.map (\problem -> p [] [ text problem ]) problems)
                       ]
                )


viewDeparture : Maybe Departure.Id -> Departure -> Html Msg
viewDeparture chosen departure =
    label [ class "departure" ]
        [ input
            [ type_ "radio"
            , name "avgang"
            , checked (chosen == Just departure.id)
            , onCheck (\_ -> DepartureChosen departure.id)
            ]
            []
        , span [ class "departure__time" ] [ text departure.scheduledDeparture ]
        , span [ class "departure__train" ] [ text departure.trainNumber ]
        , span [ class "departure__route" ] [ text (departure.origin ++ " – " ++ departure.destination) ]
        , span [ class ("tag " ++ outcomeClass departure.outcome) ] [ text (Format.outcome departure.outcome) ]
        ]


outcomeClass : Outcome -> String
outcomeClass outcome =
    case outcome of
        Ran 0 ->
            "tag--on-time"

        Ran _ ->
            "tag--late"

        Cancelled ->
            "tag--cancelled"


viewPreview : Preview -> Html Msg
viewPreview preview =
    case preview of
        NoPreview ->
            p [ class "hint" ] [ text "Når du har valgt avgang og oppgitt prisen, ser du utregningen her." ]

        PreviewFor _ Loading ->
            View.Layout.loading

        PreviewFor _ (Failed error) ->
            View.Problem.view { retry = Just ( "Prøv igjen", PreviewRetried ) } error

        PreviewFor _ (Loaded assessment) ->
            View.Calculation.assessment assessment
