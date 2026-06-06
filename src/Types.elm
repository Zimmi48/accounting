module Types exposing (..)

import Array exposing (Array)
import Basics.Extra exposing (flip)
import Browser exposing (UrlRequest)
import Browser.Dom
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
        List GroupTransactionListItem
    , groupTransactionsLoadedPages : Int
    , groupTransactionsNextCursor : Maybe GroupTransactionsCursor
    , groupTransactionsLoading : Bool
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
    { spendings : Array Spending
    , groups : Dict GroupId StoredGroup
    , persons : Dict PersonId Person
    , nextId : Int
    , totalGroupCredits : Dict String (Dict String (Amount Credit))
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
    | ToggleTransactionChecked TransactionId
    | ToggleGroupTransactionMonthFold GroupTransactionsCursor
    | SetToday Date
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
    | GroupTransactionsScrolled
        { scrollTop : Float
        , clientHeight : Float
        , scrollHeight : Float
        }
    | DialogMaskWheelScrolled Float
    | GroupTransactionsViewportChecked (Result Browser.Dom.Error Browser.Dom.Viewport)


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
    | RequestGroupTransactions
        { group : String
        , before : Maybe GroupTransactionsCursor
        , pages : Int
        }
    | ToggleTransactionCheckedRequest TransactionId
    | RequestAllTransactions
    | CheckPassword String
    | CheckAuthentication
    | ImportJson String


type alias SpendingId =
    Int


type alias TransactionId =
    { groupId : GroupId
    , year : Int
    , month : Int
    , day : Int
    , index : Int -- append-only slot for that day; writes must append to keep exact addressing stable
    }


type alias SpendingReference =
    { spendingId : SpendingId
    , transactionId : TransactionId
    }


type alias GroupTransactionsCursor =
    { year : Int
    , month : Int
    }


type alias GroupTransaction =
    { transactionId : TransactionId
    , spendingId : SpendingId
    , description : String
    , year : Int
    , month : Int
    , day : Int
    , total : Amount Debit
    , share : Amount Debit
    , checked : Bool
    }


type GroupTransactionListItem
    = GroupTransactionRow GroupTransaction
    | GroupTransactionMonthSummary
        { year : Int
        , month : Int
        , total : Amount Debit
        }
    | GroupTransactionYearSummary
        { year : Int
        , total : Amount Debit
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
        , before : Maybe GroupTransactionsCursor
        , pagesLoaded : Int
        , nextCursor : Maybe GroupTransactionsCursor
        , items : List GroupTransactionListItem
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
    , today : Maybe Date
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
    { name : String
    , belongsTo : Set String
    }


type alias Year =
    { months : Dict Int Month
    , totalCredit : Amount Credit
    }


type alias Month =
    { days : Dict Int Day
    , totalCredit : Amount Credit
    }


type alias Day =
    { transactions : Array Transaction
    , totalCredit : Amount Credit
    }


type alias Spending =
    { description : String
    , total : Amount Credit
    , transactionIds : List TransactionId
    , status : TransactionStatus
    }


type alias Transaction =
    { spendingId : SpendingId
    , secondaryDescription : String
    , group : String
    , amount : Amount ()
    , side : TransactionSide
    , groupMembersKey : String
    , groupMembers : Set String
    , status : TransactionStatus
    , checked : Bool
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


type alias StoredGroupMembers =
    Dict PersonId Share


type alias PersonId =
    Int


type alias GroupId =
    Int


type alias StoredGroup =
    { name : String
    , members : StoredGroupMembers
    , years : Dict Int Year
    , totalCredit : Amount Credit
    }


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
