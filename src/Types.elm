module Types exposing (..)

import Basics.Extra exposing (flip)
import Browser exposing (UrlRequest)
import Browser.Navigation exposing (Key)
import Date exposing (Date)
import DatePicker
import Dict exposing (Dict)
import Lamdera exposing (SessionId)
import Set exposing (Set)
import Url exposing (Url)


type alias FrontendModel =
    { page : Page
    , showDialog : Maybe Dialog
    , user : String
    , nameValidity : NameValidity
    , userGroups :
        Maybe
            { debitors : List ( String, Group, Amount Debit )
            , creditors : List ( String, Group, Amount Credit )
            }
    , group : String
    , groupValidity : NameValidity
    , groupTransactions :
        List
            { transactionId : TransactionId
            , description : String
            , year : Int
            , month : Int
            , day : Int
            , total : Amount Debit
            , share : Amount Debit
            }
    , key : Key
    , windowWidth : Int
    , windowHeight : Int
    , checkingAuthentication : Bool
    , theme : Theme
    }


type Theme
    = LightMode
    | DarkMode


type Page
    = Home
    | Json (Maybe String)
    | Import String
    | NotFound


type alias BackendModel =
    { years : Dict Int Year
    , groups : Dict String Group

    -- person set -> group -> amount
    -- could be renamed to aggregatedSpendings
    , totalGroupCredits : Dict String (Dict String (Amount Credit))
    , persons : Dict String Person
    , nextPersonId : Int
    , loggedInSessions : Set SessionId
    }


type FrontendMsg
    = UrlClicked UrlRequest
    | UrlChanged Url
    | NoOpFrontendMsg
    | ShowAddPersonDialog
    | ShowAddGroupDialog
    | ShowAddSpendingDialog (Maybe TransactionId) -- Nothing for create, Just for edit
    | ShowConfirmDeleteDialog TransactionId
    | ConfirmDeleteTransaction TransactionId
    | SetToday Date
    | Submit
    | Cancel
    | UpdateName String
    | AddMember String
    | UpdateMember Int String
    | UpdateShare Int String
    | ChangeDatePicker DatePicker.ChangeEvent
    | UpdateTotal String
    | AddCreditor String
    | UpdateCreditor Int String
    | UpdateCredit Int String
    | AddDebitor String
    | UpdateDebitor Int String
    | UpdateDebit Int String
    | UpdateGroupName String
    | UpdatePassword String
    | UpdateJson String
    | ViewportChanged Int Int
    | ToggleTheme


type ToBackend
    = NoOpToBackend
    | CheckValidName String
    | AutocompletePerson String
    | AutocompleteGroup String
    | CreatePerson String
    | CreateGroup String (Dict String Share)
    | CreateSpending
        { description : String
        , year : Int
        , month : Int
        , day : Int
        , total : Amount Credit
        , credits : Dict String (Amount Credit)
        , debits : Dict String (Amount Debit)
        }
    | EditTransaction
        { transactionId : TransactionId
        , description : String
        , year : Int
        , month : Int
        , day : Int
        , total : Amount Credit
        , credits : Dict String (Amount Credit)
        , debits : Dict String (Amount Debit)
        }
    | DeleteTransaction TransactionId
    | RequestTransactionDetails TransactionId
    | RequestUserGroups String
    | RequestGroupTransactions String
    | RequestAllTransactions
    | CheckPassword String
    | CheckAuthentication
    | ImportJson String


type alias TransactionId =
    { year : Int
    , month : Int
    , day : Int
    , index : Int
    }


type BackendMsg
    = NoOpBackendMsg


