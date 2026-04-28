module Evergreen.V26.Types exposing (..)

import Array
import Browser
import Browser.Navigation
import Date
import DatePicker
import Dict
import Lamdera
import Set
import Url


type Page
    = Home
    | Json (Maybe String)
    | Import String
    | NotFound


type alias AddPersonDialogModel =
    { name : String
    , nameInvalid : Bool
    , submitted : Bool
    }


type NameValidity
    = Complete
    | Incomplete
    | InvalidPrefix


type alias AddGroupDialogModel =
    { name : String
    , nameInvalid : Bool
    , members : List ( String, String, NameValidity )
    , submitted : Bool
    }


type alias SpendingId =
    Int


type alias TransactionLine =
    { date : Maybe Date.Date
    , dateText : String
    , datePickerModel : DatePicker.Model
    , secondaryDescription : String
    , detailsExpanded : Bool
    , group : String
    , amount : String
    , nameValidity : NameValidity
    }


type alias AddSpendingDialogModel =
    { spendingId : Maybe SpendingId
    , description : String
    , total : String
    , date : Maybe Date.Date
    , today : Maybe Date.Date
    , dateText : String
    , datePickerModel : DatePicker.Model
    , credits : List TransactionLine
    , debits : List TransactionLine
    , submitted : Bool
    }


type alias PasswordDialogModel =
    { password : String
    , submitted : Bool
    }


type Dialog
    = AddPersonDialog AddPersonDialogModel
    | AddGroupDialog AddGroupDialogModel
    | AddSpendingDialog AddSpendingDialogModel
    | ConfirmDeleteDialog SpendingId
    | PasswordDialog PasswordDialogModel


type Share
    = Share Int


type alias Group =
    Dict.Dict String Share


type Debit
    = Debit


type Amount a
    = Amount Int


type Credit
    = Credit


type alias TransactionId =
    { year : Int
    , month : Int
    , day : Int
    , index : Int
    }


type Theme
    = LightMode
    | DarkMode


type alias FrontendModel =
    { page : Page
    , showDialog : Maybe Dialog
    , errorMessage : Maybe String
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
            , spendingId : SpendingId
            , description : String
            , year : Int
            , month : Int
            , day : Int
            , total : Amount Debit
            , share : Amount Debit
            }
    , key : Browser.Navigation.Key
    , windowWidth : Int
    , windowHeight : Int
    , checkingAuthentication : Bool
    , theme : Theme
    }


type TransactionSide
    = CreditTransaction
    | DebitTransaction


type TransactionStatus
    = Active
    | Deleted
    | Replaced


type alias Transaction =
    { spendingId : SpendingId
    , secondaryDescription : String
    , group : String
    , amount : Amount ()
    , side : TransactionSide
    , groupMembersKey : String
    , groupMembers : Set.Set String
    , status : TransactionStatus
    }


type alias Day =
    { transactions : Array.Array Transaction
    , totalGroupCredits : Dict.Dict String (Dict.Dict String (Amount Credit))
    }


type alias Month =
    { days : Dict.Dict Int Day
    , totalGroupCredits : Dict.Dict String (Dict.Dict String (Amount Credit))
    }


type alias Year =
    { months : Dict.Dict Int Month
    , totalGroupCredits : Dict.Dict String (Dict.Dict String (Amount Credit))
    }


type alias Spending =
    { description : String
    , total : Amount Credit
    , transactionIds : List TransactionId
    , status : TransactionStatus
    }


type alias Person =
    { id : Int
    , belongsTo : Set.Set String
    }


type alias BackendModel =
    { years : Dict.Dict Int Year
    , spendings : Array.Array Spending
    , groups : Dict.Dict String Group
    , totalGroupCredits : Dict.Dict String (Dict.Dict String (Amount Credit))
    , persons : Dict.Dict String Person
    , nextPersonId : Int
    , loggedInSessions : Set.Set Lamdera.SessionId
    }


type alias SpendingReference =
    { spendingId : SpendingId
    , transactionId : TransactionId
    }


type FrontendMsg
    = UrlClicked Browser.UrlRequest
    | UrlChanged Url.Url
    | NoOpFrontendMsg
    | ShowAddPersonDialog
    | ShowAddGroupDialog
    | ShowAddSpendingDialog (Maybe SpendingReference)
    | ShowConfirmDeleteDialog SpendingId
    | ConfirmDeleteSpending SpendingId
    | SetToday Date.Date
    | Submit
    | Cancel
    | UpdateName String
    | AddMember String
    | UpdateMember Int String
    | UpdateShare Int String
    | UpdateSpendingDate DatePicker.ChangeEvent
    | UpdateSpendingTotal String
    | AddCreditor String
    | RemoveCredit Int
    | ToggleCreditDetails Int
    | UpdateCreditDate Int DatePicker.ChangeEvent
    | UpdateCreditSecondaryDescription Int String
    | UpdateCreditGroup Int String
    | UpdateCreditAmount Int String
    | AddDebitor String
    | RemoveDebit Int
    | ToggleDebitDetails Int
    | UpdateDebitDate Int DatePicker.ChangeEvent
    | UpdateDebitSecondaryDescription Int String
    | UpdateDebitGroup Int String
    | UpdateDebitAmount Int String
    | UpdateGroupName String
    | UpdatePassword String
    | UpdateJson String
    | ViewportChanged Int Int
    | ToggleTheme


type alias SpendingTransaction =
    { year : Int
    , month : Int
    , day : Int
    , secondaryDescription : String
    , group : String
    , amount : Amount ()
    , side : TransactionSide
    }


type ToBackend
    = NoOpToBackend
    | CheckValidName String
    | AutocompletePerson String
    | AutocompleteGroup String
    | CreatePerson String
    | CreateGroup String (Dict.Dict String Share)
    | CreateSpending
        { description : String
        , total : Amount Credit
        , transactions : List SpendingTransaction
        }
    | EditSpending
        { spendingId : SpendingId
        , description : String
        , total : Amount Credit
        , transactions : List SpendingTransaction
        }
    | DeleteSpending SpendingId
    | RequestSpendingDetails SpendingId
    | RequestUserGroups String
    | RequestGroupTransactions String
    | RequestAllTransactions
    | CheckPassword String
    | CheckAuthentication
    | ImportJson String


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
                , spendingId : SpendingId
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
    | SpendingError String
    | SpendingDetails
        { spendingId : SpendingId
        , description : String
        , total : Amount Credit
        , transactions : List SpendingTransaction
        }
