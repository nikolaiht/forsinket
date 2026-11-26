module FieldErrorTest exposing (suite)

import Expect
import FieldError exposing (Field(..), Problem(..))
import Test exposing (Test, describe, test)


suite : Test
suite =
    describe "FieldError"
        [ test "the problems with one field" <|
            \_ ->
                FieldError.for PriceField
                    [ { field = DepartureField, problem = Required }
                    , { field = PriceField, problem = NotAnAmount }
                    ]
                    |> Expect.equal [ NotAnAmount ]
        , test "errors on fields the form does not have are not lost: they are listed by the name the service gave" <|
            \_ ->
                FieldError.unplaced
                    [ { field = PriceField, problem = Required }
                    , { field = OtherField "ticket.zone", problem = OtherProblem "not_served" }
                    , { field = OtherField "channel", problem = Required }
                    ]
                    |> Expect.equal
                        [ ( "ticket.zone", OtherProblem "not_served" )
                        , ( "channel", Required )
                        ]
        ]
