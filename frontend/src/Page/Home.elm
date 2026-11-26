module Page.Home exposing (Model, Msg, init, update, view)

{-| The front page: what the service does, in the time it takes to read one
screen.

Nothing on it is written down twice. The scale of delays is drawn from the
rule set the service publishes, and the examples are worked out by the service
with the function that settles real claims.

-}

import Api
import Claim.Expenses exposing (Expenses)
import Departure exposing (Outcome(..))
import Example exposing (Example)
import Html exposing (Html, a, div, h1, h2, h3, li, ol, p, section, span, text, ul)
import Html.Attributes exposing (class)
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


init : ( Model, Cmd Msg )
init =
    ( { rules = Loading, examples = Loading }
    , Cmd.batch [ Api.getRules GotRules, Api.getExamples GotExamples ]
    )


type Msg
    = GotRules (Result Api.Error Rules)
    | GotExamples (Result Api.Error (List Example))
    | Retried


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        GotRules result ->
            ( { model | rules = Remote.fromResult result }, Cmd.none )

        GotExamples result ->
            ( { model | examples = Remote.fromResult result }, Cmd.none )

        Retried ->
            init


view : Model -> { title : String, body : List (Html Msg) }
view model =
    { title = "Erstatning ved forsinkelse"
    , body =
        [ section [ class "hero" ]
            [ h1 [] [ text "Ble toget forsinket? Se hva du har krav på." ]
            , p [ class "lead" ]
                [ text "Velg avgangen du reiste med. Forsinkelsen er allerede registrert, så du ser beløpet og utregningen før du sender kravet." ]
            , p [ class "actions" ]
                [ a [ class "button", Route.href Route.NewClaim ] [ text "Meld krav" ]
                , a [ class "button button--quiet", Route.href (Route.ReviewQueue (Route.Only Status.AwaitingReview)) ]
                    [ text "Se saksbehandlingen" ]
                ]
            ]
        , case model.rules of
            Loading ->
                View.Layout.loading

            Failed error ->
                View.Problem.view { retry = Just ( "Prøv igjen", Retried ) } error

            Loaded rules ->
                viewRules rules
        , section []
            [ h2 [] [ text "Slik går det til" ]
            , ol [ class "steps" ]
                [ li [] [ text "Du velger avgangen og oppgir billetten. Reglene regner ut beløpet, trinn for trinn." ]
                , li [] [ text "Krav uten utlegg avgjøres med en gang." ]
                , li [] [ text "Har du betalt for taxi eller buss, ser en saksbehandler på kvitteringen før kravet avgjøres." ]
                ]
            ]
        , section []
            [ h2 [] [ text "Fire eksempler" ]
            , case model.examples of
                Loading ->
                    View.Layout.loading

                Failed error ->
                    View.Problem.view { retry = Just ( "Prøv igjen", Retried ) } error

                Loaded examples ->
                    div [ class "examples" ] (List.map viewExample examples)
            ]
        ]
    }


viewRules : Rules -> Html msg
viewRules rules =
    section []
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


{-| One step on the scale of delays: from this band's minutes up to the next
band's, or with no upper end for the last one.
-}
viewBand : Band -> Maybe Int -> Html msg
viewBand band next =
    li [ class "scale__band" ]
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
