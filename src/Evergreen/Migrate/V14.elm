module Evergreen.Migrate.V14 exposing (..)

import Dict
import Evergreen.V13.Types
import Evergreen.V14.Types
import Lamdera.Migrations exposing (..)


frontendModel : Evergreen.V13.Types.FrontendModel -> ModelMigration Evergreen.V14.Types.FrontendModel Evergreen.V14.Types.FrontendMsg
frontendModel old =
    ModelMigrated
        { page = old.page |> migrate_Types_Page
        , showDialog = old.showDialog |> Maybe.map migrate_Types_Dialog
        , user = old.user
        , nameValidity = old.nameValidity |> migrate_Types_NameValidity
        , userGroups = old.userGroups |> Maybe.map migrate_UserGroups
        , group = old.group
        , groupValidity = old.groupValidity |> migrate_Types_NameValidity
        , groupTransactions = old.groupTransactions |> List.map migrate_GroupTransaction
        , key = old.key
        , windowWidth = old.windowWidth
        , windowHeight = old.windowHeight
        , isLoggedIn = False
        , loginCheckCompleted = False
        }


backendModel : Evergreen.V13.Types.BackendModel -> ModelMigration Evergreen.V14.Types.BackendModel Evergreen.V14.Types.BackendMsg
backendModel old =
    ModelMigrated
        { years = old.years |> Dict.map (\_ -> migrate_Types_Year)
        , groups = old.groups |> Dict.map (\_ -> migrate_Types_Group)
        , totalGroupCredits = old.totalGroupCredits |> Dict.map (\_ -> Dict.map (\_ -> migrate_Types_Amount))
        , persons = old.persons |> Dict.map (\_ -> migrate_Types_Person)
        , nextPersonId = old.nextPersonId
        , loggedInSessions = old.loggedInSessions
        }


frontendMsg : Evergreen.V13.Types.FrontendMsg -> MsgMigration Evergreen.V14.Types.FrontendMsg Evergreen.V14.Types.FrontendMsg
frontendMsg old =
    MsgMigrated <|
        case old of
            Evergreen.V13.Types.UrlClicked p0 ->
                Evergreen.V14.Types.UrlClicked p0

            Evergreen.V13.Types.UrlChanged p0 ->
                Evergreen.V14.Types.UrlChanged p0

            Evergreen.V13.Types.NoOpFrontendMsg ->
                Evergreen.V14.Types.NoOpFrontendMsg

            Evergreen.V13.Types.ShowAddPersonDialog ->
                Evergreen.V14.Types.ShowAddPersonDialog

            Evergreen.V13.Types.ShowAddGroupDialog ->
                Evergreen.V14.Types.ShowAddGroupDialog

            Evergreen.V13.Types.ShowAddSpendingDialog ->
                Evergreen.V14.Types.ShowAddSpendingDialog

            Evergreen.V13.Types.SetToday p0 ->
                Evergreen.V14.Types.SetToday p0

            Evergreen.V13.Types.Submit ->
                Evergreen.V14.Types.Submit

            Evergreen.V13.Types.Cancel ->
                Evergreen.V14.Types.Cancel

            Evergreen.V13.Types.UpdateName p0 ->
                Evergreen.V14.Types.UpdateName p0

            Evergreen.V13.Types.AddMember p0 ->
                Evergreen.V14.Types.AddMember p0

            Evergreen.V13.Types.UpdateMember p0 p1 ->
                Evergreen.V14.Types.UpdateMember p0 p1

            Evergreen.V13.Types.UpdateShare p0 p1 ->
                Evergreen.V14.Types.UpdateShare p0 p1

            Evergreen.V13.Types.ChangeDatePicker p0 ->
                Evergreen.V14.Types.ChangeDatePicker p0

            Evergreen.V13.Types.UpdateTotal p0 ->
                Evergreen.V14.Types.UpdateTotal p0

            Evergreen.V13.Types.AddCreditor p0 ->
                Evergreen.V14.Types.AddCreditor p0

            Evergreen.V13.Types.UpdateCreditor p0 p1 ->
                Evergreen.V14.Types.UpdateCreditor p0 p1

            Evergreen.V13.Types.UpdateCredit p0 p1 ->
                Evergreen.V14.Types.UpdateCredit p0 p1

            Evergreen.V13.Types.AddDebitor p0 ->
                Evergreen.V14.Types.AddDebitor p0

            Evergreen.V13.Types.UpdateDebitor p0 p1 ->
                Evergreen.V14.Types.UpdateDebitor p0 p1

            Evergreen.V13.Types.UpdateDebit p0 p1 ->
                Evergreen.V14.Types.UpdateDebit p0 p1

            Evergreen.V13.Types.UpdateGroupName p0 ->
                Evergreen.V14.Types.UpdateGroupName p0

            Evergreen.V13.Types.UpdatePassword p0 ->
                Evergreen.V14.Types.UpdatePassword p0

            Evergreen.V13.Types.UpdateJson p0 ->
                Evergreen.V14.Types.UpdateJson p0

            Evergreen.V13.Types.ViewportChanged p0 p1 ->
                Evergreen.V14.Types.ViewportChanged p0 p1


