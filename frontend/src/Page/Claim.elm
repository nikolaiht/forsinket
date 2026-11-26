module Page.Claim exposing (Model, Msg, init, update, view)

{-| A passenger's view of one claim.
-}

import Api
import Claim exposing (Claim)
import Claim.Id as Id exposing (Id)
import Html exposing (Html, a, h1, p, text)
import Html.Attributes exposing (class)
import Remote exposing (Remote(..))
import Route
import Time
import View.Claim
import View.Layout
import View.Problem


type alias Model =
    { id : Id
    , claim : Remote Api.Error Claim
    }


init : Id -> ( Model, Cmd Msg )
init id =
    ( { id = id, claim = Loading }, Api.getClaim id GotClaim )


type Msg
    = GotClaim (Result Api.Error Claim)
    | Retried


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        GotClaim result ->
            ( { model | claim = Remote.fromResult result }, Cmd.none )

        Retried ->
            ( { model | claim = Loading }, Api.getClaim model.id GotClaim )


view : Time.Zone -> Model -> { title : String, body : List (Html Msg) }
view zone model =
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
                        [ View.Claim.view zone claim
                        , p [ class "reference" ]
                            [ text ("Referanse: " ++ Id.toString claim.id ++ ". Ta vare på adressen til denne siden, så kan du følge kravet her.") ]
                        , p [ class "reference" ]
                            [ a [ Route.href (Route.ReviewClaim claim.id) ] [ text "Åpne saken som saksbehandler" ]
                            , text " (i demoen er saksbehandlingen åpen for alle)."
                            ]
                        ]
               )
    }
