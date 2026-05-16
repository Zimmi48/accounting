module FrontendTests exposing (suite)

{-| Focused regression tests for frontend pure helpers. They document the
amount grammar, submission gating, and derived debt calculations that the UI
depends on.
-}

import Date
import DatePicker
import Dict
import Evergreen.Migrate.V26 as MigrateV26
import Evergreen.Migrate.V31 as MigrateV31
import Evergreen.V24.Types as V24
import Evergreen.V26.Types as V26
import Evergreen.V28.Types as V28
import Evergreen.V31.Types as V31
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
            [ test "viewAmount round-trips representative cent amounts through parseAmountValue" <|
                \_ ->
                    let
                        cents =
                            [ 0, 1, 10, 105, 12345, -99, -12345 ]
                    in
                    Expect.equal
                        (List.map Just cents)
                        (cents
                            |> List.map Frontend.viewAmount
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
            , test "canSubmitSpending allows a balanced negative-total dialog" <|
                \_ ->
                    Expect.equal True (Frontend.canSubmitSpending negativeTotalDialog)
            , test "canSubmitSpending blocks dialogs whose credits and debits do not both match the total" <|
                \_ ->
                    Expect.equal
                        ( False, False )
                        ( Frontend.canSubmitSpending
                            { validDialog
                                | credits =
                                    [ completeLine "Alice" "6.00"
                                    , completeLine "Bob" "4.00"
                                    ]
                                , debits = [ completeLine "Trip" "9.00" ]
                            }
                        , Frontend.canSubmitSpending
                            { negativeTotalDialog
                                | credits = [ completeLine "Alice" "-9.00" ]
                                , debits = [ completeLine "Trip" "-10.00" ]
                            }
                        )
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
        , {- Group transaction pages now arrive newest-first with explicit month/year
             summaries, and older pages append after the current tail.
          -}
          describe "group transaction ordering"
            [ test "transactionCheckVisualState switches between explicit unchecked and checked markers" <|
                \_ ->
                    Expect.equal
                        ( Frontend.UncheckedTransactionCheck, Frontend.CheckedTransactionCheck )
                        ( Frontend.transactionCheckVisualState False
                        , Frontend.transactionCheckVisualState True
                        )
            , test "checked transaction markers use a seamless muted dot without a highlighted border" <|
                \_ ->
                    let
                        checkedStyle =
                            Frontend.transactionCheckColors Frontend.lightPalette Frontend.CheckedTransactionCheck

                        uncheckedStyle =
                            Frontend.transactionCheckColors Frontend.lightPalette Frontend.UncheckedTransactionCheck
                    in
                    Expect.equal
                        { marker = Frontend.lightPalette.subtleAccent
                        , buttonBorder = Frontend.lightPalette.border
                        , markerBorderWidth = 0
                        , markerSize = 10
                        , avoidsBrightAccent = True
                        , remainsDistinct = True
                        }
                        { marker = checkedStyle.marker
                        , buttonBorder = checkedStyle.buttonBorder
                        , markerBorderWidth = checkedStyle.markerBorderWidth
                        , markerSize = checkedStyle.markerSize
                        , avoidsBrightAccent = checkedStyle.marker /= Frontend.lightPalette.accent
                        , remainsDistinct = checkedStyle.marker /= uncheckedStyle.marker
                        }
            , test "initial ListGroupTransactions replaces existing items with the backend page" <|
                \_ ->
                    let
                        backendItems =
                            [ monthSummaryItem 2025 4 1000
                            , listedTransactionItem 2 2025 4 18
                            , listedTransactionItem 1 2025 4 18
                            ]
                    in
                    Expect.equal
                        backendItems
                        (Frontend.groupTransactionsFromBackend
                            "Trip"
                            "Trip"
                            Nothing
                            backendItems
                            [ listedTransactionItem 9 2025 4 1 ]
                        )
            , test "initial ListGroupTransactions restores reverse chronological rows while keeping summaries above each block" <|
                \_ ->
                    let
                        backendItems =
                            [ yearSummaryItem 2025 2500
                            , monthSummaryItem 2025 5 500
                            , listedTransactionItem 0 2025 5 1
                            , listedTransactionItem 1 2025 5 3
                            , monthSummaryItem 2025 4 2000
                            , listedTransactionItem 0 2025 4 17
                            , listedTransactionItem 1 2025 4 17
                            , listedTransactionItem 2 2025 4 18
                            ]
                    in
                    Expect.equal
                        [ yearSummaryItem 2025 2500
                        , monthSummaryItem 2025 5 500
                        , listedTransactionItem 1 2025 5 3
                        , listedTransactionItem 0 2025 5 1
                        , monthSummaryItem 2025 4 2000
                        , listedTransactionItem 2 2025 4 18
                        , listedTransactionItem 1 2025 4 17
                        , listedTransactionItem 0 2025 4 17
                        ]
                        (Frontend.groupTransactionsFromBackend
                            "Trip"
                            "Trip"
                            Nothing
                            backendItems
                            []
                        )
            , test "load-more ListGroupTransactions hoists the year summary and keeps appended rows reverse chronological" <|
                \_ ->
                    let
                        existingItems =
                            [ monthSummaryItem 2025 5 500
                            , listedTransactionItem 1 2025 5 3
                            , listedTransactionItem 0 2025 5 1
                            ]

                        olderItems =
                            [ yearSummaryItem 2025 2500
                            , monthSummaryItem 2025 4 2000
                            , listedTransactionItem 0 2025 4 17
                            , listedTransactionItem 1 2025 4 17
                            , listedTransactionItem 2 2025 4 18
                            ]
                    in
                    Expect.equal
                        [ yearSummaryItem 2025 2500
                        , monthSummaryItem 2025 5 500
                        , listedTransactionItem 1 2025 5 3
                        , listedTransactionItem 0 2025 5 1
                        , monthSummaryItem 2025 4 2000
                        , listedTransactionItem 2 2025 4 18
                        , listedTransactionItem 1 2025 4 17
                        , listedTransactionItem 0 2025 4 17
                        ]
                        (Frontend.groupTransactionsFromBackend
                            "Trip"
                            "Trip"
                            (Just { year = 2025, month = 5 })
                            olderItems
                            existingItems
                        )
            , test "groupTransactionViewSections keeps year headers outside foldable month sections" <|
                \_ ->
                    Expect.equal
                        [ Frontend.StandaloneGroupTransactionListItem (yearSummaryItem 2025 2500)
                        , Frontend.FoldableGroupTransactionMonthSection
                            { summary = { year = 2025, month = 5, total = Amount 500 }
                            , rows =
                                [ listedTransaction 1 2025 5 3
                                , listedTransaction 0 2025 5 1
                                ]
                            , folded = False
                            }
                        , Frontend.FoldableGroupTransactionMonthSection
                            { summary = { year = 2025, month = 4, total = Amount 2000 }
                            , rows =
                                [ listedTransaction 2 2025 4 18
                                , listedTransaction 1 2025 4 17
                                , listedTransaction 0 2025 4 17
                                ]
                            , folded = False
                            }
                        ]
                        (Frontend.groupTransactionViewSections
                            [ yearSummaryItem 2025 2500
                            , monthSummaryItem 2025 5 500
                            , listedTransactionItem 1 2025 5 3
                            , listedTransactionItem 0 2025 5 1
                            , monthSummaryItem 2025 4 2000
                            , listedTransactionItem 2 2025 4 18
                            , listedTransactionItem 1 2025 4 17
                            , listedTransactionItem 0 2025 4 17
                            ]
                        )
            , test "groupTransactionMonthSectionItems hides month rows when folded and keeps them when expanded" <|
                \_ ->
                    let
                        expandedSection =
                            { summary = { year = 2025, month = 5, total = Amount 500 }
                            , rows =
                                [ listedTransaction 1 2025 5 3
                                , listedTransaction 0 2025 5 1
                                ]
                            , folded = False
                            }

                        foldedSection =
                            { expandedSection | folded = True }
                    in
                    Expect.equal
                        ( [ monthSummaryItem 2025 5 500 ]
                        , [ monthSummaryItem 2025 5 500
                          , listedTransactionItem 1 2025 5 3
                          , listedTransactionItem 0 2025 5 1
                          ]
                        )
                        ( Frontend.groupTransactionMonthSectionItems foldedSection
                        , Frontend.groupTransactionMonthSectionItems expandedSection
                        )
            , test "toggleGroupTransactionMonthFold only folds the targeted month and keeps year headers outside the section" <|
                \_ ->
                    let
                        foldedItems =
                            Frontend.toggleGroupTransactionMonthFold
                                { year = 2025, month = 5 }
                                monthSectionedItems
                    in
                    Expect.equal
                        [ Frontend.StandaloneGroupTransactionListItem (yearSummaryItem 2025 2500)
                        , Frontend.FoldableGroupTransactionMonthSection
                            { summary = { year = 2025, month = 5, total = Amount 500 }
                            , rows =
                                [ listedTransaction 1 2025 5 3
                                , listedTransaction 0 2025 5 1
                                ]
                            , folded = True
                            }
                        , Frontend.FoldableGroupTransactionMonthSection
                            { summary = { year = 2025, month = 4, total = Amount 2000 }
                            , rows =
                                [ listedTransaction 2 2025 4 18
                                , listedTransaction 1 2025 4 17
                                , listedTransaction 0 2025 4 17
                                ]
                            , folded = False
                            }
                        ]
                        (Frontend.groupTransactionViewSections foldedItems)
            , test "fresh reload keeps a folded month collapsed while restoring reverse chronology inside every month" <|
                \_ ->
                    let
                        existingItems =
                            Frontend.toggleGroupTransactionMonthFold
                                { year = 2025, month = 5 }
                                monthSectionedItems

                        backendItems =
                            [ yearSummaryItem 2025 2500
                            , monthSummaryItem 2025 5 500
                            , listedTransactionItem 0 2025 5 1
                            , listedTransactionItem 1 2025 5 3
                            , monthSummaryItem 2025 4 2000
                            , listedTransactionItem 0 2025 4 17
                            , listedTransactionItem 1 2025 4 17
                            , listedTransactionItem 2 2025 4 18
                            ]
                    in
                    Expect.equal
                        [ Frontend.StandaloneGroupTransactionListItem (yearSummaryItem 2025 2500)
                        , Frontend.FoldableGroupTransactionMonthSection
                            { summary = { year = 2025, month = 5, total = Amount 500 }
                            , rows =
                                [ listedTransaction 1 2025 5 3
                                , listedTransaction 0 2025 5 1
                                ]
                            , folded = True
                            }
                        , Frontend.FoldableGroupTransactionMonthSection
                            { summary = { year = 2025, month = 4, total = Amount 2000 }
                            , rows =
                                [ listedTransaction 2 2025 4 18
                                , listedTransaction 1 2025 4 17
                                , listedTransaction 0 2025 4 17
                                ]
                            , folded = False
                            }
                        ]
                        (Frontend.groupTransactionViewSections
                            (Frontend.groupTransactionsFromBackend
                                "Trip"
                                "Trip"
                                Nothing
                                backendItems
                                existingItems
                            )
                        )
            , test "load-more keeps a folded newer month collapsed when an older year arrives with its header" <|
                \_ ->
                    let
                        existingItems =
                            Frontend.toggleGroupTransactionMonthFold
                                { year = 2025, month = 5 }
                                [ yearSummaryItem 2025 500
                                , monthSummaryItem 2025 5 500
                                , listedTransactionItem 0 2025 5 1
                                , listedTransactionItem 1 2025 5 3
                                ]

                        olderItems =
                            [ yearSummaryItem 2024 2000
                            , monthSummaryItem 2024 12 2000
                            , listedTransactionItem 0 2024 12 17
                            , listedTransactionItem 1 2024 12 17
                            , listedTransactionItem 2 2024 12 18
                            ]
                    in
                    Expect.equal
                        [ Frontend.StandaloneGroupTransactionListItem (yearSummaryItem 2025 500)
                        , Frontend.FoldableGroupTransactionMonthSection
                            { summary = { year = 2025, month = 5, total = Amount 500 }
                            , rows =
                                [ listedTransaction 1 2025 5 3
                                , listedTransaction 0 2025 5 1
                                ]
                            , folded = True
                            }
                        , Frontend.StandaloneGroupTransactionListItem (yearSummaryItem 2024 2000)
                        , Frontend.FoldableGroupTransactionMonthSection
                            { summary = { year = 2024, month = 12, total = Amount 2000 }
                            , rows =
                                [ listedTransaction 2 2024 12 18
                                , listedTransaction 1 2024 12 17
                                , listedTransaction 0 2024 12 17
                                ]
                            , folded = False
                            }
                        ]
                        (Frontend.groupTransactionViewSections
                            (Frontend.groupTransactionsFromBackend
                                "Trip"
                                "Trip"
                                (Just { year = 2025, month = 5 })
                                olderItems
                                existingItems
                            )
                        )
            , test "ListGroupTransactions ignores responses for another group" <|
                \_ ->
                    let
                        existingItems =
                            [ listedTransactionItem 2 2025 4 18
                            , monthSummaryItem 2025 4 1000
                            ]
                    in
                    Expect.equal
                        existingItems
                        (Frontend.groupTransactionsFromBackend
                            "Trip"
                            "Other group"
                            Nothing
                            [ listedTransactionItem 0 2025 4 16 ]
                            existingItems
                        )
            , test "groupTransactionsReloadPages keeps the current depth and still requests one page for a fresh group" <|
                \_ ->
                    Expect.equal
                        ( 1, 3 )
                        ( Frontend.groupTransactionsReloadPages { groupTransactionsLoadedPages = 0 }
                        , Frontend.groupTransactionsReloadPages { groupTransactionsLoadedPages = 3 }
                        )
            , test "operationSuccessfulRefreshPlan keeps folded months in place while replaying the loaded depth" <|
                \_ ->
                    let
                        foldedItems =
                            Frontend.toggleGroupTransactionMonthFold
                                { year = 2025, month = 5 }
                                monthSectionedItems

                        refreshPlan =
                            Frontend.operationSuccessfulRefreshPlan
                                { page = Home
                                , showDialog = Nothing
                                , errorMessage = Just "Old error"
                                , nameValidity = Complete
                                , user = "Alice"
                                , groupValidity = Complete
                                , group = "Trip"
                                , groupTransactionsLoadedPages = 3
                                , groupTransactionsLoading = False
                                , groupTransactions = foldedItems
                                }
                    in
                    Expect.equal
                        { groupTransactions = foldedItems
                        , groupTransactionsLoading = True
                        , backendRequests =
                            [ RequestUserGroups "Alice"
                            , RequestGroupTransactions
                                { group = "Trip"
                                , before = Nothing
                                , pages = 3
                                }
                            ]
                        }
                        { groupTransactions = refreshPlan.updatedModel.groupTransactions
                        , groupTransactionsLoading = refreshPlan.updatedModel.groupTransactionsLoading
                        , backendRequests = refreshPlan.backendRequests
                        }
            , test "updatedGroupTransactionsLoadedPages resets on a fresh reload and accumulates load-more pages" <|
                \_ ->
                    Expect.equal
                        ( 3, 4 )
                        ( Frontend.updatedGroupTransactionsLoadedPages Nothing 3 1
                        , Frontend.updatedGroupTransactionsLoadedPages (Just { year = 2025, month = 4 }) 1 3
                        )
            , test "toggleGroupTransactionChecked only flips the targeted transaction" <|
                \_ ->
                    let
                        firstId =
                            { groupId = 0, year = 2025, month = 4, day = 18, index = 0 }

                        secondId =
                            { groupId = 0, year = 2025, month = 4, day = 18, index = 1 }

                        firstTransaction =
                            listedTransaction 0 2025 4 18

                        secondTransaction =
                            listedTransaction 1 2025 4 18
                    in
                    Expect.equal
                        [ GroupTransactionRow { firstTransaction | checked = True }
                        , GroupTransactionMonthSummary { year = 2025, month = 4, total = Amount 1000 }
                        , GroupTransactionRow { secondTransaction | checked = True }
                        ]
                        (Frontend.toggleGroupTransactionChecked
                            firstId
                            [ GroupTransactionRow firstTransaction
                            , monthSummaryItem 2025 4 1000
                            , GroupTransactionRow { secondTransaction | checked = True }
                            ]
                        )
            , test "shouldLoadMoreGroupTransactions waits for the bottom of the list and a cursor" <|
                \_ ->
                    Expect.equal
                        ( False, True, False )
                        ( Frontend.shouldLoadMoreGroupTransactions
                            { scrollTop = 100, clientHeight = 200, scrollHeight = 400 }
                            frontendGroupTransactionsState
                        , Frontend.shouldLoadMoreGroupTransactions
                            { scrollTop = 180, clientHeight = 200, scrollHeight = 400 }
                            { frontendGroupTransactionsState
                                | groupTransactionsNextCursor = Just { year = 2025, month = 4 }
                            }
                        , Frontend.shouldLoadMoreGroupTransactions
                            { scrollTop = 180, clientHeight = 200, scrollHeight = 400 }
                            { frontendGroupTransactionsState
                                | groupTransactionsNextCursor = Just { year = 2025, month = 4 }
                                , groupTransactionsLoading = True
                            }
                        )
            , test "folding a month rechecks the viewport and triggers the older-history request once the fold reveals the end" <|
                \_ ->
                    let
                        baseModel =
                            { group = "Trip"
                            , groupTransactions = monthSectionedItems
                            , groupTransactionsLoading = False
                            , groupTransactionsNextCursor = Just { year = 2025, month = 4 }
                            , groupValidity = Complete
                            }

                        foldPlan =
                            Frontend.toggleGroupTransactionMonthFoldPlan
                                { year = 2025, month = 5 }
                                baseModel

                        beforeFoldLoadPlan =
                            Frontend.groupTransactionsViewportLoadMorePlan
                                { scrollTop = 0, clientHeight = 220, scrollHeight = 440 }
                                baseModel

                        afterFoldLoadPlan =
                            Frontend.groupTransactionsViewportLoadMorePlan
                                (Frontend.groupTransactionsScrollStateFromViewport
                                    { scene = { width = 640, height = 220 }
                                    , viewport = { x = 0, y = 0, width = 640, height = 220 }
                                    }
                                )
                                { baseModel | groupTransactions = foldPlan.groupTransactions }
                    in
                    Expect.equal
                        { foldedItems =
                            Frontend.toggleGroupTransactionMonthFold
                                { year = 2025, month = 5 }
                                monthSectionedItems
                        , rechecksViewport = True
                        , beforeFoldRequest = Nothing
                        , afterFoldLoading = True
                        , afterFoldRequest =
                            Just
                                (RequestGroupTransactions
                                    { group = "Trip"
                                    , before = Just { year = 2025, month = 4 }
                                    , pages = 1
                                    }
                                )
                        }
                        { foldedItems = foldPlan.groupTransactions
                        , rechecksViewport = foldPlan.shouldCheckViewport
                        , beforeFoldRequest = beforeFoldLoadPlan.backendRequest
                        , afterFoldLoading = afterFoldLoadPlan.updatedModel.groupTransactionsLoading
                        , afterFoldRequest = afterFoldLoadPlan.backendRequest
                        }
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
        , describe "V28 to V31 frontend migration safety"
            [ test "frontend dialog migration preserves spending editor contents that already use spending ids" <|
                \_ ->
                    Expect.equal
                        (V31.AddSpendingDialog legacyFrontendDialogV31)
                        (MigrateV31.migrate_Types_Dialog (V28.AddSpendingDialog legacyFrontendDialogV28))
            , test "frontend message and payload migration no-op stale edit intents and clear old transaction listings" <|
                \_ ->
                    Expect.equal
                        ( V31.NoOpFrontendMsg
                        , V31.ShowAddSpendingDialog Nothing
                        , V31.ListGroupTransactions { group = "Trip", transactions = [] }
                        )
                        ( MigrateV31.migrate_Types_FrontendMsg (V28.ShowAddSpendingDialog (Just legacySpendingReferenceV28))
                        , MigrateV31.migrate_Types_FrontendMsg (V28.ShowAddSpendingDialog Nothing)
                        , MigrateV31.migrate_Types_ToFrontend legacyGroupTransactionsPayloadV28
                        )
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


negativeTotalDialog : AddSpendingDialogModel
negativeTotalDialog =
    Frontend.emptySpendingDialog Nothing "Refund" "-10.00"
        |> Frontend.setSpendingDateValue sampleDate
        |> (\dialog ->
                { dialog
                    | credits = [ completeLine "Alice" "-10.00" ]
                    , debits = [ completeLine "Trip" "-10.00" ]
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
        , checked : Bool
        }
listedTransaction index year month day =
    { transactionId =
        { groupId = 0
        , year = year
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
    , checked = False
    }


listedTransactionItem : Int -> Int -> Int -> Int -> GroupTransactionListItem
listedTransactionItem index year month day =
    GroupTransactionRow (listedTransaction index year month day)


monthSummaryItem : Int -> Int -> Int -> GroupTransactionListItem
monthSummaryItem year month total =
    GroupTransactionMonthSummary
        { year = year
        , month = month
        , total = Amount total
        }


yearSummaryItem : Int -> Int -> GroupTransactionListItem
yearSummaryItem year total =
    GroupTransactionYearSummary
        { year = year
        , total = Amount total
        }


monthSectionedItems : List GroupTransactionListItem
monthSectionedItems =
    [ yearSummaryItem 2025 2500
    , monthSummaryItem 2025 5 500
    , listedTransactionItem 1 2025 5 3
    , listedTransactionItem 0 2025 5 1
    , monthSummaryItem 2025 4 2000
    , listedTransactionItem 2 2025 4 18
    , listedTransactionItem 1 2025 4 17
    , listedTransactionItem 0 2025 4 17
    ]


frontendGroupTransactionsState :
    { groupTransactionsLoading : Bool
    , groupTransactionsNextCursor : Maybe GroupTransactionsCursor
    , groupValidity : NameValidity
    }
frontendGroupTransactionsState =
    { groupTransactionsLoading = False
    , groupTransactionsNextCursor = Nothing
    , groupValidity = Complete
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


legacyFrontendDialogV28 : V28.AddSpendingDialogModel
legacyFrontendDialogV28 =
    { spendingId = Just 0
    , description = "Dinner"
    , total = "10.00"
    , date = Just sampleDate
    , today = Just sampleDate
    , dateText = "2025-04-18"
    , datePickerModel = DatePicker.init
    , credits = [ legacyTransactionLineV28 "Alice" ]
    , debits = [ legacyTransactionLineV28 "Trip" ]
    , submitted = False
    }


legacyFrontendDialogV31 : V31.AddSpendingDialogModel
legacyFrontendDialogV31 =
    { spendingId = Just 0
    , description = "Dinner"
    , total = "10.00"
    , date = Just sampleDate
    , today = Just sampleDate
    , dateText = "2025-04-18"
    , datePickerModel = DatePicker.init
    , credits = [ legacyTransactionLineV31 "Alice" ]
    , debits = [ legacyTransactionLineV31 "Trip" ]
    , submitted = False
    }


legacyTransactionIdV28 : V28.TransactionId
legacyTransactionIdV28 =
    { year = 2025
    , month = 4
    , day = 18
    , index = 0
    }


legacySpendingReferenceV28 : V28.SpendingReference
legacySpendingReferenceV28 =
    { spendingId = 0
    , transactionId = legacyTransactionIdV28
    }


legacyGroupTransactionsPayloadV28 : V28.ToFrontend
legacyGroupTransactionsPayloadV28 =
    V28.ListGroupTransactions
        { group = "Trip"
        , transactions =
            [ { transactionId = legacyTransactionIdV28
              , spendingId = 0
              , description = "Dinner"
              , year = 2025
              , month = 4
              , day = 18
              , total = V28.Amount 1000
              , share = V28.Amount 500
              }
            ]
        }


legacyTransactionLineV28 : String -> V28.TransactionLine
legacyTransactionLineV28 group =
    { date = Just sampleDate
    , dateText = "2025-04-18"
    , datePickerModel = DatePicker.init
    , secondaryDescription = ""
    , detailsExpanded = False
    , group = group
    , amount = "10.00"
    , nameValidity = V28.Complete
    }


legacyTransactionLineV31 : String -> V31.TransactionLine
legacyTransactionLineV31 group =
    { date = Just sampleDate
    , dateText = "2025-04-18"
    , datePickerModel = DatePicker.init
    , secondaryDescription = ""
    , detailsExpanded = False
    , group = group
    , amount = "10.00"
    , nameValidity = V31.Complete
    }
