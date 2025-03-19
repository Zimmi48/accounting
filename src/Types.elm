module Types exposing (..)

import Basics.Extra exposing (flip)
import Browser exposing (UrlRequest)
import Browser.Navigation exposing (Key)
import Date exposing (Date)
import DatePicker
import Dict exposing (Dict)
import Json.Encode
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
            { description : String
            , year : Int
            , month : Int
            , day : Int
            , total : Amount Debit
            , share : Amount Debit
            }
    , key : Key
    , windowWidth : Int
    , windowHeight : Int
    }


type Page
    = Home
    | Json (Maybe String)
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
    | UpdateGroupName String
    | UpdatePassword String
    | ViewportChanged Int Int


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
    | RequestGroupTransactions String
    | RequestAllTransactions
    | CheckPassword String


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
                { description : String
                , year : Int
                , month : Int
                , day : Int
                , total : Amount Debit
                , share : Amount Debit
                }
        }
    | JsonExport String


type Dialog
    = AddPersonDialog AddPersonDialogModel
    | AddGroupDialog AddGroupDialogModel
    | AddSpendingDialog AddSpendingDialogModel
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


toDebit : Amount Credit -> Amount Debit
toDebit (Amount value) =
    Amount -value


toCredit : Amount Debit -> Amount Credit
toCredit (Amount value) =
    Amount -value


toJsonExport : BackendModel -> Json.Encode.Value
toJsonExport model =
    Json.Encode.object
        [ ( "years", Json.Encode.dict (Json.Encode.int >> Json.Encode.encode 0) encodeYear model.years )
        , ( "groups", Json.Encode.dict identity (Json.Encode.dict identity encodeShare) model.groups )
        , ( "totalGroupCredits"
          , Json.Encode.dict identity (Json.Encode.dict identity encodeAmount) model.totalGroupCredits
          )
        , ( "persons", Json.Encode.dict identity encodePerson model.persons )
        , ( "nextPersonId", Json.Encode.int model.nextPersonId )
        , ( "loggedInSessions", Json.Encode.set Json.Encode.string model.loggedInSessions )
        ]


encodeYear : Year -> Json.Encode.Value
encodeYear rec =
    Json.Encode.object
        [ ( "months", Json.Encode.dict (Json.Encode.int >> Json.Encode.encode 0) encodeMonth rec.months )
        , ( "totalGroupCredits"
          , Json.Encode.dict identity (Json.Encode.dict identity encodeAmount) rec.totalGroupCredits
          )
        ]


encodeMonth : Month -> Json.Encode.Value
encodeMonth rec =
    Json.Encode.object
        [ ( "days", Json.Encode.dict (Json.Encode.int >> Json.Encode.encode 0) encodeDay rec.days )
        , ( "totalGroupCredits"
          , Json.Encode.dict identity (Json.Encode.dict identity encodeAmount) rec.totalGroupCredits
          )
        ]


encodeDay : Day -> Json.Encode.Value
encodeDay rec =
    Json.Encode.object
        [ ( "spendings", Json.Encode.list encodeSpending rec.spendings )
        , ( "totalGroupCredits"
          , Json.Encode.dict identity (Json.Encode.dict identity encodeAmount) rec.totalGroupCredits
          )
        ]


encodeSpending : Spending -> Json.Encode.Value
encodeSpending rec =
    Json.Encode.object
        [ ( "description", Json.Encode.string rec.description )
        , ( "total", encodeAmount rec.total )
        , ( "groupCredits", Json.Encode.dict identity encodeAmount rec.groupCredits )
        ]


encodeAmount : Amount a -> Json.Encode.Value
encodeAmount arg =
    case arg of
        Amount arg0 ->
            Json.Encode.object [ ( "tag", Json.Encode.string "Amount" ), ( "0", Json.Encode.int arg0 ) ]


encodeShare : Share -> Json.Encode.Value
encodeShare arg =
    case arg of
        Share arg0 ->
            Json.Encode.object [ ( "tag", Json.Encode.string "Share" ), ( "0", Json.Encode.int arg0 ) ]


encodePerson : Person -> Json.Encode.Value
encodePerson rec =
    Json.Encode.object
        [ ( "id", Json.Encode.int rec.id ), ( "belongsTo", Json.Encode.set Json.Encode.string rec.belongsTo ) ]
