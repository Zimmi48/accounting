module Types exposing (..)

import Array exposing (Array)
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
            , spendingId : SpendingId
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
    , spendings : Array Spending
    , groups : Dict String Group

    -- person set -> group -> amount
    -- could be renamed to aggregatedSpendings
    , totalGroupCredits : Dict String (Dict String (Amount Credit))
    , persons : Dict String Person
    , nextPersonId : Int
    , nextSpendingId : SpendingId
    , loggedInSessions : Set SessionId
    }


type FrontendMsg
    = UrlClicked UrlRequest
    | UrlChanged Url
    | NoOpFrontendMsg
    | ShowAddPersonDialog
    | ShowAddGroupDialog
    | ShowAddSpendingDialog (Maybe SpendingReference) -- Nothing for create, Just for edit
    | ShowConfirmDeleteDialog SpendingId
    | ConfirmDeleteSpending SpendingId
    | SetToday Date
    | Submit
    | Cancel
    | UpdateName String
    | AddMember String
    | UpdateMember Int String
    | UpdateShare Int String
    | UpdateSpendingDate DatePicker.ChangeEvent
    | UpdateSpendingTotal String
    | AddCredit
    | RemoveCredit Int
    | ToggleCreditDetails Int
    | UpdateCreditDate Int DatePicker.ChangeEvent
    | UpdateCreditSecondaryDescription Int String
    | UpdateCreditGroup Int String
    | UpdateCreditAmount Int String
    | AddDebit
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


type ToBackend
    = NoOpToBackend
    | CheckValidName String
    | AutocompletePerson String
    | AutocompleteGroup String
    | CreatePerson String
    | CreateGroup String (Dict String Share)
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


type alias SpendingId =
    Int


type alias TransactionId =
    { year : Int
    , month : Int
    , day : Int
    , index : Int
    }


type alias SpendingReference =
    { spendingId : SpendingId
    , transactionId : TransactionId
    }


type alias SpendingTransaction =
    { year : Int
    , month : Int
    , day : Int
    , secondaryDescription : String
    , group : String
    , amount : Amount ()
    , side : TransactionSide
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


type Dialog
    = AddPersonDialog AddPersonDialogModel
    | AddGroupDialog AddGroupDialogModel
    | AddSpendingDialog AddSpendingDialogModel
    | ConfirmDeleteDialog SpendingId
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
    { spendingId : Maybe SpendingId -- Nothing for create, Just for edit
    , description : String
    , total : String
    , date : Maybe Date
    , dateText : String
    , datePickerModel : DatePicker.Model
    , credits : List TransactionLine
    , debits : List TransactionLine
    , submitted : Bool
    }


type alias TransactionLine =
    { date : Maybe Date
    , dateText : String
    , datePickerModel : DatePicker.Model
    , secondaryDescription : String
    , detailsExpanded : Bool
    , group : String
    , amount : String
    , nameValidity : NameValidity
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
    { transactions : List Transaction
    , totalGroupCredits : Dict String (Dict String (Amount Credit))
    }


type alias Spending =
    { description : String
    , total : Amount Credit
    , transactionIds : List TransactionId

    -- status of the spending
    , status : TransactionStatus
    }


type alias Transaction =
    { id : TransactionId
    , spendingId : SpendingId
    , secondaryDescription : String
    , group : String
    , amount : Amount ()
    , side : TransactionSide
    , groupMembersKey : String
    , groupMembers : Set String
    , status : TransactionStatus
    }


type TransactionSide
    = CreditTransaction
    | DebitTransaction


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
