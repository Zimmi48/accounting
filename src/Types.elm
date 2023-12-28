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
    , userGroupsAndAccounts : Maybe ( List ( String, Group, Amount ), List ( String, Account, Amount ) )
    , key : Key
    }


type alias BackendModel =
    { years : Dict Int Year
    , groups : Dict String Group
    , totalGroupSpendings : Dict String TotalSpendings
    , accounts : Dict String Account
    , totalAccountTransactions : Dict String TotalSpendings
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
    | RequestUserGroupsAndAccounts String


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
    | ListUserGroupsAndAccounts
        { user : String
        , groups : List ( String, Group, Amount )
        , accounts : List ( String, Account, Amount )
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
    , totalGroupSpendings : Dict String TotalSpendings
    , totalAccountTransactions : Dict String TotalSpendings
    }


type alias Month =
    { spendings : List Spending
    , totalGroupSpendings : Dict String TotalSpendings
    , totalAccountTransactions : Dict String TotalSpendings
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


addAmount : Int -> Maybe Amount -> Maybe Amount
addAmount value maybeAmount =
    case maybeAmount of
        Nothing ->
            Just (Amount value)

        Just (Amount amount) ->
            Just (Amount (amount + value))


addAmounts : Dict String Amount -> Dict String Amount -> Dict String Amount
addAmounts =
    Dict.foldl
        (\key (Amount value) ->
            Dict.update key (addAmount value)
        )


type alias TotalSpendings =
    { groupAmounts : Dict String Amount
    , accountAmounts : Dict String Amount
    }


addToTotalSpendings :
    { a | groupSpendings : Dict String Amount, transactions : Dict String Amount }
    -> TotalSpendings
    -> TotalSpendings
addToTotalSpendings { groupSpendings, transactions } totalSpendings =
    { groupAmounts = addAmounts groupSpendings totalSpendings.groupAmounts
    , accountAmounts = addAmounts transactions totalSpendings.accountAmounts
    }


addToAllTotalGroupSpendings :
    { a | groupSpendings : Dict String Amount, transactions : Dict String Amount }
    -> Dict String TotalSpendings
    -> Dict String TotalSpendings
addToAllTotalGroupSpendings spendings totalGroupSpendings =
    let
        groupsToUpdate =
            Dict.keys spendings.groupSpendings
    in
    List.foldl
        (flip Dict.update
            (Maybe.map (addToTotalSpendings spendings)
                >> Maybe.withDefault
                    { groupAmounts = spendings.groupSpendings
                    , accountAmounts = spendings.transactions
                    }
                >> Just
            )
        )
        totalGroupSpendings
        groupsToUpdate


addToAllTotalAccountTransactions :
    { a | groupSpendings : Dict String Amount, transactions : Dict String Amount }
    -> Dict String TotalSpendings
    -> Dict String TotalSpendings
addToAllTotalAccountTransactions spendings totalAccountTransactions =
    let
        accountsToUpdate =
            Dict.keys spendings.transactions
    in
    List.foldl
        (flip Dict.update
            (Maybe.map (addToTotalSpendings spendings)
                >> Maybe.withDefault
                    { groupAmounts = spendings.groupSpendings
                    , accountAmounts = spendings.transactions
                    }
                >> Just
            )
        )
        totalAccountTransactions
        accountsToUpdate