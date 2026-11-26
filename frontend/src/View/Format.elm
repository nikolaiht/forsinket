module View.Format exposing (date, dateIn, dateTime, machineTime, minutes, oslo, outcome)

{-| Dates, times and delays, written the way they are written in Norway.

Every time on the pages is Oslo time, because that is the time the timetable
is written in. A passenger reading the page abroad sees the same clock times
as the departure board did.

-}

import Date exposing (Date)
import Departure exposing (Outcome(..))
import Iso8601
import Time exposing (Posix)
import TimeZone


{-| The time in Oslo, with its summer time rules. `Time.here` would only give
the offset that applies today, and get a time on the other side of a clock
change wrong by an hour.

The package has no zone called Oslo. In the time zone database Oslo is an
alias for Berlin, whose clock it has matched since 1970, so Berlin is the
zone to ask for.

-}
oslo : Time.Zone
oslo =
    TimeZone.europe__berlin ()


{-| `20.11.2026`
-}
date : Date -> String
date value =
    twoDigits (Date.day value) ++ "." ++ twoDigits (Date.monthNumber value) ++ "." ++ String.fromInt (Date.year value)


dateIn : Time.Zone -> Posix -> Date
dateIn zone posix =
    Date.fromPosix zone posix


{-| `21.11.2026 kl. 10:15`
-}
dateTime : Posix -> String
dateTime posix =
    date (dateIn oslo posix)
        ++ " kl. "
        ++ twoDigits (Time.toHour oslo posix)
        ++ ":"
        ++ twoDigits (Time.toMinute oslo posix)


{-| The same point in time for a `datetime` attribute.
-}
machineTime : Posix -> String
machineTime posix =
    Iso8601.fromTime posix


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
