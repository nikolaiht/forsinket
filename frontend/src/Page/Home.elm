module Page.Home exposing (Effect(..), Model, Msg, init, perform, update, view)

{-| The front page: what the service does, in the time it takes to read one
screen.

The numbers on it are not typed in here. The scale of delays, the deadline and
the limits are drawn from the rule set the service publishes, and the examples
are worked out by the service with the function that settles real claims.

-}

import Api
import Claim.Expenses exposing (Expenses)
import Departure exposing (Outcome(..))
import Example exposing (Example)
import Html exposing (Html, a, div, h1, h2, h3, li, ol, p, section, span, text, ul)
import Html.Attributes exposing (attribute, class)
import Money
import Remote exposing (Remote(..))
import Route
import Rules exposing (Band, Rules)
import Status
import View.Calculation
import View.Format as Format
import View.Layout
import View.Problem
import View.Text as Text


type alias Model =
    { rules : Remote Api.Error Rules
    , examples : Remote Api.Error (List Example)
    }


type Effect
    = FetchRules
    | FetchExamples


init : ( Model, List Effect )
init =
    ( { rules = Loading, examples = Loading }, [ FetchRules, FetchExamples ] )


type Msg
    = GotRules (Result Api.Error Rules)
    | GotExamples (Result Api.Error (List Example))
    | Retried


update : Msg -> Model -> ( Model, List Effect )
update msg model =
    case msg of
        GotRules result ->
            ( { model | rules = Remote.fromResult result }, [] )

        GotExamples result ->
            ( { model | examples = Remote.fromResult result }, [] )

        Retried ->
            init


perform : Effect -> Cmd Msg
perform effect =
    case effect of
        FetchRules ->
            Api.getRules GotRules

        FetchExamples ->
            Api.getExamples GotExamples


view : Model -> { title : String, body : List (Html Msg) }
view model =
    { title = "Erstatning ved forsinkelse"
    , body =
        section [ class "hero" ]
            [ h1 [] [ text "Ble toget forsinket? Se hva du har krav på." ]
            , p [ class "lead" ]
                [ text "Velg avgangen du reiste med. Forsinkelsen er allerede registrert, så du ser beløpet og utregningen før du sender kravet." ]
            , p [ class "actions" ]
                [ a [ class "button", Route.href Route.NewClaim ] [ text "Meld krav" ]
                , a [ class "button button--quiet", Route.href (Route.ReviewQueue (Route.Only Status.AwaitingReview)) ]
                    [ text "Se saksbehandlingen" ]
                ]
            ]
            :: viewContent model
    }


{-| The rules and the examples come from two requests. When the service cannot
be reached both fail, and saying so once is enough.
-}
viewContent : Model -> List (Html Msg)
viewContent model =
    case ( model.rules, model.examples ) of
        ( Failed error, _ ) ->
            [ View.Problem.view { retry = Just ( "Prøv igjen", Retried ) } error ]

        ( _, Failed error ) ->
            [ View.Problem.view { retry = Just ( "Prøv igjen", Retried ) } error ]

        ( Loaded rules, Loaded examples ) ->
            viewRules rules
                ++ [ section []
                        [ h2 [] [ text "Eksempler" ]
                        , div [ class "examples" ] (List.map viewExample examples)
                        ]
                   ]

        _ ->
            [ View.Layout.loading ]


viewRules : Rules -> List (Html msg)
viewRules rules =
    [ section []
        [ h2 [] [ text "Så mye av billetten får du tilbake" ]
        , ol [ class "scale" ]
            (List.map2 viewBand rules.bands (List.map (.fromMinutes >> Just) (List.drop 1 rules.bands) ++ [ Nothing ]))
        , ul [ class "terms" ]
            [ li [] [ text ("Kravet må meldes innen " ++ String.fromInt rules.claimDeadlineDays ++ " dager etter reisen.") ]
            , li [] [ text "For en periodebillett regnes erstatningen av prisen delt på antall dager billetten gjelder." ]
            , li []
                [ text
                    ("Utlegg til annen transport dekkes med inntil "
                        ++ Money.format rules.expenseCap
                        ++ " når toget er innstilt eller minst "
                        ++ Format.minutes rules.expenseMinDelayMinutes
                        ++ " forsinket."
                    )
                ]
            ]
        ]
    , section []
        [ h2 [] [ text "Slik går det til" ]
        , ol [ class "steps" ]
            [ li [] [ text "Du velger avgangen og oppgir billettype og pris. Beløpet regnes ut etter reglene, trinn for trinn." ]
            , li []
                [ text
                    ("Krav uten utlegg avgjøres med en gang, så lenge erstatningen for billetten er høyst "
                        ++ Money.format rules.autoApprovalLimit
                        ++ "."
                    )
                ]
            , li [] [ text "Har du betalt for taxi eller buss, eller er beløpet høyere, ser en saksbehandler på kravet før det avgjøres." ]
            ]
        ]
    ]


{-| One step on the scale of delays: from this band's minutes up to the next
band's, or with no upper end for the last one. The bar above the number is
filled to the band's own percentage.
-}
viewBand : Band -> Maybe Int -> Html msg
viewBand band next =
    li
        [ class "scale__band"

        -- A CSS custom property cannot be set with `Html.Attributes.style`.
        , attribute "style" ("--share: " ++ String.fromInt band.percent ++ "%")
        ]
        [ span [ class "scale__percent" ] [ text (String.fromInt band.percent ++ "\u{00A0}%") ]
        , span [ class "scale__minutes" ]
            [ text
                (case next of
                    Just upTo ->
                        String.fromInt band.fromMinutes ++ "–" ++ String.fromInt (upTo - 1) ++ " minutter"

                    Nothing ->
                        String.fromInt band.fromMinutes ++ " minutter eller mer, eller innstilt"
                )
            ]
        ]


viewExample : Example -> Html msg
viewExample example =
    div [ class "example" ]
        [ h3 [] [ text (describe example) ]
        , View.Calculation.assessment example.assessment
        ]


{-| `Enkeltbillett til 349,00 kr, 75 minutter forsinket`
-}
describe : Example -> String
describe example =
    Text.ticket example.ticket
        ++ ", "
        ++ outcomeText example.outcome
        ++ expensesText example.expenses


outcomeText : Outcome -> String
outcomeText outcome =
    case outcome of
        Ran delay ->
            Format.minutes delay ++ " forsinket"

        Cancelled ->
            "innstilt avgang"


expensesText : Maybe Expenses -> String
expensesText expenses =
    case expenses of
        Just { amount, kind } ->
            ", og " ++ String.toLower (Text.expenseKind kind) ++ " til " ++ Money.format amount

        Nothing ->
            ""
