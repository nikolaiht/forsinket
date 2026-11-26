module DraftTest exposing (suite)

import Claim.Draft as Draft exposing (Draft, ExpensesDraft(..), NewClaim, TicketKind(..))
import Claim.Expenses as Expenses exposing (Expenses)
import Claim.Ticket exposing (Ticket(..), Validity(..))
import Expect
import FieldError exposing (Field(..), FieldError, Problem(..))
import Fixtures
import Fuzz exposing (Fuzzer)
import Money
import Test exposing (Test, describe, fuzz, test)


suite : Test
suite =
    describe "Claim.Draft.validate"
        [ test "a filled-in form becomes a claim that can be sent" <|
            \_ ->
                validate complete
                    |> Expect.equal
                        (Ok
                            { departureId = Fixtures.fb16.id
                            , ticket = Fixtures.single349
                            , expenses = Nothing
                            }
                        )
        , test "a period ticket with expenses" <|
            \_ ->
                validate
                    { complete
                        | departure = Just Fixtures.fb14.id
                        , ticketKind = PeriodKind ThirtyDays
                        , price = "849"
                        , expenses = WithExpenses { amount = "620,00", kind = Expenses.Taxi }
                    }
                    |> Expect.equal
                        (Ok
                            { departureId = Fixtures.fb14.id
                            , ticket = Fixtures.period849
                            , expenses = Just Fixtures.taxi620
                            }
                        )
        , test "an empty form is told about everything that is missing, in the order of the form" <|
            \_ ->
                validate Draft.empty
                    |> Expect.equal
                        (Err
                            [ { field = DepartureField, problem = Required }
                            , { field = PriceField, problem = Required }
                            ]
                        )
        , describe "the price"
            [ priceIs "abc" [ NotAnAmount ]
            , priceIs "-349" [ NotAnAmount ]
            , priceIs "   " [ Required ]
            , priceIs "0" [ MustBePositive ]
            , priceIs "0,00 kr" [ MustBePositive ]
            , priceIs "20 000" []
            , priceIs "20 000,01" [ AboveMaximum ]
            ]
        , describe "expenses"
            [ test "an amount is required once expenses are claimed" <|
                \_ ->
                    validate { complete | expenses = WithExpenses { amount = "", kind = Expenses.Bus } }
                        |> Expect.equal (Err [ { field = ExpensesAmountField, problem = Required } ])
            , test "must be more than nothing" <|
                \_ ->
                    validate { complete | expenses = WithExpenses { amount = "0", kind = Expenses.Bus } }
                        |> Expect.equal (Err [ { field = ExpensesAmountField, problem = MustBePositive } ])
            , test "are capped at what the rules say can be claimed" <|
                \_ ->
                    validate { complete | expenses = WithExpenses { amount = "10 000,01", kind = Expenses.Other } }
                        |> Expect.equal (Err [ { field = ExpensesAmountField, problem = AboveMaximum } ])
            , test "what was typed is forgotten when expenses are not claimed after all" <|
                \_ ->
                    validate { complete | expenses = NoExpenses }
                        |> Result.map .expenses
                        |> Expect.equal (Ok Nothing)
            ]
        , test "every problem is reported at once" <|
            \_ ->
                validate
                    { date = "2026-11-20"
                    , departure = Nothing
                    , ticketKind = SingleKind
                    , price = "gratis"
                    , expenses = WithExpenses { amount = "", kind = Expenses.Taxi }
                    }
                    |> Expect.equal
                        (Err
                            [ { field = DepartureField, problem = Required }
                            , { field = PriceField, problem = NotAnAmount }
                            , { field = ExpensesAmountField, problem = Required }
                            ]
                        )
        , fuzz newClaim "a form filled in with any acceptable claim gives back exactly that claim" <|
            \claim ->
                validate (draftFor claim)
                    |> Expect.equal (Ok claim)
        ]


validate : Draft -> Result (List FieldError) NewClaim
validate =
    Draft.validate Fixtures.rules


{-| The form for example A: FB16 on a single ticket of 349 kr, no expenses.
-}
complete : Draft
complete =
    { date = "2026-11-20"
    , departure = Just Fixtures.fb16.id
    , ticketKind = SingleKind
    , price = "349"
    , expenses = NoExpenses
    }


priceIs : String -> List Problem -> Test
priceIs price problems =
    test ("\"" ++ price ++ "\"") <|
        \_ ->
            case validate { complete | price = price } of
                Ok _ ->
                    Expect.equal [] problems

                Err errors ->
                    FieldError.for PriceField errors
                        |> Expect.equal problems


{-| The form as someone would have filled it in to make this claim.
-}
draftFor : NewClaim -> Draft
draftFor claim =
    let
        ( ticketKind, price ) =
            case claim.ticket of
                Single amount ->
                    ( SingleKind, amount )

                Period amount validity ->
                    ( PeriodKind validity, amount )
    in
    { date = "2026-11-20"
    , departure = Just claim.departureId
    , ticketKind = ticketKind
    , price = Money.format price
    , expenses =
        case claim.expenses of
            Nothing ->
                NoExpenses

            Just claimed ->
                WithExpenses { amount = Money.format claimed.amount, kind = claimed.kind }
    }


newClaim : Fuzzer NewClaim
newClaim =
    Fuzz.map3 NewClaim
        (Fuzz.oneOfValues [ Fixtures.fb14.id, Fixtures.fb16.id, Fixtures.fb17.id ])
        anyTicket
        (Fuzz.maybe anyExpenses)


anyTicket : Fuzzer Ticket
anyTicket =
    let
        price : Fuzzer Money.Money
        price =
            Fuzz.map Money.fromOre (Fuzz.intRange 1 (Money.toOre Fixtures.rules.maxTicketPrice))
    in
    Fuzz.oneOf
        [ Fuzz.map Single price
        , Fuzz.map2 Period price (Fuzz.oneOfValues [ SevenDays, ThirtyDays ])
        ]


anyExpenses : Fuzzer Expenses
anyExpenses =
    Fuzz.map2 Expenses
        (Fuzz.map Money.fromOre (Fuzz.intRange 1 (Money.toOre Fixtures.rules.maxClaimedExpenses)))
        (Fuzz.oneOfValues Expenses.kinds)
