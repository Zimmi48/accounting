module Types exposing (..)

import Browser exposing (UrlRequest)
import Browser.Navigation exposing (Key)
import Date exposing (Date)
import DatePicker
import Dict exposing (Dict)
import Set exposing (Set)
import Url exposing (Url)


type alias FrontendModel =
    { showDialog : Maybe Dialog
    , showSpendingFor : String
    , nameValidity : NameValidity
    , spendings : Maybe (List Spending)
    , key : Key
    }


type alias BackendModel =
    { years : Dict Int Year
    , groups : Dict String Group
    , accounts : Dict String Account
    , persons : Set String
    }


type FrontendMsg
    = UrlClicked UrlRequest
    | UrlChanged Url
    | NoOpFrontendMsg
    | ShowAddPersonDialog
    | ShowAddAccountDialog
    | ShowAddGroupDialog
    | ShowAddSpendingDialog
    | SetToday Date
    | Submit
    | Cancel
    | UpdateName String
    | AddOwnerOrMemberName String
    | UpdateOwnerOrMemberName Int String
    | UpdateOwnerOrMemberShare Int String
    | ChangeDatePicker DatePicker.ChangeEvent
    | UpdateTotalSpending String
    | AddGroupName String
    | UpdateGroupName Int String
    | UpdateGroupAmount Int String
    | AddAccountName String
    | UpdateAccountName Int String
    | UpdateAccountAmount Int String


type ToBackend
    = NoOpToBackend
    | CheckValidName String
    | AutocompletePerson String
    | AutocompleteGroup String
    | AutocompleteAccount String
    | AddPerson String
    | AddAccount String (Dict String Share)
    | AddGroup String (Dict String Share)
    | AddSpending
        { description : String
        , year : Int
        , month : Int
        , day : Int
        , totalSpending : Amount
        , groupSpendings : Dict String Amount
        , transactions : Dict String Amount
        }


type BackendMsg
    = NoOpBackendMsg


type ToFrontend
    = NoOpToFrontend
    | OperationSuccessful
    | NameAlreadyExists String
    | InvalidPersonPrefix String
    | AutocompletePersonPrefix
        { prefix : String
        , longestCommonPrefix : String
        , complete : Bool
        }
    | InvalidGroupPrefix String
    | AutocompleteGroupPrefix
        { prefix : String
        , longestCommonPrefix : String
        , complete : Bool
        }
    | InvalidAccountPrefix String
    | AutocompleteAccountPrefix
        { prefix : String
        , longestCommonPrefix : String
        , complete : Bool
        }


type Dialog
    = AddPersonDialog AddPersonDialogModel
    | AddAccountOrGroupDialog AddAccountOrGroupDialogModel
    | AddSpendingDialog AddSpendingDialogModel


type alias AddPersonDialogModel =
    { name : String
    , nameInvalid : Bool
    , submitted : Bool
    }


type alias AddAccountOrGroupDialogModel =
    { name : String
    , nameInvalid : Bool

    -- person name, share, name validity
    , ownersOrMembers : List ( String, String, NameValidity )
    , submitted : Bool
    , account : Bool
    }


type NameValidity
    = Complete
    | Incomplete
    | InvalidPrefix


type alias AddSpendingDialogModel =
    { description : String
    , date : Maybe Date
    , dateText : String
    , datePickerModel : DatePicker.Model
    , totalSpending : String

    -- group name, amount, name validity
    , groupSpendings : List ( String, String, NameValidity )

    -- account name, amount, name validity
    , transactions : List ( String, String, NameValidity )
    , submitted : Bool
    }


type alias Year =
    { months : Dict Int Month
    , totalGroupSpendings : Dict String Amount
    , totalAccountTransactions : Dict String Amount
    }


type alias Month =
    { spendings : List Spending
    , totalGroupSpendings : Dict String Amount
    , totalAccountTransactions : Dict String Amount
    }


type alias Spending =
    { description : String
    , day : Int

    -- total amount spent on this item
    , totalSpending : Amount

    -- associates each group with the shared spending in this item
    , groupSpendings : Dict String Amount

    -- associates each account with the amount spent on this item
    , transactions : Dict String Amount
    }


type alias Account =
    Dict String Share


type alias Group =
    Dict String Share


type Share
    = Share Int


type Amount
    = Amount Int
