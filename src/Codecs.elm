module Codecs exposing (decodeString, encodeToString)

{-| Codecs for serializing and deserializing the backend model.

These codecs are auto-generated using
[gampleman/elm-review-derive](https://github.com/gampleman/elm-review-derive).

To regenerate after changing types in Types.elm, run:

    ./check-codecs.sh --regenerate

There is a CI check that verifies these codecs match the auto-generated output.
If it fails, regenerate using the command above.

-}

import Codec exposing (Codec)
import Dict
import Set
import Types
    exposing
        ( Amount(..)
        , BackendModel
        , Day
        , Month
        , Person
        , Share(..)
        , Spending
        , TransactionStatus(..)
        , Year
        )


encodeToString : BackendModel -> String
encodeToString model =
    Codec.encodeToString 0 backendCodec model


decodeString : String -> Result Codec.Error BackendModel
decodeString s =
    Codec.decodeString backendCodec s


backendCodec : Codec BackendModel
backendCodec =
    Codec.object BackendModel
        |> Codec.field
            "years"
            .years
            (Codec.map Dict.fromList Dict.toList (Codec.list (Codec.tuple Codec.int yearCodec)))
        |> Codec.field "groups" .groups (Codec.dict (Codec.dict shareCodec))
        |> Codec.field "totalGroupCredits" .totalGroupCredits (Codec.dict (Codec.dict amountCodec))
        |> Codec.field "persons" .persons (Codec.dict personCodec)
        |> Codec.field "nextPersonId" .nextPersonId Codec.int
        |> Codec.field "loggedInSessions" .loggedInSessions (Codec.set Codec.string)
        |> Codec.buildObject


yearCodec : Codec Year
yearCodec =
    Codec.object Year
        |> Codec.field
            "months"
            .months
            (Codec.map Dict.fromList Dict.toList (Codec.list (Codec.tuple Codec.int monthCodec)))
        |> Codec.field "totalGroupCredits" .totalGroupCredits (Codec.dict (Codec.dict amountCodec))
        |> Codec.buildObject


monthCodec : Codec Month
monthCodec =
    Codec.object Month
        |> Codec.field "days" .days (Codec.map Dict.fromList Dict.toList (Codec.list (Codec.tuple Codec.int dayCodec)))
        |> Codec.field "totalGroupCredits" .totalGroupCredits (Codec.dict (Codec.dict amountCodec))
        |> Codec.buildObject


dayCodec : Codec Day
dayCodec =
    Codec.object Day
        |> Codec.field "spendings" .spendings (Codec.list spendingCodec)
        |> Codec.field "totalGroupCredits" .totalGroupCredits (Codec.dict (Codec.dict amountCodec))
        |> Codec.buildObject


spendingCodec : Codec Spending
spendingCodec =
    Codec.object Spending
        |> Codec.field "description" .description Codec.string
        |> Codec.field "total" .total amountCodec
        |> Codec.field "credits" .credits (Codec.dict amountCodec)
        |> Codec.field "debits" .debits (Codec.dict amountCodec)
        |> Codec.field "status" .status transactionStatusCodec
        |> Codec.buildObject


transactionStatusCodec : Codec TransactionStatus
transactionStatusCodec =
    Codec.custom
        (\activeEncoder deletedEncoder replacedEncoder value ->
            case value of
                Types.Active ->
                    activeEncoder

                Types.Deleted ->
                    deletedEncoder

                Types.Replaced ->
                    replacedEncoder
        )
        |> Codec.variant0 "Active" Types.Active
        |> Codec.variant0 "Deleted" Types.Deleted
        |> Codec.variant0 "Replaced" Types.Replaced
        |> Codec.buildCustom


shareCodec : Codec Share
shareCodec =
    Codec.custom
        (\shareEncoder value ->
            case value of
                Types.Share argA ->
                    shareEncoder argA
        )
        |> Codec.variant1 "Share" Share Codec.int
        |> Codec.buildCustom


personCodec : Codec Person
personCodec =
    Codec.object Person
        |> Codec.field "id" .id Codec.int
        |> Codec.field "belongsTo" .belongsTo (Codec.set Codec.string)
        |> Codec.buildObject


{-| amountCodec is manually maintained because Amount has a phantom type
parameter that elm-review-derive cannot handle automatically.
-}
amountCodec : Codec (Amount a)
amountCodec =
    Codec.custom
        (\amountEncoder value ->
            case value of
                Amount arg0 ->
                    amountEncoder arg0
        )
        |> Codec.variant1 "Amount" Amount Codec.int
        |> Codec.buildCustom
