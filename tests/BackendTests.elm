module BackendTests exposing (suite)

{-| Regression tests for backend helpers that should stay safe while the
storage model remains append-only.
-}

import Array
import Backend
import Dict
import Evergreen.Migrate.V26 as MigrateV26
import Evergreen.V24.Types as V24
import Evergreen.V26.Types as V26
import Expect
import Set
import String
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
        , describe "V24 to V26 backend migration"
            [ test "migration rebuilds same-day spendings with stable transaction ids and statuses" <|
                \_ ->
                    let
                        migrated =
                            MigrateV26.migrateBackendModel legacyBackendModel

                        spendings =
                            Array.toList migrated.spendings

                        dayTransactions =
                            v26DayTransactions 2025 4 18 migrated
                    in
                    Expect.equal
                        ( [ ( "Train", [ 0, 1 ], V26.Active )
                          , ( "Breakfast", [ 0, 1 ], V26.Active )
                          , ( "Lunch", [ 2, 3 ], V26.Deleted )
                          ]
                        , [ { index = 0, spendingId = 1, group = "Alice", side = V26.CreditTransaction, status = V26.Active }
                          , { index = 1, spendingId = 1, group = "Trip", side = V26.DebitTransaction, status = V26.Active }
                          , { index = 2, spendingId = 2, group = "Bob", side = V26.CreditTransaction, status = V26.Deleted }
                          , { index = 3, spendingId = 2, group = "Solo", side = V26.DebitTransaction, status = V26.Deleted }
                          ]
                        )
                        ( spendings
                            |> List.map
                                (\spending ->
                                    ( spending.description
                                    , List.map .index spending.transactionIds
                                    , spending.status
                                    )
                                )
                        , dayTransactions
                            |> List.indexedMap
                                (\index transaction ->
                                    { index = index
                                    , spendingId = transaction.spendingId
                                    , group = transaction.group
                                    , side = transaction.side
                                    , status = transaction.status
                                    }
                                )
                        )
            , test "migration assigns spending ids chronologically across legacy days" <|
                \_ ->
                    let
                        migrated =
                            MigrateV26.migrateBackendModel legacyBackendModel
                    in
                    Expect.equal
                        [ ( 0, "Train", [ "2025-4-17-0", "2025-4-17-1" ] )
                        , ( 1, "Breakfast", [ "2025-4-18-0", "2025-4-18-1" ] )
                        , ( 2, "Lunch", [ "2025-4-18-2", "2025-4-18-3" ] )
                        ]
                        (migrated.spendings
                            |> Array.toIndexedList
                            |> List.map
                                (\( spendingId, spending ) ->
                                    ( spendingId
                                    , spending.description
                                    , spending.transactionIds
                                        |> List.map transactionIdToString
                                    )
                                )
                        )
            , test "migration rebuilds member metadata from groups and fallback names" <|
                \_ ->
                    let
                        migrated =
                            MigrateV26.migrateBackendModel legacyBackendModel

                        trainCredit =
                            v26FindTransaction { year = 2025, month = 4, day = 17, index = 0 } migrated

                        lunchDebit =
                            v26FindTransaction { year = 2025, month = 4, day = 18, index = 3 } migrated
                    in
                    Expect.equal
                        ( Just
                            ( "1,2"
                            , Set.fromList [ "Alice", "Bob" ]
                            )
                        , Just
                            ( "2"
                            , Set.fromList [ "Bob", "Solo" ]
                            )
                        )
                        ( trainCredit |> Maybe.map (\transaction -> ( transaction.groupMembersKey, transaction.groupMembers ))
                        , lunchDebit |> Maybe.map (\transaction -> ( transaction.groupMembersKey, transaction.groupMembers ))
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


legacyBackendModel : V24.BackendModel
legacyBackendModel =
    { years =
        Dict.fromList
            [ ( 2025
              , { months =
                    Dict.fromList
                        [ ( 4
                          , { days =
                                Dict.fromList
                                    [ ( 17
                                      , legacyDay
                                            [ legacySpending "Train" 500 [ ( "Alice", 500 ) ] [ ( "Trip", 500 ) ] V24.Active
                                            ]
                                      )
                                    , ( 18
                                      , legacyDay
                                            [ legacySpending "Breakfast" 1200 [ ( "Alice", 1200 ) ] [ ( "Trip", 1200 ) ] V24.Active
                                            , legacySpending "Lunch" 800 [ ( "Bob", 800 ) ] [ ( "Solo", 800 ) ] V24.Deleted
                                            ]
                                      )
                                    ]
                            , totalGroupCredits = legacyTotals 250
                            }
                          )
                        ]
                , totalGroupCredits = legacyTotals 500
                }
              )
            ]
    , groups =
        Dict.fromList
            [ ( "Trip"
              , Dict.fromList
                    [ ( "Alice", V24.Share 1 )
                    , ( "Bob", V24.Share 1 )
                    ]
              )
            ]
    , totalGroupCredits = legacyTotals 750
    , persons =
        Dict.fromList
            [ ( "Alice", { id = 1, belongsTo = Set.singleton "Trip" } )
            , ( "Bob", { id = 2, belongsTo = Set.singleton "Trip" } )
            ]
    , nextPersonId = 3
    , loggedInSessions = Set.empty
    }


legacyDay : List V24.Spending -> V24.Day
legacyDay spendings =
    { spendings = spendings
    , totalGroupCredits = legacyTotals 125
    }


legacySpending :
    String
    -> Int
    -> List ( String, Int )
    -> List ( String, Int )
    -> V24.TransactionStatus
    -> V24.Spending
legacySpending description total credits debits status =
    { description = description
    , total = V24.Amount total
    , credits = credits |> Dict.fromList |> Dict.map (\_ amount -> V24.Amount amount)
    , debits = debits |> Dict.fromList |> Dict.map (\_ amount -> V24.Amount amount)
    , status = status
    }


legacyTotals : Int -> Dict.Dict String (Dict.Dict String (V24.Amount V24.Credit))
legacyTotals amount =
    Dict.fromList
        [ ( "Trip"
          , Dict.fromList
                [ ( "Alice", V24.Amount amount ) ]
          )
        ]


v26FindTransaction : V26.TransactionId -> V26.BackendModel -> Maybe V26.Transaction
v26FindTransaction transactionId model =
    model.years
        |> Dict.get transactionId.year
        |> Maybe.andThen (.months >> Dict.get transactionId.month)
        |> Maybe.andThen (.days >> Dict.get transactionId.day)
        |> Maybe.andThen (.transactions >> Array.get transactionId.index)


v26DayTransactions : Int -> Int -> Int -> V26.BackendModel -> List V26.Transaction
v26DayTransactions year month day model =
    model.years
        |> Dict.get year
        |> Maybe.andThen (.months >> Dict.get month)
        |> Maybe.andThen (.days >> Dict.get day)
        |> Maybe.map (.transactions >> Array.toList)
        |> Maybe.withDefault []


transactionIdToString : V26.TransactionId -> String
transactionIdToString transactionId =
    String.fromInt transactionId.year
        ++ "-"
        ++ String.fromInt transactionId.month
        ++ "-"
        ++ String.fromInt transactionId.day
        ++ "-"
        ++ String.fromInt transactionId.index
