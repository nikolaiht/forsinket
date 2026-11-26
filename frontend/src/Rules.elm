module Rules exposing (Band, Rules, decoder)

{-| The rules claims are assessed by, as the service publishes them. The front
page shows this table, and the forms take their upper limits from it, so
neither can drift away from what the service actually applies.
-}

import Json.Decode as Decode exposing (Decoder)
import Money exposing (Money)


type alias Rules =
    { version : String
    , claimDeadlineDays : Int
    , bands : List Band
    , expenseMinDelayMinutes : Int
    , expenseCap : Money
    , autoApprovalLimit : Money
    , maxTicketPrice : Money
    , maxClaimedExpenses : Money
    }


{-| From this many minutes of delay, this share of the ticket value is paid.
-}
type alias Band =
    { fromMinutes : Int
    , percent : Int
    }


decoder : Decoder Rules
decoder =
    Decode.map8 Rules
        (Decode.field "version" Decode.string)
        (Decode.field "claimDeadlineDays" Decode.int)
        (Decode.field "bands" (Decode.list bandDecoder))
        (Decode.field "expenseMinDelayMinutes" Decode.int)
        (Decode.field "expenseCap" Money.decoder)
        (Decode.field "autoApprovalLimit" Money.decoder)
        (Decode.field "maxTicketPrice" Money.decoder)
        (Decode.field "maxClaimedExpenses" Money.decoder)


bandDecoder : Decoder Band
bandDecoder =
    Decode.map2 Band
        (Decode.field "fromMinutes" Decode.int)
        (Decode.field "percent" Decode.int)
