module Page.ReviewClaim exposing (Effect(..), Model, Msg(..), Saving(..), init, perform, update, view)

{-| An officer's view of one claim: the same facts the passenger sees, and
the decision that is theirs to make.

What an officer can do follows from the claim's status. A claim that waits for
review gets the decision form, an approved claim gets the payout button, and
anything else gets neither. There is no "can decide" flag to keep in step with
the status: the view matches on the status, and so does `update`.

-}

import Api
import Browser.Dom as Dom
import Claim exposing (Claim, Status(..))
import Claim.Calculation exposing (Calculation, ExpenseAssessment(..))
import Claim.Decision as Decision exposing (Choice(..), Decision)
import Claim.Id exposing (Id)
import Claim.Reason as Reason exposing (RejectionReason(..))
import FieldError exposing (Field(..), FieldError)
import Html exposing (Html, a, button, form, h1, h2, p, section, text)
import Html.Attributes exposing (class, disabled, novalidate, type_)
import Html.Events exposing (onClick, onSubmit)
import Money exposing (Money)
import Remote exposing (Remote(..))
import Route
import Status
import Task
import View.Claim
import View.Form exposing (InputMode(..))
import View.Layout
import View.Problem
import View.Text as Text


type alias Model =
    { id : Id
    , claim : Remote Api.Error Claim
    , draft : Decision.Draft
    , saving : Saving
    , errors : List FieldError
    }


type Saving
    = Idle
    | Saving
    | SaveFailed Api.Error


{-| What the page asks to have done. `update` returns these as values, and
`perform` turns them into commands. A test can therefore check that a decision
is sent for the right claim and the right version, without sending anything.
-}
type Effect
    = FetchClaim Id
    | SendDecision Id Int Decision
    | SendPayout Id Int
    | FocusErrors


init : Id -> ( Model, List Effect )
init id =
    ( { id = id
      , claim = Loading
      , draft = Decision.empty
      , saving = Idle
      , errors = []
      }
    , [ FetchClaim id ]
    )



-- UPDATE


{-| Every answer says which claim it is about. An answer about another claim
than the one on the page, from a request made before the officer moved on, is
dropped: showing it would put one claim's facts above another claim's form.
-}
type Msg
    = GotClaim Id (Result Api.Error Claim)
    | Reloaded
    | ChoiceChanged Choice
    | ApprovedExpensesChanged String
    | NoteChanged String
    | OfficerChanged String
    | DecisionSubmitted
    | PayoutRequested
    | GotSaved Id (Result Api.Error Claim)
    | NoOp


update : Msg -> Model -> ( Model, List Effect )
update msg model =
    case msg of
        GotClaim id result ->
            if id == model.id then
                ( { model | claim = Remote.fromResult result }, [] )

            else
                ( model, [] )

        Reloaded ->
            ( { model | claim = Loading, saving = Idle }, [ FetchClaim model.id ] )

        ChoiceChanged choice ->
            -- The errors were about the fields of the other verdict.
            ( { model | draft = withChoice choice model.draft, errors = [] }, [] )

        ApprovedExpensesChanged amount ->
            ( edit ApprovedExpensesField (\draft -> { draft | approvedExpenses = amount }) model, [] )

        NoteChanged note ->
            ( edit NoteField (\draft -> { draft | note = note }) model, [] )

        OfficerChanged officer ->
            ( edit OfficerField (\draft -> { draft | officer = officer }) model, [] )

        DecisionSubmitted ->
            case ( model.saving, model.claim ) of
                ( Saving, _ ) ->
                    ( model, [] )

                ( _, Loaded claim ) ->
                    case claim.status of
                        AwaitingReview { calculation } ->
                            case Decision.validate { maxCoverable = maxCoverable calculation } model.draft of
                                Ok decision ->
                                    ( { model | saving = Saving, errors = [] }
                                    , [ SendDecision claim.id claim.version decision ]
                                    )

                                Err errors ->
                                    ( { model | saving = Idle, errors = errors }, [ FocusErrors ] )

                        _ ->
                            ( model, [] )

                _ ->
                    ( model, [] )

        PayoutRequested ->
            case ( model.saving, model.claim ) of
                ( Saving, _ ) ->
                    ( model, [] )

                ( _, Loaded claim ) ->
                    case claim.status of
                        Approved _ ->
                            ( { model | saving = Saving }, [ SendPayout claim.id claim.version ] )

                        _ ->
                            ( model, [] )

                _ ->
                    ( model, [] )

        GotSaved id result ->
            if id == model.id then
                saved result model

            else
                ( model, [] )

        NoOp ->
            ( model, [] )


