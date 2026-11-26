module Page.ReviewQueue exposing (Model, Msg, init, update, view)

{-| The officers' list of claims.
-}

import Api
import Claim
import Html exposing (Html, a, h1, nav, p, table, tbody, td, text, th, thead, tr)
import Html.Attributes exposing (attribute, class, scope)
import Money
import Remote exposing (Remote(..))
import Route exposing (Filter(..))
import Status
import Time
import View.Format as Format
import View.Layout
import View.Problem
import View.Status


type alias Model =
    { filter : Filter
    , claims : Remote Api.Error (List Claim.Summary)
    }


init : Filter -> ( Model, Cmd Msg )
init filter =
    ( { filter = filter, claims = Loading }, fetch filter )


fetch : Filter -> Cmd Msg
fetch filter =
    Api.getClaims (statusOf filter) GotClaims


statusOf : Filter -> Maybe Status.Name
statusOf filter =
    case filter of
        All ->
            Nothing

        Only status ->
            Just status


type Msg
    = GotClaims (Result Api.Error (List Claim.Summary))
    | Retried


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        GotClaims result ->
            ( { model | claims = Remote.fromResult result }, Cmd.none )

        Retried ->
            ( { model | claims = Loading }, fetch model.filter )


view : Time.Zone -> Model -> { title : String, body : List (Html Msg) }
view zone model =
    { title = "Saksbehandling"
    , body =
        [ h1 [] [ text "Saksbehandling" ]
        , p [ class "lead" ]
            [ text "Krav med utlegg, og krav over grensen for automatisk innvilgelse, venter her på en saksbehandler." ]
        , nav [ class "tabs", attribute "aria-label" "Vis krav etter status" ]
            (List.map (tab model.filter)
                [ ( "Til behandling", Only Status.AwaitingReview )
                , ( "Innvilget", Only Status.Approved )
                , ( "Utbetalt", Only Status.PaidOut )
                , ( "Avslått", Only Status.Rejected )
                , ( "Alle", All )
                ]
            )
        , case model.claims of
            Loading ->
                View.Layout.loading

            Failed error ->
                View.Problem.view { retry = Just ( "Prøv igjen", Retried ) } error

            Loaded [] ->
                p [ class "hint" ] [ text (emptyText model.filter) ]

            Loaded claims ->
                table [ class "claims" ]
                    [ thead []
                        [ tr []
                            [ th [ scope "col" ] [ text "Avgang" ]
                            , th [ scope "col" ] [ text "Mottatt" ]
                            , th [ scope "col" ] [ text "Status" ]
                            , th [ scope "col", class "claims__amount" ] [ text "Sum" ]
                            ]
                        ]
                    , tbody [] (List.map (row zone) claims)
                    ]
        ]
    }


tab : Filter -> ( String, Filter ) -> Html msg
tab current ( label, filter ) =
    a
        (Route.href (Route.ReviewQueue filter)
            :: (if filter == current then
                    [ attribute "aria-current" "page" ]

                else
                    []
               )
        )
        [ text label ]


row : Time.Zone -> Claim.Summary -> Html msg
row zone claim =
    tr []
        [ th [ scope "row" ]
            [ a [ Route.href (Route.ReviewClaim claim.id) ]
                [ text (claim.trainNumber ++ " " ++ Format.date claim.departureDate) ]
            ]
        , td [] [ text (Format.dateTime zone claim.submittedAt) ]
        , td [] [ View.Status.badge claim.status ]
        , td [ class "claims__amount" ]
            [ text
                (claim.total
                    |> Maybe.map Money.format
                    |> Maybe.withDefault "–"
                )
            ]
        ]


emptyText : Filter -> String
emptyText filter =
    case filter of
        Only Status.AwaitingReview ->
            "Ingen krav venter på behandling."

        Only _ ->
            "Ingen krav har denne statusen."

        All ->
            "Ingen krav er meldt ennå."
