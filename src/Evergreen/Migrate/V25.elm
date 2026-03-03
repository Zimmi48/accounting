module Evergreen.Migrate.V25 exposing (..)

{-| This migration file was created to support sub-transactions in spendings.

Changes:

  - Spending now has subTransactions instead of flat credits/debits
  - Each spending from V24 is converted to have a single sub-transaction with no date/description override

-}

import Dict
import Evergreen.V24.Types
import Evergreen.V25.Types
import Lamdera.Migrations exposing (..)


frontendModel : Evergreen.V24.Types.FrontendModel -> ModelMigration Evergreen.V25.Types.FrontendModel Evergreen.V25.Types.FrontendMsg
frontendModel old =
    ModelMigrated ( migrate_Types_FrontendModel old, Cmd.none )


backendModel : Evergreen.V24.Types.BackendModel -> ModelMigration Evergreen.V25.Types.BackendModel Evergreen.V25.Types.BackendMsg
backendModel old =
    ModelMigrated ( migrate_Types_BackendModel old, Cmd.none )


frontendMsg : Evergreen.V24.Types.FrontendMsg -> MsgMigration Evergreen.V25.Types.FrontendMsg Evergreen.V25.Types.FrontendMsg
frontendMsg old =
    MsgMigrated ( migrate_Types_FrontendMsg old, Cmd.none )


toBackend : Evergreen.V24.Types.ToBackend -> MsgMigration Evergreen.V25.Types.ToBackend Evergreen.V25.Types.BackendMsg
toBackend old =
    MsgOldValueIgnored


backendMsg : Evergreen.V24.Types.BackendMsg -> MsgMigration Evergreen.V25.Types.BackendMsg Evergreen.V25.Types.BackendMsg
backendMsg old =
    MsgUnchanged


toFrontend : Evergreen.V24.Types.ToFrontend -> MsgMigration Evergreen.V25.Types.ToFrontend Evergreen.V25.Types.FrontendMsg
toFrontend old =
    MsgOldValueIgnored


migrate_Types_FrontendModel : Evergreen.V24.Types.FrontendModel -> Evergreen.V25.Types.FrontendModel
migrate_Types_FrontendModel old =
    { page = old.page |> migrate_Types_Page
    , showDialog = old.showDialog |> Maybe.map migrate_Types_Dialog
    , user = old.user
    , nameValidity = old.nameValidity |> migrate_Types_NameValidity
    , userGroups =
        old.userGroups
            |> Maybe.map
                (\rec ->
                    { debitors = rec.debitors |> List.map (\( t1, t2, t3 ) -> ( t1, t2 |> migrate_Types_Group, t3 |> migrate_Types_Amount ))
                    , creditors = rec.creditors |> List.map (\( t1, t2, t3 ) -> ( t1, t2 |> migrate_Types_Group, t3 |> migrate_Types_Amount ))
                    }
                )
    , group = old.group
    , groupValidity = old.groupValidity |> migrate_Types_NameValidity
    , groupTransactions =
        old.groupTransactions
            |> List.map
                (\rec ->
                    { transactionId = rec.transactionId |> migrate_Types_TransactionId
                    , description = rec.description
                    , year = rec.year
                    , month = rec.month
                    , day = rec.day
                    , total = rec.total |> migrate_Types_Amount
                    , share = rec.share |> migrate_Types_Amount
                    }
                )
    , key = old.key
    , windowWidth = old.windowWidth
    , windowHeight = old.windowHeight
    , checkingAuthentication = old.checkingAuthentication
    , theme = old.theme |> migrate_Types_Theme
    }


