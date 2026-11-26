module View.Problem exposing (field, formErrors, view)

{-| What went wrong, said so that the person reading can do something about
it. Every `Api.Error` and every `FieldError.Problem` has its own words here.
-}

import Api
import FieldError exposing (FieldError, Problem(..))
import Html exposing (Html, button, details, div, li, p, summary, text, ul)
import Html.Attributes exposing (attribute, class, type_)
import Html.Events exposing (onClick)


{-| What is wrong with a field. `limit` is the highest amount the field takes,
already written out, for the fields that have one.
-}
field : { limit : Maybe String } -> Problem -> String
field { limit } problem =
    case problem of
        Required ->
            "Dette må fylles ut."

        NotAnAmount ->
            "Skriv et beløp, for eksempel 349 eller 349,50."

        MustBePositive ->
            "Beløpet må være større enn null."

        MustNotBeNegative ->
            "Beløpet kan ikke være negativt."

        AboveMaximum ->
            case limit of
                Just highest ->
                    "Beløpet kan ikke være høyere enn " ++ highest ++ "."

                Nothing ->
                    "Beløpet er for høyt."

        UnknownDeparture ->
            "Avgangen finnes ikke. Velg en avgang fra listen."

        DepartureInFuture ->
            "Avgangen har ikke gått ennå."

        UnsupportedValidity ->
            "Periodebilletten må gjelde i 7 eller 30 dager."

        UnknownValue ->
            "Verdien ble ikke godtatt. Velg på nytt."

        TooLong ->
            "Teksten er for lang. Bruk høyst 500 tegn."

        InvalidFormat ->
            "Bruk 2 til 10 bokstaver."

        OtherProblem code ->
            "Verdien ble ikke godtatt (" ++ code ++ ")."


apiError : Api.Error -> String
apiError error =
    case error of
        Api.Offline ->
            "Får ikke kontakt med tjenesten. Sjekk nettforbindelsen og prøv igjen."

        Api.Timeout ->
            "Tjenesten brukte for lang tid på å svare. Prøv igjen."

        Api.NotFound ->
            "Fant ikke kravet. Sjekk at adressen er riktig."

        Api.Invalid _ ->
            "Noen av feltene ble ikke godtatt. Se meldingene ved feltene."

        Api.VersionConflict ->
            "Saken er endret av noen andre siden du åpnet den. Last den inn på nytt før du gjør noe mer."

        Api.InvalidTransition ->
            "Dette kan ikke gjøres med saken slik den står nå. Last den inn på nytt."

        Api.DemoLimitReached ->
            "Demoen har nådd grensen for antall krav. Den nullstilles jevnlig, så prøv igjen senere."

        Api.Unexpected _ ->
            "Noe uventet gikk galt. Prøv igjen."


{-| An error, with a way out when there is one: a button that tries again.
-}
view : { retry : Maybe ( String, msg ) } -> Api.Error -> Html msg
view { retry } error =
    div [ class "notice notice--error", attribute "role" "alert" ]
        [ p [] [ text (apiError error) ]
        , case error of
            Api.Unexpected technical ->
                details []
                    [ summary [] [ text "Teknisk forklaring" ]
                    , p [ class "notice__technical" ] [ text technical ]
                    ]

            _ ->
                text ""
        , case retry of
            Just ( label, msg ) ->
                button [ type_ "button", class "button button--quiet", onClick msg ] [ text label ]

            Nothing ->
                text ""
        ]


{-| The notice above a form's button when the form was not accepted. It says
so, and lists the errors that have no field to be shown next to: the ones on
fields the service knows and this app does not.
-}
formErrors : String -> List FieldError -> Html msg
formErrors message errors =
    if List.isEmpty errors then
        text ""

    else
        div [ class "notice notice--error", attribute "role" "alert" ]
            [ p [] [ text message ]
            , case FieldError.unplaced errors of
                [] ->
                    text ""

                unplaced ->
                    ul []
                        (List.map
                            (\( path, problem ) -> li [] [ text ("«" ++ path ++ "»: " ++ field { limit = Nothing } problem) ])
                            unplaced
                        )
            ]