toBackend : Evergreen.V13.Types.ToBackend -> MsgMigration Evergreen.V14.Types.ToBackend Evergreen.V14.Types.BackendMsg
toBackend old =
    MsgMigrated <|
        case old of
            Evergreen.V13.Types.NoOpToBackend ->
                Evergreen.V14.Types.NoOpToBackend

            Evergreen.V13.Types.CheckValidName p0 ->
                Evergreen.V14.Types.CheckValidName p0

            Evergreen.V13.Types.AutocompletePerson p0 ->
                Evergreen.V14.Types.AutocompletePerson p0

            Evergreen.V13.Types.AutocompleteGroup p0 ->
                Evergreen.V14.Types.AutocompleteGroup p0

            Evergreen.V13.Types.CreatePerson p0 ->
                Evergreen.V14.Types.CreatePerson p0

            Evergreen.V13.Types.CreateGroup p0 p1 ->
                Evergreen.V14.Types.CreateGroup p0 (p1 |> Dict.map (\_ -> migrate_Types_Share))

            Evergreen.V13.Types.CreateSpending p0 ->
                Evergreen.V14.Types.CreateSpending
                    { description = p0.description
                    , year = p0.year
                    , month = p0.month
                    , day = p0.day
                    , total = p0.total |> migrate_Types_Amount
                    , credits = p0.credits |> Dict.map (\_ -> migrate_Types_Amount)
                    , debits = p0.debits |> Dict.map (\_ -> migrate_Types_Amount)
                    }

            Evergreen.V13.Types.RequestUserGroups p0 ->
                Evergreen.V14.Types.RequestUserGroups p0

            Evergreen.V13.Types.RequestGroupTransactions p0 ->
                Evergreen.V14.Types.RequestGroupTransactions p0

            Evergreen.V13.Types.RequestAllTransactions ->
                Evergreen.V14.Types.RequestAllTransactions

            Evergreen.V13.Types.CheckPassword p0 ->
                Evergreen.V14.Types.CheckPassword p0

            Evergreen.V13.Types.ImportJson p0 ->
                Evergreen.V14.Types.ImportJson p0


backendMsg : Evergreen.V13.Types.BackendMsg -> MsgMigration Evergreen.V14.Types.BackendMsg Evergreen.V14.Types.BackendMsg
backendMsg old =
    MsgMigrated <|
        case old of
            Evergreen.V13.Types.NoOpBackendMsg ->
                Evergreen.V14.Types.NoOpBackendMsg


