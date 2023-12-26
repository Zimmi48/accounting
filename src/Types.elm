module Types exposing (..)

import Browser exposing (UrlRequest)
import Browser.Navigation exposing (Key)
import Dict exposing (Dict)
import Set exposing (Set)
import Url exposing (Url)


type alias FrontendModel =
    { showDialog : Maybe Dialog
    , key : Key
    }


type alias BackendModel =
    { years : Dict String Year
    , groups : Dict String Group
    , accounts : Dict String Account
    , persons : Set String
    }


type FrontendMsg
    = UrlClicked UrlRequest
    | UrlChanged Url
    | NoOpFrontendMsg
    | ShowDialog Dialog
    | Submit
    | Cancel
    | UpdateName String
      -- index, name, share
    | UpdateOwnerOrMember Int String String


type ToBackend
    = NoOpToBackend
    | CheckNoPerson String
    | CheckNoAccount String
    | CheckNoGroup String
    | AddPerson String
    | AddAccount String (Dict String Share)
    | AddGroup String (Dict String Share)


type BackendMsg
    = NoOpBackendMsg


type ToFrontend
    = NoOpToFrontend
    | OperationSuccessful
    | PersonAlreadyExists String
    | AccountAlreadyExists String
    | GroupAlreadyExists String


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
    , ownersOrMembers : List ( String, String )
    , submitted : Bool
    , account : Bool
    }


type alias AddSpendingDialogModel =
    { description : String
    , day : Int
    , month : Int
    , year : Int
    , totalSpending : Int
    , sharedSpending : List ( String, Int )
    , personalSpending : List ( String, Int )
    , transactions : List ( String, Int )
    , submitted : Bool
    }


type alias Year =
    { months : Dict Int Month
    , totalSharedSpending : Dict String Amount
    , totalPersonalSpending : Dict String Amount
    , totalAccountTransactions : Dict String Amount
    }


type alias Month =
    { spendings : List Spending
    , totalSharedSpending : Dict String Amount
    , totalPersonalSpending : Dict String Amount
    , totalAccountTransactions : Dict String Amount
    }


type alias Spending =
    { description : String
    , day : Int

    -- total amount spent on this item
    , totalSpending : Amount

    -- associates each group with the shared spending in this item
    , sharedSpending : Dict String Amount

    -- associates each person with the personal share in this item
    , personalSpending : Dict String Amount

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
