module MigrationTests exposing (suite)

{-| Evergreen migration tests focus on data integrity across the V24 -> V26
storage split and on the frontend's refusal to reuse stale transaction-addressed
state after IDs changed shape.
-}

import Array
import Date
import DatePicker
import Dict
import Evergreen.Migrate.V26 as MigrateV26
import Evergreen.V24.Types as V24
import Evergreen.V26.Types as V26
import Expect
import Set
import Test exposing (..)
import Time exposing (Month(..))


type alias SpendingSummary =
    { description : String
    , total : Int
    , status : V26.TransactionStatus
    , transactionIds : List V26.TransactionId
    }


type alias ReferencedTransactionSummary =
    { transactionId : V26.TransactionId
    , group : String
    , amount : Int
    , side : V26.TransactionSide
    , status : V26.TransactionStatus
    , groupMembersKey : String
    , groupMembers : List String
    }


type alias StoredTransactionSummary =
    { transactionId : V26.TransactionId
    , spendingId : Int
    , group : String
    , amount : Int
    , side : V26.TransactionSide
    , status : V26.TransactionStatus
    }


type alias MigrationTotalsSummary =
    { root : List ( String, List ( String, Int ) )
    , year2025 : Maybe (List ( String, List ( String, Int ) ))
    , april2025 : Maybe (List ( String, List ( String, Int ) ))
    , day18 : Maybe (List ( String, List ( String, Int ) ))
    , day19 : Maybe (List ( String, List ( String, Int ) ))
    }


type alias FrontendMessageSafetySummary =
    { showAddSpendingDialog : V26.FrontendMsg
    , showConfirmDeleteDialog : V26.FrontendMsg
    , confirmDeleteTransaction : V26.FrontendMsg
    , editTransaction : V26.ToBackend
    , deleteTransaction : V26.ToBackend
    , requestTransactionDetails : V26.ToBackend
    , listGroupTransactions : V26.ToFrontend
    , transactionDetails : V26.ToFrontend
    }


type alias CreateDialogSummary =
    { spendingId : Maybe V26.SpendingId
    , description : String
    , total : String
    , dateText : String
    , today : Maybe Date.Date
    , credits : List TransactionLineSummary
    , debits : List TransactionLineSummary
    , submitted : Bool
    }


type alias TransactionLineSummary =
    { group : String
    , amount : String
    , validity : V26.NameValidity
    , detailsExpanded : Bool
    }


