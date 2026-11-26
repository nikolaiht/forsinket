module Example exposing (Example, decoder)

{-| A worked example for the front page: a ticket, what happened to the
train, and what the rules make of it. The service works each one out with the
function that settles real claims.
-}

import Claim.Calculation as Calculation exposing (Assessment)
import Claim.Expenses as Expenses exposing (Expenses)
import Claim.Ticket as Ticket exposing (Ticket)
import Departure exposing (Outcome)
import Json.Decode as Decode exposing (Decoder)


type alias Example =
    { ticket : Ticket
    , expenses : Maybe Expenses
    , outcome : Outcome
    , assessment : Assessment
    }


decoder : Decoder Example
decoder =
    Decode.map4 Example
        (Decode.field "ticket" Ticket.decoder)
        (Decode.field "expenses" (Decode.nullable Expenses.decoder))
        (Decode.field "outcome" Departure.outcomeDecoder)
        (Decode.field "assessment" Calculation.assessmentDecoder)
