module LoggedIn exposing (Model, init, view, Msg, update)


import Html exposing (..)
import Html.Attributes exposing (..)
import Html.Events exposing (..)
import Json.Encode as Encode
import Json.Decode as Decode exposing ((:=))
import Task
import Http
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
      , div [ style [ ("text-align", "center") , ("margin", "10px 0") ] ]
          [ button
            [ onClick CreateTransaction
            , style
                [ ("background-color", "#4CAF50")
                , ("border", "none")
                , ("color", "white")
                , ("padding", "15px 32px")
                , ("text-align", "center")
                , ("font-weight", "bold")
                , ("display", "inline-block")
                , ("cursor", "pointer")
                ]
            ]
            [ text "Add new transaction" ]
          ]
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
  let width = toString (100 // List.length lines) ++ "%" in
  List.map (\e -> td [ style [ ("width", width) , ("padding", "3px 15px 0 5px") ] ] [e]) lines |> tr []


inputStyle : Attribute a
inputStyle =
  style
    [ ("width", "100%")
    , ("height", "30px")
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


-- if update returns Nothing, it means the connection has failed
update : Msg -> Model -> Maybe (Model, Cmd Msg)
update msg ({ newTransaction } as model) =
  case msg of
    UpdateObject s ->
      { model |
        newTransaction = { newTransaction | object = s }
      , recentError = Nothing
      } |> updateStandard

    UpdateValue s ->
      { model |
        newTransaction = { newTransaction | value = s }
      , recentError = Nothing
      } |> updateStandard

    UpdateDate s ->
      { model |
        newTransaction = { newTransaction | date = s }
      , recentError = Nothing
      } |> updateStandard

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

        Just
          ( { model | recentError = Nothing }
          , Task.perform Error CreatedTransaction
              <| createData model.session transactionTable transaction
          )

    CreatedTransaction () ->
      { model |
        transactions = model.newTransaction :: model.transactions
      , newTransaction = Transaction "" "" ""
      } |> updateStandard

    FetchTransactions t ->
      { model | transactions = t } |> updateStandard

    Error e ->
      case e of
        Kinvey.HttpError (Http.BadResponse 401 _) ->
          Nothing

        _ ->
          { model | recentError = Just e } |> updateStandard

    NoOp ->
      model |> updateStandard


updateStandard : a -> Maybe ( a, Cmd b )
updateStandard model = Just (model, Cmd.none)
