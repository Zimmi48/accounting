module LoggedIn exposing (Model, init, view, Msg, update)


import AddAccount
import AddButton
import AddContact
import AddTransaction
import Date.Format as Date
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
  , addAccount : AddButton.Model AddAccount.Model AddAccount.Msg Account
  , contacts : Maybe (List Contact)
  , addContact : AddButton.Model AddContact.Model AddContact.Msg Contact
  , recentError : String
  }


transactionTable : String
transactionTable = "transactions"


init : Session -> (Model, Cmd Msg)
init session =
  let
    (addContactModel, addContactCmd) =
      AddButton.init
        { session = session
        , table = "contacts"
        , decoder = decodeContact
        , title = "Add a new contact"
        , init = AddContact.init
        , update = AddContact.update
        , view = AddContact.view
        }

    (addAccountModel, addAccountCmd) =
      AddButton.init
        { session = session
        , table = "accounts"
        , decoder = decodeAccount
        , title = "Create a new account"
        , init = AddAccount.init
        , update = AddAccount.update
        , view = AddAccount.view
        }

  in
    
  { session = session
  , transactions = Nothing
  , addTransaction = Nothing
  , accounts = Nothing
  , selectedAccount = Nothing
  , selectedAccountValue = Nothing
  , addAccount = addAccountModel
  , contacts = Nothing
  , addContact = addContactModel
  , recentError = ""
  } !
    [ Task.perform Error FetchTransactions
        <| getData session transactionTable (Kinvey.ReverseSort "date")
        <| decodeTransaction
    , Cmd.map AddAccountMsg addAccountCmd
    , Cmd.map AddContactMsg addContactCmd
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
            (if existAccount then Just (OpenAddTransaction False) else Nothing)
        , text " " -- for spacing
        , successButton
            "Add a new income"
            (if existAccount then Just (OpenAddTransaction True) else Nothing)
        , text " " -- for spacing
        , AddButton.view model.addAccount |> App.map AddAccountMsg
        , text " " -- for spacing
        , AddButton.view model.addContact |> App.map AddContactMsg
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
        , viewDialog
            "Add a new transaction"
            model.addTransaction
            CloseAddTransaction
            AddTransactionMsg
            AddTransaction.view
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
  | AddAccountMsg (AddButton.Msg AddAccount.Msg Account)
  | UpdateSelectedAccount String
  | AddContactMsg (AddButton.Msg AddContact.Msg Contact)
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
      let (addAccount, cmd, ret) = AddButton.update msg model.addAccount in
      case ret of
        Nothing ->
          Just
            ( { model | addAccount = addAccount }
            , Cmd.map AddAccountMsg cmd
            )

        Just (Ok accounts) ->
          Just
            ( { model |
                addAccount = addAccount
              , accounts = Just accounts
              }
            , Cmd.map AddAccountMsg cmd
            )

        Just (Err (Kinvey.HttpError (Http.BadResponse 401 _))) ->
          Nothing

        Just (Err e) ->
          Just
            ( { model |
                addAccount = addAccount
              , recentError = Kinvey.errorToString e
              }
            , Cmd.map AddAccountMsg cmd
            )          

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

    AddContactMsg msg ->
      let (addContact, cmd, ret) = AddButton.update msg model.addContact in
      case ret of
        Nothing ->
          Just
            ( { model | addContact = addContact }
            , Cmd.map AddContactMsg cmd
            )

        Just (Ok contacts) ->
          Just
            ( { model |
                addContact = addContact
              , contacts = Just contacts
              }
            , Cmd.map AddContactMsg cmd
            )

        Just (Err (Kinvey.HttpError (Http.BadResponse 401 _))) ->
          Nothing

        Just (Err e) ->
          Just
            ( { model |
                addContact = addContact
              , recentError = Kinvey.errorToString e
              }
            , Cmd.map AddContactMsg cmd
            )          

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