toFrontend : Evergreen.V13.Types.ToFrontend -> MsgMigration Evergreen.V14.Types.ToFrontend Evergreen.V14.Types.FrontendMsg
toFrontend old =
    MsgMigrated <|
        case old of
            Evergreen.V13.Types.NoOpToFrontend ->
                Evergreen.V14.Types.NoOpToFrontend

            Evergreen.V13.Types.OperationSuccessful ->
                Evergreen.V14.Types.OperationSuccessful

            Evergreen.V13.Types.NameAlreadyExists p0 ->
                Evergreen.V14.Types.NameAlreadyExists p0

            Evergreen.V13.Types.InvalidPersonPrefix p0 ->
                Evergreen.V14.Types.InvalidPersonPrefix p0

            Evergreen.V13.Types.AutocompletePersonPrefix p0 ->
                Evergreen.V14.Types.AutocompletePersonPrefix
                    { prefixLower = p0.prefixLower
                    , longestCommonPrefix = p0.longestCommonPrefix
                    , complete = p0.complete
                    }

            Evergreen.V13.Types.InvalidGroupPrefix p0 ->
                Evergreen.V14.Types.InvalidGroupPrefix p0

            Evergreen.V13.Types.AutocompleteGroupPrefix p0 ->
                Evergreen.V14.Types.AutocompleteGroupPrefix
                    { prefixLower = p0.prefixLower
                    , longestCommonPrefix = p0.longestCommonPrefix
                    , complete = p0.complete
                    }

            Evergreen.V13.Types.ListUserGroups p0 ->
                Evergreen.V14.Types.ListUserGroups
                    { user = p0.user
                    , debitors = p0.debitors |> List.map (\(a, b, c) -> (a, b |> migrate_Types_Group, c |> migrate_Types_Amount))
                    , creditors = p0.creditors |> List.map (\(a, b, c) -> (a, b |> migrate_Types_Group, c |> migrate_Types_Amount))
                    }

            Evergreen.V13.Types.ListGroupTransactions p0 ->
                Evergreen.V14.Types.ListGroupTransactions
                    { group = p0.group
                    , transactions = p0.transactions |> List.map migrate_GroupTransaction
                    }

            Evergreen.V13.Types.JsonExport p0 ->
                Evergreen.V14.Types.JsonExport p0


-- Helper migration functions
migrate_Types_Page : Evergreen.V13.Types.Page -> Evergreen.V14.Types.Page
migrate_Types_Page old =
    case old of
        Evergreen.V13.Types.Home ->
            Evergreen.V14.Types.Home

        Evergreen.V13.Types.Json p0 ->
            Evergreen.V14.Types.Json p0

        Evergreen.V13.Types.Import p0 ->
            Evergreen.V14.Types.Import p0

        Evergreen.V13.Types.NotFound ->
            Evergreen.V14.Types.NotFound


migrate_Types_Dialog : Evergreen.V13.Types.Dialog -> Evergreen.V14.Types.Dialog
migrate_Types_Dialog old =
    case old of
        Evergreen.V13.Types.AddPersonDialog p0 ->
            Evergreen.V14.Types.AddPersonDialog (migrate_Types_AddPersonDialogModel p0)

        Evergreen.V13.Types.AddGroupDialog p0 ->
            Evergreen.V14.Types.AddGroupDialog (migrate_Types_AddGroupDialogModel p0)

        Evergreen.V13.Types.AddSpendingDialog p0 ->
            Evergreen.V14.Types.AddSpendingDialog (migrate_Types_AddSpendingDialogModel p0)

        Evergreen.V13.Types.PasswordDialog p0 ->
            Evergreen.V14.Types.PasswordDialog (migrate_Types_PasswordDialogModel p0)


migrate_Types_AddPersonDialogModel : Evergreen.V13.Types.AddPersonDialogModel -> Evergreen.V14.Types.AddPersonDialogModel
migrate_Types_AddPersonDialogModel old =
    { name = old.name
    , nameInvalid = old.nameInvalid
    , submitted = old.submitted
    }


migrate_Types_AddGroupDialogModel : Evergreen.V13.Types.AddGroupDialogModel -> Evergreen.V14.Types.AddGroupDialogModel
migrate_Types_AddGroupDialogModel old =
    { name = old.name
    , nameInvalid = old.nameInvalid
    , members = old.members |> List.map (\(a, b, c) -> (a, b, migrate_Types_NameValidity c))
    , submitted = old.submitted
    }


migrate_Types_AddSpendingDialogModel : Evergreen.V13.Types.AddSpendingDialogModel -> Evergreen.V14.Types.AddSpendingDialogModel
migrate_Types_AddSpendingDialogModel old =
    { description = old.description
    , date = old.date
    , dateText = old.dateText
    , datePickerModel = old.datePickerModel
    , total = old.total
    , credits = old.credits |> List.map (\(a, b, c) -> (a, b, migrate_Types_NameValidity c))
    , debits = old.debits |> List.map (\(a, b, c) -> (a, b, migrate_Types_NameValidity c))
    , submitted = old.submitted
    }


migrate_Types_PasswordDialogModel : Evergreen.V13.Types.PasswordDialogModel -> Evergreen.V14.Types.PasswordDialogModel
migrate_Types_PasswordDialogModel old =
    { password = old.password
    , submitted = old.submitted
    }


