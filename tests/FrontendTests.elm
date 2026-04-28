module FrontendTests exposing (suite)

{-| Focused regression tests for frontend pure helpers. They document the
amount grammar, submission gating, and derived debt calculations that the UI
depends on.
-}

import Date
import DatePicker
import Dict
import Evergreen.Migrate.V26 as MigrateV26
import Evergreen.V24.Types as V24
import Evergreen.V26.Types as V26
import Expect
import Frontend
import Test exposing (..)
import Time exposing (Month(..))
import Types exposing (..)


suite : Test
suite =
    describe "Frontend pure helpers"
        [ {- Keep amount parsing/formatting examples explicit so contributors can
             see which user inputs are intentionally accepted.
          -}
          describe "amount parsing and formatting"
            [ test "formatAmountValue round-trips representative cent amounts through parseAmountValue" <|
                \_ ->
                    let
                        cents =
                            [ 0, 1, 10, 105, 12345, -99, -12345 ]
                    in
                    Expect.equal
                        (List.map Just cents)
                        (cents
                            |> List.map Frontend.formatAmountValue
                            |> List.map Frontend.parseAmountValue
                        )
            , test "parseAmountValue accepts commas and rejects more than two decimals" <|
                \_ ->
                    Expect.equal
                        ( Just 1234, Just -550, Nothing )
                        ( Frontend.parseAmountValue "12,34"
                        , Frontend.parseAmountValue "-5.5"
                        , Frontend.parseAmountValue "12.345"
                        )
            ]
        , {- The spending dialog only exposes extra row details when the user has
             actually diverged from the dialog defaults or manually expanded the
             section.
          -}
          describe "transaction detail visibility"
            [ test "transactionLineDetailsVisible stays collapsed for a default row and opens for explicit details" <|
                \_ ->
                    let
                        line =
                            Frontend.defaultTransactionLine (Just sampleDate) Nothing "10.00"
                    in
                    Expect.equal
                        ( False, True, True )
                        ( Frontend.transactionLineDetailsVisible (Just sampleDate) line
                        , Frontend.transactionLineDetailsVisible (Just sampleDate) { line | detailsExpanded = True }
                        , Frontend.transactionLineDetailsVisible (Just sampleDate) { line | secondaryDescription = "Tip" }
                        )
            ]
        , {- canSubmitSpending is the last pure guard before a request goes to the
             backend, so these cases document what the dialog considers complete.
          -}
          describe "spending submission gating"
            [ test "canSubmitSpending allows a fully populated balanced dialog" <|
                \_ ->
                    Expect.equal True (Frontend.canSubmitSpending validDialog)
            , test "canSubmitSpending blocks incomplete transaction lines even when the total parses" <|
                \_ ->
                    let
                        invalidCredit =
                            completeLine "Alice" "10.00"
                                |> (\line -> { line | nameValidity = Incomplete })
                    in
                    Expect.equal
                        False
                        (Frontend.canSubmitSpending { validDialog | credits = [ invalidCredit ] })
            ]
        , {- Group transactions arrive oldest-first from the backend traversal, so
             the frontend must reverse them at the consumer boundary before the
             view reads `model.groupTransactions`.
          -}
          describe "group transaction ordering"
            [ test "ListGroupTransactions stores an ascending backend response as newest-first" <|
                \_ ->
                    let
                        backendTransactions =
                            [ listedTransaction 0 2025 4 16
                            , listedTransaction 0 2025 4 17
                            , listedTransaction 1 2025 4 18
                            , listedTransaction 2 2025 4 18
                            ]
                    in
                    Expect.equal
                        [ listedTransaction 2 2025 4 18
                        , listedTransaction 1 2025 4 18
                        , listedTransaction 0 2025 4 17
                        , listedTransaction 0 2025 4 16
                        ]
                        (Frontend.groupTransactionsFromBackend
                            "Trip"
                            "Trip"
                            backendTransactions
                            [ listedTransaction 9 2025 4 1 ]
                        )
            , test "ListGroupTransactions ignores responses for another group" <|
                \_ ->
                    let
                        existingTransactions =
                            [ listedTransaction 2 2025 4 18
                            , listedTransaction 0 2025 4 16
                            ]
                    in
                    Expect.equal
                        existingTransactions
                        (Frontend.groupTransactionsFromBackend
                            "Trip"
                            "Other group"
                            [ listedTransaction 0 2025 4 16 ]
                            existingTransactions
                        )
            ]
        , {- Debt summaries are derived entirely on the client. This example keeps
             the "who owes whom" math easy to review.
          -}
          describe "personalAmountsDue"
            [ test "personalAmountsDue subtracts credits from each member's share of debits" <|
                \_ ->
                    Expect.equal
                        (Dict.fromList [ ( "Alice", Amount -500 ), ( "Bob", Amount 500 ) ])
                        (Frontend.personalAmountsDue
                            [ ( "Dinner", Dict.fromList [ ( "Alice", Share 1 ), ( "Bob", Share 1 ) ], Amount 1000 ) ]
                            [ ( "Alice paid", Dict.fromList [ ( "Alice", Share 1 ) ], Amount 1000 ) ]
                        )
            ]
        , describe "V24 to V26 frontend migration safety"
            [ test "frontend dialog migration preserves create drafts but strips edit identity" <|
                \_ ->
                    case MigrateV26.migrateFrontendDialog (Just (V24.AddSpendingDialog legacyCreateDialog)) of
                        Just (V26.AddSpendingDialog dialog) ->
                            Expect.equal
                                { spendingId = Nothing
                                , description = legacyCreateDialog.description
                                , total = legacyCreateDialog.total
                                , credits = [ "Alice" ]
                                , debits = [ "Trip" ]
                                }
                                { spendingId = dialog.spendingId
                                , description = dialog.description
                                , total = dialog.total
                                , credits = List.map .group dialog.credits
                                , debits = List.map .group dialog.debits
                                }

                        other ->
                            Expect.fail ("Expected create dialog to survive migration, got: " ++ Debug.toString other)
            , test "frontend dialog and message migration no-op legacy transaction-bound edit/delete flows" <|
                \_ ->
                    Expect.equal
                        ( Nothing
                        , V26.NoOpFrontendMsg
                        , V26.NoOpFrontendMsg
                        )
                        ( MigrateV26.migrateFrontendDialog (Just (V24.AddSpendingDialog legacyEditDialog))
                        , MigrateV26.migrateFrontendMsg (V24.ShowAddSpendingDialog (Just legacyTransactionId))
                        , MigrateV26.migrateFrontendMsg (V24.ShowConfirmDeleteDialog legacyTransactionId)
                        )
            , test "backend/frontend payload migration resets legacy transaction references instead of reusing them" <|
                \_ ->
                    Expect.equal
                        { edit = V26.NoOpToBackend
                        , detailsRequest = V26.NoOpToBackend
                        , detailsResponse = V26.SpendingError "Please reopen the spending editor after the update."
                        , groupTransactions =
                            V26.ListGroupTransactions
                                { group = "Trip"
                                , transactions = []
                                }
                        }
                        { edit = MigrateV26.migrateToBackend (V24.EditTransaction legacyEditPayload)
                        , detailsRequest = MigrateV26.migrateToBackend (V24.RequestTransactionDetails legacyTransactionId)
                        , detailsResponse = MigrateV26.migrateToFrontend (V24.TransactionDetails legacyTransactionDetails)
                        , groupTransactions =
                            MigrateV26.migrateToFrontend
                                (V24.ListGroupTransactions
                                    { group = "Trip"
                                    , transactions = [ legacyListedTransaction ]
                                    }
                                )
                        }
            ]
        ]


