module CodecsTests exposing (suite)

{-| Import/export must preserve the backend model exactly. This regression test
keeps the JSON round-trip honest without touching live Lamdera persistence.
-}

import Backend
import Codecs
import Dict
import Expect
import Set
import Test exposing (..)
import Types exposing (..)


suite : Test
suite =
    describe "Backend model codecs"
        [ test "encodeToString followed by decodeString round-trips a populated model" <|
            \_ ->
                Expect.equal
                    (Ok roundTripModel)
                    (roundTripModel
                        |> Codecs.encodeToString
                        |> Codecs.decodeString
                    )
        ]


roundTripModel : Backend.Model
roundTripModel =
    let
        seededModel =
            Tuple.first Backend.init
                |> (\model ->
                        { model
                            | persons =
                                Dict.fromList
                                    [ ( 1, { name = "Alice", belongsTo = Set.empty } )
                                    , ( 2, { name = "Bob", belongsTo = Set.empty } )
                                    ]
                            , nextId = 4
                            , groups =
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
                                      , { name = "Trip"
                                        , members = Dict.fromList [ ( 1, Share 1 ), ( 2, Share 1 ) ]
                                        , years = Dict.empty
                                        , totalCredit = Amount 0
                                        }
                                      )
                                    ]
                        }
                   )

        createdModel =
            createSpending
                "Dinner"
                (Amount 1000)
                [ { year = 2025
                  , month = 4
                  , day = 18
                  , secondaryDescription = "Paid upfront"
                  , group = "Alice"
                  , amount = Amount 1000
                  , side = CreditTransaction
                  }
                , { year = 2025
                  , month = 4
                  , day = 18
                  , secondaryDescription = "Shared meal"
                  , group = "Trip"
                  , amount = Amount 1000
                  , side = DebitTransaction
                  }
                ]
                seededModel

        reconciledModel =
            case Backend.getSpendingTransactionsWithIds 0 createdModel |> List.head of
                Just ( transactionId, _ ) ->
                    Backend.toggleTransactionCheckedInModel transactionId createdModel

                Nothing ->
                    createdModel
    in
    deleteSpending 0 reconciledModel


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


createSpending : String -> Amount Credit -> List SpendingTransaction -> Backend.Model -> Backend.Model
createSpending description total transactions model =
    case Backend.createSpendingInModel description total transactions model of
        Ok updatedModel ->
            updatedModel

        Err errorMessage ->
            Debug.todo errorMessage
