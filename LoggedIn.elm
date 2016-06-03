module LoggedIn exposing (Model, init, view, Msg, update)


import String
import Date exposing (Date)
import Date.Format as Date
import Time exposing (Time)
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
  , dateValue : String
  , recentError : String
  }


type alias Transaction =
  { object : String
  , value : Float
  , date : Date
  }


initTransaction : Transaction
initTransaction = Transaction "" 0 (Date.fromTime 0)


transactionTable : String
transactionTable = "transactions"


init : Session -> (Model, Cmd Msg)
init session =
  Model session [] initTransaction "" "" !
    [ Task.perform Error FetchTransactions
        <| getData session transactionTable
        <| Decode.object3 Transaction
            ("object" := Decode.string)
            ("value" := Decode.float)
            ("date" := Decode.customDecoder Decode.string Date.fromString)
    , Task.perform Error CurrentTime Time.now
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
                , onInput UpdateObject
                , value model.newTransaction.object
                ]
              , [ placeholder "Value"
                , type' "number"
                , onInput UpdateValue
                , value
                    ( if model.newTransaction.value == 0 then
                        ""
                        
                      else
                        toString model.newTransaction.value
                    )
                ]
              , [ placeholder "Date"
                , type' "date"
                , onInput UpdateDate
                , value model.dateValue
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
          [ text model.recentError
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
    , text (toString value)
    , text (Date.format "%e %b %Y" date)
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
  | CurrentTime Time
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
      , recentError = ""
      } |> updateStandard

    UpdateValue s ->
      case if String.isEmpty s then Ok 0 else String.toFloat s of
        Ok value ->
          if value > 0 || String.isEmpty s then
            { model |
              newTransaction = { newTransaction | value = value }
            , recentError = ""
            } |> updateStandard

          else
            { model |
              recentError = "Value should be a positive number"
            } |> updateStandard

        Err _ ->
          { model |
            recentError = "Value should be a positive number"
          } |> updateStandard

    UpdateDate s ->
      case
        if String.isEmpty s then
          Ok (Date.fromTime 0)

        else
          Date.fromString s
      of
        Ok date ->
          { model |
            newTransaction = { newTransaction | date = date }
          , dateValue = s
          , recentError = ""
          } |> updateStandard

        Err e ->
          Debug.log "wierd 2"
          { model |
            dateValue = s
          , recentError = e
          } |> updateStandard

    CurrentTime t ->
        if model.dateValue == "" then
          let today = Date.fromTime t in
          { model |
            newTransaction = { newTransaction | date = today }
          , dateValue = Date.format "%Y-%m-%d" today
          } |> updateStandard

        else
          model |> updateStandard

    CreateTransaction ->
      let
        transaction =
          Encode.object
            [ ("object", Encode.string model.newTransaction.object)
            , ("value", Encode.float model.newTransaction.value)
            , ( "date"
              , Encode.string
                  <| Date.formatISO8601 model.newTransaction.date
              )
            ]

      in

        Just
          ( { model | recentError = "" }
          , Task.perform Error CreatedTransaction
              <| createData model.session transactionTable transaction
          )

    CreatedTransaction () ->
      { model |
        transactions = model.newTransaction :: model.transactions
      , newTransaction = initTransaction
      } |> updateStandard

    FetchTransactions t ->
      { model | transactions = t } |> updateStandard

    Error e ->
      case e of
        Kinvey.HttpError (Http.BadResponse 401 _) ->
          Nothing

        _ ->
          { model
            | recentError = Kinvey.errorToString e
          } |> updateStandard

    NoOp ->
      model |> updateStandard


updateStandard : a -> Maybe ( a, Cmd b )
updateStandard model = Just (model, Cmd.none)