sampleDate : Date.Date
sampleDate =
    Date.fromCalendarDate 2025 Apr 18


completeLine : String -> String -> TransactionLine
completeLine group amount =
    Frontend.defaultTransactionLine (Just sampleDate) Nothing amount
        |> (\line ->
                { line
                    | group = group
                    , amount = amount
                    , nameValidity = Complete
                }
           )


validDialog : AddSpendingDialogModel
validDialog =
    Frontend.emptySpendingDialog Nothing "Dinner" "10.00"
        |> Frontend.setSpendingDateValue sampleDate
        |> (\dialog ->
                { dialog
                    | credits = [ completeLine "Alice" "10.00" ]
                    , debits = [ completeLine "Trip" "10.00" ]
                }
           )


listedTransaction :
    Int
    -> Int
    -> Int
    -> Int
    ->
        { transactionId : TransactionId
        , spendingId : SpendingId
        , description : String
        , year : Int
        , month : Int
        , day : Int
        , total : Amount Debit
        , share : Amount Debit
        }
listedTransaction index year month day =
    { transactionId =
        { year = year
        , month = month
        , day = day
        , index = index
        }
    , spendingId = 0
    , description = "Dinner"
    , year = year
    , month = month
    , day = day
    , total = Amount 1000
    , share = Amount 500
    }


legacyTransactionId : V24.TransactionId
legacyTransactionId =
    { year = 2025
    , month = 4
    , day = 18
    , index = 2
    }


legacyCreateDialog : V24.AddSpendingDialogModel
legacyCreateDialog =
    { transactionId = Nothing
    , description = "Dinner"
    , date = Just sampleDate
    , dateText = "2025-04-18"
    , datePickerModel = DatePicker.init
    , total = "10.00"
    , credits = [ ( "Alice", "10.00", V24.Complete ) ]
    , debits = [ ( "Trip", "10.00", V24.Complete ) ]
    , submitted = False
    }


legacyEditDialog : V24.AddSpendingDialogModel
legacyEditDialog =
    { legacyCreateDialog | transactionId = Just legacyTransactionId }


legacyEditPayload :
    { transactionId : V24.TransactionId
    , description : String
    , year : Int
    , month : Int
    , day : Int
    , total : V24.Amount V24.Credit
    , credits : Dict.Dict String (V24.Amount V24.Credit)
    , debits : Dict.Dict String (V24.Amount V24.Debit)
    }
legacyEditPayload =
    { transactionId = legacyTransactionId
    , description = "Dinner"
    , year = 2025
    , month = 4
    , day = 18
    , total = V24.Amount 1000
    , credits = Dict.fromList [ ( "Alice", V24.Amount 1000 ) ]
    , debits = Dict.fromList [ ( "Trip", V24.Amount 1000 ) ]
    }


legacyTransactionDetails :
    { transactionId : V24.TransactionId
    , description : String
    , year : Int
    , month : Int
    , day : Int
    , total : V24.Amount V24.Credit
    , credits : Dict.Dict String (V24.Amount V24.Credit)
    , debits : Dict.Dict String (V24.Amount V24.Debit)
    }
legacyTransactionDetails =
    legacyEditPayload


legacyListedTransaction :
    { transactionId : V24.TransactionId
    , description : String
    , year : Int
    , month : Int
    , day : Int
    , total : V24.Amount V24.Debit
    , share : V24.Amount V24.Debit
    }
legacyListedTransaction =
    { transactionId = legacyTransactionId
    , description = "Dinner"
    , year = 2025
    , month = 4
    , day = 18
    , total = V24.Amount 1000
    , share = V24.Amount 500
    }
