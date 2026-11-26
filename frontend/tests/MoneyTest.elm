module MoneyTest exposing (suite)

import Expect
import Fixtures exposing (ore)
import Fuzz exposing (Fuzzer)
import Json.Decode as Decode
import Json.Encode as Encode
import Money exposing (Money, ParseError(..))
import Test exposing (Test, describe, fuzz, test)


suite : Test
suite =
    describe "Money"
        [ describe "parse reads what people type"
            (List.map parsesTo
                [ ( "349", 34900 )
                , ( "349,5", 34950 )
                , ( "349,50", 34950 )
                , ( "349.50", 34950 )
                , ( "1 234,50", 123450 )
                , ( "1\u{00A0}234,50", 123450 )
                , ( " 349 kr", 34900 )
                , ( "349,00 kr", 34900 )
                , ( "349KR", 34900 )
                , ( "kr 349", 34900 )
                , ( "kr 349,50", 34950 )
                , ( "349,-", 34900 )
                , ( "kr 349,-", 34900 )
                , ( "0", 0 )
                , ( "0,05", 5 )
                , ( "007", 700 )
                ]
            )
        , describe "parse turns down what is not an amount"
            (List.map (failsWith Empty) [ "", "   ", "\u{00A0}" ]
                ++ List.map (failsWith NotAnAmount)
                    [ "abc"
                    , "-5"
                    , "+5"
                    , "3,456"
                    , "1,2,3"
                    , "1.234,50"
                    , ","
                    , ",50"
                    , "5,"
                    , "kr"
                    , ",-"
                    , "349,5,-"
                    , "kr 349 kr"
                    , "12 kr 50"
                    , "1e3"
                    , "٣٤٩"
                    , "12345678901234567890"
                    ]
            )
        , describe "fromOre"
            [ test "an amount is a whole number of øre, zero or more" <|
                \_ ->
                    List.map (Money.fromOre >> Maybe.map Money.toOre) [ 0, 1, 34900 ]
                        |> Expect.equal [ Just 0, Just 1, Just 34900 ]
            , test "a negative number is not an amount" <|
                \_ ->
                    Money.fromOre -1
                        |> Expect.equal Nothing
            ]
        , describe "format"
            [ test "writes kroner and øre the Norwegian way, with spaces that do not break" <|
                \_ ->
                    Money.format (ore 123450)
                        |> Expect.equal "1\u{00A0}234,50\u{00A0}kr"
            , test "always shows two decimals" <|
                \_ ->
                    List.map (ore >> Money.format) [ 0, 5, 50, 34900, 100000000 ]
                        |> Expect.equal
                            [ "0,00\u{00A0}kr"
                            , "0,05\u{00A0}kr"
                            , "0,50\u{00A0}kr"
                            , "349,00\u{00A0}kr"
                            , "1\u{00A0}000\u{00A0}000,00\u{00A0}kr"
                            ]
            ]
        , fuzz amount "what format writes, parse reads back" <|
            \money ->
                Money.parse (Money.format money)
                    |> Expect.equal (Ok money)
        , fuzz typed "whatever is typed, parse gives an amount of zero or more, or says no" <|
            \text ->
                case Money.parse text of
                    Ok money ->
                        Money.toOre money |> Expect.atLeast 0

                    Err _ ->
                        Expect.pass
        , fuzz typed "an amount that parses is the same amount when it is written out and read again" <|
            \text ->
                case Money.parse text of
                    Ok money ->
                        Money.parse (Money.format money) |> Expect.equal (Ok money)

                    Err _ ->
                        Expect.pass
        , describe "JSON"
            [ fuzz amount "an amount survives being encoded and decoded" <|
                \money ->
                    Decode.decodeValue Money.decoder (Money.encode money)
                        |> Expect.equal (Ok money)
            , test "is a whole number of øre" <|
                \_ ->
                    Encode.encode 0 (Money.encode (ore 34900))
                        |> Expect.equal "34900"
            , test "a negative amount is not an amount" <|
                \_ ->
                    Decode.decodeString Money.decoder "-1"
                        |> Expect.err
            , test "a fraction of an øre is not an amount" <|
                \_ ->
                    Decode.decodeString Money.decoder "349.5"
                        |> Expect.err
            ]
        ]


{-| Amounts up to 20 million kroner.
-}
amount : Fuzzer Money
amount =
    Fuzz.map ore (Fuzz.intRange 0 2000000000)


{-| Text made of the characters people use when they type an amount, in any
order. About half of what this gives is an amount, which a fuzzer of arbitrary
strings almost never is.
-}
typed : Fuzzer String
typed =
    Fuzz.listOfLengthBetween 0
        8
        (Fuzz.frequencyValues
            [ ( 12, "3" ), ( 6, "0" ), ( 6, "49" ), ( 3, "," ), ( 1, "." ), ( 2, " " ), ( 1, "kr" ), ( 1, "-" ), ( 1, "\u{00A0}" ) ]
        )
        |> Fuzz.map String.concat


parsesTo : ( String, Int ) -> Test
parsesTo ( input, expected ) =
    test ("\"" ++ input ++ "\"") <|
        \_ ->
            Money.parse input
                |> Expect.equal (Ok (ore expected))


failsWith : ParseError -> String -> Test
failsWith error input =
    test ("\"" ++ input ++ "\"") <|
        \_ ->
            Money.parse input
                |> Expect.equal (Err error)
