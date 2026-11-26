module Page.Claim exposing (Effect(..), Model, Msg(..), init, perform, update, view)

{-| A passenger's view of one claim.
-}

import Api
import Claim exposing (Claim)
import Claim.Id as Id exposing (Id)
import Html exposing (Html, a, h1, p, text)
import Html.Attributes exposing (class)
import Remote exposing (Remote(..))
import Route
import View.Claim
import View.Layout
import View.Problem


type alias Model =
    { id : Id
    , claim : Remote Api.Error Claim
    }


type Effect
    = FetchClaim Id


init : Id -> ( Model, List Effect )
init id =
    ( { id = id, claim = Loading }, [ FetchClaim id ] )


{-| An answer says which claim it is about, so that one that arrives after
the page has moved on to another claim is not shown as that claim.
-}
type Msg
    = GotClaim Id (Result Api.Error Claim)
    | Retried


update : Msg -> Model -> ( Model, List Effect )
update msg model =
    case msg of
        GotClaim id result ->
            if id == model.id then
                ( { model | claim = Remote.fromResult result }, [] )

            else
                ( model, [] )

        Retried ->
            ( { model | claim = Loading }, [ FetchClaim model.id ] )


perform : Effect -> Cmd Msg
perform effect =
    case effect of
        FetchClaim id ->
            Api.getClaim id (GotClaim id)


view : Model -> { title : String, body : List (Html Msg) }
view model =
    { title = "Kravet ditt"
    , body =
        h1 [] [ text "Kravet ditt" ]
            :: (case model.claim of
                    Loading ->
                        [ View.Layout.loading ]

                    Failed Api.NotFound ->
                        -- Asking again will not make a claim that does not exist appear.
                        [ View.Problem.view { retry = Nothing } Api.NotFound ]

                    Failed error ->
                        [ View.Problem.view { retry = Just ( "Prøv igjen", Retried ) } error ]

                    Loaded claim ->
                        [ View.Claim.view claim
                        , p [ class "reference" ]
                            [ text ("Referanse: " ++ Id.toString claim.id ++ ". Ta vare på adressen til denne siden, så kan du følge kravet her.") ]
                        , p [ class "reference" ]
                            [ a [ Route.href (Route.ReviewClaim claim.id) ] [ text "Åpne saken som saksbehandler" ]
                            , text " (i demoen er saksbehandlingen åpen for alle)."
                            ]
                        ]
               )
    }
