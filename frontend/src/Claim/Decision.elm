module Claim.Decision exposing (Choice(..), Decision, Draft, Verdict(..), empty, encode, maxNoteLength, validate)

{-| The form an officer decides a claim with.

As with a new claim, the `Draft` is what is in the form, and a `Decision` is
what `validate` makes of it when everything is in order.

-}

import Claim.Reason as Reason exposing (RejectionReason)
import FieldError exposing (Field(..), FieldError, Problem(..))
import Json.Encode as Encode
import Money exposing (Money)
import Validation exposing (Minimum(..))


type alias Draft =
    { choice : Choice
    , approvedExpenses : String
    , note : String
    , officer : String
    }


{-| A rejection always has a reason, and an approval never has one, so the
reason lives inside the choice.
-}
type Choice
    = Approving
    | Rejecting RejectionReason


empty : Draft
empty =
    { choice = Approving
    , approvedExpenses = ""
    , note = ""
    , officer = ""
    }


type alias Decision =
    { officer : String
    , note : String
    , verdict : Verdict
    }


type Verdict
    = Approve Money
    | Reject RejectionReason


{-| `maxCoverable` is the most the rules let an officer cover of this claim's
expenses, or `Nothing` when the claim has no expenses to review. Then there is
no amount to ask for, and nothing is covered.

The service checks all of this again. These checks are here so the officer is
told at once, next to the field.

-}
validate : { maxCoverable : Maybe Money } -> Draft -> Result (List FieldError) Decision
validate { maxCoverable } draft =
    Ok (\verdict note officer -> { officer = officer, note = note, verdict = verdict })
        |> Validation.andMap (verdictOf maxCoverable draft)
        |> Validation.andMap (noteOf draft)
        |> Validation.andMap (officerOf draft.officer)


verdictOf : Maybe Money -> Draft -> Result (List FieldError) Verdict
verdictOf maxCoverable draft =
    case ( draft.choice, maxCoverable ) of
        ( Rejecting reason, _ ) ->
            Ok (Reject reason)

        ( Approving, Nothing ) ->
            Ok (Approve Money.zero)

        ( Approving, Just limit ) ->
            Validation.amount ApprovedExpensesField { atLeast = ZeroOrMore, atMost = limit } draft.approvedExpenses
                |> Result.map Approve


{-| An approval can speak for itself. A rejection has to be explained.
-}
noteOf : Draft -> Result (List FieldError) String
noteOf draft =
    let
        note : String
        note =
            String.trim draft.note
    in
    if String.length note > maxNoteLength then
        Err [ { field = NoteField, problem = TooLong } ]

    else
        case ( draft.choice, note ) of
            ( Rejecting _, "" ) ->
                Err [ { field = NoteField, problem = Required } ]

            _ ->
                Ok note


maxNoteLength : Int
maxNoteLength =
    500


officerOf : String -> Result (List FieldError) String
officerOf raw =
    let
        officer : String
        officer =
            String.trim raw
    in
    if String.isEmpty officer then
        Err [ { field = OfficerField, problem = Required } ]

    else if String.length officer < 2 || String.length officer > 10 || not (String.all isLetter officer) then
        Err [ { field = OfficerField, problem = InvalidFormat } ]

    else
        Ok officer


{-| `Char.isAlpha` only knows a to z, and an officer may well be called Åse. A
character that has an upper and a lower case is a letter in every alphabet
that has cases, which covers the initials this field is for.
-}
isLetter : Char -> Bool
isLetter char =
    Char.toUpper char /= Char.toLower char


encode : Int -> Decision -> Encode.Value
encode expectedVersion decision =
    Encode.object
        [ ( "expectedVersion", Encode.int expectedVersion )
        , ( "officer", Encode.string decision.officer )
        , ( "note", Encode.string decision.note )
        , ( "decision"
          , case decision.verdict of
                Approve approvedExpenses ->
                    Encode.object
                        [ ( "type", Encode.string "approve" )
                        , ( "approvedExpenses", Money.encode approvedExpenses )
                        ]

                Reject reason ->
                    Encode.object
                        [ ( "type", Encode.string "reject" )
                        , ( "reason", Encode.string (Reason.rejectionToString reason) )
                        ]
          )
        ]
