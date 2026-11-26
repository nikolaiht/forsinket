module Page.NewClaim exposing (Departures(..), Effect(..), Model, Msg(..), Preview(..), Submission(..), init, perform, update, view)

{-| The form a passenger makes a claim with.

The model has no flags. Whether the departures are loading, whether there is a
preview, whether the claim is on its way: each is a type with one value per
situation, so the page cannot be in two of them at once.

-}

import Api
import Browser.Dom as Dom
import Browser.Navigation as Nav
import Claim exposing (Claim)
import Claim.Calculation exposing (Assessment)
import Claim.Draft as Draft exposing (Draft, ExpensesDraft(..), NewClaim, TicketKind(..))
import Claim.Expenses as Expenses
import Claim.Id exposing (Id)
import Claim.Ticket exposing (Validity(..))
import Date exposing (Date)
import Departure exposing (Departure, Outcome(..))
import FieldError exposing (Field(..), FieldError)
import Html exposing (Html, button, div, fieldset, form, h1, h2, input, label, legend, p, section, span, text)
import Html.Attributes exposing (attribute, checked, class, disabled, for, id, name, novalidate, type_, value)
import Html.Events exposing (onCheck, onInput, onSubmit)
import Money
import Remote exposing (Remote(..))
import Route
import Rules exposing (Rules)
import Task
import Time
import View.Calculation
import View.Form exposing (InputMode(..))
import View.Format as Format
import View.Layout
import View.Problem
import View.Text as Text


