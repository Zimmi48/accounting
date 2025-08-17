module Types exposing (..)

import Basics.Extra exposing (flip)
import Browser exposing (UrlRequest)
import Browser.Navigation exposing (Key)
import Codec exposing (Codec, Value)
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
    }


type Page
    = Home
    | Json (Maybe String)
    | Import String
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
    | ShowEditTransactionDialog TransactionId
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
    | UpdateJson String
    | RequestDeleteTransaction TransactionId
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
    | EditTransaction
        { transactionId : TransactionId
        , description : String
        , year : Int
        , month : Int
        , day : Int
        , total : Amount Credit
        , credits : Dict String (Amount Credit)
        , debits : Dict String (Amount Debit)
        }
    | DeleteTransaction TransactionId
    | RequestUserGroups String
    | RequestGroupTransactions String
    | RequestAllTransactions
    | CheckPassword String
    | CheckAuthentication
    | ImportJson String


type alias TransactionId =
    { year : Int
    , month : Int
    , day : Int
    , index : Int
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


type Dialog
    = AddPersonDialog AddPersonDialogModel
    | AddGroupDialog AddGroupDialogModel
    | AddSpendingDialog AddSpendingDialogModel
    | EditTransactionDialog EditTransactionDialogModel
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


type alias EditTransactionDialogModel =
    { transactionId : TransactionId
    , description : String
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
    
    -- status of the transaction
    , status : TransactionStatus
    }


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


encodeToString : BackendModel -> String
encodeToString model =
    Codec.encodeToString 0 backendCodec model


decodeString : String -> Result Codec.Error BackendModel
decodeString s =
    Codec.decodeString backendCodec s


backendCodec : Codec BackendModel
backendCodec =
    Codec.object BackendModel
        |> Codec.field
            "years"
            .years
            (Codec.map Dict.fromList Dict.toList (Codec.list (Codec.tuple Codec.int yearCodec)))
        |> Codec.field "groups" .groups (Codec.dict (Codec.dict shareCodec))
        |> Codec.field "totalGroupCredits" .totalGroupCredits (Codec.dict (Codec.dict amountCodec))
        |> Codec.field "persons" .persons (Codec.dict personCodec)
        |> Codec.field "nextPersonId" .nextPersonId Codec.int
        |> Codec.field "loggedInSessions" .loggedInSessions (Codec.set Codec.string)
        |> Codec.buildObject


yearCodec : Codec Year
yearCodec =
    Codec.object Year
        |> Codec.field
            "months"
            .months
            (Codec.map Dict.fromList Dict.toList (Codec.list (Codec.tuple Codec.int monthCodec)))
        |> Codec.field "totalGroupCredits" .totalGroupCredits (Codec.dict (Codec.dict amountCodec))
        |> Codec.buildObject


monthCodec : Codec Month
monthCodec =
    Codec.object Month
        |> Codec.field "days" .days (Codec.map Dict.fromList Dict.toList (Codec.list (Codec.tuple Codec.int dayCodec)))
        |> Codec.field "totalGroupCredits" .totalGroupCredits (Codec.dict (Codec.dict amountCodec))
        |> Codec.buildObject


dayCodec : Codec Day
dayCodec =
    Codec.object Day
        |> Codec.field "spendings" .spendings (Codec.list spendingCodec)
        |> Codec.field "totalGroupCredits" .totalGroupCredits (Codec.dict (Codec.dict amountCodec))
        |> Codec.buildObject


spendingCodec : Codec Spending
spendingCodec =
    Codec.object Spending
        |> Codec.field "description" .description Codec.string
        |> Codec.field "total" .total amountCodec
        |> Codec.field "groupCredits" .groupCredits (Codec.dict amountCodec)
        |> Codec.field "status" .status transactionStatusCodec
        |> Codec.buildObject


transactionStatusCodec : Codec TransactionStatus
transactionStatusCodec =
    Codec.custom
        (\activeEncoder deletedEncoder replacedEncoder value ->
            case value of
                Active ->
                    activeEncoder

                Deleted ->
                    deletedEncoder

                Replaced ->
                    replacedEncoder
        )
        |> Codec.variant0 "Active" Active
        |> Codec.variant0 "Deleted" Deleted
        |> Codec.variant0 "Replaced" Replaced
        |> Codec.buildCustom


amountCodec : Codec (Amount a)
amountCodec =
    Codec.custom
        (\amountEncoder value ->
            case value of
                Amount arg0 ->
                    amountEncoder arg0
        )
        |> Codec.variant1 "Amount" Amount Codec.int
        |> Codec.buildCustom


shareCodec : Codec Share
shareCodec =
    Codec.custom
        (\shareEncoder value ->
            case value of
                Share arg0 ->
                    shareEncoder arg0
        )
        |> Codec.variant1 "Share" Share Codec.int
        |> Codec.buildCustom


personCodec : Codec Person
personCodec =
    Codec.object Person
        |> Codec.field "id" .id Codec.int
        |> Codec.field "belongsTo" .belongsTo (Codec.set Codec.string)
        |> Codec.buildObject
