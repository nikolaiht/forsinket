module Claim.Draft exposing (Draft, ExpensesDraft(..), NewClaim, TicketKind(..), empty, encode, validate)

{-| The form for a new claim.

A `Draft` is what is in the form right now: text exactly as it was typed, and
choices as they stand. It can be half finished or plain wrong. A `NewClaim` is
a claim that can be sent, and the only way to get one is `validate`. So there
is no flag saying whether the form has been checked: either you hold a
`NewClaim`, or you hold the list of what is wrong.

-}

import Claim.Expenses as Expenses exposing (Expenses)
import Claim.Ticket as Ticket exposing (Ticket(..), Validity)
import Departure
import FieldError exposing (Field(..), FieldError, Problem(..))
import Json.Encode as Encode
import Rules exposing (Rules)
import Validation exposing (Minimum(..))


type alias Draft =
    { departure : Maybe Departure.Id
    , ticketKind : TicketKind
    , price : String
    , expenses : ExpensesDraft
    }


type TicketKind
    = SingleKind
    | PeriodKind Validity


{-| The amount and kind are only there when expenses are claimed. Unticking
the box drops them, so a stale amount cannot follow a claim out the door.
-}
type ExpensesDraft
    = NoExpenses
    | WithExpenses { amount : String, kind : Expenses.Kind }


empty : Draft
empty =
    { departure = Nothing
    , ticketKind = SingleKind
    , price = ""
    , expenses = NoExpenses
    }


type alias NewClaim =
    { departureId : Departure.Id
    , ticket : Ticket
    , expenses : Maybe Expenses
    }


{-| Turn the form into a claim, or into everything that is wrong with it, in
the order of the form. The limits come from the rules the service publishes,
so the form and the service agree on what is too much.
-}
validate : Rules -> Draft -> Result (List FieldError) NewClaim
validate rules draft =
    Ok NewClaim
        |> Validation.andMap (departure draft.departure)
        |> Validation.andMap (ticket rules draft)
        |> Validation.andMap (expenses rules draft.expenses)


departure : Maybe Departure.Id -> Result (List FieldError) Departure.Id
departure chosen =
    Result.fromMaybe [ { field = DepartureField, problem = Required } ] chosen


ticket : Rules -> Draft -> Result (List FieldError) Ticket
ticket rules draft =
    Validation.amount PriceField { atLeast = MoreThanZero, atMost = rules.maxTicketPrice } draft.price
        |> Result.map
            (\price ->
                case draft.ticketKind of
                    SingleKind ->
                        Single price

                    PeriodKind validity ->
                        Period price validity
            )


expenses : Rules -> ExpensesDraft -> Result (List FieldError) (Maybe Expenses)
expenses rules draft =
    case draft of
        NoExpenses ->
            Ok Nothing

        WithExpenses { amount, kind } ->
            Validation.amount ExpensesAmountField { atLeast = MoreThanZero, atMost = rules.maxClaimedExpenses } amount
                |> Result.map (\claimed -> Just { amount = claimed, kind = kind })


encode : NewClaim -> Encode.Value
encode claim =
    Encode.object
        [ ( "departureId", Departure.encodeId claim.departureId )
        , ( "ticket", Ticket.encode claim.ticket )
        , ( "expenses"
          , claim.expenses
                |> Maybe.map Expenses.encode
                |> Maybe.withDefault Encode.null
          )
        ]
