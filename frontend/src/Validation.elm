module Validation exposing (amount, andMap)

{-| Checking a form so that every problem is found, not just the first.

`Result.andThen` stops at the first error, which is right when one step needs
the result of the one before. The fields of a form do not depend on each
other, and someone who got three of them wrong should be told about all three.
`andMap` checks them side by side and keeps every error:

    Ok NewClaim
        |> andMap (departure draft)
        |> andMap (ticket rules draft)
        |> andMap (expenses rules draft)

-}

import FieldError exposing (Field, FieldError, Problem(..))
import Money exposing (Money)


{-| Feed one more checked field to a constructor. If both sides have errors,
the result has all of them, in the order the fields were checked.
-}
andMap : Result (List e) a -> Result (List e) (a -> b) -> Result (List e) b
andMap next soFar =
    case ( soFar, next ) of
        ( Ok function, Ok value ) ->
            Ok (function value)

        ( Err errors, Ok _ ) ->
            Err errors

        ( Ok _, Err errors ) ->
            Err errors

        ( Err errors, Err more ) ->
            Err (errors ++ more)


{-| Read an amount from a text field, between a lower and an upper limit.
-}
amount : Field -> { atLeast : Money, atMost : Money } -> String -> Result (List FieldError) Money
amount field limits text =
    let
        problem : Problem -> Result (List FieldError) Money
        problem what =
            Err [ { field = field, problem = what } ]
    in
    case Money.parse text of
        Err Money.Empty ->
            problem Required

        Err Money.NotAnAmount ->
            problem NotAnAmount

        Ok money ->
            if Money.toOre money < Money.toOre limits.atLeast then
                problem MustBePositive

            else if Money.toOre money > Money.toOre limits.atMost then
                problem AboveMaximum

            else
                Ok money
