module LoggedIn exposing (Model, init, view, Msg, update)


import AddAccount
import AddTransaction
import Date.Format as Date
import Dialog
import Html exposing (..)
import Html.App as App
import Html.Attributes exposing (..)
import Html.Events exposing (..)
import Http
import Kinvey exposing (Session)
import Lib exposing (..)
import List.Extra as List
import MyKinvey exposing (..)
import Task


-- TODO : insert new transactions in the list depending on their date


type alias Model =
  { session : Session
  , transactions : Maybe (List Transaction)
  , addTransaction : Maybe AddTransaction.Model
  , accounts : Maybe (List Account)
  , selectedAccount : Maybe Account
  , selectedAccountValue : Maybe Float
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
  , transactions = Nothing
  , addTransaction = Nothing
  , accounts = Nothing
  , selectedAccount = Nothing
  , selectedAccountValue = Nothing
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
  let
    existAccount =
      Maybe.withDefault False
      <| Maybe.map (List.any (always True)) model.accounts
  in
  case (model.transactions, model.accounts) of
    (Just transactions, Just accounts) ->
      div []
        [ successButton
            "Add a new expense"
            (OpenAddTransaction False)
            existAccount
        , text " " -- for spacing
        , successButton
            "Add a new income"
             (OpenAddTransaction True)
             existAccount
        , text " " -- for spacing
        , successButton "Create a new account" OpenAddAccount True
        , div
            [ class "text-danger" ]
            [ text model.recentError ]
        , h2 [] [ text "List of recent transactions" ]
        , div
            [ class "row" ]
            [ accountSelector
                ({ name = "All accounts" , value = 0 , id = "" }
                :: accounts)
                UpdateSelectedAccount
                [ ("form-inline", True)
                , ("col-md-4", True)
                ]
            , div
                [ classList
                    [ ("col-md-4", True)
                    , ("h4", True)
                    ]
                ]
                [ text
                  <| Maybe.withDefault ""
                  <| Maybe.map (toString >> (++) "Total: ")
                  <| model.selectedAccountValue
                ]
            ]
        , div
            [ class "container" ]
            <| List.intersperse (hr [] [])
            <| List.map viewTransaction
            <| filterTransactions model.selectedAccount
            <| transactions
        , Dialog.view
          <| Maybe.map addTransactionIntoConfig model.addTransaction
        , Dialog.view
          <| Maybe.map addAccountIntoConfig model.addAccount
        ]

    _ ->
      div [ class "text-info" ] [ text "Loading" ]


viewTransaction : Transaction -> Html msg
viewTransaction { object , value , date } =
  div
    [ class "row" ]
    [ div [ class "col-md-4" ] [ text object ]
    , div [ class "col-md-4" ] [ text (toString value) ]
    , div [ class "col-md-4" ] [ text (Date.format "%e %b %Y" date) ]
    ]


successButton : String -> Msg -> Bool -> Html Msg
successButton buttonText msg enabled =
  button
    [ onClick msg
    , classList
        [ ("btn", True)
        , ("btn-success", True)
        ]
    , disabled (not enabled)
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


filterTransactions : Maybe Account -> List Transaction -> List Transaction
filterTransactions selected =
  case selected of
    Nothing ->
      identity

    Just { id } ->
      List.filter (.accountId >> (==) id)


accountValue : Account -> List Transaction -> Float
accountValue account =
  filterTransactions (Just account) >>
  List.foldl (.value >> (+)) account.value


type Msg
  = AddTransactionMsg AddTransaction.Msg
  | OpenAddTransaction Bool
  | CloseAddTransaction
  | CreatedTransaction Transaction
  | FetchTransactions (List Transaction)
  | AddAccountMsg AddAccount.Msg
  | OpenAddAccount
  | CloseAddAccount
  | CreatedAccount Account
  | FetchAccounts (List Account)
  | UpdateSelectedAccount String
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

    OpenAddTransaction income ->
      case model.accounts of
        Just accounts ->
          let (addTransaction, cmd) = AddTransaction.init income accounts in
          Just
          ( { model |
              addTransaction = Just addTransaction
            }
          , Cmd.map AddTransactionMsg cmd
          )

        Nothing ->
          model |> updateStandard

    CloseAddTransaction ->
      { model | addTransaction = Nothing } |> updateStandard

    CreatedTransaction transaction ->
      { model |
        transactions = Maybe.map ((::) transaction) model.transactions
      , addTransaction = Nothing
      , selectedAccountValue =
          case (model.selectedAccount, model.selectedAccountValue) of
            (Just account, Just value) ->
              if transaction.accountId == account.id then
                Just (value + transaction.value)
              else
                model.selectedAccountValue

            _ ->
              model.selectedAccountValue
      } |> updateStandard

    FetchTransactions t ->
      { model | transactions = Just t } |> updateStandard

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
        accounts =
          Maybe.map
            (\accounts -> accounts ++ [ account ])
            model.accounts
      , addAccount = Nothing
      } |> updateStandard

    FetchAccounts a ->
      { model | accounts = Just a } |> updateStandard


    UpdateSelectedAccount id ->
      let
        selectedAccount =
          model.accounts `Maybe.andThen`
          List.find (.id >> ((==) id))
       in
      { model |
        selectedAccount = selectedAccount
      , selectedAccountValue =
          Maybe.map2 accountValue selectedAccount model.transactions
      } |> updateStandard

    Error e ->
      case e of
        Kinvey.HttpError (Http.BadResponse 401 _) ->
          Nothing

        _ ->
          { model
            | recentError = Kinvey.errorToString e
          } |> updateStandard


updateStandard : a -> Maybe (a, Cmd b)
updateStandard model = Just (model, Cmd.none)
