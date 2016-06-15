module LoggedIn exposing (Model, init, view, Msg, update)


import AddAccount
import AddContact
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
  , addContact : Maybe AddContact.Model
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
  , addContact = Nothing
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
        , text " " -- for spacing
        , successButton "Add a new contact" OpenAddContact True
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
        , viewDialog
            "Create a new account"          
            model.addAccount
            CloseAddAccount
            AddAccountMsg
            AddAccount.view
        , viewDialog
            "Add a new contact"
            model.addContact
            CloseAddContact
            AddContactMsg
            AddContact.view
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


viewDialog : String -> Maybe dialogModel -> msg -> (dialogMsg -> msg) -> (dialogModel -> Html dialogMsg) -> Html msg
viewDialog title model closeMsg forwardMsg view =
  Maybe.map
    (\model ->
       { closeMessage = Just closeMsg
       , header = Just (h4 [] [text title])
       , body = Just (App.map forwardMsg <| view model)
       , footer = Nothing
       }
    )
    model
  |> Dialog.view


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
  | OpenAddContact
  | CloseAddContact
  | AddContactMsg AddContact.Msg
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

    AddContactMsg msg ->
      case (Maybe.map (AddContact.update msg) model.addContact) of
        Just (addContact, Nothing) ->
          { model | addContact = Just addContact } |> updateStandard

        Just (addContact, Just contact) ->
          Just
            ( { model | addContact = Just addContact }
            , Cmd.none
            -- , Task.perform Error CreatedContact
            --   <| createData model.session contactTable decodeContact contact
            )

        Nothing ->
          model |> updateStandard

    OpenAddContact ->
      { model | addContact = Just AddContact.init } |> updateStandard

    CloseAddContact ->
      { model | addContact = Nothing } |> updateStandard

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