migrate_Types_BackendModel : Evergreen.V24.Types.BackendModel -> Evergreen.V25.Types.BackendModel
migrate_Types_BackendModel old =
    { years = old.years |> Dict.map (\_ -> migrate_Types_Year)
    , groups = old.groups |> Dict.map (\_ -> migrate_Types_Group)
    , totalGroupCredits = old.totalGroupCredits |> Dict.map (\_ -> Dict.map (\_ -> migrate_Types_Amount))
    , persons = old.persons |> Dict.map (\_ -> migrate_Types_Person)
    , nextPersonId = old.nextPersonId
    , loggedInSessions = old.loggedInSessions
    }


migrate_Types_AddGroupDialogModel : Evergreen.V24.Types.AddGroupDialogModel -> Evergreen.V25.Types.AddGroupDialogModel
migrate_Types_AddGroupDialogModel old =
    { name = old.name
    , nameInvalid = old.nameInvalid
    , members = old.members |> List.map (\( t1, t2, t3 ) -> ( t1, t2, t3 |> migrate_Types_NameValidity ))
    , submitted = old.submitted
    }


migrate_Types_AddPersonDialogModel : Evergreen.V24.Types.AddPersonDialogModel -> Evergreen.V25.Types.AddPersonDialogModel
migrate_Types_AddPersonDialogModel old =
    old


migrate_Types_AddSpendingDialogModel : Evergreen.V24.Types.AddSpendingDialogModel -> Evergreen.V25.Types.AddSpendingDialogModel
migrate_Types_AddSpendingDialogModel old =
    { transactionId = old.transactionId |> Maybe.map migrate_Types_TransactionId
    , description = old.description
    , date = old.date
    , dateText = old.dateText
    , datePickerModel = old.datePickerModel
    , total = old.total
    , credits = old.credits |> List.map (\( t1, t2, t3 ) -> ( t1, t2, t3 |> migrate_Types_NameValidity ))
    , debits = old.debits |> List.map (\( t1, t2, t3 ) -> ( t1, t2, t3 |> migrate_Types_NameValidity ))
    , submitted = old.submitted
    }


migrate_Types_Amount : Evergreen.V24.Types.Amount a_old -> Evergreen.V25.Types.Amount a_new
migrate_Types_Amount old =
    case old of
        Evergreen.V24.Types.Amount p0 ->
            Evergreen.V25.Types.Amount p0


migrate_Types_Dialog : Evergreen.V24.Types.Dialog -> Evergreen.V25.Types.Dialog
migrate_Types_Dialog old =
    case old of
        Evergreen.V24.Types.AddPersonDialog p0 ->
            Evergreen.V25.Types.AddPersonDialog (p0 |> migrate_Types_AddPersonDialogModel)

        Evergreen.V24.Types.AddGroupDialog p0 ->
            Evergreen.V25.Types.AddGroupDialog (p0 |> migrate_Types_AddGroupDialogModel)

        Evergreen.V24.Types.AddSpendingDialog p0 ->
            Evergreen.V25.Types.AddSpendingDialog (p0 |> migrate_Types_AddSpendingDialogModel)

        Evergreen.V24.Types.ConfirmDeleteDialog p0 ->
            Evergreen.V25.Types.ConfirmDeleteDialog (p0 |> migrate_Types_TransactionId)

        Evergreen.V24.Types.PasswordDialog p0 ->
            Evergreen.V25.Types.PasswordDialog (p0 |> migrate_Types_PasswordDialogModel)


