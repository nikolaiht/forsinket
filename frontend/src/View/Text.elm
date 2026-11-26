module View.Text exposing (expenseKind, ineligibility, rejectionReason, reviewReason, status, ticket)

{-| The Norwegian words for the things the service names in English.

Each function is a `case` over a custom type, so a value added on the server
side, and to the type here, does not compile until it has been given a word.

-}

import Claim.Expenses as Expenses
import Claim.Reason exposing (IneligibilityReason(..), RejectionReason(..), ReviewReason(..))
import Claim.Ticket as Ticket exposing (Ticket(..))
import Money
import Status


status : Status.Name -> String
status name =
    case name of
        Status.Received ->
            "Mottatt"

        Status.AwaitingReview ->
            "Til behandling"

        Status.Approved ->
            "Innvilget"

        Status.Rejected ->
            "Avslått"

        Status.PaidOut ->
            "Utbetalt"


ineligibility : IneligibilityReason -> String
ineligibility reason =
    case reason of
        SubmittedTooLate ->
            "Kravet kom etter fristen."

        DelayBelowThreshold ->
            "Forsinkelsen var for kort til å gi erstatning."


reviewReason : ReviewReason -> String
reviewReason reason =
    case reason of
        ExpensesClaimed ->
            "utlegget må vurderes mot kvitteringen"

        AboveAutoApprovalLimit ->
            "beløpet er over grensen for automatisk innvilgelse"


rejectionReason : RejectionReason -> String
rejectionReason reason =
    case reason of
        InvalidTicket ->
            "Billetten gjaldt ikke for reisen"

        DuplicateClaim ->
            "Reisen er allerede erstattet"

        OtherReason ->
            "Annen grunn"


expenseKind : Expenses.Kind -> String
expenseKind kind =
    case kind of
        Expenses.Taxi ->
            "Taxi"

        Expenses.Bus ->
            "Buss"

        Expenses.Other ->
            "Annet"


{-| `Enkeltbillett til 349,00 kr`
-}
ticket : Ticket -> String
ticket value =
    case value of
        Single price ->
            "Enkeltbillett til " ++ Money.format price

        Period price validity ->
            String.fromInt (Ticket.validityDays validity) ++ "-dagersbillett til " ++ Money.format price
