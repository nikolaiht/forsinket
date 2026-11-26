module Route exposing (Filter(..), Route(..), fromUrl, href, toString)

{-| The pages of the app, and their addresses.

The rest of the program never builds or reads an address as a string. It says
`Route.href (Route.Claim id)`, and it is handed a `Route`. This module is the
one place that knows a claim lives at `/krav/<id>`.

-}

import Claim.Id as Id exposing (Id)
import Html
import Html.Attributes
import Status
import Url exposing (Url)
import Url.Builder as Builder
import Url.Parser as Parser exposing ((</>), (<?>), Parser)
import Url.Parser.Query as Query


type Route
    = Home
    | NewClaim
    | Claim Id
    | ReviewQueue Filter
    | ReviewClaim Id


{-| Which claims the officers' list shows.
-}
type Filter
    = All
    | Only Status.Name


{-| The page an address leads to, or `Nothing` when it leads nowhere.
-}
fromUrl : Url -> Maybe Route
fromUrl url =
    Parser.parse parser url
        |> Maybe.andThen identity


{-| Every branch gives a `Maybe Route`, because the address of the list can
have the right path and still be wrong: `?status=tull` is not a page.
-}
parser : Parser (Maybe Route -> a) a
parser =
    Parser.oneOf
        [ Parser.map (Just Home) Parser.top
        , Parser.map (Just NewClaim) (Parser.s "krav" </> Parser.s "nytt")
        , Parser.map (Just << Claim) (Parser.s "krav" </> claimId)
        , Parser.map (Maybe.map ReviewQueue) (Parser.s "saksbehandling" <?> filterQuery)
        , Parser.map (Just << ReviewClaim) (Parser.s "saksbehandling" </> claimId)
        ]


claimId : Parser (Id -> a) a
claimId =
    Parser.custom "CLAIM_ID" Id.fromString


{-| The officers' list opens on the claims that wait for them, so that is the
filter when the address names none.
-}
filterQuery : Query.Parser (Maybe Filter)
filterQuery =
    Query.custom "status"
        (\values ->
            case values of
                [] ->
                    Just (Only Status.AwaitingReview)

                [ value ] ->
                    List.filter (\( text, _ ) -> text == value) filters
                        |> List.head
                        |> Maybe.map Tuple.second

                _ ->
                    Nothing
        )


{-| The filters by the word that stands for them in the address.
-}
filters : List ( String, Filter )
filters =
    [ ( "venter", Only Status.AwaitingReview )
    , ( "innvilget", Only Status.Approved )
    , ( "utbetalt", Only Status.PaidOut )
    , ( "avslatt", Only Status.Rejected )
    , ( "mottatt", Only Status.Received )
    , ( "alle", All )
    ]


toString : Route -> String
toString route =
    case route of
        Home ->
            Builder.absolute [] []

        NewClaim ->
            Builder.absolute [ "krav", "nytt" ] []

        Claim id ->
            Builder.absolute [ "krav", Id.toString id ] []

        ReviewQueue filter ->
            Builder.absolute [ "saksbehandling" ] (filterParameters filter)

        ReviewClaim id ->
            Builder.absolute [ "saksbehandling", Id.toString id ] []


filterParameters : Filter -> List Builder.QueryParameter
filterParameters filter =
    if filter == Only Status.AwaitingReview then
        []

    else
        List.filter (\( _, candidate ) -> candidate == filter) filters
            |> List.take 1
            |> List.map (\( text, _ ) -> Builder.string "status" text)


href : Route -> Html.Attribute msg
href route =
    Html.Attributes.href (toString route)