migrate_Types_FrontendMsg : Evergreen.V24.Types.FrontendMsg -> Evergreen.V25.Types.FrontendMsg
migrate_Types_FrontendMsg old =
    case old of
        Evergreen.V24.Types.UrlClicked p0 ->
            Evergreen.V25.Types.UrlClicked p0

        Evergreen.V24.Types.UrlChanged p0 ->
            Evergreen.V25.Types.UrlChanged p0

        Evergreen.V24.Types.NoOpFrontendMsg ->
            Evergreen.V25.Types.NoOpFrontendMsg

        Evergreen.V24.Types.ShowAddPersonDialog ->
            Evergreen.V25.Types.ShowAddPersonDialog

        Evergreen.V24.Types.ShowAddGroupDialog ->
            Evergreen.V25.Types.ShowAddGroupDialog

        Evergreen.V24.Types.ShowAddSpendingDialog p0 ->
            Evergreen.V25.Types.ShowAddSpendingDialog (p0 |> Maybe.map migrate_Types_TransactionId)

        Evergreen.V24.Types.ShowConfirmDeleteDialog p0 ->
            Evergreen.V25.Types.ShowConfirmDeleteDialog (p0 |> migrate_Types_TransactionId)

        Evergreen.V24.Types.ConfirmDeleteTransaction p0 ->
            Evergreen.V25.Types.ConfirmDeleteTransaction (p0 |> migrate_Types_TransactionId)

        Evergreen.V24.Types.SetToday p0 ->
            Evergreen.V25.Types.SetToday p0

        Evergreen.V24.Types.Submit ->
            Evergreen.V25.Types.Submit

        Evergreen.V24.Types.Cancel ->
            Evergreen.V25.Types.Cancel

        Evergreen.V24.Types.UpdateName p0 ->
            Evergreen.V25.Types.UpdateName p0

        Evergreen.V24.Types.AddMember p0 ->
            Evergreen.V25.Types.AddMember p0

        Evergreen.V24.Types.UpdateMember p0 p1 ->
            Evergreen.V25.Types.UpdateMember p0 p1

        Evergreen.V24.Types.UpdateShare p0 p1 ->
            Evergreen.V25.Types.UpdateShare p0 p1

        Evergreen.V24.Types.ChangeDatePicker p0 ->
            Evergreen.V25.Types.ChangeDatePicker p0

        Evergreen.V24.Types.UpdateTotal p0 ->
            Evergreen.V25.Types.UpdateTotal p0

        Evergreen.V24.Types.AddCreditor p0 ->
            Evergreen.V25.Types.AddCreditor p0

        Evergreen.V24.Types.UpdateCreditor p0 p1 ->
            Evergreen.V25.Types.UpdateCreditor p0 p1

        Evergreen.V24.Types.UpdateCredit p0 p1 ->
            Evergreen.V25.Types.UpdateCredit p0 p1

        Evergreen.V24.Types.AddDebitor p0 ->
            Evergreen.V25.Types.AddDebitor p0

        Evergreen.V24.Types.UpdateDebitor p0 p1 ->
            Evergreen.V25.Types.UpdateDebitor p0 p1

        Evergreen.V24.Types.UpdateDebit p0 p1 ->
            Evergreen.V25.Types.UpdateDebit p0 p1

        Evergreen.V24.Types.UpdateGroupName p0 ->
            Evergreen.V25.Types.UpdateGroupName p0

        Evergreen.V24.Types.UpdatePassword p0 ->
            Evergreen.V25.Types.UpdatePassword p0

        Evergreen.V24.Types.UpdateJson p0 ->
            Evergreen.V25.Types.UpdateJson p0

        Evergreen.V24.Types.ViewportChanged p0 p1 ->
            Evergreen.V25.Types.ViewportChanged p0 p1

        Evergreen.V24.Types.ToggleTheme ->
            Evergreen.V25.Types.ToggleTheme


migrate_Types_Group : Evergreen.V24.Types.Group -> Evergreen.V25.Types.Group
migrate_Types_Group old =
    old |> Dict.map (\k -> migrate_Types_Share)


migrate_Types_NameValidity : Evergreen.V24.Types.NameValidity -> Evergreen.V25.Types.NameValidity
migrate_Types_NameValidity old =
    case old of
        Evergreen.V24.Types.Complete ->
            Evergreen.V25.Types.Complete

        Evergreen.V24.Types.Incomplete ->
            Evergreen.V25.Types.Incomplete

        Evergreen.V24.Types.InvalidPrefix ->
            Evergreen.V25.Types.InvalidPrefix


