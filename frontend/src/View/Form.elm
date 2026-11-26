module View.Form exposing (Field, InputMode(..), choice, textArea, textField)

{-| Form fields that are put together the same way every time: a label tied
to its input, a hint, and the problems with what was typed, each tied to the
input so that a screen reader reads them out with the field.
-}

import Html exposing (Html, div, fieldset, input, label, legend, p, span, text, textarea)
import Html.Attributes exposing (attribute, checked, class, for, id, name, type_, value)
import Html.Events exposing (onCheck, onInput)


type alias Field msg =
    { id : String
    , label : String
    , hint : Maybe String
    , value : String
    , onInput : String -> msg
    , problems : List String
    }


{-| Which keyboard a phone shows for the field.
-}
type InputMode
    = Text
    | Decimal


textField : InputMode -> Field msg -> Html msg
textField inputMode field =
    wrapper field
        (input
            ([ type_ "text"
             , id field.id
             , class "field__input"
             , value field.value
             , onInput field.onInput
             , attribute "inputmode"
                (case inputMode of
                    Text ->
                        "text"

                    Decimal ->
                        "decimal"
                )
             , attribute "autocomplete" "off"
             ]
                ++ describedBy field
            )
            []
        )


textArea : Field msg -> Html msg
textArea field =
    wrapper field
        (textarea
            ([ id field.id
             , class "field__input field__input--area"
             , value field.value
             , onInput field.onInput
             , attribute "rows" "3"
             ]
                ++ describedBy field
            )
            []
        )


wrapper : Field msg -> Html msg -> Html msg
wrapper field control =
    div [ class "field" ]
        (label [ for field.id, class "field__label" ] [ text field.label ]
            :: (case field.hint of
                    Just hint ->
                        [ p [ id (field.id ++ "-hint"), class "field__hint" ] [ text hint ] ]

                    Nothing ->
                        []
               )
            ++ [ control, problemList field.id field.problems ]
        )


{-| Tells assistive technology which texts belong to the input, and that the
input is in error when it is.
-}
describedBy : Field msg -> List (Html.Attribute msg)
describedBy field =
    let
        ids : List String
        ids =
            List.filterMap identity
                [ Maybe.map (\_ -> field.id ++ "-hint") field.hint
                , if List.isEmpty field.problems then
                    Nothing

                  else
                    Just (field.id ++ "-problems")
                ]
    in
    if List.isEmpty ids then
        []

    else
        attribute "aria-describedby" (String.join " " ids)
            :: (if List.isEmpty field.problems then
                    []

                else
                    [ attribute "aria-invalid" "true" ]
               )


problemList : String -> List String -> Html msg
problemList fieldId problems =
    if List.isEmpty problems then
        text ""

    else
        div [ id (fieldId ++ "-problems"), class "field__problems" ]
            (List.map (\problem -> p [] [ text problem ]) problems)


{-| A question with a handful of answers, of which exactly one is chosen:
radio buttons in a `fieldset`, so the question is read out with each answer.
-}
choice :
    { name : String
    , legend : String
    , options : List ( String, a )
    , chosen : a
    , onChoose : a -> msg
    , problems : List String
    }
    -> Html msg
choice config =
    fieldset
        (class "choice"
            :: (if List.isEmpty config.problems then
                    []

                else
                    [ attribute "aria-describedby" (config.name ++ "-problems") ]
               )
        )
        (legend [ class "field__label" ] [ text config.legend ]
            :: List.indexedMap
                (\index ( optionLabel, option ) ->
                    label [ class "choice__option" ]
                        [ input
                            [ type_ "radio"
                            , name config.name
                            , id (config.name ++ "-" ++ String.fromInt index)
                            , checked (config.chosen == option)
                            , onCheck (\_ -> config.onChoose option)
                            ]
                            []
                        , span [] [ text optionLabel ]
                        ]
                )
                config.options
            ++ [ problemList config.name config.problems ]
        )
