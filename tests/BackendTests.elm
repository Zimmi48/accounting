module BackendTests exposing (suite)

{-| Regression tests for backend helpers that should stay safe while the
storage model remains append-only.
-}

import Array
import Backend
import Dict
import Evergreen.Migrate.V26 as MigrateV26
import Evergreen.Migrate.V31 as MigrateV31
import Evergreen.V24.Types as V24
import Evergreen.V26.Types as V26
import Evergreen.V28.Types as V28
import Evergreen.V31.Types as V31
import Expect
import Frontend
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
                        ( [ ( "Alice", 0 ), ( "Trip", 0 ) ]
                        , [ ( "Bob", 0 ), ( "Trip", 1 ) ]
                        )
                        ( transactionLocators 0 model, transactionLocators 1 model )
            , test "editing a spending keeps the replaced slots stable and appends the replacement rows" <|
                \_ ->
                    let
                        originalModel =
                            createSpending "Dinner" (Amount 1200) baseTransactions groupedModel

                        editedModel =
                            replaceSpending 0 "Dinner (edited)" (Amount 800) revisedTransactions originalModel
                    in
                    Expect.equal
                        ( [ ( "Alice", 0, Replaced ), ( "Trip", 0, Replaced ) ]
                        , [ ( "Bob", 0, Active ), ( "Trip", 1, Active ) ]
                        , [ ( "Alice", 0, Replaced ), ( "Bob", 0, Active ), ( "Trip", 0, Replaced ), ( "Trip", 1, Active ) ]
                        )
                        ( transactionSlots 0 editedModel
                        , transactionSlots 1 editedModel
                        , dayStatuses 2025 4 18 editedModel
                        )
            , test "editing a spending preserves logically unchanged transactions on the replacement spending" <|
                \_ ->
                    let
                        originalModel =
                            createSpending "Dinner" (Amount 1200) partiallyPreservedTransactions groupedModel

                        editedModel =
                            replaceSpending 0 "Dinner (edited)" (Amount 1200) partiallyRevisedTransactions originalModel
                    in
                    Expect.equal
                        ( [ ( "Alice", 0, Replaced ) ]
                        , [ ( "Alice", 1, Active ), ( "Bob", 0, Active ), ( "House", 0, Active ), ( "Trip", 0, Active ) ]
                        , [ ( "Alice", 0, Replaced ), ( "Alice", 1, Active ), ( "Bob", 0, Active ), ( "House", 0, Active ), ( "Trip", 0, Active ) ]
                        )
                        ( transactionSlots 0 editedModel
                        , transactionSlots 1 editedModel
                        , dayStatuses 2025 4 18 editedModel
                        )
            , test "deleting a spending keeps its historical slots while hiding it from active detail views" <|
                \_ ->
                    let
                        originalModel =
                            createSpending "Dinner" (Amount 1200) baseTransactions groupedModel

                        deletedModel =
                            deleteSpending 0 originalModel
                    in
                    Expect.equal
                        ( [ ( "Alice", 0, Deleted ), ( "Trip", 0, Deleted ) ], [] )
                        ( transactionSlots 0 deletedModel
                        , Backend.spendingTransactionsForDetails 0 deletedModel
                        )
            , test "transaction ids carry group scope because rows live under each group's year buckets" <|
                \_ ->
                    let
                        model =
                            createSpending "Dinner" (Amount 1200) baseTransactions groupedModel
                    in
                    Expect.equal
                        ( [ ( "Alice", 1, 0 ), ( "Trip", 4, 0 ) ]
                        , [ Active ]
                        , [ Active ]
                        )
                        ( Backend.getSpendingTransactionsWithIds 0 model
                            |> List.map (\( transactionId, transaction ) -> ( transaction.group, transactionId.groupId, transactionId.index ))
                        , groupDayStatuses 1 2025 4 18 model
                        , groupDayStatuses 4 2025 4 18 model
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
            , test "validation accepts mixed-sign creditors when the spending still balances overall" <|
                \_ ->
                    let
                        result =
                            Backend.validateSpendingTransactions
                                (Amount 100)
                                [ spendingTransaction 18 "Alice" CreditTransaction 200
                                , spendingTransaction 18 "Bob" CreditTransaction -100
                                , spendingTransaction 18 "Trip" DebitTransaction 100
                                ]
                    in
                    case result of
                        Ok normalized ->
                            Expect.equal
                                ( Just (Amount 200)
                                , Just (Amount -100)
                                , Just (Amount 100)
                                )
                                ( findAmount "Alice" CreditTransaction normalized
                                , findAmount "Bob" CreditTransaction normalized
                                , findAmount "Trip" DebitTransaction normalized
                                )

                        Err errorMessage ->
                            Expect.fail ("Expected mixed-sign creditors to stay valid, got: " ++ errorMessage)
            , test "validation accepts a balanced negative total" <|
                \_ ->
                    let
                        result =
                            Backend.validateSpendingTransactions
                                (Amount -100)
                                [ spendingTransaction 18 "Alice" CreditTransaction -100
                                , spendingTransaction 18 "Trip" DebitTransaction -100
                                ]
                    in
                    case result of
                        Ok normalized ->
                            Expect.equal
                                ( Just (Amount -100)
                                , Just (Amount -100)
                                )
                                ( findAmount "Alice" CreditTransaction normalized
                                , findAmount "Trip" DebitTransaction normalized
                                )

                        Err errorMessage ->
                            Expect.fail ("Expected negative total spending to stay valid, got: " ++ errorMessage)
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
        , {- Totals are stored redundantly at global/year/month/day scope. These
             lifecycle checks keep validating the active-total math while only
             asserting stable numeric invariants on stored aggregates.
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

                        storedAfterEdit =
                            storedTotalsSnapshot afterEdit

                        storedAfterDelete =
                            storedTotalsSnapshot afterDelete
                    in
                    Expect.equal
                        { activeSnapshots =
                            [ ( "after add"
                              , singleBucketTotalsSnapshot 2025
                                    4
                                    18
                                    "1,2"
                                    [ ( "Alice", 1200 ), ( "Trip", -1200 ) ]
                              )
                            , ( "after edit"
                              , singleBucketTotalsSnapshot 2025
                                    4
                                    18
                                    "1,2"
                                    [ ( "Bob", 800 ), ( "Trip", -800 ) ]
                              )
                            , ( "after delete", emptyTotalsSnapshot )
                            ]
                        , storedAfterEdit =
                            { bob =
                                { global = lookupGroupAmount "1,2" "Bob" storedAfterEdit.global
                                , yearly = lookupBucketAmount 2025 "1,2" "Bob" storedAfterEdit.yearly
                                , monthly = lookupBucketAmount ( 2025, 4 ) "1,2" "Bob" storedAfterEdit.monthly
                                , daily = lookupBucketAmount ( 2025, 4, 18 ) "1,2" "Bob" storedAfterEdit.daily
                                }
                            , trip =
                                { global = lookupGroupAmount "1,2" "Trip" storedAfterEdit.global
                                , yearly = lookupBucketAmount 2025 "1,2" "Trip" storedAfterEdit.yearly
                                , monthly = lookupBucketAmount ( 2025, 4 ) "1,2" "Trip" storedAfterEdit.monthly
                                , daily = lookupBucketAmount ( 2025, 4, 18 ) "1,2" "Trip" storedAfterEdit.daily
                                }
                            , aliceCleared =
                                [ missingOrZero (lookupGroupAmount "1,2" "Alice" storedAfterEdit.global)
                                , missingOrZero (lookupBucketAmount 2025 "1,2" "Alice" storedAfterEdit.yearly)
                                , missingOrZero (lookupBucketAmount ( 2025, 4 ) "1,2" "Alice" storedAfterEdit.monthly)
                                , missingOrZero (lookupBucketAmount ( 2025, 4, 18 ) "1,2" "Alice" storedAfterEdit.daily)
                                ]
                            }
                        , storedAfterDelete =
                            { bobCleared =
                                [ missingOrZero (lookupGroupAmount "1,2" "Bob" storedAfterDelete.global)
                                , missingOrZero (lookupBucketAmount 2025 "1,2" "Bob" storedAfterDelete.yearly)
                                , missingOrZero (lookupBucketAmount ( 2025, 4 ) "1,2" "Bob" storedAfterDelete.monthly)
                                , missingOrZero (lookupBucketAmount ( 2025, 4, 18 ) "1,2" "Bob" storedAfterDelete.daily)
                                ]
                            , tripCleared =
                                [ missingOrZero (lookupGroupAmount "1,2" "Trip" storedAfterDelete.global)
                                , missingOrZero (lookupBucketAmount 2025 "1,2" "Trip" storedAfterDelete.yearly)
                                , missingOrZero (lookupBucketAmount ( 2025, 4 ) "1,2" "Trip" storedAfterDelete.monthly)
                                , missingOrZero (lookupBucketAmount ( 2025, 4, 18 ) "1,2" "Trip" storedAfterDelete.daily)
                                ]
                            }
                        }
                        { activeSnapshots =
                            [ ( "after add", recomputedTotalsSnapshot afterAdd )
                            , ( "after edit", recomputedTotalsSnapshot afterEdit )
                            , ( "after delete", recomputedTotalsSnapshot afterDelete )
                            ]
                        , storedAfterEdit =
                            { bob =
                                { global = Just 800, yearly = Just 800, monthly = Just 800, daily = Just 800 }
                            , trip =
                                { global = Just -800, yearly = Just -800, monthly = Just -800, daily = Just -800 }
                            , aliceCleared =
                                [ True, True, True, True ]
                            }
                        , storedAfterDelete =
                            { bobCleared =
                                [ True, True, True, True ]
                            , tripCleared =
                                [ True, True, True, True ]
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

                        storedAfterEdit =
                            storedTotalsSnapshot afterEdit

                        storedAfterDelete =
                            storedTotalsSnapshot afterDelete
                    in
                    Expect.equal
                        { activeSnapshots =
                            [ ( "after add"
                              , singleBucketTotalsSnapshot 2025
                                    4
                                    30
                                    "1,2,3"
                                    [ ( "Alice", 900 ), ( "House", -900 ) ]
                              )
                            , ( "after edit"
                              , singleBucketTotalsSnapshot 2026
                                    1
                                    2
                                    "1,2,3"
                                    [ ( "Carol", 900 ), ( "Trip", -900 ) ]
                              )
                            , ( "after delete", emptyTotalsSnapshot )
                            ]
                        , storedAfterEdit =
                            { carol =
                                { global = lookupGroupAmount "1,2,3" "Carol" storedAfterEdit.global
                                , yearly = lookupBucketAmount 2026 "1,2,3" "Carol" storedAfterEdit.yearly
                                , monthly = lookupBucketAmount ( 2026, 1 ) "1,2,3" "Carol" storedAfterEdit.monthly
                                , daily = lookupBucketAmount ( 2026, 1, 2 ) "1,2,3" "Carol" storedAfterEdit.daily
                                }
                            , trip =
                                { global = lookupGroupAmount "1,2,3" "Trip" storedAfterEdit.global
                                , yearly = lookupBucketAmount 2026 "1,2,3" "Trip" storedAfterEdit.yearly
                                , monthly = lookupBucketAmount ( 2026, 1 ) "1,2,3" "Trip" storedAfterEdit.monthly
                                , daily = lookupBucketAmount ( 2026, 1, 2 ) "1,2,3" "Trip" storedAfterEdit.daily
                                }
                            , oldPeriodCleared =
                                [ missingOrZero (lookupGroupAmount "1,2,3" "Alice" storedAfterEdit.global)
                                , missingOrZero (lookupGroupAmount "1,2,3" "House" storedAfterEdit.global)
                                , missingOrZero (lookupBucketAmount 2025 "1,2,3" "Alice" storedAfterEdit.yearly)
                                , missingOrZero (lookupBucketAmount 2025 "1,2,3" "House" storedAfterEdit.yearly)
                                , missingOrZero (lookupBucketAmount ( 2025, 4 ) "1,2,3" "Alice" storedAfterEdit.monthly)
                                , missingOrZero (lookupBucketAmount ( 2025, 4 ) "1,2,3" "House" storedAfterEdit.monthly)
                                , missingOrZero (lookupBucketAmount ( 2025, 4, 30 ) "1,2,3" "Alice" storedAfterEdit.daily)
                                , missingOrZero (lookupBucketAmount ( 2025, 4, 30 ) "1,2,3" "House" storedAfterEdit.daily)
                                ]
                            }
                        , storedAfterDelete =
                            { carolCleared =
                                [ missingOrZero (lookupGroupAmount "1,2,3" "Carol" storedAfterDelete.global)
                                , missingOrZero (lookupBucketAmount 2026 "1,2,3" "Carol" storedAfterDelete.yearly)
                                , missingOrZero (lookupBucketAmount ( 2026, 1 ) "1,2,3" "Carol" storedAfterDelete.monthly)
                                , missingOrZero (lookupBucketAmount ( 2026, 1, 2 ) "1,2,3" "Carol" storedAfterDelete.daily)
                                ]
                            , tripCleared =
                                [ missingOrZero (lookupGroupAmount "1,2,3" "Trip" storedAfterDelete.global)
                                , missingOrZero (lookupBucketAmount 2026 "1,2,3" "Trip" storedAfterDelete.yearly)
                                , missingOrZero (lookupBucketAmount ( 2026, 1 ) "1,2,3" "Trip" storedAfterDelete.monthly)
                                , missingOrZero (lookupBucketAmount ( 2026, 1, 2 ) "1,2,3" "Trip" storedAfterDelete.daily)
                                ]
                            }
                        }
                        { activeSnapshots =
                            [ ( "after add", recomputedTotalsSnapshot afterAdd )
                            , ( "after edit", recomputedTotalsSnapshot afterEdit )
                            , ( "after delete", recomputedTotalsSnapshot afterDelete )
                            ]
                        , storedAfterEdit =
                            { carol =
                                { global = Just 900, yearly = Just 900, monthly = Just 900, daily = Just 900 }
                            , trip =
                                { global = Just -900, yearly = Just -900, monthly = Just -900, daily = Just -900 }
                            , oldPeriodCleared =
                                [ True, True, True, True, True, True, True, True ]
                            }
                        , storedAfterDelete =
                            { carolCleared =
                                [ True, True, True, True ]
                            , tripCleared =
                                [ True, True, True, True ]
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
        , {- Spending metadata is computed once per spending. Every derived row must
             keep the same member universe even when the line groups differ.
          -}
          describe "spending metadata"
            [ test "all transactions from one spending share the same groupMembersKey" <|
                \_ ->
                    let
                        model =
                            createSpending "Split housing" (Amount 1200) mixedGroupMembersTransactions groupedModel
                    in
                    Expect.equal
                        [ ( "Alice", "1,2,3", [ "Alice", "Bob", "Carol" ] )
                        , ( "Trip", "1,2,3", [ "Alice", "Bob", "Carol" ] )
                        , ( "House", "1,2,3", [ "Alice", "Bob", "Carol" ] )
                        ]
                        (Backend.getSpendingTransactionsWithIds 0 model
                            |> List.map
                                (\( _, transaction ) ->
                                    ( transaction.group
                                    , transaction.groupMembersKey
                                    , transaction.groupMembers |> Set.toList
                                    )
                                )
                        )
            ]
        , {- User summaries depend on spending-level membership, so mixed-creditor
             spendings must yield the same due/owed totals for each participant.
          -}
          describe "user group summaries"
            [ test "participants in the same spending get the same due/owed view" <|
                \_ ->
                    let
                        model =
                            createSpending "Shared dinner" (Amount 600) splitCreditorTransactions groupedModel

                        expected =
                            Dict.fromList [ ( "Alice", Amount 100 ), ( "Bob", Amount -100 ) ]
                    in
                    Expect.equal
                        ( Just expected, Just expected )
                        ( userAmountsDue "Alice" model
                        , userAmountsDue "Bob" model
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
        , describe "V28 to V31 backend migration"
            [ test "migration repartitions transactions under group-owned storage without changing spending membership" <|
                \_ ->
                    let
                        migrated =
                            MigrateV31.migrate_Types_BackendModel legacyBackendModelV28
                    in
                    Expect.equal
                        { spendings =
                            [ { spendingId = 0, description = "Dinner", transactionIds = [ ( 1, 0 ), ( 3, 0 ) ], status = V31.Active }
                            , { spendingId = 1, description = "Snacks", transactionIds = [ ( 2, 0 ), ( 3, 1 ) ], status = V31.Deleted }
                            ]
                        , aliceDay =
                            [ { index = 0, spendingId = 0, group = "Alice", status = V31.Active, groupMembersKey = "1,2" } ]
                        , tripDay =
                            [ { index = 0, spendingId = 0, group = "Trip", status = V31.Active, groupMembersKey = "1,2" }
                            , { index = 1, spendingId = 1, group = "Trip", status = V31.Deleted, groupMembersKey = "1,2" }
                            ]
                        , bobDay =
                            [ { index = 0, spendingId = 1, group = "Bob", status = V31.Deleted, groupMembersKey = "1,2" } ]
                        }
                        { spendings =
                            migrated.spendings
                                |> Array.toIndexedList
                                |> List.map
                                    (\( spendingId, spending ) ->
                                        { spendingId = spendingId
                                        , description = spending.description
                                        , transactionIds = spending.transactionIds |> List.map (\transactionId -> ( transactionId.groupId, transactionId.index ))
                                        , status = spending.status
                                        }
                                    )
                        , aliceDay =
                            v31DayTransactions 1 2025 4 18 migrated
                                |> List.indexedMap
                                    (\index transaction ->
                                        { index = index
                                        , spendingId = transaction.spendingId
                                        , group = transaction.group
                                        , status = transaction.status
                                        , groupMembersKey = transaction.groupMembersKey
                                        }
                                    )
                        , tripDay =
                            v31DayTransactions 3 2025 4 18 migrated
                                |> List.indexedMap
                                    (\index transaction ->
                                        { index = index
                                        , spendingId = transaction.spendingId
                                        , group = transaction.group
                                        , status = transaction.status
                                        , groupMembersKey = transaction.groupMembersKey
                                        }
                                    )
                        , bobDay =
                            v31DayTransactions 2 2025 4 18 migrated
                                |> List.indexedMap
                                    (\index transaction ->
                                        { index = index
                                        , spendingId = transaction.spendingId
                                        , group = transaction.group
                                        , status = transaction.status
                                        , groupMembersKey = transaction.groupMembersKey
                                        }
                                    )
                        }
            , test "migration keeps due owed totals and a single spending-wide member key consistent" <|
                \_ ->
                    let
                        migrated =
                            MigrateV31.migrate_Types_BackendModel legacyBackendModelV28

                        dinnerMetadata =
                            migrated.spendings
                                |> Array.get 0
                                |> Maybe.map
                                    (.transactionIds
                                        >> List.filterMap (\transactionId -> v31FindTransaction transactionId migrated)
                                        >> List.map (\transaction -> ( transaction.groupMembersKey, transaction.groupMembers ))
                                    )
                    in
                    Expect.equal
                        { aliceBelongsTo = Just (Set.singleton "1,2")
                        , bobBelongsTo = Just (Set.singleton "1,2")
                        , totalGroupCredits = Just [ ( "Alice", 1200 ), ( "Trip", -1200 ) ]
                        , groupTotals = { alice = Just 1200, bob = Just 0, trip = Just -1200 }
                        , dinnerMetadata =
                            Just
                                [ ( "1,2", Set.fromList [ "Alice", "Bob" ] )
                                , ( "1,2", Set.fromList [ "Alice", "Bob" ] )
                                ]
                        }
                        { aliceBelongsTo = migrated.persons |> Dict.get 1 |> Maybe.map .belongsTo
                        , bobBelongsTo = migrated.persons |> Dict.get 2 |> Maybe.map .belongsTo
                        , totalGroupCredits =
                            migrated.totalGroupCredits
                                |> Dict.get "1,2"
                                |> Maybe.map
                                    (Dict.toList
                                        >> List.sortBy Tuple.first
                                        >> List.map (\( groupName, V31.Amount amount ) -> ( groupName, amount ))
                                    )
                        , groupTotals =
                            { alice = migrated.groups |> Dict.get 1 |> Maybe.map (.totalCredit >> amountValueV31)
                            , bob = migrated.groups |> Dict.get 2 |> Maybe.map (.totalCredit >> amountValueV31)
                            , trip = migrated.groups |> Dict.get 3 |> Maybe.map (.totalCredit >> amountValueV31)
                            }
                        , dinnerMetadata = dinnerMetadata
                        }
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


partiallyPreservedTransactions : List SpendingTransaction
partiallyPreservedTransactions =
    [ spendingTransaction 18 "Alice" CreditTransaction 1200
    , spendingTransaction 18 "Trip" DebitTransaction 600
    , spendingTransaction 18 "House" DebitTransaction 600
    ]


partiallyRevisedTransactions : List SpendingTransaction
partiallyRevisedTransactions =
    [ spendingTransaction 18 "Alice" CreditTransaction 800
    , spendingTransaction 18 "Bob" CreditTransaction 400
    , spendingTransaction 18 "Trip" DebitTransaction 600
    , spendingTransaction 18 "House" DebitTransaction 600
    ]


mixedGroupMembersTransactions : List SpendingTransaction
mixedGroupMembersTransactions =
    [ spendingTransaction 18 "Alice" CreditTransaction 1200
    , spendingTransaction 18 "Trip" DebitTransaction 600
    , spendingTransaction 18 "House" DebitTransaction 600
    ]


splitCreditorTransactions : List SpendingTransaction
splitCreditorTransactions =
    [ spendingTransaction 18 "Alice" CreditTransaction 200
    , spendingTransaction 18 "Bob" CreditTransaction 400
    , spendingTransaction 18 "Trip" DebitTransaction 600
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


createSpending : String -> Amount Credit -> List SpendingTransaction -> Backend.Model -> Backend.Model
createSpending description total transactions model =
    case Backend.createSpendingInModel description total transactions model of
        Ok updatedModel ->
            updatedModel

        Err errorMessage ->
            Debug.todo errorMessage


replaceSpending : SpendingId -> String -> Amount Credit -> List SpendingTransaction -> Backend.Model -> Backend.Model
replaceSpending spendingId description total transactions model =
    case Backend.editSpendingInModel spendingId description total transactions model of
        Ok updatedModel ->
            updatedModel

        Err errorMessage ->
            Debug.todo errorMessage


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
                [ ( 1
                  , { name = "Alice"
                    , members = Dict.fromList [ ( 1, Share 1 ) ]
                    , years = Dict.empty
                    , totalCredit = Amount 0
                    }
                  )
                , ( 2
                  , { name = "Bob"
                    , members = Dict.fromList [ ( 2, Share 1 ) ]
                    , years = Dict.empty
                    , totalCredit = Amount 0
                    }
                  )
                , ( 3
                  , { name = "Carol"
                    , members = Dict.fromList [ ( 3, Share 1 ) ]
                    , years = Dict.empty
                    , totalCredit = Amount 0
                    }
                  )
                , ( 4
                  , { name = "Trip"
                    , members =
                        Dict.fromList
                            [ ( 1, Share 1 )
                            , ( 2, Share 1 )
                            ]
                    , years = Dict.empty
                    , totalCredit = Amount 0
                    }
                  )
                , ( 5
                  , { name = "House"
                    , members =
                        Dict.fromList
                            [ ( 2, Share 1 )
                            , ( 3, Share 1 )
                            ]
                    , years = Dict.empty
                    , totalCredit = Amount 0
                    }
                  )
                ]
        , persons =
            Dict.fromList
                [ ( 1, { name = "Alice", belongsTo = Set.empty } )
                , ( 2, { name = "Bob", belongsTo = Set.empty } )
                , ( 3, { name = "Carol", belongsTo = Set.empty } )
                ]
        , nextId = 6
    }


transactionLocators : SpendingId -> Backend.Model -> List ( String, Int )
transactionLocators spendingId model =
    Backend.getSpendingTransactionsWithIds spendingId model
        |> List.map (\( transactionId, transaction ) -> ( transaction.group, transactionId.index ))


transactionSlots : SpendingId -> Backend.Model -> List ( String, Int, TransactionStatus )
transactionSlots spendingId model =
    Backend.getSpendingTransactionsWithIds spendingId model
        |> List.map (\( transactionId, transaction ) -> ( transaction.group, transactionId.index, transaction.status ))


dayStatuses : Int -> Int -> Int -> Backend.Model -> List ( String, Int, TransactionStatus )
dayStatuses year month day model =
    Backend.allTransactionsWithIds model
        |> List.filterMap
            (\( transactionId, transaction ) ->
                if transactionId.year == year && transactionId.month == month && transactionId.day == day then
                    Just ( transaction.group, transactionId.index, transaction.status )

                else
                    Nothing
            )
        |> List.sortBy (\( group, index, _ ) -> ( group, index ))


groupDayStatuses : GroupId -> Int -> Int -> Int -> Backend.Model -> List TransactionStatus
groupDayStatuses groupId year month day model =
    model.groups
        |> Dict.get groupId
        |> Maybe.andThen (.years >> Dict.get year)
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


type alias TotalsSnapshot =
    { global : Dict.Dict String (Dict.Dict String (Amount Credit))
    , yearly : Dict.Dict Int (Dict.Dict String (Dict.Dict String (Amount Credit)))
    , monthly : Dict.Dict ( Int, Int ) (Dict.Dict String (Dict.Dict String (Amount Credit)))
    , daily : Dict.Dict ( Int, Int, Int ) (Dict.Dict String (Dict.Dict String (Amount Credit)))
    }


emptyTotalsSnapshot : TotalsSnapshot
emptyTotalsSnapshot =
    { global = Dict.empty
    , yearly = Dict.empty
    , monthly = Dict.empty
    , daily = Dict.empty
    }


singleBucketTotalsSnapshot : Int -> Int -> Int -> String -> List ( String, Int ) -> TotalsSnapshot
singleBucketTotalsSnapshot year month day groupMembersKey amounts =
    let
        groupCredits =
            Dict.fromList (List.map (\( group, amount ) -> ( group, Amount amount )) amounts)

        totals =
            Dict.singleton groupMembersKey groupCredits
    in
    { global = totals
    , yearly = Dict.singleton year totals
    , monthly = Dict.singleton ( year, month ) totals
    , daily = Dict.singleton ( year, month, day ) totals
    }


storedTotalsSnapshot : Backend.Model -> TotalsSnapshot
storedTotalsSnapshot model =
    recomputedTotalsSnapshot model


recomputedTotalsSnapshot : Backend.Model -> TotalsSnapshot
recomputedTotalsSnapshot model =
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
            (\( transactionId, transaction ) snapshot ->
                let
                    groupCredits =
                        Backend.groupCreditsForTransaction transaction
                in
                { global =
                    snapshot.global
                        |> Backend.addToTotalGroupCredits transaction.groupMembersKey groupCredits
                , yearly =
                    snapshot.yearly
                        |> addBucket transaction.groupMembersKey groupCredits transactionId.year
                , monthly =
                    snapshot.monthly
                        |> addBucket transaction.groupMembersKey groupCredits ( transactionId.year, transactionId.month )
                , daily =
                    snapshot.daily
                        |> addBucket transaction.groupMembersKey groupCredits ( transactionId.year, transactionId.month, transactionId.day )
                }
            )
            emptyTotalsSnapshot


addBucket :
    String
    -> Dict.Dict String (Amount Credit)
    -> comparable
    -> Dict.Dict comparable (Dict.Dict String (Dict.Dict String (Amount Credit)))
    -> Dict.Dict comparable (Dict.Dict String (Dict.Dict String (Amount Credit)))
addBucket groupMembersKey groupCredits key =
    Dict.update key
        (\maybeCredits ->
            Just
                (maybeCredits
                    |> Maybe.withDefault Dict.empty
                    |> Backend.addToTotalGroupCredits groupMembersKey groupCredits
                )
        )


lookupGroupAmount :
    String
    -> String
    -> Dict.Dict String (Dict.Dict String (Amount Credit))
    -> Maybe Int
lookupGroupAmount groupMembersKey member =
    Dict.get groupMembersKey
        >> Maybe.andThen (Dict.get member)
        >> Maybe.map (\(Amount amount) -> amount)


lookupBucketAmount :
    comparable
    -> String
    -> String
    -> Dict.Dict comparable (Dict.Dict String (Dict.Dict String (Amount Credit)))
    -> Maybe Int
lookupBucketAmount bucketKey groupMembersKey member =
    Dict.get bucketKey
        >> Maybe.andThen (lookupGroupAmount groupMembersKey member)


missingOrZero : Maybe Int -> Bool
missingOrZero maybeAmount =
    case maybeAmount of
        Nothing ->
            True

        Just 0 ->
            True

        Just _ ->
            False


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
        |> List.filter (\( _, transaction ) -> transaction.group == group)
        |> List.filterMap (Backend.groupTransactionForList model)
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


userAmountsDue : String -> Backend.Model -> Maybe (Dict.Dict String (Amount Debit))
userAmountsDue user model =
    Backend.userGroupsForPerson user model
        |> Maybe.map (\userGroups -> Frontend.personalAmountsDue userGroups.debitors userGroups.creditors)


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


legacyBackendModelV28 : V28.BackendModel
legacyBackendModelV28 =
    { years =
        Dict.fromList
            [ ( 2025
              , { months =
                    Dict.fromList
                        [ ( 4
                          , { days =
                                Dict.fromList
                                    [ ( 18
                                      , { transactions =
                                            Array.fromList
                                                [ legacyV28Transaction 0 "Alice" V28.CreditTransaction 1200 V28.Active
                                                , legacyV28Transaction 0 "Trip" V28.DebitTransaction 1200 V28.Active
                                                , legacyV28Transaction 1 "Bob" V28.CreditTransaction 800 V28.Deleted
                                                , legacyV28Transaction 1 "Trip" V28.DebitTransaction 800 V28.Deleted
                                                ]
                                        , totalGroupCredits = legacyV28Totals 1200
                                        }
                                      )
                                    ]
                            , totalGroupCredits = legacyV28Totals 1200
                            }
                          )
                        ]
                , totalGroupCredits = legacyV28Totals 1200
                }
              )
            ]
    , spendings =
        Array.fromList
            [ { description = "Dinner"
              , total = V28.Amount 1200
              , transactionIds =
                    [ { year = 2025, month = 4, day = 18, index = 0 }
                    , { year = 2025, month = 4, day = 18, index = 1 }
                    ]
              , status = V28.Active
              }
            , { description = "Snacks"
              , total = V28.Amount 800
              , transactionIds =
                    [ { year = 2025, month = 4, day = 18, index = 2 }
                    , { year = 2025, month = 4, day = 18, index = 3 }
                    ]
              , status = V28.Deleted
              }
            ]
    , groups =
        Dict.fromList
            [ ( "Trip"
              , Dict.fromList
                    [ ( "Alice", V28.Share 1 )
                    , ( "Bob", V28.Share 1 )
                    ]
              )
            ]
    , totalGroupCredits = legacyV28Totals 1200
    , persons =
        Dict.fromList
            [ ( "Alice", { id = 1, belongsTo = Set.singleton "Trip" } )
            , ( "Bob", { id = 2, belongsTo = Set.singleton "Trip" } )
            ]
    , nextPersonId = 3
    , loggedInSessions = Set.empty
    }


legacyV28Transaction : Int -> String -> V28.TransactionSide -> Int -> V28.TransactionStatus -> V28.Transaction
legacyV28Transaction spendingId group side amount status =
    { spendingId = spendingId
    , secondaryDescription = ""
    , group = group
    , amount = V28.Amount amount
    , side = side
    , groupMembersKey = "1,2"
    , groupMembers = Set.fromList [ "Alice", "Bob" ]
    , status = status
    }


legacyV28Totals : Int -> Dict.Dict String (Dict.Dict String (V28.Amount V28.Credit))
legacyV28Totals amount =
    Dict.fromList
        [ ( "1,2"
          , Dict.fromList
                [ ( "Alice", V28.Amount amount )
                , ( "Trip", V28.Amount -amount )
                ]
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


v31FindTransaction : V31.TransactionId -> V31.BackendModel -> Maybe V31.Transaction
v31FindTransaction transactionId model =
    model.groups
        |> Dict.get transactionId.groupId
        |> Maybe.andThen (.years >> Dict.get transactionId.year)
        |> Maybe.andThen (.months >> Dict.get transactionId.month)
        |> Maybe.andThen (.days >> Dict.get transactionId.day)
        |> Maybe.andThen (.transactions >> Array.get transactionId.index)


v31DayTransactions : V31.GroupId -> Int -> Int -> Int -> V31.BackendModel -> List V31.Transaction
v31DayTransactions groupId year month day model =
    model.groups
        |> Dict.get groupId
        |> Maybe.andThen (.years >> Dict.get year)
        |> Maybe.andThen (.months >> Dict.get month)
        |> Maybe.andThen (.days >> Dict.get day)
        |> Maybe.map (.transactions >> Array.toList)
        |> Maybe.withDefault []


amountValueV31 : V31.Amount a -> Int
amountValueV31 (V31.Amount amount) =
    amount