saved : Result Api.Error Claim -> Model -> ( Model, List Effect )
saved result model =
    case ( result, Remote.map .status model.claim ) of
        ( Ok claim, _ ) ->
            ( { model | claim = Loaded claim, draft = Decision.empty, saving = Idle, errors = [] }, [] )

        ( Err (Api.Invalid errors), Loaded (AwaitingReview _) ) ->
            -- The decision form is on the page, so its fields can show what was refused.
            ( { model | saving = Idle, errors = errors }, [ FocusErrors ] )

        ( Err error, _ ) ->
            -- What the officer typed is kept, so nothing has to be written twice.
            ( { model | saving = SaveFailed error }, [] )


withChoice : Choice -> Decision.Draft -> Decision.Draft
withChoice choice draft =
    { draft | choice = choice }


edit : Field -> (Decision.Draft -> Decision.Draft) -> Model -> Model
edit field change model =
    { model
        | draft = change model.draft
        , errors = List.filter (\error -> error.field /= field) model.errors
    }


{-| The most an officer may cover of the claimed expenses, when there are
expenses to review at all.
-}
maxCoverable : Calculation -> Maybe Money
maxCoverable calculation =
    case calculation.expenses of
        PendingReview pending ->
            Just pending.maxCoverable

        _ ->
            Nothing


perform : Effect -> Cmd Msg
perform effect =
    case effect of
        FetchClaim id ->
            Api.getClaim id (GotClaim id)

        SendDecision id version decision ->
            Api.postDecision id version decision (GotSaved id)

        SendPayout id version ->
            Api.postPayout id version (GotSaved id)

        FocusErrors ->
            Task.attempt (\_ -> NoOp) (Dom.focus View.Problem.formErrorsId)



-- VIEW


view : Model -> { title : String, body : List (Html Msg) }
view model =
    { title = "Behandle krav"
    , body =
        p [ class "back" ] [ a [ Route.href (Route.ReviewQueue (Route.Only Status.AwaitingReview)) ] [ text "Til listen over krav" ] ]
            :: h1 [] [ text "Behandle krav" ]
            :: (case model.claim of
                    Loading ->
                        [ View.Layout.loading ]

                    Failed Api.NotFound ->
                        [ View.Problem.view { retry = Nothing } Api.NotFound ]

                    Failed error ->
                        [ View.Problem.view { retry = Just ( "Prøv igjen", Reloaded ) } error ]

                    Loaded claim ->
                        [ View.Claim.view claim
                        , section [ class "decision" ]
                            (h2 [] [ text "Vedtak" ]
                                :: viewActions claim model
                                ++ [ case model.saving of
                                        SaveFailed error ->
                                            View.Problem.view { retry = Just ( "Last inn saken på nytt", Reloaded ) } error

                                        _ ->
                                            text ""
                                   ]
                            )
                        ]
               )
    }


isSaving : Model -> Bool
isSaving model =
    case model.saving of
        Saving ->
            True

        _ ->
            False


{-| What can be done to the claim as it stands.
-}
viewActions : Claim -> Model -> List (Html Msg)
viewActions claim model =
    case claim.status of
        AwaitingReview { calculation } ->
            [ viewDecisionForm calculation model ]

        Approved { calculation } ->
            [ p [] [ text ("Kravet er innvilget. " ++ Money.format calculation.total ++ " er klart til utbetaling.") ]
            , button [ type_ "button", class "button", onClick PayoutRequested, disabled (isSaving model) ]
                [ text
                    (if isSaving model then
                        "Registrerer …"

                     else
                        "Registrer utbetaling"
                    )
                ]
            ]

        Received ->
            [ p [] [ text "Kravet er mottatt, men ikke vurdert ennå." ] ]

        Rejected _ ->
            [ p [] [ text "Kravet er avslått. Saken er ferdig behandlet." ] ]

        PaidOut _ ->
            [ p [] [ text "Kravet er utbetalt. Saken er ferdig behandlet." ] ]


