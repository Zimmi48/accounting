module Types exposing (..)

import Basics.Extra exposing (flip)
import Browser exposing (UrlRequest)
import Browser.Navigation exposing (Key)
import Date exposing (Date)
import DatePicker
import Dict exposing (Dict)
import Set exposing (Set)
import Url exposing (Url)


type alias FrontendModel =
    { showDialog : Maybe Dialog
    , user : String
    , nameValidity : NameValidity
    , userGroups :
        Maybe
            { debitors : List ( String, Group, Amount Debit )
            , creditors : List ( String, Group, Amount Credit )
            }
    , key : Key
    }


type alias BackendModel =
    { years : Dict Int Year
    , groups : Dict String Group

    -- person set -> group -> amount
    -- could be renamed to aggregatedSpendings
    , totalGroupCredits : Dict String (Dict String (Amount Credit))
    , persons : Dict String Person
    , nextPersonId : Int
    }


type FrontendMsg
    = UrlClicked UrlRequest
    | UrlChanged Url
    | NoOpFrontendMsg
    | ShowAddPersonDialog
    | ShowAddGroupDialog
    | ShowAddSpendingDialog
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
    | RequestUserGroups String


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
    | ListUserGroups
        { user : String
        , debitors : List ( String, Group, Amount Debit )
        , creditors : List ( String, Group, Amount Credit )
        }


type Dialog
    = AddPersonDialog AddPersonDialogModel
    | AddGroupDialog AddGroupDialogModel
    | AddSpendingDialog AddSpendingDialogModel


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


type NameValidity
    = Complete
    | Incomplete
    | InvalidPrefix


type alias AddSpendingDialogModel =
    { description : String
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
    { spendings : List Spending
    , totalGroupCredits : Dict String (Dict String (Amount Credit))
    }


type alias Spending =
    { description : String
    , day : Int

    -- total amount of the transaction
    , total : Amount Credit

    -- associates each group with an amount (credit = positive or debit = negative) in this transaction
    , groupCredits : Dict String (Amount Credit)
    }


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


addAmounts : Dict String (Amount a) -> Dict String (Amount a) -> Dict String (Amount a)
addAmounts =
    Dict.foldl
        (\key (Amount value) ->
            Dict.update key (addAmount value)
        )
