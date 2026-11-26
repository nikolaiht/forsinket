module FieldError exposing (Field(..), FieldError, Problem(..), decoder, for, unplaced)

{-| What is wrong with one field of a form.

The forms check what is typed before anything is sent, and the service checks
again when it arrives. Both kinds of error are a `FieldError`, so a problem the
service finds is shown next to the same input, in the same words, as one the
form finds itself.

-}

import Json.Decode as Decode exposing (Decoder)


type alias FieldError =
    { field : Field
    , problem : Problem
    }


type Field
    = DepartureField
    | PriceField
    | ValidityField
    | ExpensesAmountField
    | ExpensesKindField
    | OfficerField
    | NoteField
    | ReasonField
    | ApprovedExpensesField
    | OtherField String


type Problem
    = Required
    | NotAnAmount
    | MustBePositive
    | MustNotBeNegative
    | AboveMaximum
    | UnknownDeparture
    | DepartureInFuture
    | UnsupportedValidity
    | UnknownValue
    | TooLong
    | InvalidFormat
    | OtherProblem String


{-| The problems with one field.
-}
for : Field -> List FieldError -> List Problem
for field errors =
    List.filter (\error -> error.field == field) errors
        |> List.map .problem


{-| The errors on fields this app does not know, with the name the service
gave the field. A form has no input to show them next to, so it lists them.
-}
unplaced : List FieldError -> List ( String, Problem )
unplaced errors =
    List.filterMap
        (\error ->
            case error.field of
                OtherField path ->
                    Just ( path, error.problem )

                _ ->
                    Nothing
        )
        errors


{-| An error as the service sends it: the path of the field in the request, and
a code. A path or a code this app does not know is kept as it is, so the user
is still told that something is wrong.
-}
decoder : Decoder FieldError
decoder =
    Decode.map2 FieldError
        (Decode.field "field" (Decode.map fieldFromPath Decode.string))
        (Decode.field "code" (Decode.map problemFromCode Decode.string))


fieldFromPath : String -> Field
fieldFromPath path =
    case path of
        "departureId" ->
            DepartureField

        "ticket.price" ->
            PriceField

        "ticket.validityDays" ->
            ValidityField

        "expenses.amount" ->
            ExpensesAmountField

        "expenses.kind" ->
            ExpensesKindField

        "officer" ->
            OfficerField

        "note" ->
            NoteField

        "decision.reason" ->
            ReasonField

        "decision.approvedExpenses" ->
            ApprovedExpensesField

        _ ->
            OtherField path


problemFromCode : String -> Problem
problemFromCode code =
    case code of
        "required" ->
            Required

        "must_be_positive" ->
            MustBePositive

        "must_not_be_negative" ->
            MustNotBeNegative

        "above_maximum" ->
            AboveMaximum

        "unknown_departure" ->
            UnknownDeparture

        "departure_in_future" ->
            DepartureInFuture

        "unsupported_validity" ->
            UnsupportedValidity

        "unknown_value" ->
            UnknownValue

        "too_long" ->
            TooLong

        "invalid_format" ->
            InvalidFormat

        _ ->
            OtherProblem code
