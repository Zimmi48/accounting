module Evergreen.V8.Types exposing (..)

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


type alias AddSpendingDialogModel =
    { description : String
    , date : Maybe Date.Date
    , dateText : String
    , datePickerModel : DatePicker.Model
    , total : String
    , credits : List ( String, String, NameValidity )
    , debits : List ( String, String, NameValidity )
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
            { description : String
            , year : Int
            , month : Int
            , day : Int
            , total : Amount Debit
            , share : Amount Debit
            }
    , key : Browser.Navigation.Key
    , windowWidth : Int
    , windowHeight : Int
    }


type alias Spending =
    { description : String
    , total : Amount Credit
    , groupCredits : Dict.Dict String (Amount Credit)
    }


type alias Day =
    { spendings : List Spending
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


type alias Person =
    { id : Int
    , belongsTo : Set.Set String
    }


type alias BackendModel =
    { years : Dict.Dict Int Year
    , groups : Dict.Dict String Group
    , totalGroupCredits : Dict.Dict String (Dict.Dict String (Amount Credit))
    , persons : Dict.Dict String Person
    , nextPersonId : Int
    , loggedInSessions : Set.Set Lamdera.SessionId
    }


type FrontendMsg
    = UrlClicked Browser.UrlRequest
    | UrlChanged Url.Url
    | NoOpFrontendMsg
    | ShowAddPersonDialog
    | ShowAddGroupDialog
    | ShowAddSpendingDialog
    | SetToday Date.Date
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
    | ViewportChanged Int Int


type ToBackend
    = NoOpToBackend
    | CheckValidName String
    | AutocompletePerson String
    | AutocompleteGroup String
    | CreatePerson String
    | CreateGroup String (Dict.Dict String Share)
    | CreateSpending
        { description : String
        , year : Int
        , month : Int
        , day : Int
        , total : Amount Credit
        , credits : Dict.Dict String (Amount Credit)
        , debits : Dict.Dict String (Amount Debit)
        }
    | RequestUserGroups String
    | RequestGroupTransactions String
    | CheckPassword String


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
    | ListGroupTransactions
        { group : String
        , transactions :
            List
                { description : String
                , year : Int
                , month : Int
                , day : Int
                , total : Amount Debit
                , share : Amount Debit
                }
        }
