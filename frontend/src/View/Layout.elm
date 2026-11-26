module View.Layout exposing (Section(..), document, loading)

{-| What every page has around it: the header, the main area and the footer
that says what this is.
-}

import Browser
import Html exposing (Html, a, div, footer, header, main_, nav, p, span, text)
import Html.Attributes exposing (attribute, class, href, id)
import Route
import Status


{-| Which part of the app a page belongs to, for marking the menu.
-}
type Section
    = Front
    | Passenger
    | Officer


document : Section -> { title : String, body : List (Html msg) } -> Browser.Document msg
document section page =
    { title = page.title ++ " – Fjordbanen reisegaranti"
    , body =
        [ a [ class "skip-link", href "#innhold" ] [ text "Hopp til innholdet" ]
        , header [ class "site-header" ]
            [ div [ class "site-header__inner" ]
                [ a [ class "wordmark", Route.href Route.Home ]
                    [ span [ class "wordmark__name" ] [ text "Fjordbanen" ]
                    , span [ class "wordmark__service" ] [ text "Reisegaranti" ]
                    ]
                , nav [ attribute "aria-label" "Hovedmeny" ]
                    [ menuLink (section == Passenger) Route.NewClaim "Meld krav"
                    , menuLink (section == Officer) (Route.ReviewQueue (Route.Only awaitingReview)) "Saksbehandling"
                    ]
                ]
            ]
        , main_ [ id "innhold", class "page" ] page.body
        , footer [ class "site-footer" ]
            [ p []
                [ text "Dette er en demo. Fjordbanen finnes ikke, reglene er laget for demoen, og alle data er syntetiske. På den åpne demoen nullstilles dataene jevnlig." ]
            ]
        ]
    }


awaitingReview : Status.Name
awaitingReview =
    Status.AwaitingReview


menuLink : Bool -> Route.Route -> String -> Html msg
menuLink isCurrent route label =
    a
        (Route.href route
            :: (if isCurrent then
                    [ attribute "aria-current" "true" ]

                else
                    []
               )
        )
        [ text label ]


loading : Html msg
loading =
    p [ class "loading", attribute "role" "status" ] [ text "Henter …" ]
