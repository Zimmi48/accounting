module LoggedIn exposing (Model, init, view, Msg, update)


import AddTransaction
import AddAccount
import Date.Format as Date
import Dialog
import Html exposing (..)
import Html.App as App
import Html.Attributes exposing (..)
import Html.Events exposing (..)
import Http
import Kinvey exposing (Session)
import Lib exposing (..)
import MyKinvey exposing (..)
import Positive
import Task


type alias Model =
  { session : Session
  , transactions : List Transaction
  , addTransaction : Maybe AddTransaction.Model
  , accounts : List Account
  , addAccount : Maybe AddAccount.Model
  , recentError : String
  }


transactionTable : String
transactionTable = "transactions"


accountTable : String
accountTable = "accounts"


init : Session -> (Model, Cmd Msg)
init session =
  { session = session
  , transactions = []
  , addTransaction = Nothing
  , accounts = []
  , addAccount = Nothing
  , recentError = ""
  } !
    [ Task.perform Error FetchTransactions
        <| getData session transactionTable (Kinvey.ReverseSort "date")
        <| decodeTransaction
    , Task.perform Error FetchAccounts
        <| getData session accountTable Kinvey.NoSort
        <| decodeAccount
    ]


view : Model -> Html Msg
view model =
  div []
    [ successButton "Add a new transaction" OpenAddTransaction
    , text " " -- for spacing
    , successButton "Create a new account" OpenAddAccount
    , div
        [ style [ ("color", "red") ] ]
        [ text model.recentError ]
    , h2 [] [ text "List of recent transactions" ]
    , div
        [ class "container" ]
        <| List.intersperse (hr [] [])
        <| List.map viewTransaction model.transactions
    , Dialog.view
      <| Maybe.map addTransactionIntoConfig model.addTransaction
    , Dialog.view
      <| Maybe.map addAccountIntoConfig model.addAccount
    ]


viewTransaction : Transaction -> Html msg
viewTransaction { object , value , date } =
  div
    [ class "row" ]
    [ div [ class "col-md-4" ] [ text object ]
    , div [ class "col-md-4" ] [ text (toString <| Positive.toNum value) ]
    , div [ class "col-md-4" ] [ text (Date.format "%e %b %Y" date) ]
    ]


successButton : String -> Msg -> Html Msg
successButton buttonText msg =
  button
    [ onClick msg
    , classList
        [ ("btn", True)
        , ("btn-success", True)
        ]
    ]
  [ text buttonText ]


addTransactionIntoConfig : AddTransaction.Model -> Dialog.Config Msg
addTransactionIntoConfig model =
  { closeMessage = Just CloseAddTransaction
  , header = Just (h4 [] [text "Add a new transaction"])
  , body = Just (App.map AddTransactionMsg <| AddTransaction.view model)
  , footer = Nothing
  }


addAccountIntoConfig : AddAccount.Model -> Dialog.Config Msg
addAccountIntoConfig model =
  { closeMessage = Just CloseAddAccount
  , header = Just (h4 [] [text "Create a new account"])
  , body = Just (App.map AddAccountMsg <| AddAccount.view model)
  , footer = Nothing
  }


type Msg
  = AddTransactionMsg AddTransaction.Msg
  | OpenAddTransaction
  | CloseAddTransaction
  | CreatedTransaction Transaction
  | FetchTransactions (List Transaction)
  | AddAccountMsg AddAccount.Msg
  | OpenAddAccount
  | CloseAddAccount
  | CreatedAccount Account
  | FetchAccounts (List Account)
  | Error Kinvey.Error


-- if update returns Nothing, it means the connection has failed
update : Msg -> Model -> Maybe (Model, Cmd Msg)
update msg model =
  case msg of
    AddTransactionMsg msg ->
      case Maybe.map (AddTransaction.update msg) model.addTransaction of
        Just (addTransaction, cmd, Nothing) ->
          Just
            ( { model | addTransaction = Just addTransaction }
            , Cmd.map AddTransactionMsg cmd
            )

        Just (addTransaction, cmd, Just newTransaction) ->
          Just
            ( { model |
                addTransaction = Just addTransaction
              , recentError = ""
              }
            ! [ Task.perform Error CreatedTransaction
                <| createData
                     model.session
                     transactionTable
                     decodeTransaction
                     newTransaction
              , Cmd.map AddTransactionMsg cmd
              ]
            )
            
        Nothing ->
          model |> updateStandard

    OpenAddTransaction ->
      let (addTransaction, cmd) = AddTransaction.init model.accounts in
      Just
        ( { model |
            addTransaction = Just addTransaction
          }
        , Cmd.map AddTransactionMsg cmd
        )

    CloseAddTransaction ->
      { model | addTransaction = Nothing } |> updateStandard

    CreatedTransaction transaction ->
      { model |
        transactions = transaction :: model.transactions
      , addTransaction = Nothing
      } |> updateStandard

    FetchTransactions t ->
      { model | transactions = t } |> updateStandard

    AddAccountMsg msg ->
      case (Maybe.map (AddAccount.update msg) model.addAccount) of
        Just (addAccountModel, Nothing) ->
          { model |
            addAccount = Just addAccountModel
          } |> updateStandard

        Just (addAccountModel, Just account) ->
          Just
            ( { model |
                addAccount = Just addAccountModel
              }
            , Task.perform Error CreatedAccount
              <| createData model.session accountTable decodeAccount account
            )

        Nothing ->
          model |> updateStandard
        
    OpenAddAccount ->
      { model | addAccount = Just AddAccount.init } |> updateStandard

    CloseAddAccount ->
      { model | addAccount = Nothing } |> updateStandard

    CreatedAccount account ->
      { model |
        accounts = model.accounts ++ [ account ]
      , addAccount = Nothing
      } |> updateStandard

    FetchAccounts a ->
      { model | accounts = a } |> updateStandard
    
    Error e ->
      case e of
        Kinvey.HttpError (Http.BadResponse 401 _) ->
          Nothing

        _ ->
          { model
            | recentError = Kinvey.errorToString e
          } |> updateStandard


updateStandard : a -> Maybe ( a, Cmd b )
updateStandard model = Just (model, Cmd.none)
