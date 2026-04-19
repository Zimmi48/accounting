module BackendTests exposing (suite)

{-| Regression tests for backend helpers that should stay safe while the
storage model remains append-only.
-}

import Array
import Backend
import Dict
import Expect
import Test exposing (..)
import Types exposing (..)


suite : Test
suite =
    describe "Backend pure helpers"
        [ {- These assertions protect append-only slot stability. Edits and
             deletes should never reshuffle older day positions because the UI
             addresses rows through those derived indexes.
          -}
          describe "append-only transaction slots"
            [ test "creating another spending on the same day appends new slots instead of reusing old ones" <|
                \_ ->
                    let
                        model =
                            emptyModel
                                |> Backend.createSpendingInModel "Breakfast" (Amount 1200) baseTransactions
                                |> Backend.createSpendingInModel "Lunch" (Amount 800) revisedTransactions
                    in
                    Expect.equal
                        ( [ 0, 1 ], [ 2, 3 ] )
                        ( transactionIndexes 0 model, transactionIndexes 1 model )
            , test "editing a spending keeps the replaced slots stable and appends the replacement rows" <|
                \_ ->
                    let
                        originalModel =
                            Backend.createSpendingInModel "Dinner" (Amount 1200) baseTransactions emptyModel

                        editedModel =
                            replaceSpending 0 "Dinner (edited)" (Amount 800) revisedTransactions originalModel
                    in
                    Expect.equal
                        ( [ ( 0, Replaced ), ( 1, Replaced ) ]
                        , [ ( 2, Active ), ( 3, Active ) ]
                        , [ Replaced, Replaced, Active, Active ]
                        )
                        ( transactionSlots 0 editedModel
                        , transactionSlots 1 editedModel
                        , dayStatuses 2025 4 18 editedModel
                        )
            , test "deleting a spending keeps its historical slots while hiding it from active detail views" <|
                \_ ->
                    let
                        originalModel =
                            Backend.createSpendingInModel "Dinner" (Amount 1200) baseTransactions emptyModel

                        deletedModel =
                            deleteSpending 0 originalModel
                    in
                    Expect.equal
                        ( [ ( 0, Deleted ), ( 1, Deleted ) ], [] )
                        ( transactionSlots 0 deletedModel
                        , Backend.spendingTransactionsForDetails 0 deletedModel
                        )
            ]
        , {- These tests document how backend validation first normalizes the
             transaction list and then enforces balance and non-empty groups.
          -}
          describe "spending validation and normalization"
            [ test "validation merges duplicate transaction keys before checking the spending total" <|
                \_ ->
                    let
                        result =
                            Backend.validateSpendingTransactions
                                (Amount 500)
                                [ spendingTransaction 18 "Alice" CreditTransaction 300
                                , spendingTransaction 18 "Alice" CreditTransaction 200
                                , spendingTransaction 18 "Trip" DebitTransaction 500
                                ]
                    in
                    case result of
                        Ok normalized ->
                            Expect.equal
                                ( 2
                                , Just (Amount 500)
                                , Just (Amount 500)
                                )
                                ( List.length normalized
                                , findAmount "Alice" CreditTransaction normalized
                                , findAmount "Trip" DebitTransaction normalized
                                )

                        Err errorMessage ->
                            Expect.fail ("Expected normalized transactions, got: " ++ errorMessage)
            , test "normalization drops keys whose combined amount becomes zero" <|
                \_ ->
                    Expect.equal
                        []
                        (Backend.normalizeSpendingTransactions
                            [ spendingTransaction 18 "Alice" CreditTransaction 500
                            , spendingTransaction 18 "Alice" CreditTransaction -500
                            ]
                        )
            , test "validation rejects blank groups even when numeric totals would balance" <|
                \_ ->
                    Expect.equal
                        (Err "Spending total must match total credits and total debits")
                        (Backend.validateSpendingTransactions
                            (Amount 500)
                            [ spendingTransaction 18 "   " CreditTransaction 500
                            , spendingTransaction 18 "Trip" DebitTransaction 500
                            ]
                        )
            ]
        ]


emptyModel : Backend.Model
emptyModel =
    Tuple.first Backend.init


baseTransactions : List SpendingTransaction
baseTransactions =
    [ spendingTransaction 18 "Alice" CreditTransaction 1200
    , spendingTransaction 18 "Trip" DebitTransaction 1200
    ]


revisedTransactions : List SpendingTransaction
revisedTransactions =
    [ spendingTransaction 18 "Bob" CreditTransaction 800
    , spendingTransaction 18 "Trip" DebitTransaction 800
    ]


spendingTransaction : Int -> String -> TransactionSide -> Int -> SpendingTransaction
spendingTransaction day group side amount =
    { year = 2025
    , month = 4
    , day = day
    , secondaryDescription = ""
    , group = group
    , amount = Amount amount
    , side = side
    }


replaceSpending : SpendingId -> String -> Amount Credit -> List SpendingTransaction -> Backend.Model -> Backend.Model
replaceSpending spendingId description total transactions model =
    let
        activeTransactions =
            Backend.getSpendingTransactionsWithIds spendingId model
                |> List.filter (\( _, transaction ) -> transaction.status == Active)

        cleanedModel =
            List.foldl
                Backend.removeTransactionFromModel
                (model
                    |> Backend.setSpendingStatus spendingId Replaced
                    |> Backend.setTransactionStatuses spendingId Replaced
                )
                activeTransactions
    in
    Backend.createSpendingInModel description total transactions cleanedModel


deleteSpending : SpendingId -> Backend.Model -> Backend.Model
deleteSpending spendingId model =
    let
        activeTransactions =
            Backend.getSpendingTransactionsWithIds spendingId model
                |> List.filter (\( _, transaction ) -> transaction.status == Active)
    in
    List.foldl
        Backend.removeTransactionFromModel
        (model
            |> Backend.setSpendingStatus spendingId Deleted
            |> Backend.setTransactionStatuses spendingId Deleted
        )
        activeTransactions


transactionIndexes : SpendingId -> Backend.Model -> List Int
transactionIndexes spendingId model =
    Backend.getSpendingTransactionsWithIds spendingId model
        |> List.map (\( transactionId, _ ) -> transactionId.index)


transactionSlots : SpendingId -> Backend.Model -> List ( Int, TransactionStatus )
transactionSlots spendingId model =
    Backend.getSpendingTransactionsWithIds spendingId model
        |> List.map (\( transactionId, transaction ) -> ( transactionId.index, transaction.status ))


dayStatuses : Int -> Int -> Int -> Backend.Model -> List TransactionStatus
dayStatuses year month day model =
    model.years
        |> Dict.get year
        |> Maybe.andThen (.months >> Dict.get month)
        |> Maybe.andThen (.days >> Dict.get day)
        |> Maybe.map (.transactions >> Array.toList >> List.map .status)
        |> Maybe.withDefault []


findAmount : String -> TransactionSide -> List SpendingTransaction -> Maybe (Amount ())
findAmount group side transactions =
    transactions
        |> List.filter (\transaction -> transaction.group == group && transaction.side == side)
        |> List.head
        |> Maybe.map .amount
