module Types exposing (..)

import Browser exposing (UrlRequest)
import Browser.Navigation exposing (Key)
import Dict exposing (Dict)
import Url exposing (Url)


type alias FrontendModel =
    { showDialog : Maybe Dialog
    , key : Key
    }


type alias BackendModel =
    { years : Dict String Year
    , groups : Dict String Group
    , accounts : Dict String Account
    , persons : List String
    }


type FrontendMsg
    = UrlClicked UrlRequest
    | UrlChanged Url
    | NoOpFrontendMsg
    | ShowDialog Dialog
    | Submit
    | Cancel
    | UpdateName String


type ToBackend
    = NoOpToBackend


type BackendMsg
    = NoOpBackendMsg


type ToFrontend
    = NoOpToFrontend


type Dialog
    = AddPersonDialog AddPersonDialogModel
    | AddAccountDialog AddAccountDialogModel
    | AddGroupDialog AddGroupDialogModel
    | AddSpendingDialog AddSpendingDialogModel


type alias AddPersonDialogModel =
    { name : String
    }


type alias AddAccountDialogModel =
    { name : String
    , owner : String
    , bank : String
    }


type alias AddGroupDialogModel =
    { name : String
    , members : List ( String, Int )
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
    }


type alias Year =
    { months : Dict Int Month
    , totalSharedSpending : Dict String Int
    , totalPersonalSpending : Dict String Int
    , totalAccountTransactions : Dict String Int
    }


type alias Month =
    { spendings : List Spending
    , totalSharedSpending : Dict String Int
    , totalPersonalSpending : Dict String Int
    , totalAccountTransactions : Dict String Int
    }


type alias Spending =
    { description : String
    , day : Int

    -- total amount spent on this item
    , totalSpending : Int

    -- associates each group with the shared spending in this item
    , sharedSpending : Dict String Int

    -- associates each person with the personal share in this item
    , personalSpending : Dict String Int

    -- associates each account with the amount spent on this item
    , transactions : Dict String Int
    }


type alias Account =
    { owner : String
    , bank : String
    }


type alias Group =
    Dict String Int