viewDecisionForm : Calculation -> Model -> Html Msg
viewDecisionForm calculation model =
    let
        problems : Field -> Maybe String -> List String
        problems field limit =
            FieldError.for field model.errors
                |> List.map (View.Problem.field { limit = limit } field)

        -- The reject option carries the reason that is chosen, or the first
        -- one, so that picking "reject" always gives a complete choice.
        rejecting : Choice
        rejecting =
            case model.draft.choice of
                Rejecting reason ->
                    Rejecting reason

                Approving ->
                    Rejecting InvalidTicket
    in
    form [ class "decision__form", onSubmit DecisionSubmitted, novalidate True ]
        (List.concat
            [ [ View.Form.choice
                    { name = "vedtak"
                    , legend = "Hva blir vedtaket?"
                    , options = [ ( "Innvilg kravet", Approving ), ( "Avslå kravet", rejecting ) ]
                    , chosen = model.draft.choice
                    , onChoose = ChoiceChanged
                    , problems = []
                    }
              ]
            , case ( model.draft.choice, maxCoverable calculation ) of
                ( Approving, Just limit ) ->
                    [ View.Form.textField Decimal
                        { id = "godkjent-utlegg"
                        , label = "Hvor mye av utlegget godkjennes?"
                        , hint =
                            Just
                                ("Billetterstatningen på "
                                    ++ Money.format calculation.ticketCompensation
                                    ++ " følger av reglene. Av utlegget kan inntil "
                                    ++ Money.format limit
                                    ++ " dekkes."
                                )
                        , value = model.draft.approvedExpenses
                        , onInput = ApprovedExpensesChanged
                        , problems = problems ApprovedExpensesField (Just (Money.format limit))
                        }
                    ]

                ( Approving, Nothing ) ->
                    [ p [ class "hint" ]
                        [ text
                            ("Kravet har ingen utlegg å vurdere. Billetterstatningen på "
                                ++ Money.format calculation.ticketCompensation
                                ++ " følger av reglene."
                            )
                        ]
                    ]

                ( Rejecting reason, _ ) ->
                    [ View.Form.choice
                        { name = "grunn"
                        , legend = "Hvorfor avslås kravet?"
                        , options = List.map (\option -> ( Text.rejectionReason option, Rejecting option )) Reason.rejectionReasons
                        , chosen = Rejecting reason
                        , onChoose = ChoiceChanged
                        , problems = problems ReasonField Nothing
                        }
                    ]
            , [ View.Form.textArea
                    { id = "begrunnelse"
                    , label = "Begrunnelse"
                    , hint =
                        Just
                            (case model.draft.choice of
                                Approving ->
                                    "Valgfritt. Passasjeren ser det du skriver."

                                Rejecting _ ->
                                    "Forklar avslaget. Passasjeren ser det du skriver."
                            )
                    , value = model.draft.note
                    , onInput = NoteChanged
                    , problems = problems NoteField Nothing
                    }
              , View.Form.textField Text
                    { id = "saksbehandler"
                    , label = "Dine initialer"
                    , hint = Just "2 til 10 bokstaver."
                    , value = model.draft.officer
                    , onInput = OfficerChanged
                    , problems = problems OfficerField Nothing
                    }
              , View.Problem.formErrors "Vedtaket er ikke lagret. Rett opp det som er markert, og prøv igjen." model.errors
              , button [ type_ "submit", class "button", disabled (isSaving model) ]
                    [ text
                        (case ( model.saving, model.draft.choice ) of
                            ( Saving, _ ) ->
                                "Lagrer vedtaket …"

                            ( _, Approving ) ->
                                "Innvilg kravet"

                            ( _, Rejecting _ ) ->
                                "Avslå kravet"
                        )
                    ]
              ]
            ]
        )