suite : Test
suite =
    describe "Evergreen migration V24 -> V26"
        [ describe "backend model migration"
            [ test "migrateBackendModel preserves spendings, statuses, and per-day transaction slots" <|
                \_ ->
                    let
                        migrated =
                            MigrateV26.migrateBackendModel legacyBackendModel
                    in
                    Expect.equal
                        [ { description = "Breakfast"
                          , total = 1200
                          , status = V26.Active
                          , transactionIds = [ transactionId 2025 4 18 0, transactionId 2025 4 18 1 ]
                          }
                        , { description = "Utilities"
                          , total = 900
                          , status = V26.Deleted
                          , transactionIds = [ transactionId 2025 4 18 2, transactionId 2025 4 18 3 ]
                          }
                        , { description = "Road trip adjustment"
                          , total = 700
                          , status = V26.Replaced
                          , transactionIds = [ transactionId 2025 4 19 0, transactionId 2025 4 19 1, transactionId 2025 4 19 2 ]
                          }
                        ]
                        (migrated.spendings
                            |> Array.toList
                            |> List.map spendingSummary
                        )
            , test "migrateBackendModel keeps every migrated spending reference pointed at the right transactions" <|
                \_ ->
                    let
                        migrated =
                            MigrateV26.migrateBackendModel legacyBackendModel
                    in
                    Expect.equal
                        { storedTransactionIds = allStoredTransactionIds migrated
                        , spendings =
                            [ { spendingId = 0
                              , transactions =
                                    [ { transactionId = transactionId 2025 4 18 0
                                      , group = "Alice"
                                      , amount = 1200
                                      , side = V26.CreditTransaction
                                      , status = V26.Active
                                      , groupMembersKey = "0,1"
                                      , groupMembers = [ "Alice", "Bob" ]
                                      }
                                    , { transactionId = transactionId 2025 4 18 1
                                      , group = "Trip"
                                      , amount = 1200
                                      , side = V26.DebitTransaction
                                      , status = V26.Active
                                      , groupMembersKey = "0,1"
                                      , groupMembers = [ "Alice", "Bob" ]
                                      }
                                    ]
                              }
                            , { spendingId = 1
                              , transactions =
                                    [ { transactionId = transactionId 2025 4 18 2
                                      , group = "Bob"
                                      , amount = 900
                                      , side = V26.CreditTransaction
                                      , status = V26.Deleted
                                      , groupMembersKey = "1,2"
                                      , groupMembers = [ "Bob", "Cara" ]
                                      }
                                    , { transactionId = transactionId 2025 4 18 3
                                      , group = "Utilities"
                                      , amount = 900
                                      , side = V26.DebitTransaction
                                      , status = V26.Deleted
                                      , groupMembersKey = "1,2"
                                      , groupMembers = [ "Bob", "Cara" ]
                                      }
                                    ]
                              }
                            , { spendingId = 2
                              , transactions =
                                    [ { transactionId = transactionId 2025 4 19 0
                                      , group = "Bob"
                                      , amount = 300
                                      , side = V26.CreditTransaction
                                      , status = V26.Replaced
                                      , groupMembersKey = "0,1,2"
                                      , groupMembers = [ "Alice", "Bob", "Cara" ]
                                      }
                                    , { transactionId = transactionId 2025 4 19 1
                                      , group = "Cara"
                                      , amount = 400
                                      , side = V26.CreditTransaction
                                      , status = V26.Replaced
                                      , groupMembersKey = "0,1,2"
                                      , groupMembers = [ "Alice", "Bob", "Cara" ]
                                      }
                                    , { transactionId = transactionId 2025 4 19 2
                                      , group = "House"
                                      , amount = 700
                                      , side = V26.DebitTransaction
                                      , status = V26.Replaced
                                      , groupMembersKey = "0,1,2"
                                      , groupMembers = [ "Alice", "Bob", "Cara" ]
                                      }
                                    ]
                              }
                            ]
                        }
                        { storedTransactionIds = allReferencedTransactionIds migrated
                        , spendings =
                            migrated.spendings
                                |> Array.toList
                                |> List.indexedMap (referencedTransactionsForSpending migrated)
                        }
            , test "migrateBackendModel preserves migrated day storage and copied credit totals" <|
                \_ ->
                    let
                        migrated =
                            MigrateV26.migrateBackendModel legacyBackendModel
                    in
                    Expect.equal
                        { day18 =
                            [ { transactionId = transactionId 2025 4 18 0
                              , spendingId = 0
                              , group = "Alice"
                              , amount = 1200
                              , side = V26.CreditTransaction
                              , status = V26.Active
                              }
                            , { transactionId = transactionId 2025 4 18 1
                              , spendingId = 0
                              , group = "Trip"
                              , amount = 1200
                              , side = V26.DebitTransaction
                              , status = V26.Active
                              }
                            , { transactionId = transactionId 2025 4 18 2
                              , spendingId = 1
                              , group = "Bob"
                              , amount = 900
                              , side = V26.CreditTransaction
                              , status = V26.Deleted
                              }
                            , { transactionId = transactionId 2025 4 18 3
                              , spendingId = 1
                              , group = "Utilities"
                              , amount = 900
                              , side = V26.DebitTransaction
                              , status = V26.Deleted
                              }
                            ]
                        , day19 =
                            [ { transactionId = transactionId 2025 4 19 0
                              , spendingId = 2
                              , group = "Bob"
                              , amount = 300
                              , side = V26.CreditTransaction
                              , status = V26.Replaced
                              }
                            , { transactionId = transactionId 2025 4 19 1
                              , spendingId = 2
                              , group = "Cara"
                              , amount = 400
                              , side = V26.CreditTransaction
                              , status = V26.Replaced
                              }
                            , { transactionId = transactionId 2025 4 19 2
                              , spendingId = 2
                              , group = "House"
                              , amount = 700
                              , side = V26.DebitTransaction
                              , status = V26.Replaced
                              }
                            ]
                        , totals =
                            { root = [ ( "root", [ ( "Trip", 500 ) ] ) ]
                            , year2025 = Just [ ( "year", [ ( "Trip", 300 ) ] ) ]
                            , april2025 = Just [ ( "month", [ ( "House", -700 ), ( "Trip", 1200 ) ] ) ]
                            , day18 = Just [ ( "day-18", [ ( "Trip", 1200 ), ( "Utilities", -900 ) ] ) ]
                            , day19 = Just [ ( "day-19", [ ( "House", -700 ) ] ) ]
                            }
                        }
                        { day18 = dayTransactionSummary 2025 4 18 migrated
                        , day19 = dayTransactionSummary 2025 4 19 migrated
                        , totals = migrationTotalsSummary migrated
                        }
            ]
        , describe "frontend migration safety"
            [ test "migrateFrontendDialog drops edit dialogs whose stored transaction id can no longer be trusted" <|
                \_ ->
                    Expect.equal
                        Nothing
                        (MigrateV26.migrateFrontendDialog (Just legacyEditDialog))
            , test "frontend message migrations neutralize stale transaction-addressed actions and payloads" <|
                \_ ->
                    Expect.equal
                        { showAddSpendingDialog = V26.NoOpFrontendMsg
                        , showConfirmDeleteDialog = V26.NoOpFrontendMsg
                        , confirmDeleteTransaction = V26.NoOpFrontendMsg
                        , editTransaction = V26.NoOpToBackend
                        , deleteTransaction = V26.NoOpToBackend
                        , requestTransactionDetails = V26.NoOpToBackend
                        , listGroupTransactions = V26.ListGroupTransactions { group = "Trip", transactions = [] }
                        , transactionDetails = V26.SpendingError "Please reopen the spending editor after the update."
                        }
                        frontendMessageSafetySummary
            , test "migrateFrontendDialog keeps a create dialog but resets its new spending reference to Nothing" <|
                \_ ->
                    case MigrateV26.migrateFrontendDialog (Just legacyCreateDialog) of
                        Just (V26.AddSpendingDialog dialog) ->
                            Expect.equal
                                { spendingId = Nothing
                                , description = "Breakfast"
                                , total = "12.00"
                                , dateText = "2025-04-18"
                                , today = Nothing
                                , credits = [ { group = "Alice", amount = "12.00", validity = V26.Complete, detailsExpanded = False } ]
                                , debits = [ { group = "Trip", amount = "12.00", validity = V26.Complete, detailsExpanded = False } ]
                                , submitted = True
                                }
                                (createDialogSummary dialog)

                        _ ->
                            Expect.fail "Expected create dialog to survive migration"
            ]
        ]


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
                                    [ ( 18
                                      , { spendings =
                                            [ { description = "Breakfast"
                                              , total = V24.Amount 1200
                                              , credits = Dict.fromList [ ( "Alice", V24.Amount 1200 ) ]
                                              , debits = Dict.fromList [ ( "Trip", V24.Amount 1200 ) ]
                                              , status = V24.Active
                                              }
                                            , { description = "Utilities"
                                              , total = V24.Amount 900
                                              , credits = Dict.fromList [ ( "Bob", V24.Amount 900 ) ]
                                              , debits = Dict.fromList [ ( "Utilities", V24.Amount 900 ) ]
                                              , status = V24.Deleted
                                              }
                                            ]
                                        , totalGroupCredits =
                                            Dict.fromList
                                                [ ( "day-18"
                                                  , Dict.fromList
                                                        [ ( "Trip", V24.Amount 1200 )
                                                        , ( "Utilities", V24.Amount -900 )
                                                        ]
                                                  )
                                                ]
                                        }
                                      )
                                    , ( 19
                                      , { spendings =
                                            [ { description = "Road trip adjustment"
                                              , total = V24.Amount 700
                                              , credits =
                                                    Dict.fromList
                                                        [ ( "Bob", V24.Amount 300 )
                                                        , ( "Cara", V24.Amount 400 )
                                                        ]
                                              , debits = Dict.fromList [ ( "House", V24.Amount 700 ) ]
                                              , status = V24.Replaced
                                              }
                                            ]
                                        , totalGroupCredits =
                                            Dict.fromList
                                                [ ( "day-19"
                                                  , Dict.fromList [ ( "House", V24.Amount -700 ) ]
                                                  )
                                                ]
                                        }
                                      )
                                    ]
                            , totalGroupCredits =
                                Dict.fromList
                                    [ ( "month"
                                      , Dict.fromList
                                            [ ( "House", V24.Amount -700 )
                                            , ( "Trip", V24.Amount 1200 )
                                            ]
                                      )
                                    ]
                            }
                          )
                        ]
                , totalGroupCredits = Dict.fromList [ ( "year", Dict.fromList [ ( "Trip", V24.Amount 300 ) ] ) ]
                }
              )
            ]
    , groups =
        Dict.fromList
            [ ( "Trip", Dict.fromList [ ( "Alice", V24.Share 1 ), ( "Bob", V24.Share 1 ) ] )
            , ( "Utilities", Dict.fromList [ ( "Bob", V24.Share 1 ), ( "Cara", V24.Share 2 ) ] )
            , ( "House", Dict.fromList [ ( "Alice", V24.Share 1 ), ( "Cara", V24.Share 1 ) ] )
            ]
    , totalGroupCredits = Dict.fromList [ ( "root", Dict.fromList [ ( "Trip", V24.Amount 500 ) ] ) ]
    , persons =
        Dict.fromList
            [ ( "Alice", { id = 0, belongsTo = Set.fromList [ "trip-house" ] } )
            , ( "Bob", { id = 1, belongsTo = Set.fromList [ "trip-only" ] } )
            , ( "Cara", { id = 2, belongsTo = Set.fromList [ "utilities-house" ] } )
            ]
    , nextPersonId = 3
    , loggedInSessions = Set.empty
    }


