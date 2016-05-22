module LoggedIn exposing (Model, init, view, Msg, update)


import Html exposing (..)
import Html.Attributes exposing (..)
import Html.Events exposing (..)
import Json.Encode as Encode
import Task
import Kinvey exposing (Session)
import MyKinvey exposing (..)


type alias Model =
  { session : Session
  , transactions : List Transaction
  , newTransaction : Transaction
  , recentError : Maybe Kinvey.Error
  }


type alias Transaction =
  { object : String
  , value : String
  , date : String
  }


init : Session -> (Model, Cmd msg)
init session =
  Model session [] (Transaction "" "" "") Nothing ! []
       

view : Model -> Html Msg
view model =
  let
    addTransaction =
      div []
        [ input
            [ placeholder "Object"
            , value model.newTransaction.object
            , onInput UpdateObject
            ] []
        , input
            [ placeholder "Value"
            , value model.newTransaction.value
            , type' "number"
            , onInput UpdateValue
            ] []
        , input
            [ type' "date"
            , value model.newTransaction.date
            , onInput UpdateDate
            ] []
        , button
            [ onClick CreateTransaction ]
            [ text "Add new transaction" ]
        ]

    listTransactions =
      div []
        [ text "List of recent transactions"
        , div [] <| List.map viewTransaction model.transactions
        ]

  in
    
  div []
    [ addTransaction
    , div [ style [ ("color", "red") ] ]
        [ text
            <| Maybe.withDefault ""
            <| Maybe.map Kinvey.errorToString model.recentError
        ]
    , listTransactions
    ]


viewTransaction : Transaction -> Html msg
viewTransaction { object , value , date } =
  div []
    [ text object
    , text value
    , text date
    ]
                    
type Msg
  = NoOp
  | UpdateObject String
  | UpdateValue String
  | UpdateDate String
  | CreateTransaction
  | CreatedTransaction ()
  | Error Kinvey.Error

    
update : Msg -> Model -> (Model, Cmd Msg)
update msg ({ newTransaction } as model) =
  case msg of
    UpdateObject s ->
      { model |
        newTransaction = { newTransaction | object = s }
      , recentError = Nothing
      } ! []

    UpdateValue s ->
      { model |
        newTransaction = { newTransaction | value = s }
      , recentError = Nothing
      } ! []

    UpdateDate s ->
      { model |
        newTransaction = { newTransaction | date = s }
      , recentError = Nothing
      } ! []

    CreateTransaction ->
      let
        transaction =
          Encode.object
            [ ("object", Encode.string model.newTransaction.object)
            , ("value", Encode.string model.newTransaction.value)
            -- should be a float
            , ("date", Encode.string model.newTransaction.date)
            ]
          
      in
        
      { model | recentError = Nothing }
        ! [ Task.perform Error CreatedTransaction
              <| createData model.session "transactions" transaction
          ]

    CreatedTransaction () ->
      { model |
        transactions = model.newTransaction :: model.transactions
      , newTransaction = Transaction "" "" ""
      } ! []

    Error e ->
      { model | recentError = Just e } ! []

    NoOp ->
      model ! []
