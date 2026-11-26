module Remote exposing (Remote(..), fromResult, map)

{-| Something the app has asked the service for.

It is loading, it failed, or it is here. A page that holds a `Remote` cannot
show data and a spinner at once, and cannot forget the case where the request
failed, because `case` makes it handle all three.

There is no "not asked" case. Every page asks for what it needs as it opens,
so nothing is ever in that state.

-}


type Remote error value
    = Loading
    | Failed error
    | Loaded value


fromResult : Result error value -> Remote error value
fromResult result =
    case result of
        Ok value ->
            Loaded value

        Err error ->
            Failed error


map : (a -> b) -> Remote error a -> Remote error b
map change remote =
    case remote of
        Loading ->
            Loading

        Failed error ->
            Failed error

        Loaded value ->
            Loaded (change value)