migrate_Types_NameValidity : Evergreen.V13.Types.NameValidity -> Evergreen.V14.Types.NameValidity
migrate_Types_NameValidity old =
    case old of
        Evergreen.V13.Types.Complete ->
            Evergreen.V14.Types.Complete

        Evergreen.V13.Types.Incomplete ->
            Evergreen.V14.Types.Incomplete

        Evergreen.V13.Types.InvalidPrefix ->
            Evergreen.V14.Types.InvalidPrefix


migrate_UserGroups : { debitors : List ( String, Evergreen.V13.Types.Group, Evergreen.V13.Types.Amount Evergreen.V13.Types.Debit ), creditors : List ( String, Evergreen.V13.Types.Group, Evergreen.V13.Types.Amount Evergreen.V13.Types.Credit ) } -> { debitors : List ( String, Evergreen.V14.Types.Group, Evergreen.V14.Types.Amount Evergreen.V14.Types.Debit ), creditors : List ( String, Evergreen.V14.Types.Group, Evergreen.V14.Types.Amount Evergreen.V14.Types.Credit ) }
migrate_UserGroups old =
    { debitors = old.debitors |> List.map (\(a, b, c) -> (a, migrate_Types_Group b, migrate_Types_Amount c))
    , creditors = old.creditors |> List.map (\(a, b, c) -> (a, migrate_Types_Group b, migrate_Types_Amount c))
    }


migrate_GroupTransaction : { description : String, year : Int, month : Int, day : Int, total : Evergreen.V13.Types.Amount Evergreen.V13.Types.Debit, share : Evergreen.V13.Types.Amount Evergreen.V13.Types.Debit } -> { description : String, year : Int, month : Int, day : Int, total : Evergreen.V14.Types.Amount Evergreen.V14.Types.Debit, share : Evergreen.V14.Types.Amount Evergreen.V14.Types.Debit }
migrate_GroupTransaction old =
    { description = old.description
    , year = old.year
    , month = old.month
    , day = old.day
    , total = migrate_Types_Amount old.total
    , share = migrate_Types_Amount old.share
    }


migrate_Types_Year : Evergreen.V13.Types.Year -> Evergreen.V14.Types.Year
migrate_Types_Year old =
    { months = old.months |> Dict.map (\_ -> migrate_Types_Month)
    , totalGroupCredits = old.totalGroupCredits |> Dict.map (\_ -> Dict.map (\_ -> migrate_Types_Amount))
    }


migrate_Types_Month : Evergreen.V13.Types.Month -> Evergreen.V14.Types.Month
migrate_Types_Month old =
    { days = old.days |> Dict.map (\_ -> migrate_Types_Day)
    , totalGroupCredits = old.totalGroupCredits |> Dict.map (\_ -> Dict.map (\_ -> migrate_Types_Amount))
    }


migrate_Types_Day : Evergreen.V13.Types.Day -> Evergreen.V14.Types.Day
migrate_Types_Day old =
    { spendings = old.spendings |> List.map migrate_Types_Spending
    , totalGroupCredits = old.totalGroupCredits |> Dict.map (\_ -> Dict.map (\_ -> migrate_Types_Amount))
    }


migrate_Types_Spending : Evergreen.V13.Types.Spending -> Evergreen.V14.Types.Spending
migrate_Types_Spending old =
    { description = old.description
    , total = migrate_Types_Amount old.total
    , groupCredits = old.groupCredits |> Dict.map (\_ -> migrate_Types_Amount)
    }


migrate_Types_Group : Evergreen.V13.Types.Group -> Evergreen.V14.Types.Group
migrate_Types_Group old =
    old |> Dict.map (\_ -> migrate_Types_Share)


migrate_Types_Share : Evergreen.V13.Types.Share -> Evergreen.V14.Types.Share
migrate_Types_Share old =
    case old of
        Evergreen.V13.Types.Share p0 ->
            Evergreen.V14.Types.Share p0


migrate_Types_Amount : Evergreen.V13.Types.Amount a -> Evergreen.V14.Types.Amount b
migrate_Types_Amount old =
    case old of
        Evergreen.V13.Types.Amount p0 ->
            Evergreen.V14.Types.Amount p0


migrate_Types_Person : Evergreen.V13.Types.Person -> Evergreen.V14.Types.Person
migrate_Types_Person old =
    { id = old.id
    , belongsTo = old.belongsTo
    }