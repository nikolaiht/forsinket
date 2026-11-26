module FormatTest exposing (suite)

import Date
import Departure exposing (Outcome(..))
import Expect
import Fixtures
import Test exposing (Test, describe, test)
import Time exposing (Month(..))
import View.Format as Format


suite : Test
suite =
    describe "View.Format"
        [ test "a date is written day first" <|
            \_ ->
                Format.date (Date.fromCalendarDate 2026 Nov 20)
                    |> Expect.equal "20.11.2026"
        , test "days and months under ten keep their zero" <|
            \_ ->
                Format.date (Date.fromCalendarDate 2027 Jan 5)
                    |> Expect.equal "05.01.2027"
        , test "a point in time is written in the reader's time zone" <|
            \_ ->
                Format.dateTime oslo (Fixtures.time "2026-11-21T09:15:00Z")
                    |> Expect.equal "21.11.2026 kl. 10:15"
        , test "a point in time late in the evening belongs to the next day further east" <|
            \_ ->
                Format.dateTime oslo (Fixtures.time "2026-11-21T23:30:00Z")
                    |> Expect.equal "22.11.2026 kl. 00:30"
        , describe "what happened to a departure"
            [ test "on time" <|
                \_ -> Format.outcome (Ran 0) |> Expect.equal "I rute"
            , test "one minute" <|
                \_ -> Format.outcome (Ran 1) |> Expect.equal "1 minutt forsinket"
            , test "several minutes" <|
                \_ -> Format.outcome (Ran 61) |> Expect.equal "61 minutter forsinket"
            , test "cancelled" <|
                \_ -> Format.outcome Cancelled |> Expect.equal "Innstilt"
            ]
        ]


{-| Oslo in winter: one hour ahead of UTC.
-}
oslo : Time.Zone
oslo =
    Time.customZone 60 []
