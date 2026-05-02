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
                            groupedModel
                                |> createSpending "Breakfast" (Amount 1200) baseTransactions
                                |> createSpending "Lunch" (Amount 800) revisedTransactions
                    in
                    Expect.equal
                        ( [ "0-2025-4-18-0", "3-2025-4-18-0" ]
                        , [ "1-2025-4-18-0", "3-2025-4-18-1" ]
                        )
                        ( transactionIds 0 model, transactionIds 1 model )
            , test "editing a spending keeps the replaced slots stable and appends the replacement rows" <|
                \_ ->
                    let
                        originalModel =
                            createSpending "Dinner" (Amount 1200) baseTransactions groupedModel

                        editedModel =
                            replaceSpending 0 "Dinner (edited)" (Amount 800) revisedTransactions originalModel
                    in
                    Expect.equal
                        { original = [ ( "0-2025-4-18-0", Replaced ), ( "3-2025-4-18-0", Replaced ) ]
                        , replacement = [ ( "1-2025-4-18-0", Active ), ( "3-2025-4-18-1", Active ) ]
                        , aliceDay = [ Replaced ]
                        , bobDay = [ Active ]
                        , tripDay = [ Replaced, Active ]
                        }
                        { original = transactionSlots 0 editedModel
                        , replacement = transactionSlots 1 editedModel
                        , aliceDay = dayStatuses "Alice" 2025 4 18 editedModel
                        , bobDay = dayStatuses "Bob" 2025 4 18 editedModel
                        , tripDay = dayStatuses "Trip" 2025 4 18 editedModel
                        }
            , test "deleting a spending keeps its historical slots while hiding it from active detail views" <|
                \_ ->
                    let
                        originalModel =
                            createSpending "Dinner" (Amount 1200) baseTransactions groupedModel

                        deletedModel =
                            deleteSpending 0 originalModel
                    in
                    Expect.equal
                        ( [ ( "0-2025-4-18-0", Deleted ), ( "3-2025-4-18-0", Deleted ) ]
                        , [ Deleted ]
                        , []
                        )
                        ( transactionSlots 0 deletedModel
                        , dayStatuses "Trip" 2025 4 18 deletedModel
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
        , {- Totals now live inside each owning group. These checks keep the
             stored per-group aggregates aligned with the active transaction set.
          -}
          describe "spending lifecycle totals"
            [ test "same-day add/edit/delete keeps active totals exact and clears stale amounts numerically" <|
                \_ ->
                    let
                        afterAdd =
                            groupedModel
                                |> createSpending "Dinner" (Amount 1200) groupedBaseTransactions

                        afterEdit =
                            replaceSpending 0 "Dinner (edited)" (Amount 800) groupedRevisedTransactions afterAdd

                        afterDelete =
                            deleteSpending 1 afterEdit
                    in
                    Expect.equal
                        { activeSnapshots =
                            [ ( "after add"
                              , Dict.fromList
                                    [ ( "Alice", fullGroupTotalSummary 1200 )
                                    , ( "Trip", fullGroupTotalSummary -1200 )
                                    ]
                              )
                            , ( "after edit"
                              , Dict.fromList
                                    [ ( "Bob", fullGroupTotalSummary 800 )
                                    , ( "Trip", fullGroupTotalSummary -800 )
                                    ]
                              )
                            , ( "after delete", Dict.empty )
                            ]
                        , storedAfterEdit =
                            { bob = storedGroupTotalSummary "Bob" 2025 4 18 afterEdit
                            , trip = storedGroupTotalSummary "Trip" 2025 4 18 afterEdit
                            , aliceCleared = groupTotalCleared (storedGroupTotalSummary "Alice" 2025 4 18 afterEdit)
                            }
                        , storedAfterDelete =
                            { bobCleared = groupTotalCleared (storedGroupTotalSummary "Bob" 2025 4 18 afterDelete)
                            , tripCleared = groupTotalCleared (storedGroupTotalSummary "Trip" 2025 4 18 afterDelete)
                            }
                        }
                        { activeSnapshots =
                            [ ( "after add", recomputedGroupTotalsSummary 2025 4 18 [ "Alice", "Trip" ] afterAdd )
                            , ( "after edit", recomputedGroupTotalsSummary 2025 4 18 [ "Bob", "Trip" ] afterEdit )
                            , ( "after delete", recomputedGroupTotalsSummary 2025 4 18 [ "Bob", "Trip" ] afterDelete )
                            ]
                        , storedAfterEdit =
                            { bob = fullGroupTotalSummary 800
                            , trip = fullGroupTotalSummary -800
                            , aliceCleared = True
                            }
                        , storedAfterDelete =
                            { bobCleared = True
                            , tripCleared = True
                            }
                        }
            , test "cross-period edits and deletion move active totals without stale non-zero leftovers" <|
                \_ ->
                    let
                        afterAdd =
                            groupedModel
                                |> createSpending "Road trip" (Amount 900) crossPeriodTransactions

                        afterEdit =
                            replaceSpending 0 "Road trip (moved)" (Amount 900) crossPeriodRevisedTransactions afterAdd

                        afterDelete =
                            deleteSpending 1 afterEdit
                    in
                    Expect.equal
                        { activeSnapshots =
                            [ ( "after add"
                              , Dict.fromList
                                    [ ( "Alice", fullGroupTotalSummary 900 )
                                    , ( "House", fullGroupTotalSummary -900 )
                                    ]
                              )
                            , ( "after edit"
                              , Dict.fromList
                                    [ ( "Carol", fullGroupTotalSummary 900 )
                                    , ( "Trip", fullGroupTotalSummary -900 )
                                    ]
                              )
                            , ( "after delete", Dict.empty )
                            ]
                        , storedAfterEdit =
                            { carol = storedGroupTotalSummary "Carol" 2026 1 2 afterEdit
                            , trip = storedGroupTotalSummary "Trip" 2026 1 2 afterEdit
                            , oldPeriodCleared =
                                [ groupTotalCleared (storedGroupTotalSummary "Alice" 2025 4 30 afterEdit)
                                , groupTotalCleared (storedGroupTotalSummary "House" 2025 4 30 afterEdit)
                                ]
                            }
                        , storedAfterDelete =
                            { carolCleared = groupTotalCleared (storedGroupTotalSummary "Carol" 2026 1 2 afterDelete)
                            , tripCleared = groupTotalCleared (storedGroupTotalSummary "Trip" 2026 1 2 afterDelete)
                            }
                        }
                        { activeSnapshots =
                            [ ( "after add", recomputedGroupTotalsSummary 2025 4 30 [ "Alice", "House" ] afterAdd )
                            , ( "after edit", recomputedGroupTotalsSummary 2026 1 2 [ "Carol", "Trip" ] afterEdit )
                            , ( "after delete", recomputedGroupTotalsSummary 2026 1 2 [ "Carol", "Trip" ] afterDelete )
                            ]
                        , storedAfterEdit =
                            { carol = fullGroupTotalSummary 900
                            , trip = fullGroupTotalSummary -900
                            , oldPeriodCleared = [ True, True ]
                            }
                        , storedAfterDelete =
                            { carolCleared = True
                            , tripCleared = True
                            }
                        }
            , test "group listings and spending details only expose the current active replacement rows" <|
                \_ ->
                    let
                        afterAdd =
                            groupedModel
                                |> createSpending "Dinner" (Amount 1200) groupedBaseTransactions

                        afterEdit =
                            replaceSpending 0 "Dinner (edited)" (Amount 800) groupedRevisedTransactions afterAdd

                        afterDelete =
                            deleteSpending 1 afterEdit
                    in
                    Expect.equal
                        { aliceAfterAdd =
                            [ { description = "Dinner"
                              , year = 2025
                              , month = 4
                              , day = 18
                              , total = Amount 1200
                              , share = Amount -1200
                              }
                            ]
                        , tripAfterAdd =
                            [ { description = "Dinner"
                              , year = 2025
                              , month = 4
                              , day = 18
                              , total = Amount 1200
                              , share = Amount 1200
                              }
                            ]
                        , bobAfterEdit =
                            [ { description = "Dinner (edited)"
                              , year = 2025
                              , month = 4
                              , day = 18
                              , total = Amount 800
                              , share = Amount -800
                              }
                            ]
                        , tripAfterEdit =
                            [ { description = "Dinner (edited)"
                              , year = 2025
                              , month = 4
                              , day = 18
                              , total = Amount 800
                              , share = Amount 800
                              }
                            ]
                        , detailsAfterEdit = groupedRevisedTransactions
                        , tripAfterDelete = []
                        , detailsAfterDelete = []
                        }
                        { aliceAfterAdd = listedTransactions "Alice" afterAdd
                        , tripAfterAdd = listedTransactions "Trip" afterAdd
                        , bobAfterEdit = listedTransactions "Bob" afterEdit
                        , tripAfterEdit = listedTransactions "Trip" afterEdit
                        , detailsAfterEdit = Backend.spendingTransactionsForDetails 1 afterEdit
                        , tripAfterDelete = listedTransactions "Trip" afterDelete
                        , detailsAfterDelete = Backend.spendingTransactionsForDetails 1 afterDelete
                        }
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
                                        |> List.map v26TransactionIdToString
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


groupedBaseTransactions : List SpendingTransaction
groupedBaseTransactions =
    [ spendingTransaction 18 "Alice" CreditTransaction 1200
    , spendingTransaction 18 "Trip" DebitTransaction 1200
    ]


groupedRevisedTransactions : List SpendingTransaction
groupedRevisedTransactions =
    [ spendingTransaction 18 "Bob" CreditTransaction 800
    , spendingTransaction 18 "Trip" DebitTransaction 800
    ]


crossPeriodTransactions : List SpendingTransaction
crossPeriodTransactions =
    [ datedSpendingTransaction 2025 4 30 "Alice" CreditTransaction 900
    , datedSpendingTransaction 2025 4 30 "House" DebitTransaction 900
    ]


crossPeriodRevisedTransactions : List SpendingTransaction
crossPeriodRevisedTransactions =
    [ datedSpendingTransaction 2026 1 2 "Carol" CreditTransaction 900
    , datedSpendingTransaction 2026 1 2 "Trip" DebitTransaction 900
    ]


spendingTransaction : Int -> String -> TransactionSide -> Int -> SpendingTransaction
spendingTransaction day group side amount =
    datedSpendingTransaction 2025 4 day group side amount


datedSpendingTransaction : Int -> Int -> Int -> String -> TransactionSide -> Int -> SpendingTransaction
datedSpendingTransaction year month day group side amount =
    { year = year
    , month = month
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
    createSpending description total transactions cleanedModel


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


groupedModel : Backend.Model
groupedModel =
    { emptyModel
        | groups =
            Dict.fromList
                [ ( "Alice"
                  , storedGroup 0 [ ( "Alice", Share 1 ) ]
                  )
                , ( "Bob"
                  , storedGroup 1 [ ( "Bob", Share 1 ) ]
                  )
                , ( "Carol"
                  , storedGroup 2 [ ( "Carol", Share 1 ) ]
                  )
                , ( "Trip"
                  , storedGroup 3
                        [ ( "Alice", Share 1 )
                        , ( "Bob", Share 1 )
                        ]
                  )
                , ( "House"
                  , storedGroup 4
                        [ ( "Bob", Share 1 )
                        , ( "Carol", Share 1 )
                        ]
                  )
                ]
        , persons =
            Dict.fromList
                [ ( "Alice", { id = 0, belongsTo = Set.fromList [ 0, 3 ] } )
                , ( "Bob", { id = 1, belongsTo = Set.fromList [ 1, 3, 4 ] } )
                , ( "Carol", { id = 2, belongsTo = Set.fromList [ 2, 4 ] } )
                ]
        , nextId = 5
    }


storedGroup : GroupId -> List ( String, Share ) -> StoredGroup
storedGroup id members =
    { id = id
    , members = Dict.fromList members
    , years = Dict.empty
    , totalCredit = Amount 0
    }


createSpending : String -> Amount Credit -> List SpendingTransaction -> Backend.Model -> Backend.Model
createSpending description total transactions model =
    case Backend.createSpendingInModel description total transactions model of
        Ok updatedModel ->
            updatedModel

        Err errorMessage ->
            Debug.todo errorMessage


transactionIds : SpendingId -> Backend.Model -> List String
transactionIds spendingId model =
    Backend.getSpendingTransactionsWithIds spendingId model
        |> List.map (\( transactionId, _ ) -> currentTransactionIdToString transactionId)


transactionSlots : SpendingId -> Backend.Model -> List ( String, TransactionStatus )
transactionSlots spendingId model =
    Backend.getSpendingTransactionsWithIds spendingId model
        |> List.map (\( transactionId, transaction ) -> ( currentTransactionIdToString transactionId, transaction.status ))


dayStatuses : String -> Int -> Int -> Int -> Backend.Model -> List TransactionStatus
dayStatuses group year month day model =
    model.groups
        |> Dict.get group
        |> Maybe.map .years
        |> Maybe.andThen (Dict.get year)
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


type alias GroupTotalSummary =
    { total : Maybe Int
    , yearly : Maybe Int
    , monthly : Maybe Int
    , daily : Maybe Int
    }


fullGroupTotalSummary : Int -> GroupTotalSummary
fullGroupTotalSummary amount =
    { total = Just amount
    , yearly = Just amount
    , monthly = Just amount
    , daily = Just amount
    }


storedGroupTotalSummary : String -> Int -> Int -> Int -> Backend.Model -> GroupTotalSummary
storedGroupTotalSummary groupName year month day model =
    { total =
        model.groups
            |> Dict.get groupName
            |> Maybe.map (.totalCredit >> amountValue)
    , yearly =
        model.groups
            |> Dict.get groupName
            |> Maybe.andThen (.years >> Dict.get year)
            |> Maybe.map (.totalCredit >> amountValue)
    , monthly =
        model.groups
            |> Dict.get groupName
            |> Maybe.andThen (.years >> Dict.get year)
            |> Maybe.andThen (.months >> Dict.get month)
            |> Maybe.map (.totalCredit >> amountValue)
    , daily =
        model.groups
            |> Dict.get groupName
            |> Maybe.andThen (.years >> Dict.get year)
            |> Maybe.andThen (.months >> Dict.get month)
            |> Maybe.andThen (.days >> Dict.get day)
            |> Maybe.map (.totalCredit >> amountValue)
    }


recomputedGroupTotals : Backend.Model -> Dict.Dict String GroupTotalSummary
recomputedGroupTotals model =
    Backend.allTransactionsWithIds model
        |> List.filter
            (\( _, transaction ) ->
                transaction.status
                    == Active
                    && (Array.get transaction.spendingId model.spendings
                            |> Maybe.map (.status >> (==) Active)
                            |> Maybe.withDefault False
                       )
            )
        |> List.foldl
            (\( transactionId, transaction ) ->
                let
                    groupCredit =
                        Backend.groupCreditForTransaction transaction
                in
                Dict.update transaction.group
                    (\maybeSummary ->
                        let
                            updatedSummary =
                                maybeSummary
                                    |> Maybe.withDefault (fullGroupTotalSummary 0)
                                    |> addGroupCredit groupCredit
                        in
                        Just updatedSummary
                    )
            )
            Dict.empty


addGroupCredit : Amount Credit -> GroupTotalSummary -> GroupTotalSummary
addGroupCredit (Amount amount) summary =
    { total = summary.total |> Maybe.withDefault 0 |> (+) amount |> Just
    , yearly = summary.yearly |> Maybe.withDefault 0 |> (+) amount |> Just
    , monthly = summary.monthly |> Maybe.withDefault 0 |> (+) amount |> Just
    , daily = summary.daily |> Maybe.withDefault 0 |> (+) amount |> Just
    }


recomputedGroupTotalsSummary : Int -> Int -> Int -> List String -> Backend.Model -> Dict.Dict String GroupTotalSummary
recomputedGroupTotalsSummary year month day names model =
    let
        allSummaries =
            recomputedGroupTotals model
    in
    names
        |> List.filterMap
            (\name ->
                Dict.get name allSummaries
                    |> Maybe.andThen
                        (\summary ->
                            if summary.total == Just 0 then
                                Nothing

                            else
                                Just
                                    ( name
                                    , { total = summary.total
                                      , yearly = summary.yearly
                                      , monthly = summary.monthly
                                      , daily = summary.daily
                                      }
                                    )
                        )
            )
        |> Dict.fromList


groupTotalCleared : GroupTotalSummary -> Bool
groupTotalCleared summary =
    [ summary.total, summary.yearly, summary.monthly, summary.daily ]
        |> List.all
            (\maybeAmount ->
                case maybeAmount of
                    Nothing ->
                        True

                    Just 0 ->
                        True

                    Just _ ->
                        False
            )


amountValue : Amount a -> Int
amountValue (Amount amount) =
    amount


listedTransactions :
    String
    -> Backend.Model
    ->
        List
            { description : String
            , year : Int
            , month : Int
            , day : Int
            , total : Amount Debit
            , share : Amount Debit
            }
listedTransactions group model =
    Backend.allTransactionsWithIds model
        |> List.filterMap
            (\( transactionId, transaction ) ->
                if transaction.group == group then
                    Backend.groupTransactionForList model ( transactionId, transaction )

                else
                    Nothing
            )
        |> List.map
            (\transaction ->
                { description = transaction.description
                , year = transaction.year
                , month = transaction.month
                , day = transaction.day
                , total = transaction.total
                , share = transaction.share
                }
            )


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


currentTransactionIdToString : TransactionId -> String
currentTransactionIdToString transactionId =
    String.fromInt transactionId.groupId
        ++ "-"
        ++ String.fromInt transactionId.year
        ++ "-"
        ++ String.fromInt transactionId.month
        ++ "-"
        ++ String.fromInt transactionId.day
        ++ "-"
        ++ String.fromInt transactionId.index


v26TransactionIdToString : V26.TransactionId -> String
v26TransactionIdToString transactionId =
    String.fromInt transactionId.year
        ++ "-"
        ++ String.fromInt transactionId.month
        ++ "-"
        ++ String.fromInt transactionId.day
        ++ "-"
        ++ String.fromInt transactionId.index
