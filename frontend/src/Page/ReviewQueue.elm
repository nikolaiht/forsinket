module Page.ReviewQueue exposing (Effect(..), Model, Msg(..), init, perform, update, view)

{-| The officers' list of claims.
-}

import Api
import Claim
import Html exposing (Html, a, h1, nav, p, table, tbody, td, text, th, thead, tr)
import Html.Attributes exposing (attribute, class, datetime, scope)
import Money
import Remote exposing (Remote(..))
import Route exposing (Filter(..))
import Status
import View.Format as Format
import View.Layout
import View.Problem
import View.Status


type alias Model =
    { filter : Filter
    , claims : Remote Api.Error (List Claim.Summary)
    }


type Effect
    = FetchClaims Filter


init : Filter -> ( Model, List Effect )
init filter =
    ( { filter = filter, claims = Loading }, [ FetchClaims filter ] )


{-| An answer says which filter it is for. Clicking two tabs quickly sends
two requests, and the answers can come back in either order.
-}
type Msg
    = GotClaims Filter (Result Api.Error (List Claim.Summary))
    | Retried


update : Msg -> Model -> ( Model, List Effect )
update msg model =
    case msg of
        GotClaims filter result ->
            if filter == model.filter then
                ( { model | claims = Remote.fromResult result }, [] )

            else
                ( model, [] )

        Retried ->
            ( { model | claims = Loading }, [ FetchClaims model.filter ] )


perform : Effect -> Cmd Msg
perform effect =
    case effect of
        FetchClaims filter ->
            Api.getClaims (statusOf filter) (GotClaims filter)


statusOf : Filter -> Maybe Status.Name
statusOf filter =
    case filter of
        All ->
            Nothing

        Only status ->
            Just status


view : Model -> { title : String, body : List (Html Msg) }
view model =
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
                    , tbody [] (List.map row claims)
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


row : Claim.Summary -> Html msg
row claim =
    tr []
        [ th [ scope "row" ]
            [ a [ Route.href (Route.ReviewClaim claim.id) ]
                [ text (claim.trainNumber ++ " " ++ Format.date claim.departureDate) ]
            ]
        , td []
            [ Html.time [ datetime (Format.machineTime claim.submittedAt) ] [ text (Format.dateTime claim.submittedAt) ] ]
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