type alias Model =
    { rules : Remote Api.Error Rules
    , date : String
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


{-| While a claim is on its way, the page remembers which claim. The form is
locked until the answer comes, and only the answer about that claim counts.
-}
type Submission
    = NotSubmitted
    | Submitting NewClaim
    | SubmitFailed Api.Error


{-| What the page asks to have done. `update` returns these as values and
never builds a command itself, so a test can see exactly what was asked for.
`perform` is the only place they become commands.
-}
type Effect
    = FetchRules
    | FetchToday
    | FetchDepartures Date
    | AskForPreview NewClaim
    | SendClaim NewClaim
    | ShowClaim Id
    | FocusErrors


init : ( Model, List Effect )
init =
    ( { rules = Loading
      , date = ""
      , draft = Draft.empty
      , departures = NoDate
      , preview = NoPreview
      , submission = NotSubmitted
      , errors = []
      }
    , [ FetchRules, FetchToday ]
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
    | GotSubmit NewClaim (Result Api.Error Claim)
    | NoOp


update : Msg -> Model -> ( Model, List Effect )
update msg model =
    case ( msg, model.submission ) of
        ( GotSubmit sent result, Submitting claim ) ->
            if sent == claim then
                submitted result model

            else
                ( model, [] )

        ( GotSubmit _ _, _ ) ->
            -- An answer about a claim this page is not waiting for.
            ( model, [] )

        ( GotRules result, _ ) ->
            refreshPreview { model | rules = Remote.fromResult result }

        ( GotDepartures date result, _ ) ->
            case model.departures of
                For chosen _ ->
                    if chosen == date then
                        ( { model | departures = For date (Remote.fromResult result) }, [] )

                    else
                        ( model, [] )

                NoDate ->
                    ( model, [] )

        ( GotPreview claim result, _ ) ->
            gotPreview claim result model

        ( NoOp, _ ) ->
            ( model, [] )

        ( _, Submitting _ ) ->
            -- The claim is on its way. Whatever the passenger does to the form
            -- now would be about a claim that has already been sent.
            ( model, [] )

        ( RulesRetried, _ ) ->
            ( { model | rules = Loading }, [ FetchRules ] )

        ( GotToday today, _ ) ->
            if String.isEmpty model.date then
                chooseDate (Date.toIsoString today) model

            else
                ( model, [] )

        ( DateChanged date, _ ) ->
            chooseDate date model

        ( DeparturesRetried, _ ) ->
            chooseDate model.date model

        ( DepartureChosen departure, _ ) ->
            edit DepartureField (\draft -> { draft | departure = Just departure }) model

        ( TicketKindChosen kind, _ ) ->
            edit ValidityField (\draft -> { draft | ticketKind = kind }) model

        ( PriceChanged price, _ ) ->
            edit PriceField (\draft -> { draft | price = price }) model

        ( ExpensesToggled True, _ ) ->
            edit ExpensesAmountField
                (\draft -> { draft | expenses = WithExpenses { amount = "", kind = Expenses.Taxi } })
                model

        ( ExpensesToggled False, _ ) ->
            edit ExpensesAmountField (\draft -> { draft | expenses = NoExpenses }) model

        ( ExpensesAmountChanged amount, _ ) ->
            edit ExpensesAmountField (changeExpenses (\expenses -> { expenses | amount = amount })) model

        ( ExpensesKindChosen kind, _ ) ->
            edit ExpensesKindField (changeExpenses (\expenses -> { expenses | kind = kind })) model

        ( PreviewRetried, _ ) ->
            refreshPreview { model | preview = NoPreview }

        ( Submitted, _ ) ->
            case model.rules of
                Loaded rules ->
                    case Draft.validate rules model.draft of
                        Ok claim ->
                            ( { model | submission = Submitting claim, errors = [] }, [ SendClaim claim ] )

                        Err errors ->
                            ( { model | submission = NotSubmitted, errors = errors }, [ FocusErrors ] )

                _ ->
                    ( model, [] )


submitted : Result Api.Error Claim -> Model -> ( Model, List Effect )
submitted result model =
    case result of
        Ok claim ->
            ( model, [ ShowClaim claim.id ] )

        Err (Api.Invalid errors) ->
            ( { model | submission = NotSubmitted, errors = errors }, [ FocusErrors ] )

        Err error ->
            ( { model | submission = SubmitFailed error }, [] )


gotPreview : NewClaim -> Result Api.Error Assessment -> Model -> ( Model, List Effect )
gotPreview claim result model =
    case ( model.preview, result ) of
        ( NoPreview, _ ) ->
            ( model, [] )

        ( PreviewFor asked _, Err (Api.Invalid errors) ) ->
            if asked == claim then
                -- The form looked complete here, but the service will not have
                -- it. The reasons belong on the fields, where they can be fixed.
                ( { model | preview = NoPreview, errors = errors }, [] )

            else
                ( model, [] )

        ( PreviewFor asked _, _ ) ->
            if asked == claim then
                ( { model | preview = PreviewFor claim (Remote.fromResult result) }, [] )

            else
                ( model, [] )


{-| A new date means new departures, so whatever departure was chosen no
longer applies.
-}
chooseDate : String -> Model -> ( Model, List Effect )
chooseDate raw model =
    let
        draft : Draft
        draft =
            model.draft

        withDate : Model
        withDate =
            { model
                | date = raw
                , draft = { draft | departure = Nothing }
                , errors = List.filter (\error -> error.field /= DepartureField) model.errors
                , submission = NotSubmitted
            }
    in
    case parseDate raw of
        Just date ->
            refreshPreview { withDate | departures = For date Loading }
                |> Tuple.mapSecond ((::) (FetchDepartures date))

        Nothing ->
            refreshPreview { withDate | departures = NoDate }


{-| `Date.fromIsoString` also reads `2026-11` and `2026-W47-1`. A date field
gives `2026-11-20` or nothing, so only that form counts.
-}
parseDate : String -> Maybe Date
parseDate raw =
    if String.length raw == 10 && String.all (\char -> Char.isDigit char || char == '-') raw then
        Result.toMaybe (Date.fromIsoString raw)

    else
        Nothing


{-| Change one field. Its errors are about what it used to say, so they go,
and the preview is asked for again if the form now says something else.
-}
edit : Field -> (Draft -> Draft) -> Model -> ( Model, List Effect )
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
refreshPreview : Model -> ( Model, List Effect )
refreshPreview model =
    case model.rules of
        Loaded rules ->
            case ( Draft.validate rules model.draft, model.preview ) of
                ( Ok claim, PreviewFor asked _ ) ->
                    if asked == claim then
                        ( model, [] )

                    else
                        ( { model | preview = PreviewFor claim Loading }, [ AskForPreview claim ] )

                ( Ok claim, NoPreview ) ->
                    ( { model | preview = PreviewFor claim Loading }, [ AskForPreview claim ] )

                ( Err _, _ ) ->
                    ( { model | preview = NoPreview }, [] )

        _ ->
            ( { model | preview = NoPreview }, [] )


perform : Nav.Key -> Effect -> Cmd Msg
perform key effect =
    case effect of
        FetchRules ->
            Api.getRules GotRules

        FetchToday ->
            Task.perform (Format.dateIn Format.oslo >> GotToday) Time.now

        FetchDepartures date ->
            Api.getDepartures date (GotDepartures date)

        AskForPreview claim ->
            Api.postAssessment claim (GotPreview claim)

        SendClaim claim ->
            Api.postClaim claim (GotSubmit claim)

        ShowClaim claimId ->
            Nav.pushUrl key (Route.toString (Route.Claim claimId))

        FocusErrors ->
            Task.attempt (\_ -> NoOp) (Dom.focus View.Problem.formErrorsId)



-- VIEW


view : Model -> { title : String, body : List (Html Msg) }
view model =
    { title = "Meld krav"
    , body =
        [ h1 [] [ text "Meld krav om erstatning" ]
        , p [ class "lead" ]
            [ text "Velg avgangen du reiste med, og oppgi billettype og pris. Du ser hva du kan forvente før du sender kravet." ]
        , case model.rules of
            Loading ->
                View.Layout.loading

            Failed error ->
                View.Problem.view { retry = Just ( "Prøv igjen", RulesRetried ) } error

            Loaded rules ->
                viewForm rules model
        ]
    }


isSubmitting : Model -> Bool
isSubmitting model =
    case model.submission of
        Submitting _ ->
            True

        _ ->
            False


viewForm : Rules -> Model -> Html Msg
viewForm rules model =
    let
        problems : Field -> Maybe String -> List String
        problems field limit =
            FieldError.for field model.errors
                |> List.map (View.Problem.field { limit = limit } field)
    in
    form [ class "claim-form", onSubmit Submitted, novalidate True ]
        [ -- One fieldset around every input, so that all of them are locked
          -- with a single attribute while the claim is on its way.
          fieldset [ class "claim-form__fields", disabled (isSubmitting model) ]
            [ section []
                [ h2 [] [ text "Reisen" ]
                , div [ class "field" ]
                    [ label [ for "reisedato", class "field__label" ] [ text "Reisedato" ]
                    , input
                        [ type_ "date"
                        , id "reisedato"
                        , class "field__input"
                        , value model.date
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
                    , chosen = model.draft.ticketKind
                    , onChoose = TicketKindChosen
                    , problems = problems ValidityField Nothing
                    }
                , View.Form.textField Decimal
                    { id = "pris"
                    , label = "Hva kostet billetten?"
                    , hint = Just "Hele prisen i kroner, for eksempel 349 eller 349,50."
                    , value = model.draft.price
                    , onInput = PriceChanged
                    , problems = problems PriceField (Just (Money.format rules.maxTicketPrice))
                    }
                ]
            , section [] (h2 [] [ text "Utlegg" ] :: viewExpenses rules problems model.draft.expenses)
            ]
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
        , button [ type_ "submit", class "button", disabled (isSubmitting model) ]
            [ text
                (if isSubmitting model then
                    "Sender kravet …"

                 else
                    "Send kravet"
                )
            ]
        ]


viewExpenses : Rules -> (Field -> Maybe String -> List String) -> ExpensesDraft -> List (Html Msg)
viewExpenses rules problems expenses =
    label [ class "choice__option" ]
        [ input
            [ type_ "checkbox"
            , checked
                (case expenses of
                    WithExpenses _ ->
                        True

                    NoExpenses ->
                        False
                )
            , onCheck ExpensesToggled
            ]
            []
        , span [] [ text "Jeg betalte selv for annen transport, for eksempel taxi eller buss" ]
        ]
        :: (case expenses of
                NoExpenses ->
                    []

                WithExpenses { amount, kind } ->
                    [ View.Form.textField Decimal
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
                        , value = amount
                        , onInput = ExpensesAmountChanged
                        , problems = problems ExpensesAmountField (Just (Money.format rules.maxClaimedExpenses))
                        }
                    , View.Form.choice
                        { name = "utleggstype"
                        , legend = "Hva betalte du for?"
                        , options = List.map (\option -> ( Text.expenseKind option, option )) Expenses.kinds
                        , chosen = kind
                        , onChoose = ExpensesKindChosen
                        , problems = problems ExpensesKindField Nothing
                        }
                    ]
           )


{-| The departures of the chosen date, or why there are none to show. A
problem with the departure is shown in every case: there may be no list to
mark, but the passenger still has to be told that a departure is missing.
-}
viewDepartures : List String -> Model -> Html Msg
viewDepartures problems model =
    let
        problemList : Html Msg
        problemList =
            if List.isEmpty problems then
                text ""

            else
                div [ id "avgang-problems", class "field__problems" ]
                    (List.map (\problem -> p [] [ text problem ]) problems)
    in
    case model.departures of
        NoDate ->
            div [] [ p [ class "hint" ] [ text "Velg en dato for å se avgangene." ], problemList ]

        For _ Loading ->
            div [] [ View.Layout.loading, problemList ]

        For _ (Failed error) ->
            div [] [ View.Problem.view { retry = Just ( "Prøv igjen", DeparturesRetried ) } error, problemList ]

        For _ (Loaded []) ->
            div []
                [ p [ class "hint" ]
                    [ text "Ingen avganger har gått denne dagen ennå. Du kan melde krav når avgangstiden er passert." ]
                , problemList
                ]

        For _ (Loaded departures) ->
            let
                describedByProblems : List (Html.Attribute Msg)
                describedByProblems =
                    if List.isEmpty problems then
                        []

                    else
                        [ attribute "aria-describedby" "avgang-problems" ]
            in
            fieldset (class "departures" :: describedByProblems)
                (legend [ class "field__label" ] [ text "Hvilken avgang reiste du med?" ]
                    :: List.map (viewDeparture model.draft.departure) departures
                    ++ [ problemList ]
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
