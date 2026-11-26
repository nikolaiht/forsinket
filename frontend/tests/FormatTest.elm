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
        , describe "a point in time is written as the clock showed in Oslo, like the timetable"
            [ test "in winter, one hour ahead of UTC" <|
                \_ ->
                    Format.dateTime (Fixtures.time "2026-11-21T09:15:00Z")
                        |> Expect.equal "21.11.2026 kl. 10:15"
            , test "in summer, two hours ahead" <|
                \_ ->
                    Format.dateTime (Fixtures.time "2026-07-01T09:15:00Z")
                        |> Expect.equal "01.07.2026 kl. 11:15"
            , test "late in the evening it is already the next day" <|
                \_ ->
                    Format.dateTime (Fixtures.time "2026-11-21T23:30:00Z")
                        |> Expect.equal "22.11.2026 kl. 00:30"
            ]
        , test "the date in Oslo at a point in time" <|
            \_ ->
                Format.dateIn Format.oslo (Fixtures.time "2026-11-21T23:30:00Z")
                    |> Expect.equal (Date.fromCalendarDate 2026 Nov 22)
        , test "a point in time for machines is ISO 8601" <|
            \_ ->
                Format.machineTime (Fixtures.time "2026-11-21T09:15:00Z")
                    |> Expect.equal "2026-11-21T09:15:00.000Z"
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
