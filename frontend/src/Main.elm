module Main exposing (main)

{-| The program. It knows which page is showing and passes each message on to
that page. Everything a page does lives in that page's module.

A page's `update` returns the effects it wants as values. This module is where
they are carried out, with each page's own `perform`.

-}

import Browser
import Browser.Dom as Dom
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
    , url : Url
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
            open key (Route.fromUrl url)
    in
    ( { key = key, url = url, page = page }, cmd )


{-| The page an address leads to, freshly started.
-}
open : Nav.Key -> Maybe Route -> ( Page, Cmd Msg )
open key route =
    case route of
        Nothing ->
            ( NotFound, Cmd.none )

        Just Route.Home ->
            Home.init |> started Home HomeMsg Home.perform

        Just Route.NewClaim ->
            NewClaim.init |> started NewClaim NewClaimMsg (NewClaim.perform key)

        Just (Route.Claim id) ->
            ClaimPage.init id |> started Claim ClaimMsg ClaimPage.perform

        Just (Route.ReviewQueue filter) ->
            ReviewQueue.init filter |> started ReviewQueue ReviewQueueMsg ReviewQueue.perform

        Just (Route.ReviewClaim id) ->
            ReviewClaim.init id |> started ReviewClaim ReviewClaimMsg ReviewClaim.perform


started : (pageModel -> Page) -> (pageMsg -> Msg) -> (effect -> Cmd pageMsg) -> ( pageModel, List effect ) -> ( Page, Cmd Msg )
started toPage toMsg perform ( pageModel, effects ) =
    ( toPage pageModel, performAll toMsg perform effects )


performAll : (pageMsg -> Msg) -> (effect -> Cmd pageMsg) -> List effect -> Cmd Msg
performAll toMsg perform effects =
    Cmd.map toMsg (Cmd.batch (List.map perform effects))



-- UPDATE


type Msg
    = LinkClicked Browser.UrlRequest
    | UrlChanged Url
    | HomeMsg Home.Msg
    | NewClaimMsg NewClaim.Msg
    | ClaimMsg ClaimPage.Msg
    | ReviewQueueMsg ReviewQueue.Msg
    | ReviewClaimMsg ReviewClaim.Msg
    | NoOp


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case ( msg, model.page ) of
        ( LinkClicked (Browser.Internal url), _ ) ->
            if url.path == model.url.path && url.query == model.url.query then
                -- A link to a place on the page that is already showing, such
                -- as "skip to the content". Going there through the address
                -- bar would start the page again and empty a half-filled form.
                ( model, url.fragment |> Maybe.map focus |> Maybe.withDefault Cmd.none )

            else
                ( model, Nav.pushUrl model.key (Url.toString url) )

        ( LinkClicked (Browser.External href), _ ) ->
            ( model, Nav.load href )

        ( UrlChanged url, _ ) ->
            let
                ( page, cmd ) =
                    open model.key (Route.fromUrl url)
            in
            -- A new page: put focus at the top of its content, where a screen
            -- reader starts reading and the next Tab continues from.
            ( { model | url = url, page = page }, Cmd.batch [ cmd, focus Layout.mainId ] )

        ( HomeMsg pageMsg, Home pageModel ) ->
            Home.update pageMsg pageModel
                |> showing Home HomeMsg Home.perform model

        ( NewClaimMsg pageMsg, NewClaim pageModel ) ->
            NewClaim.update pageMsg pageModel
                |> showing NewClaim NewClaimMsg (NewClaim.perform model.key) model

        ( ClaimMsg pageMsg, Claim pageModel ) ->
            ClaimPage.update pageMsg pageModel
                |> showing Claim ClaimMsg ClaimPage.perform model

        ( ReviewQueueMsg pageMsg, ReviewQueue pageModel ) ->
            ReviewQueue.update pageMsg pageModel
                |> showing ReviewQueue ReviewQueueMsg ReviewQueue.perform model

        ( ReviewClaimMsg pageMsg, ReviewClaim pageModel ) ->
            ReviewClaim.update pageMsg pageModel
                |> showing ReviewClaim ReviewClaimMsg ReviewClaim.perform model

        _ ->
            -- A message for a kind of page that is no longer showing. A message
            -- for the same kind of page, but about something that page has
            -- moved on from, is recognised and dropped by the page itself.
            ( model, Cmd.none )


showing : (pageModel -> Page) -> (pageMsg -> Msg) -> (effect -> Cmd pageMsg) -> Model -> ( pageModel, List effect ) -> ( Model, Cmd Msg )
showing toPage toMsg perform model ( pageModel, effects ) =
    ( { model | page = toPage pageModel }, performAll toMsg perform effects )


focus : String -> Cmd Msg
focus elementId =
    Task.attempt (\_ -> NoOp) (Dom.focus elementId)



-- VIEW


view : Model -> Browser.Document Msg
view model =
    case model.page of
        Home pageModel ->
            Layout.document Layout.NoSection (mapped HomeMsg (Home.view pageModel))

        NewClaim pageModel ->
            Layout.document Layout.NewClaimPage (mapped NewClaimMsg (NewClaim.view pageModel))

        Claim pageModel ->
            Layout.document Layout.NoSection (mapped ClaimMsg (ClaimPage.view pageModel))

        ReviewQueue pageModel ->
            Layout.document Layout.OfficerPages (mapped ReviewQueueMsg (ReviewQueue.view pageModel))

        ReviewClaim pageModel ->
            Layout.document Layout.OfficerPages (mapped ReviewClaimMsg (ReviewClaim.view pageModel))

        NotFound ->
            Layout.document Layout.NoSection
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