type ToFrontend
    = NoOpToFrontend
    | OperationSuccessful
    | NameAlreadyExists String
    | InvalidPersonPrefix String
    | AutocompletePersonPrefix
        { prefixLower : String
        , longestCommonPrefix : String
        , complete : Bool
        }
    | InvalidGroupPrefix String
    | AutocompleteGroupPrefix
        { prefixLower : String
        , longestCommonPrefix : String
        , complete : Bool
        }
    | ListUserGroups
        { user : String
        , debitors : List ( String, Group, Amount Debit )
        , creditors : List ( String, Group, Amount Credit )
        }
    | ListGroupTransactions
        { group : String
        , transactions :
            List
                { transactionId : TransactionId
                , description : String
                , year : Int
                , month : Int
                , day : Int
                , total : Amount Debit
                , share : Amount Debit
                }
        }
    | AuthenticationStatus Bool
    | JsonExport String
    | TransactionError String
    | TransactionDetails
        { transactionId : TransactionId
        , description : String
        , year : Int
        , month : Int
        , day : Int
        , total : Amount Credit
        , credits : Dict String (Amount Credit)
        , debits : Dict String (Amount Debit)
        }


type Dialog
    = AddPersonDialog AddPersonDialogModel
    | AddGroupDialog AddGroupDialogModel
    | AddSpendingDialog AddSpendingDialogModel
    | ConfirmDeleteDialog TransactionId
    | PasswordDialog PasswordDialogModel


type alias AddPersonDialogModel =
    { name : String
    , nameInvalid : Bool
    , submitted : Bool
    }


type alias AddGroupDialogModel =
    { name : String
    , nameInvalid : Bool

    -- person name, share, name validity
    , members : List ( String, String, NameValidity )
    , submitted : Bool
    }


type alias PasswordDialogModel =
    { password : String
    , submitted : Bool
    }


type NameValidity
    = Complete
    | Incomplete
    | InvalidPrefix


type alias AddSpendingDialogModel =
    { transactionId : Maybe TransactionId -- Nothing for create, Just for edit
    , description : String
    , date : Maybe Date
    , dateText : String
    , datePickerModel : DatePicker.Model
    , total : String

    -- group name, amount, name validity
    , credits : List ( String, String, NameValidity )

    -- group name, amount, name validity
    , debits : List ( String, String, NameValidity )
    , submitted : Bool
    }


type alias Person =
    { id : Int
    , belongsTo : Set String
    }


type alias Year =
    { months : Dict Int Month
    , totalGroupCredits : Dict String (Dict String (Amount Credit))
    }


type alias Month =
    { days : Dict Int Day
    , totalGroupCredits : Dict String (Dict String (Amount Credit))
    }


type alias Day =
    { spendings : List Spending
    , totalGroupCredits : Dict String (Dict String (Amount Credit))
    }


type alias Spending =
    { description : String

    -- total amount of the transaction
    , total : Amount Credit

    -- groups that receive credit (positive amounts)
    , credits : Dict String (Amount Credit)

    -- groups that are debited (positive amounts, but semantically debits)
    , debits : Dict String (Amount Debit)

    -- status of the transaction
    , status : TransactionStatus
    }


type TransactionStatus
    = Active
    | Deleted
    | Replaced


type alias Group =
    Dict String Share


type Share
    = Share Int


type Amount a
    = Amount Int


type Credit
    = Credit


type Debit
    = Debit


addAmount : Int -> Maybe (Amount a) -> Maybe (Amount a)
addAmount value maybeAmount =
    case maybeAmount of
        Nothing ->
            Just (Amount value)

        Just (Amount amount) ->
            Just (Amount (amount + value))


addAmountToAmount : Amount a -> Amount a -> Amount a
addAmountToAmount (Amount a) (Amount b) =
    Amount (a + b)


addAmounts : Dict String (Amount a) -> Dict String (Amount a) -> Dict String (Amount a)
addAmounts =
    Dict.foldl
        (\key (Amount value) ->
            Dict.update key (addAmount value)
        )


toDebit : Amount Credit -> Amount Debit
toDebit (Amount value) =
    Amount -value


toCredit : Amount Debit -> Amount Credit
toCredit (Amount value) =
    Amount -value
