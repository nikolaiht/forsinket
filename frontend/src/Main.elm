module Main exposing (main)

{-| The program. It knows which page is showing and passes each message on to
that page. Everything a page does lives in that page's module.
-}

import Browser
import Browser.Navigation as Nav
import Html exposing (Html, a, h1, p, text)
import Html.Attributes exposing (class)
import Page.Claim as ClaimPage
import Page.Home as Home
import Page.NewClaim as NewClaim
import Page.ReviewClaim as ReviewClaim
import Page.ReviewQueue as ReviewQueue
import Route exposing (Route)
import Task
import Time
import Url exposing (Url)
import View.Layout as Layout


main : Program () Model Msg
main =
    Browser.application
        { init = init
        , view = view
        , update = update
        , subscriptions = \_ -> Sub.none
        , onUrlRequest = LinkClicked
        , onUrlChange = UrlChanged
        }



-- MODEL


type alias Model =
    { key : Nav.Key
    , zone : Time.Zone
    , page : Page
    }


{-| Exactly one page is showing, and only that page's state exists. Leaving a
page throws its state away, so nothing stale is waiting when you come back.
-}
type Page
    = Home Home.Model
    | NewClaim NewClaim.Model
    | Claim ClaimPage.Model
    | ReviewQueue ReviewQueue.Model
    | ReviewClaim ReviewClaim.Model
    | NotFound


init : () -> Url -> Nav.Key -> ( Model, Cmd Msg )
init _ url key =
    let
        ( page, cmd ) =
            open (Route.fromUrl url)
    in
    -- Times are shown in UTC for the instant it takes the browser to say
    -- which time zone it is in.
    ( { key = key, zone = Time.utc, page = page }
    , Cmd.batch [ cmd, Task.perform GotZone Time.here ]
    )


{-| The page an address leads to, freshly started.
-}
open : Maybe Route -> ( Page, Cmd Msg )
open route =
    case route of
        Nothing ->
            ( NotFound, Cmd.none )

        Just Route.Home ->
            Home.init |> Tuple.mapBoth Home (Cmd.map HomeMsg)

        Just Route.NewClaim ->
            NewClaim.init |> Tuple.mapBoth NewClaim (Cmd.map NewClaimMsg)

        Just (Route.Claim id) ->
            ClaimPage.init id |> Tuple.mapBoth Claim (Cmd.map ClaimMsg)

        Just (Route.ReviewQueue filter) ->
            ReviewQueue.init filter |> Tuple.mapBoth ReviewQueue (Cmd.map ReviewQueueMsg)

        Just (Route.ReviewClaim id) ->
            ReviewClaim.init id |> Tuple.mapBoth ReviewClaim (Cmd.map ReviewClaimMsg)



-- UPDATE


type Msg
    = LinkClicked Browser.UrlRequest
    | UrlChanged Url
    | GotZone Time.Zone
    | HomeMsg Home.Msg
    | NewClaimMsg NewClaim.Msg
    | ClaimMsg ClaimPage.Msg
    | ReviewQueueMsg ReviewQueue.Msg
    | ReviewClaimMsg ReviewClaim.Msg


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case ( msg, model.page ) of
        ( LinkClicked (Browser.Internal url), _ ) ->
            ( model, Nav.pushUrl model.key (Url.toString url) )

        ( LinkClicked (Browser.External href), _ ) ->
            ( model, Nav.load href )

        ( UrlChanged url, _ ) ->
            let
                ( page, cmd ) =
                    open (Route.fromUrl url)
            in
            ( { model | page = page }, cmd )

        ( GotZone zone, _ ) ->
            ( { model | zone = zone }, Cmd.none )

        ( HomeMsg pageMsg, Home pageModel ) ->
            Home.update pageMsg pageModel
                |> showing Home HomeMsg model

        ( NewClaimMsg pageMsg, NewClaim pageModel ) ->
            NewClaim.update (\route -> Nav.pushUrl model.key (Route.toString route)) pageMsg pageModel
                |> showing NewClaim NewClaimMsg model

        ( ClaimMsg pageMsg, Claim pageModel ) ->
            ClaimPage.update pageMsg pageModel
                |> showing Claim ClaimMsg model

        ( ReviewQueueMsg pageMsg, ReviewQueue pageModel ) ->
            ReviewQueue.update pageMsg pageModel
                |> showing ReviewQueue ReviewQueueMsg model

        ( ReviewClaimMsg pageMsg, ReviewClaim pageModel ) ->
            ReviewClaim.update pageMsg pageModel
                |> showing ReviewClaim ReviewClaimMsg model

        _ ->
            -- An answer for a page that is no longer showing. The page it was
            -- for is gone, so there is nothing to do with it.
            ( model, Cmd.none )


showing : (pageModel -> Page) -> (pageMsg -> Msg) -> Model -> ( pageModel, Cmd pageMsg ) -> ( Model, Cmd Msg )
showing toPage toMsg model ( pageModel, cmd ) =
    ( { model | page = toPage pageModel }, Cmd.map toMsg cmd )



-- VIEW


view : Model -> Browser.Document Msg
view model =
    case model.page of
        Home pageModel ->
            Layout.document Layout.Front (mapped HomeMsg (Home.view pageModel))

        NewClaim pageModel ->
            Layout.document Layout.Passenger (mapped NewClaimMsg (NewClaim.view pageModel))

        Claim pageModel ->
            Layout.document Layout.Passenger (mapped ClaimMsg (ClaimPage.view model.zone pageModel))

        ReviewQueue pageModel ->
            Layout.document Layout.Officer (mapped ReviewQueueMsg (ReviewQueue.view model.zone pageModel))

        ReviewClaim pageModel ->
            Layout.document Layout.Officer (mapped ReviewClaimMsg (ReviewClaim.view model.zone pageModel))

        NotFound ->
            Layout.document Layout.Front
                { title = "Fant ikke siden"
                , body =
                    [ h1 [] [ text "Fant ikke siden" ]
                    , p [ class "lead" ] [ text "Adressen leder ikke til noe. Den kan være skrevet feil, eller lenken kan være gammel." ]
                    , p [] [ a [ Route.href Route.Home ] [ text "Gå til forsiden" ] ]
                    ]
                }


mapped : (pageMsg -> Msg) -> { title : String, body : List (Html pageMsg) } -> { title : String, body : List (Html Msg) }
mapped toMsg page =
    { title = page.title
    , body = List.map (Html.map toMsg) page.body
    }