legacyEditDialog : V24.Dialog
legacyEditDialog =
    V24.AddSpendingDialog
        { transactionId = Just legacyTransactionId
        , description = "Breakfast"
        , date = Just sampleDate
        , dateText = "2025-04-18"
        , datePickerModel = DatePicker.init
        , total = "12.00"
        , credits = [ ( "Alice", "12.00", V24.Complete ) ]
        , debits = [ ( "Trip", "12.00", V24.Complete ) ]
        , submitted = True
        }


legacyCreateDialog : V24.Dialog
legacyCreateDialog =
    V24.AddSpendingDialog
        { transactionId = Nothing
        , description = "Breakfast"
        , date = Just sampleDate
        , dateText = "2025-04-18"
        , datePickerModel = DatePicker.init
        , total = "12.00"
        , credits = [ ( "Alice", "12.00", V24.Complete ) ]
        , debits = [ ( "Trip", "12.00", V24.Complete ) ]
        , submitted = True
        }


legacyTransactionId : V24.TransactionId
legacyTransactionId =
    { year = 2025, month = 4, day = 18, index = 0 }


sampleDate : Date.Date
sampleDate =
    Date.fromCalendarDate 2025 Apr 18


transactionId : Int -> Int -> Int -> Int -> V26.TransactionId
transactionId year month day index =
    { year = year, month = month, day = day, index = index }


