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
                                    [ ( "Alice", { id = 0, belongsTo = Set.singleton 0 } )
                                    , ( "Bob", { id = 1, belongsTo = Set.singleton 1 } )
                                    ]
                            , nextId = 3
                            , groups =
                                Dict.fromList
                                    [ ( "Alice"
                                      , { id = 0
                                        , members = Dict.fromList [ ( "Alice", Share 1 ) ]
                                        , years = Dict.empty
                                        , totalCredit = Amount 0
                                        }
                                      )
                                    , ( "Bob"
                                      , { id = 1
                                        , members = Dict.fromList [ ( "Bob", Share 1 ) ]
                                        , years = Dict.empty
                                        , totalCredit = Amount 0
                                        }
                                      )
                                    , ( "Trip"
                                      , { id = 2
                                        , members = Dict.fromList [ ( "Alice", Share 1 ), ( "Bob", Share 1 ) ]
                                        , years = Dict.empty
                                        , totalCredit = Amount 0
                                        }
                                      )
                                    ]
                        }
                   )

        createdModel =
            case
                Backend.createSpendingInModel
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
            of
                Ok model ->
                    model

                Err errorMessage ->
                    Debug.todo errorMessage
    in
    deleteSpending 0 createdModel


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
