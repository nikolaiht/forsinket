module DecisionTest exposing (suite)

import Claim.Decision as Decision exposing (Choice(..), Decision, Draft, Verdict(..))
import Claim.Reason exposing (RejectionReason(..))
import Expect
import FieldError exposing (Field(..), FieldError, Problem(..))
import Money exposing (Money)
import Test exposing (Test, describe, test)


suite : Test
suite =
    describe "Claim.Decision.validate"
        [ describe "approving a claim with expenses to review"
            [ test "covers what the officer typed" <|
                \_ ->
                    validateWithExpenses approval
                        |> Expect.equal
                            (Ok
                                { officer = "KN"
                                , note = "Kvitteringen viser 500 kr."
                                , verdict = Approve (Money.fromOre 50000)
                                }
                            )
            , test "nothing at all may be covered" <|
                \_ ->
                    validateWithExpenses { approval | approvedExpenses = "0" }
                        |> Result.map .verdict
                        |> Expect.equal (Ok (Approve Money.zero))
            , test "everything that can be covered may be covered" <|
                \_ ->
                    validateWithExpenses { approval | approvedExpenses = "620" }
                        |> Result.map .verdict
                        |> Expect.equal (Ok (Approve (Money.fromOre 62000)))
            , test "but not one øre more" <|
                \_ ->
                    validateWithExpenses { approval | approvedExpenses = "620,01" }
                        |> Expect.equal (Err [ { field = ApprovedExpensesField, problem = AboveMaximum } ])
            , test "an amount has to be given" <|
                \_ ->
                    validateWithExpenses { approval | approvedExpenses = "" }
                        |> Expect.equal (Err [ { field = ApprovedExpensesField, problem = Required } ])
            , test "and has to be an amount" <|
                \_ ->
                    validateWithExpenses { approval | approvedExpenses = "alt" }
                        |> Expect.equal (Err [ { field = ApprovedExpensesField, problem = NotAnAmount } ])
            , test "a note is welcome but not needed" <|
                \_ ->
                    validateWithExpenses { approval | note = "  " }
                        |> Result.map .note
                        |> Expect.equal (Ok "")
            ]
        , describe "approving a claim with no expenses to review"
            [ test "covers nothing, whatever is left in the field" <|
                \_ ->
                    Decision.validate { maxCoverable = Nothing } { approval | approvedExpenses = "alt" }
                        |> Result.map .verdict
                        |> Expect.equal (Ok (Approve Money.zero))
            ]
        , describe "rejecting"
            [ test "records the reason" <|
                \_ ->
                    validateWithExpenses rejection
                        |> Expect.equal
                            (Ok
                                { officer = "KN"
                                , note = "Samme reise er allerede erstattet."
                                , verdict = Reject DuplicateClaim
                                }
                            )
            , test "has to be explained" <|
                \_ ->
                    validateWithExpenses { rejection | note = "   " }
                        |> Expect.equal (Err [ { field = NoteField, problem = Required } ])
            , test "ignores what was typed as approved expenses" <|
                \_ ->
                    validateWithExpenses { rejection | approvedExpenses = "alt" }
                        |> Result.map .verdict
                        |> Expect.equal (Ok (Reject DuplicateClaim))
            ]
        , describe "the officer signs with 2 to 10 letters"
            (List.map (officerIs []) [ "KN", "åse", "ABCDEFGHIJ", "  KN  " ]
                ++ List.map (officerIs [ InvalidFormat ]) [ "K", "KN1", "K N", "ABCDEFGHIJK", "K." ]
                ++ List.map (officerIs [ Required ]) [ "", "   " ]
            )
        , describe "the note"
            [ test "is trimmed" <|
                \_ ->
                    validateWithExpenses { approval | note = "  Ok.  " }
                        |> Result.map .note
                        |> Expect.equal (Ok "Ok.")
            , test "can be 500 characters" <|
                \_ ->
                    validateWithExpenses { approval | note = String.repeat 500 "a" }
                        |> Expect.ok
            , test "but not 501" <|
                \_ ->
                    validateWithExpenses { approval | note = String.repeat 501 "a" }
                        |> Expect.equal (Err [ { field = NoteField, problem = TooLong } ])
            ]
        , test "every problem is reported at once, in the order of the form" <|
            \_ ->
                validateWithExpenses { choice = Approving, approvedExpenses = "900", note = String.repeat 501 "a", officer = "" }
                    |> Expect.equal
                        (Err
                            [ { field = ApprovedExpensesField, problem = AboveMaximum }
                            , { field = NoteField, problem = TooLong }
                            , { field = OfficerField, problem = Required }
                            ]
                        )
        ]


maxCoverable : Money
maxCoverable =
    Money.fromOre 62000


validateWithExpenses : Draft -> Result (List FieldError) Decision
validateWithExpenses =
    Decision.validate { maxCoverable = Just maxCoverable }


approval : Draft
approval =
    { choice = Approving
    , approvedExpenses = "500"
    , note = "Kvitteringen viser 500 kr."
    , officer = "KN"
    }


rejection : Draft
rejection =
    { choice = Rejecting DuplicateClaim
    , approvedExpenses = ""
    , note = "Samme reise er allerede erstattet."
    , officer = "KN"
    }


officerIs : List Problem -> String -> Test
officerIs problems officer =
    test ("\"" ++ officer ++ "\"") <|
        \_ ->
            case validateWithExpenses { approval | officer = officer } of
                Ok _ ->
                    Expect.equal [] problems

                Err errors ->
                    FieldError.for OfficerField errors
                        |> Expect.equal problems