spendingSummary : V26.Spending -> SpendingSummary
spendingSummary spending =
    { description = spending.description
    , total = amountValue spending.total
    , status = spending.status
    , transactionIds = spending.transactionIds
    }


referencedTransactionsForSpending : V26.BackendModel -> Int -> V26.Spending -> { spendingId : Int, transactions : List ReferencedTransactionSummary }
referencedTransactionsForSpending model spendingId spending =
    { spendingId = spendingId
    , transactions =
        spending.transactionIds
            |> List.filterMap
                (\id ->
                    findTransaction id model
                        |> Maybe.map
                            (\transaction ->
                                { transactionId = id
                                , group = transaction.group
                                , amount = amountValue transaction.amount
                                , side = transaction.side
                                , status = transaction.status
                                , groupMembersKey = transaction.groupMembersKey
                                , groupMembers = transaction.groupMembers |> Set.toList
                                }
                            )
                )
    }


allReferencedTransactionIds : V26.BackendModel -> List V26.TransactionId
allReferencedTransactionIds model =
    model.spendings
        |> Array.toList
        |> List.concatMap .transactionIds


allStoredTransactionIds : V26.BackendModel -> List V26.TransactionId
allStoredTransactionIds model =
    model.years
        |> Dict.toList
        |> List.concatMap
            (\( year, yearRecord ) ->
                yearRecord.months
                    |> Dict.toList
                    |> List.concatMap
                        (\( month, monthRecord ) ->
                            monthRecord.days
                                |> Dict.toList
                                |> List.concatMap
                                    (\( day, dayRecord ) ->
                                        dayRecord.transactions
                                            |> Array.toIndexedList
                                            |> List.map (\( index, _ ) -> transactionId year month day index)
                                    )
                        )
            )


dayTransactionSummary : Int -> Int -> Int -> V26.BackendModel -> List StoredTransactionSummary
dayTransactionSummary year month day model =
    model.years
        |> Dict.get year
        |> Maybe.andThen (.months >> Dict.get month)
        |> Maybe.andThen (.days >> Dict.get day)
        |> Maybe.map
            (.transactions
                >> Array.toIndexedList
                >> List.map
                    (\( index, transaction ) ->
                        { transactionId = transactionId year month day index
                        , spendingId = transaction.spendingId
                        , group = transaction.group
                        , amount = amountValue transaction.amount
                        , side = transaction.side
                        , status = transaction.status
                        }
                    )
            )
        |> Maybe.withDefault []