migrate_Types_Page : Evergreen.V24.Types.Page -> Evergreen.V25.Types.Page
migrate_Types_Page old =
    case old of
        Evergreen.V24.Types.Home ->
            Evergreen.V25.Types.Home

        Evergreen.V24.Types.Json p0 ->
            Evergreen.V25.Types.Json p0

        Evergreen.V24.Types.Import p0 ->
            Evergreen.V25.Types.Import p0

        Evergreen.V24.Types.NotFound ->
            Evergreen.V25.Types.NotFound


migrate_Types_PasswordDialogModel : Evergreen.V24.Types.PasswordDialogModel -> Evergreen.V25.Types.PasswordDialogModel
migrate_Types_PasswordDialogModel old =
    old


migrate_Types_Share : Evergreen.V24.Types.Share -> Evergreen.V25.Types.Share
migrate_Types_Share old =
    case old of
        Evergreen.V24.Types.Share p0 ->
            Evergreen.V25.Types.Share p0


migrate_Types_TransactionId : Evergreen.V24.Types.TransactionId -> Evergreen.V25.Types.TransactionId
migrate_Types_TransactionId old =
    old


migrate_Types_Theme : Evergreen.V24.Types.Theme -> Evergreen.V25.Types.Theme
migrate_Types_Theme old =
    case old of
        Evergreen.V24.Types.LightMode ->
            Evergreen.V25.Types.LightMode

        Evergreen.V24.Types.DarkMode ->
            Evergreen.V25.Types.DarkMode


migrate_Types_Person : Evergreen.V24.Types.Person -> Evergreen.V25.Types.Person
migrate_Types_Person old =
    old


migrate_Types_Year : Evergreen.V24.Types.Year -> Evergreen.V25.Types.Year
migrate_Types_Year old =
    { months = old.months |> Dict.map (\_ -> migrate_Types_Month)
    , totalGroupCredits = old.totalGroupCredits |> Dict.map (\_ -> Dict.map (\_ -> migrate_Types_Amount))
    }


migrate_Types_Month : Evergreen.V24.Types.Month -> Evergreen.V25.Types.Month
migrate_Types_Month old =
    { days = old.days |> Dict.map (\_ -> migrate_Types_Day)
    , totalGroupCredits = old.totalGroupCredits |> Dict.map (\_ -> Dict.map (\_ -> migrate_Types_Amount))
    }


migrate_Types_Day : Evergreen.V24.Types.Day -> Evergreen.V25.Types.Day
migrate_Types_Day old =
    { spendings = old.spendings |> List.map migrate_Types_Spending
    , totalGroupCredits = old.totalGroupCredits |> Dict.map (\_ -> Dict.map (\_ -> migrate_Types_Amount))
    }


{-| Convert V24 Spending (with flat credits/debits) to V25 Spending (with subTransactions)
-}
migrate_Types_Spending : Evergreen.V24.Types.Spending -> Evergreen.V25.Types.Spending
migrate_Types_Spending old =
    { description = old.description
    , total = old.total |> migrate_Types_Amount
    , subTransactions =
        [ { date = Nothing
          , secondaryDescription = Nothing
          , credits = old.credits |> Dict.map (\_ -> migrate_Types_Amount)
          , debits = old.debits |> Dict.map (\_ -> migrate_Types_Amount)
          }
        ]
    , status = old.status |> migrate_Types_TransactionStatus
    }


migrate_Types_TransactionStatus : Evergreen.V24.Types.TransactionStatus -> Evergreen.V25.Types.TransactionStatus
migrate_Types_TransactionStatus old =
    case old of
        Evergreen.V24.Types.Active ->
            Evergreen.V25.Types.Active

        Evergreen.V24.Types.Deleted ->
            Evergreen.V25.Types.Deleted

        Evergreen.V24.Types.Replaced ->
            Evergreen.V25.Types.Replaced
