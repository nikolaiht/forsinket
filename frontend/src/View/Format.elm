module View.Format exposing (date, dateTime, minutes, outcome)

{-| Dates, times and delays, written the way they are written in Norway.
-}

import Date exposing (Date)
import Departure exposing (Outcome(..))
import Time exposing (Posix)


{-| `20.11.2026`
-}
date : Date -> String
date value =
    twoDigits (Date.day value) ++ "." ++ twoDigits (Date.monthNumber value) ++ "." ++ String.fromInt (Date.year value)


{-| `21.11.2026 kl. 10:15`, in the time zone of whoever is reading.
-}
dateTime : Time.Zone -> Posix -> String
dateTime zone posix =
    date (Date.fromPosix zone posix)
        ++ " kl. "
        ++ twoDigits (Time.toHour zone posix)
        ++ ":"
        ++ twoDigits (Time.toMinute zone posix)


outcome : Outcome -> String
outcome value =
    case value of
        Ran 0 ->
            "I rute"

        Ran delay ->
            minutes delay ++ " forsinket"

        Cancelled ->
            "Innstilt"


minutes : Int -> String
minutes count =
    if count == 1 then
        "1 minutt"

    else
        String.fromInt count ++ " minutter"


twoDigits : Int -> String
twoDigits number =
    String.padLeft 2 '0' (String.fromInt number)