migrationTotalsSummary : V26.BackendModel -> MigrationTotalsSummary
migrationTotalsSummary model =
    { root = groupCreditTotalsToSummary model.totalGroupCredits
    , year2025 =
        model.years
            |> Dict.get 2025
            |> Maybe.map (.totalGroupCredits >> groupCreditTotalsToSummary)
    , april2025 =
        model.years
            |> Dict.get 2025
            |> Maybe.andThen (.months >> Dict.get 4)
            |> Maybe.map (.totalGroupCredits >> groupCreditTotalsToSummary)
    , day18 =
        model.years
            |> Dict.get 2025
            |> Maybe.andThen (.months >> Dict.get 4)
            |> Maybe.andThen (.days >> Dict.get 18)
            |> Maybe.map (.totalGroupCredits >> groupCreditTotalsToSummary)
    , day19 =
        model.years
            |> Dict.get 2025
            |> Maybe.andThen (.months >> Dict.get 4)
            |> Maybe.andThen (.days >> Dict.get 19)
            |> Maybe.map (.totalGroupCredits >> groupCreditTotalsToSummary)
    }


findTransaction : V26.TransactionId -> V26.BackendModel -> Maybe V26.Transaction
findTransaction id model =
    model.years
        |> Dict.get id.year
        |> Maybe.andThen (.months >> Dict.get id.month)
        |> Maybe.andThen (.days >> Dict.get id.day)
        |> Maybe.andThen (.transactions >> Array.get id.index)


groupCreditTotalsToSummary : Dict.Dict String (Dict.Dict String (V26.Amount V26.Credit)) -> List ( String, List ( String, Int ) )
groupCreditTotalsToSummary totals =
    totals
        |> Dict.toList
        |> List.map
            (\( groupKey, groupTotals ) ->
                ( groupKey
                , groupTotals
                    |> Dict.toList
                    |> List.map (\( name, amount ) -> ( name, amountValue amount ))
                )
            )


frontendMessageSafetySummary : FrontendMessageSafetySummary
frontendMessageSafetySummary =
    { showAddSpendingDialog = MigrateV26.migrateFrontendMsg (V24.ShowAddSpendingDialog (Just legacyTransactionId))
    , showConfirmDeleteDialog = MigrateV26.migrateFrontendMsg (V24.ShowConfirmDeleteDialog legacyTransactionId)
    , confirmDeleteTransaction = MigrateV26.migrateFrontendMsg (V24.ConfirmDeleteTransaction legacyTransactionId)
    , editTransaction =
        MigrateV26.migrateToBackend
            (V24.EditTransaction
                { transactionId = legacyTransactionId
                , description = "Breakfast"
                , year = 2025
                , month = 4
                , day = 18
                , total = V24.Amount 1200
                , credits = Dict.fromList [ ( "Alice", V24.Amount 1200 ) ]
                , debits = Dict.fromList [ ( "Trip", V24.Amount 1200 ) ]
                }
            )
    , deleteTransaction = MigrateV26.migrateToBackend (V24.DeleteTransaction legacyTransactionId)
    , requestTransactionDetails = MigrateV26.migrateToBackend (V24.RequestTransactionDetails legacyTransactionId)
    , listGroupTransactions =
        MigrateV26.migrateToFrontend
            (V24.ListGroupTransactions
                { group = "Trip"
                , transactions =
                    [ { transactionId = legacyTransactionId
                      , description = "Breakfast"
                      , year = 2025
                      , month = 4
                      , day = 18
                      , total = V24.Amount 1200
                      , share = V24.Amount 600
                      }
                    ]
                }
            )
    , transactionDetails =
        MigrateV26.migrateToFrontend
            (V24.TransactionDetails
                { transactionId = legacyTransactionId
                , description = "Breakfast"
                , year = 2025
                , month = 4
                , day = 18
                , total = V24.Amount 1200
                , credits = Dict.fromList [ ( "Alice", V24.Amount 1200 ) ]
                , debits = Dict.fromList [ ( "Trip", V24.Amount 1200 ) ]
                }
            )
    }


createDialogSummary : V26.AddSpendingDialogModel -> CreateDialogSummary
createDialogSummary dialog =
    { spendingId = dialog.spendingId
    , description = dialog.description
    , total = dialog.total
    , dateText = dialog.dateText
    , today = dialog.today
    , credits = List.map transactionLineSummary dialog.credits
    , debits = List.map transactionLineSummary dialog.debits
    , submitted = dialog.submitted
    }


transactionLineSummary : V26.TransactionLine -> TransactionLineSummary
transactionLineSummary line =
    { group = line.group
    , amount = line.amount
    , validity = line.nameValidity
    , detailsExpanded = line.detailsExpanded
    }


amountValue : V26.Amount a -> Int
amountValue amount =
    case amount of
        V26.Amount value ->
            value
