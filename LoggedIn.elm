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
  , transactions : List (String, String, String)
  , object : String
  , value : String
  , date : String
  }


init : Session -> (Model, Cmd msg)
init session =
  Model session [] "" "" "" ! []
       

view : Model -> Html Msg
view model =
  let
    addTransaction =
      div []
        [ input
            [ placeholder "Object"
            , value model.object
            , onInput UpdateObject
            ] []
        , input
            [ placeholder "Value"
            , value model.value
            , type' "number"
            , onInput UpdateValue
            ] []
        , input
            [ type' "date"
            , value model.date
            , onInput UpdateDate
            ] []
        , button
            [ onClick CreateTransaction ]
            [ text "Add new transaction" ]
        ]

    listTransactions =
      div []
        [ text "List of recent transactions"
        ]

  in
    
  div []
    [ addTransaction
    , listTransactions
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
update msg model =
  case msg of
    UpdateObject s ->
      { model | object = s } ! []

    UpdateValue s ->
      { model | value = s } ! []

    UpdateDate s ->
      { model | date = s } ! []

    CreateTransaction ->
      let
        transaction =
          Encode.object
            [ ("object", Encode.string model.object)
            , ("value", Encode.string model.value) -- should be a float
            , ("date", Encode.string model.date)
            ]
          
      in
        
      model
        ! [ Task.perform Error CreatedTransaction
              <| createData model.session "transactions" transaction
          ]

    CreatedTransaction () ->
      { model |
        transactions =
          (model.object, model.value, model.date) :: model.transactions
      , object = ""
      , value = ""
      , date = ""
      } ! []

    _ ->
      model ! []
