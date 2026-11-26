module Page.ReviewClaim exposing (Model, Msg(..), Saving(..), init, update, view)

{-| An officer's view of one claim: the same facts the passenger sees, and
the decision that is theirs to make.

What an officer can do follows from the claim's status. A claim that waits for
review gets the decision form, an approved claim gets the payout button, and
anything else gets neither. There is no "can decide" flag to keep in step with
the status: the view matches on the status, and so does `update`.

-}

import Api
import Claim exposing (Claim, Status(..))
import Claim.Calculation exposing (Calculation, ExpenseAssessment(..))
import Claim.Decision as Decision exposing (Choice(..))
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
import Time
import View.Claim
import View.Form
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


init : Id -> ( Model, Cmd Msg )
init id =
    ( { id = id
      , claim = Loading
      , draft = Decision.empty
      , saving = Idle
      , errors = []
      }
    , Api.getClaim id GotClaim
    )



-- UPDATE


type Msg
    = GotClaim (Result Api.Error Claim)
    | Reloaded
    | ChoiceChanged Choice
    | ApprovedExpensesChanged String
    | NoteChanged String
    | OfficerChanged String
    | DecisionSubmitted
    | PayoutRequested
    | GotSaved (Result Api.Error Claim)


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        GotClaim result ->
            ( { model | claim = Remote.fromResult result }, Cmd.none )

        Reloaded ->
            ( { model | claim = Loading, saving = Idle }, Api.getClaim model.id GotClaim )

        ChoiceChanged choice ->
            ( edit ReasonField (\draft -> { draft | choice = choice }) model, Cmd.none )

        ApprovedExpensesChanged amount ->
            ( edit ApprovedExpensesField (\draft -> { draft | approvedExpenses = amount }) model, Cmd.none )

        NoteChanged note ->
            ( edit NoteField (\draft -> { draft | note = note }) model, Cmd.none )

        OfficerChanged officer ->
            ( edit OfficerField (\draft -> { draft | officer = officer }) model, Cmd.none )

        DecisionSubmitted ->
            case ( model.saving, model.claim ) of
                ( Saving, _ ) ->
                    ( model, Cmd.none )

                ( _, Loaded claim ) ->
                    case claim.status of
                        AwaitingReview { calculation } ->
                            case Decision.validate { maxCoverable = maxCoverable calculation } model.draft of
                                Ok decision ->
                                    ( { model | saving = Saving, errors = [] }
                                    , Api.postDecision claim.id claim.version decision GotSaved
                                    )

                                Err errors ->
                                    ( { model | saving = Idle, errors = errors }, Cmd.none )

                        _ ->
                            ( model, Cmd.none )

                _ ->
                    ( model, Cmd.none )

        PayoutRequested ->
            case ( model.saving, model.claim ) of
                ( Saving, _ ) ->
                    ( model, Cmd.none )

                ( _, Loaded claim ) ->
                    case claim.status of
                        Approved _ ->
                            ( { model | saving = Saving }, Api.postPayout claim.id claim.version GotSaved )

                        _ ->
                            ( model, Cmd.none )

                _ ->
                    ( model, Cmd.none )

        GotSaved (Ok claim) ->
            ( { model | claim = Loaded claim, draft = Decision.empty, saving = Idle, errors = [] }, Cmd.none )

        GotSaved (Err (Api.Invalid errors)) ->
            ( { model | saving = Idle, errors = errors }, Cmd.none )

        GotSaved (Err error) ->
            -- What the officer typed is kept, so nothing has to be written twice.
            ( { model | saving = SaveFailed error }, Cmd.none )


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



-- VIEW


view : Time.Zone -> Model -> { title : String, body : List (Html Msg) }
view zone model =
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
                        [ View.Claim.view zone claim
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


{-| What can be done to the claim as it stands.
-}
viewActions : Claim -> Model -> List (Html Msg)
viewActions claim model =
    case claim.status of
        AwaitingReview { calculation } ->
            [ viewDecisionForm calculation model ]

        Approved { calculation } ->
            [ p [] [ text ("Kravet er innvilget. " ++ Money.format calculation.total ++ " er klart til utbetaling.") ]
            , button [ type_ "button", class "button", onClick PayoutRequested, disabled (model.saving == Saving) ]
                [ text
                    (if model.saving == Saving then
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
                |> List.map (View.Problem.field { limit = limit })

        isApproving : Bool
        isApproving =
            model.draft.choice == Approving
    in
    form [ class "decision__form", onSubmit DecisionSubmitted, novalidate True ]
        (List.concat
            [ [ View.Form.choice
                    { name = "vedtak"
                    , legend = "Hva blir vedtaket?"
                    , options = [ ( "Innvilg kravet", True ), ( "Avslå kravet", False ) ]
                    , chosen = Just isApproving
                    , onChoose =
                        \approve ->
                            if approve then
                                ChoiceChanged Approving

                            else
                                ChoiceChanged (Rejecting InvalidTicket)
                    , problems = []
                    }
              ]
            , case ( model.draft.choice, maxCoverable calculation ) of
                ( Approving, Just limit ) ->
                    [ View.Form.textField "decimal"
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
                        , options = List.map (\option -> ( Text.rejectionReason option, option )) Reason.rejectionReasons
                        , chosen = Just reason
                        , onChoose = \option -> ChoiceChanged (Rejecting option)
                        , problems = problems ReasonField Nothing
                        }
                    ]
            , [ View.Form.textArea
                    { id = "begrunnelse"
                    , label = "Begrunnelse"
                    , hint =
                        Just
                            (if isApproving then
                                "Valgfritt. Passasjeren ser det du skriver."

                             else
                                "Forklar avslaget. Passasjeren ser det du skriver."
                            )
                    , value = model.draft.note
                    , onInput = NoteChanged
                    , problems = problems NoteField Nothing
                    }
              , View.Form.textField "text"
                    { id = "saksbehandler"
                    , label = "Dine initialer"
                    , hint = Just "2 til 10 bokstaver."
                    , value = model.draft.officer
                    , onInput = OfficerChanged
                    , problems = problems OfficerField Nothing
                    }
              , View.Problem.formErrors "Vedtaket er ikke lagret. Rett opp det som er markert, og prøv igjen." model.errors
              , button [ type_ "submit", class "button", disabled (model.saving == Saving) ]
                    [ text
                        (case ( model.saving, isApproving ) of
                            ( Saving, _ ) ->
                                "Lagrer vedtaket …"

                            ( _, True ) ->
                                "Innvilg kravet"

                            ( _, False ) ->
                                "Avslå kravet"
                        )
                    ]
              ]
            ]
        )
