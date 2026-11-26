module View.Layout exposing (Section(..), document, loading, mainId)

{-| What every page has around it: the header, the main area and the footer
that says what this is.
-}

import Browser
import Html exposing (Html, a, div, footer, header, main_, nav, p, span, text)
import Html.Attributes exposing (attribute, class, href, id, tabindex)
import Route
import Status


{-| Which menu entry a page is, if it is one of them.
-}
type Section
    = NewClaimPage
    | OfficerPages
    | NoSection


{-| The id of the main area. `Main` moves focus here when the page changes,
and it is where the link that skips the menu leads.
-}
mainId : String
mainId =
    "innhold"


document : Section -> { title : String, body : List (Html msg) } -> Browser.Document msg
document section page =
    { title = page.title ++ " – Tindbanen reisegaranti"
    , body =
        [ a [ class "skip-link", href ("#" ++ mainId) ] [ text "Hopp til innholdet" ]
        , header [ class "site-header" ]
            [ div [ class "site-header__inner" ]
                [ a [ class "wordmark", Route.href Route.Home ]
                    [ span [ class "wordmark__name" ] [ text "Tindbanen" ]
                    , span [ class "wordmark__service" ] [ text "Reisegaranti" ]
                    ]
                , nav [ attribute "aria-label" "Hovedmeny" ]
                    [ menuLink (section == NewClaimPage) Route.NewClaim "Meld krav"
                    , menuLink (section == OfficerPages) (Route.ReviewQueue (Route.Only awaitingReview)) "Saksbehandling"
                    ]
                ]
            ]
        , main_ [ id mainId, tabindex -1, class "page" ] page.body
        , footer [ class "site-footer" ]
            [ p []
                [ text "Dette er en demo. Tindbanen finnes ikke, reglene er laget for demoen, og alle data er syntetiske. På den åpne demoen nullstilles dataene jevnlig." ]
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
                    [ attribute "aria-current" "page" ]

                else
                    []
               )
        )
        [ text label ]


loading : Html msg
loading =
    p [ class "loading", attribute "role" "status" ] [ text "Henter …" ]
