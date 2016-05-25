module LoggedIn exposing (Model, init, view, Msg, update)


import Html exposing (..)
import Html.Attributes exposing (..)
import Html.Events exposing (..)
import Json.Encode as Encode
import Json.Decode as Decode exposing ((:=))
import Task
import Kinvey exposing (Session)
import MyKinvey exposing (..)


-- TODO : always check for HTTP 401 Unauthorized response and go back
-- to Login page when it occurs


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


transactionTable : String
transactionTable = "transactions"


init : Session -> (Model, Cmd Msg)
init session =
  Model session [] (Transaction "" "" "") Nothing !
    [ Task.perform Error FetchTransactions
        <| getData session transactionTable
        <| Decode.object3 Transaction
            ("object" := Decode.string)
            ("value" := Decode.string)
            ("date" := Decode.string)
    ]


view : Model -> Html Msg
view model =
  let
    addTransaction =
      [ table
          [ style
              [ ("width", "100%")
              ]
          ]
          [ (List.map (\attrs -> input (inputStyle :: attrs) []) >> tr')
              [ [ placeholder "Object"
                , value model.newTransaction.object
                , onInput UpdateObject
                ]
              , [ placeholder "Value"
                , value model.newTransaction.value
                , type' "number"
                , onInput UpdateValue
                ]
              , [ placeholder "Date"
                , value model.newTransaction.date
                , type' "date"
                , onInput UpdateDate
                ]
              ]
          ]
      , button
          [ onClick CreateTransaction ]
          [ text "Add new transaction" ]
      , div [ style [ ("color", "red") ] ]
          [ text
              <| Maybe.withDefault ""
              <| Maybe.map Kinvey.errorToString model.recentError
          ]
      ]

    listTransactions =
      [ h2 [] [ text "List of recent transactions" ]
      , table
          [ style
              [ ("width", "100%")
              , ("border", "1px solid black")
              ]
          ]
          <| List.map viewTransaction model.transactions
      ]

  in

  div [] ( addTransaction ++ listTransactions )


viewTransaction : Transaction -> Html msg
viewTransaction { object , value , date } =
  tr'
    [ text object
    , text value
    , text date
    ]


-- tr' puts each element of the list into a td node and the whole thing into
-- a tr node
tr' : List (Html a) -> Html a
tr' lines =
  List.map (\e -> td [ style [ ("width", "30%") ] ] [e]) lines |> tr []


inputStyle : Attribute a
inputStyle =
  style
    [ ("width", "90%")
    ]

    
type Msg
  = NoOp
  | UpdateObject String
  | UpdateValue String
  | UpdateDate String
  | CreateTransaction
  | CreatedTransaction ()
  | FetchTransactions (List Transaction)
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
              <| createData model.session transactionTable transaction
          ]

    CreatedTransaction () ->
      { model |
        transactions = model.newTransaction :: model.transactions
      , newTransaction = Transaction "" "" ""
      } ! []

    FetchTransactions t ->
      { model | transactions = t } ! []

    Error e ->
      { model | recentError = Just e } ! []

    NoOp ->
      model ! []
