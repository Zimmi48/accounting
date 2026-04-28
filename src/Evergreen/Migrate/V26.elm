module Evergreen.Migrate.V26 exposing (..)

import Array
import DatePicker
import Dict
import Evergreen.V24.Types
import Evergreen.V26.Types
import Lamdera.Migrations exposing (..)
import List
import Maybe
import Set
import String


frontendModel : Evergreen.V24.Types.FrontendModel -> ModelMigration Evergreen.V26.Types.FrontendModel Evergreen.V26.Types.FrontendMsg
frontendModel old =
    ModelMigrated ( migrateFrontendModel old, Cmd.none )


backendModel : Evergreen.V24.Types.BackendModel -> ModelMigration Evergreen.V26.Types.BackendModel Evergreen.V26.Types.BackendMsg
backendModel old =
    ModelMigrated ( migrateBackendModel old, Cmd.none )


frontendMsg : Evergreen.V24.Types.FrontendMsg -> MsgMigration Evergreen.V26.Types.FrontendMsg Evergreen.V26.Types.FrontendMsg
frontendMsg old =
    MsgMigrated ( migrateFrontendMsg old, Cmd.none )


toBackend : Evergreen.V24.Types.ToBackend -> MsgMigration Evergreen.V26.Types.ToBackend Evergreen.V26.Types.BackendMsg
toBackend old =
    MsgMigrated ( migrateToBackend old, Cmd.none )


backendMsg : Evergreen.V24.Types.BackendMsg -> MsgMigration Evergreen.V26.Types.BackendMsg Evergreen.V26.Types.BackendMsg
backendMsg _ =
    MsgUnchanged


toFrontend : Evergreen.V24.Types.ToFrontend -> MsgMigration Evergreen.V26.Types.ToFrontend Evergreen.V26.Types.FrontendMsg
toFrontend old =
    MsgMigrated ( migrateToFrontend old, Cmd.none )


invalidSpendingId : Evergreen.V26.Types.SpendingId
invalidSpendingId =
    -1


type alias MigratedStorage =
    { years : Dict.Dict Int Evergreen.V26.Types.Year
    , spendings : Array.Array Evergreen.V26.Types.Spending
    }


type alias LegacyStorageState =
    { nextSpendingId : Int
    , reversedSpendings : List Evergreen.V26.Types.Spending
    }


type alias LegacySpendingMetadata =
    { groupMembersKey : String
    , groupMembers : Set.Set String
    }


migrateFrontendModel : Evergreen.V24.Types.FrontendModel -> Evergreen.V26.Types.FrontendModel
migrateFrontendModel old =
    { page = migratePage old.page
    , showDialog = migrateFrontendDialog old.showDialog
    , errorMessage = Nothing
    , user = old.user
    , nameValidity = migrateNameValidity old.nameValidity
    , userGroups =
        old.userGroups
            |> Maybe.map
                (\rec ->
                    { debitors = rec.debitors |> List.map (\( name, group, amount ) -> ( name, migrateGroup group, migrateAmount amount ))
                    , creditors = rec.creditors |> List.map (\( name, group, amount ) -> ( name, migrateGroup group, migrateAmount amount ))
                    }
                )
    , group = old.group
    , groupValidity = migrateNameValidity old.groupValidity
    , groupTransactions = []
    , key = old.key
    , windowWidth = old.windowWidth
    , windowHeight = old.windowHeight
    , checkingAuthentication = old.checkingAuthentication
    , theme = migrateTheme old.theme
    }


migrateFrontendDialog : Maybe Evergreen.V24.Types.Dialog -> Maybe Evergreen.V26.Types.Dialog
migrateFrontendDialog maybeDialog =
    case maybeDialog of
        Just dialog ->
            case dialog of
                Evergreen.V24.Types.AddPersonDialog addPersonDialog ->
                    Just (Evergreen.V26.Types.AddPersonDialog (migrateAddPersonDialogModel addPersonDialog))

                Evergreen.V24.Types.AddGroupDialog addGroupDialog ->
                    Just (Evergreen.V26.Types.AddGroupDialog (migrateAddGroupDialogModel addGroupDialog))

                Evergreen.V24.Types.AddSpendingDialog addSpendingDialog ->
                    case addSpendingDialog.transactionId of
                        Nothing ->
                            Just (Evergreen.V26.Types.AddSpendingDialog (migrateAddSpendingDialogModel addSpendingDialog))

                        Just _ ->
                            Nothing

                Evergreen.V24.Types.ConfirmDeleteDialog _ ->
                    Nothing

                Evergreen.V24.Types.PasswordDialog passwordDialog ->
                    Just (Evergreen.V26.Types.PasswordDialog (migratePasswordDialogModel passwordDialog))

        Nothing ->
            Nothing


migrateBackendModel : Evergreen.V24.Types.BackendModel -> Evergreen.V26.Types.BackendModel
migrateBackendModel old =
    let
        storage =
            migrateLegacyStorage old
    in
    { years = storage.years
    , spendings = storage.spendings
    , groups = old.groups |> Dict.map (\_ group -> migrateGroup group)
    , totalGroupCredits = migrateGroupCreditTotals old.totalGroupCredits
    , persons = old.persons
    , nextPersonId = old.nextPersonId
    , loggedInSessions = old.loggedInSessions
    }


migrateLegacyStorage : Evergreen.V24.Types.BackendModel -> MigratedStorage
migrateLegacyStorage oldModel =
    let
        ( years, finalState ) =
            oldModel.years
                |> Dict.toList
                |> List.foldl
                    (\( yearNumber, oldYear ) ( yearsAcc, stateAcc ) ->
                        let
                            ( migratedYear, nextState ) =
                                migrateLegacyYear oldModel yearNumber oldYear stateAcc
                        in
                        ( Dict.insert yearNumber migratedYear yearsAcc, nextState )
                    )
                    ( Dict.empty
                    , { nextSpendingId = 0
                      , reversedSpendings = []
                      }
                    )
    in
    { years = years
    , spendings = finalState.reversedSpendings |> List.reverse |> Array.fromList
    }


migrateLegacyYear : Evergreen.V24.Types.BackendModel -> Int -> Evergreen.V24.Types.Year -> LegacyStorageState -> ( Evergreen.V26.Types.Year, LegacyStorageState )
migrateLegacyYear oldModel yearNumber oldYear state =
    let
        ( months, nextState ) =
            oldYear.months
                |> Dict.toList
                |> List.foldl
                    (\( monthNumber, oldMonth ) ( monthsAcc, stateAcc ) ->
                        let
                            ( migratedMonth, updatedState ) =
                                migrateLegacyMonth oldModel yearNumber monthNumber oldMonth stateAcc
                        in
                        ( Dict.insert monthNumber migratedMonth monthsAcc, updatedState )
                    )
                    ( Dict.empty, state )
    in
    ( { months = months
      , totalGroupCredits = migrateGroupCreditTotals oldYear.totalGroupCredits
      }
    , nextState
    )


migrateLegacyMonth : Evergreen.V24.Types.BackendModel -> Int -> Int -> Evergreen.V24.Types.Month -> LegacyStorageState -> ( Evergreen.V26.Types.Month, LegacyStorageState )
migrateLegacyMonth oldModel yearNumber monthNumber oldMonth state =
    let
        ( days, nextState ) =
            oldMonth.days
                |> Dict.toList
                |> List.foldl
                    (\( dayNumber, oldDay ) ( daysAcc, stateAcc ) ->
                        let
                            ( migratedDay, updatedState ) =
                                migrateLegacyDay oldModel yearNumber monthNumber dayNumber oldDay stateAcc
                        in
                        ( Dict.insert dayNumber migratedDay daysAcc, updatedState )
                    )
                    ( Dict.empty, state )
    in
    ( { days = days
      , totalGroupCredits = migrateGroupCreditTotals oldMonth.totalGroupCredits
      }
    , nextState
    )


migrateLegacyDay : Evergreen.V24.Types.BackendModel -> Int -> Int -> Int -> Evergreen.V24.Types.Day -> LegacyStorageState -> ( Evergreen.V26.Types.Day, LegacyStorageState )
migrateLegacyDay oldModel yearNumber monthNumber dayNumber oldDay state =
    let
        ( reversedTransactions, _, nextState ) =
            oldDay.spendings
                |> List.foldl
                    (\oldSpending ( transactionsAcc, nextIndex, stateAcc ) ->
                        let
                            spendingId =
                                stateAcc.nextSpendingId

                            transactions =
                                legacyStoredTransactionsForSpending oldModel spendingId yearNumber monthNumber dayNumber oldSpending

                            transactionCount =
                                List.length transactions

                            migratedSpending =
                                { description = oldSpending.description
                                , total = migrateAmount oldSpending.total
                                , transactionIds = transactionIdsForDay yearNumber monthNumber dayNumber nextIndex transactionCount
                                , status = migrateTransactionStatus oldSpending.status
                                }

                            nextStorageState =
                                { nextSpendingId = spendingId + 1
                                , reversedSpendings = migratedSpending :: stateAcc.reversedSpendings
                                }
                        in
                        ( List.reverse transactions ++ transactionsAcc
                        , nextIndex + transactionCount
                        , nextStorageState
                        )
                    )
                    ( [], 0, state )
    in
    ( { transactions = reversedTransactions |> List.reverse |> Array.fromList
      , totalGroupCredits = migrateGroupCreditTotals oldDay.totalGroupCredits
      }
    , nextState
    )


legacyStoredTransactionsForSpending : Evergreen.V24.Types.BackendModel -> Evergreen.V26.Types.SpendingId -> Int -> Int -> Int -> Evergreen.V24.Types.Spending -> List Evergreen.V26.Types.Transaction
legacyStoredTransactionsForSpending oldModel spendingId yearNumber monthNumber dayNumber oldSpending =
    let
        metadata =
            legacySpendingMetadata oldModel oldSpending

        status =
            migrateTransactionStatus oldSpending.status
    in
    legacySpendingTransactions yearNumber monthNumber dayNumber oldSpending.credits oldSpending.debits
        |> List.map
            (\transaction ->
                { spendingId = spendingId
                , secondaryDescription = transaction.secondaryDescription
                , group = transaction.group
                , amount = transaction.amount
                , side = transaction.side
                , groupMembersKey = metadata.groupMembersKey
                , groupMembers = metadata.groupMembers
                , status = status
                }
            )


legacySpendingMetadata : Evergreen.V24.Types.BackendModel -> Evergreen.V24.Types.Spending -> LegacySpendingMetadata
legacySpendingMetadata oldModel oldSpending =
    let
        groupMembers =
            Dict.keys oldSpending.credits
                ++ Dict.keys oldSpending.debits
                |> List.concatMap
                    (\group ->
                        Dict.get group oldModel.groups
                            |> Maybe.map Dict.keys
                            |> Maybe.withDefault [ group ]
                    )
                |> Set.fromList
    in
    { groupMembersKey =
        groupMembers
            |> Set.toList
            |> List.filterMap (\name -> Dict.get name oldModel.persons)
            |> List.map (.id >> String.fromInt)
            |> String.join ","
    , groupMembers = groupMembers
    }


transactionIdsForDay : Int -> Int -> Int -> Int -> Int -> List Evergreen.V26.Types.TransactionId
transactionIdsForDay yearNumber monthNumber dayNumber startIndex count =
    if count <= 0 then
        []

    else
        List.range startIndex (startIndex + count - 1)
            |> List.map
                (\index ->
                    { year = yearNumber
                    , month = monthNumber
                    , day = dayNumber
                    , index = index
                    }
                )


legacySpendingTransactions : Int -> Int -> Int -> Dict.Dict String (Evergreen.V24.Types.Amount a) -> Dict.Dict String (Evergreen.V24.Types.Amount b) -> List Evergreen.V26.Types.SpendingTransaction
legacySpendingTransactions yearNumber monthNumber dayNumber credits debits =
    legacyTransactionsForSide yearNumber monthNumber dayNumber Evergreen.V26.Types.CreditTransaction credits
        ++ legacyTransactionsForSide yearNumber monthNumber dayNumber Evergreen.V26.Types.DebitTransaction debits


legacyTransactionsForSide : Int -> Int -> Int -> Evergreen.V26.Types.TransactionSide -> Dict.Dict String (Evergreen.V24.Types.Amount a) -> List Evergreen.V26.Types.SpendingTransaction
legacyTransactionsForSide yearNumber monthNumber dayNumber side amounts =
    amounts
        |> Dict.toList
        |> List.map
            (\( group, amount ) ->
                { year = yearNumber
                , month = monthNumber
                , day = dayNumber
                , secondaryDescription = ""
                , group = group
                , amount = migrateAmount amount
                , side = side
                }
            )


migrateFrontendMsg : Evergreen.V24.Types.FrontendMsg -> Evergreen.V26.Types.FrontendMsg
migrateFrontendMsg old =
    case old of
        Evergreen.V24.Types.UrlClicked urlRequest ->
            Evergreen.V26.Types.UrlClicked urlRequest

        Evergreen.V24.Types.UrlChanged url ->
            Evergreen.V26.Types.UrlChanged url

        Evergreen.V24.Types.NoOpFrontendMsg ->
            Evergreen.V26.Types.NoOpFrontendMsg

        Evergreen.V24.Types.ShowAddPersonDialog ->
            Evergreen.V26.Types.ShowAddPersonDialog

        Evergreen.V24.Types.ShowAddGroupDialog ->
            Evergreen.V26.Types.ShowAddGroupDialog

        Evergreen.V24.Types.ShowAddSpendingDialog maybeTransactionId ->
            case maybeTransactionId of
                Nothing ->
                    Evergreen.V26.Types.ShowAddSpendingDialog Nothing

                Just _ ->
                    Evergreen.V26.Types.NoOpFrontendMsg

        Evergreen.V24.Types.ShowConfirmDeleteDialog _ ->
            Evergreen.V26.Types.NoOpFrontendMsg

        Evergreen.V24.Types.ConfirmDeleteTransaction _ ->
            Evergreen.V26.Types.NoOpFrontendMsg

        Evergreen.V24.Types.SetToday date ->
            Evergreen.V26.Types.SetToday date

        Evergreen.V24.Types.Submit ->
            Evergreen.V26.Types.Submit

        Evergreen.V24.Types.Cancel ->
            Evergreen.V26.Types.Cancel

        Evergreen.V24.Types.UpdateName name ->
            Evergreen.V26.Types.UpdateName name

        Evergreen.V24.Types.AddMember member ->
            Evergreen.V26.Types.AddMember member

        Evergreen.V24.Types.UpdateMember index member ->
            Evergreen.V26.Types.UpdateMember index member

        Evergreen.V24.Types.UpdateShare index share ->
            Evergreen.V26.Types.UpdateShare index share

        Evergreen.V24.Types.ChangeDatePicker changeEvent ->
            Evergreen.V26.Types.UpdateSpendingDate changeEvent

        Evergreen.V24.Types.UpdateTotal total ->
            Evergreen.V26.Types.UpdateSpendingTotal total

        Evergreen.V24.Types.AddCreditor group ->
            Evergreen.V26.Types.AddCreditor group

        Evergreen.V24.Types.UpdateCreditor index group ->
            Evergreen.V26.Types.UpdateCreditGroup index group

        Evergreen.V24.Types.UpdateCredit index amount ->
            Evergreen.V26.Types.UpdateCreditAmount index amount

        Evergreen.V24.Types.AddDebitor group ->
            Evergreen.V26.Types.AddDebitor group

        Evergreen.V24.Types.UpdateDebitor index group ->
            Evergreen.V26.Types.UpdateDebitGroup index group

        Evergreen.V24.Types.UpdateDebit index amount ->
            Evergreen.V26.Types.UpdateDebitAmount index amount

        Evergreen.V24.Types.UpdateGroupName group ->
            Evergreen.V26.Types.UpdateGroupName group

        Evergreen.V24.Types.UpdatePassword password ->
            Evergreen.V26.Types.UpdatePassword password

        Evergreen.V24.Types.UpdateJson json ->
            Evergreen.V26.Types.UpdateJson json

        Evergreen.V24.Types.ViewportChanged width height ->
            Evergreen.V26.Types.ViewportChanged width height

        Evergreen.V24.Types.ToggleTheme ->
            Evergreen.V26.Types.ToggleTheme


migrateToBackend : Evergreen.V24.Types.ToBackend -> Evergreen.V26.Types.ToBackend
migrateToBackend old =
    case old of
        Evergreen.V24.Types.NoOpToBackend ->
            Evergreen.V26.Types.NoOpToBackend

        Evergreen.V24.Types.CheckValidName name ->
            Evergreen.V26.Types.CheckValidName name

        Evergreen.V24.Types.AutocompletePerson prefix ->
            Evergreen.V26.Types.AutocompletePerson prefix

        Evergreen.V24.Types.AutocompleteGroup prefix ->
            Evergreen.V26.Types.AutocompleteGroup prefix

        Evergreen.V24.Types.CreatePerson name ->
            Evergreen.V26.Types.CreatePerson name

        Evergreen.V24.Types.CreateGroup name members ->
            Evergreen.V26.Types.CreateGroup name (members |> Dict.map (\_ share -> migrateShare share))

        Evergreen.V24.Types.CreateSpending payload ->
            Evergreen.V26.Types.CreateSpending
                { description = payload.description
                , total = migrateAmount payload.total
                , transactions = legacySpendingTransactions payload.year payload.month payload.day payload.credits payload.debits
                }

        Evergreen.V24.Types.EditTransaction _ ->
            Evergreen.V26.Types.NoOpToBackend

        Evergreen.V24.Types.DeleteTransaction _ ->
            Evergreen.V26.Types.NoOpToBackend

        Evergreen.V24.Types.RequestTransactionDetails _ ->
            Evergreen.V26.Types.NoOpToBackend

        Evergreen.V24.Types.RequestUserGroups user ->
            Evergreen.V26.Types.RequestUserGroups user

        Evergreen.V24.Types.RequestGroupTransactions group ->
            Evergreen.V26.Types.RequestGroupTransactions group

        Evergreen.V24.Types.RequestAllTransactions ->
            Evergreen.V26.Types.RequestAllTransactions

        Evergreen.V24.Types.CheckPassword password ->
            Evergreen.V26.Types.CheckPassword password

        Evergreen.V24.Types.CheckAuthentication ->
            Evergreen.V26.Types.CheckAuthentication

        Evergreen.V24.Types.ImportJson json ->
            Evergreen.V26.Types.ImportJson json


migrateToFrontend : Evergreen.V24.Types.ToFrontend -> Evergreen.V26.Types.ToFrontend
migrateToFrontend old =
    case old of
        Evergreen.V24.Types.NoOpToFrontend ->
            Evergreen.V26.Types.NoOpToFrontend

        Evergreen.V24.Types.OperationSuccessful ->
            Evergreen.V26.Types.OperationSuccessful

        Evergreen.V24.Types.NameAlreadyExists name ->
            Evergreen.V26.Types.NameAlreadyExists name

        Evergreen.V24.Types.InvalidPersonPrefix prefix ->
            Evergreen.V26.Types.InvalidPersonPrefix prefix

        Evergreen.V24.Types.AutocompletePersonPrefix payload ->
            Evergreen.V26.Types.AutocompletePersonPrefix payload

        Evergreen.V24.Types.InvalidGroupPrefix prefix ->
            Evergreen.V26.Types.InvalidGroupPrefix prefix

        Evergreen.V24.Types.AutocompleteGroupPrefix payload ->
            Evergreen.V26.Types.AutocompleteGroupPrefix payload

        Evergreen.V24.Types.ListUserGroups payload ->
            Evergreen.V26.Types.ListUserGroups
                { user = payload.user
                , debitors = payload.debitors |> List.map (\( name, group, amount ) -> ( name, migrateGroup group, migrateAmount amount ))
                , creditors = payload.creditors |> List.map (\( name, group, amount ) -> ( name, migrateGroup group, migrateAmount amount ))
                }

        Evergreen.V24.Types.ListGroupTransactions payload ->
            Evergreen.V26.Types.ListGroupTransactions
                { group = payload.group
                , transactions = []
                }

        Evergreen.V24.Types.AuthenticationStatus isAuthenticated ->
            Evergreen.V26.Types.AuthenticationStatus isAuthenticated

        Evergreen.V24.Types.JsonExport json ->
            Evergreen.V26.Types.JsonExport json

        Evergreen.V24.Types.TransactionError errorMessage ->
            Evergreen.V26.Types.SpendingError errorMessage

        Evergreen.V24.Types.TransactionDetails _ ->
            Evergreen.V26.Types.SpendingError "Please reopen the spending editor after the update."


migrateAddPersonDialogModel : Evergreen.V24.Types.AddPersonDialogModel -> Evergreen.V26.Types.AddPersonDialogModel
migrateAddPersonDialogModel old =
    old


migrateAddGroupDialogModel : Evergreen.V24.Types.AddGroupDialogModel -> Evergreen.V26.Types.AddGroupDialogModel
migrateAddGroupDialogModel old =
    { name = old.name
    , nameInvalid = old.nameInvalid
    , members = old.members |> List.map (\( name, share, validity ) -> ( name, share, migrateNameValidity validity ))
    , submitted = old.submitted
    }


migrateAddSpendingDialogModel : Evergreen.V24.Types.AddSpendingDialogModel -> Evergreen.V26.Types.AddSpendingDialogModel
migrateAddSpendingDialogModel old =
    { spendingId = Nothing
    , description = old.description
    , total = old.total
    , date = old.date
    , today = Nothing
    , dateText = old.dateText
    , datePickerModel = old.datePickerModel
    , credits = old.credits |> List.map (migrateLegacyTransactionLine old.dateText old.datePickerModel)
    , debits = old.debits |> List.map (migrateLegacyTransactionLine old.dateText old.datePickerModel)
    , submitted = old.submitted
    }


migrateLegacyTransactionLine : String -> DatePicker.Model -> ( String, String, Evergreen.V24.Types.NameValidity ) -> Evergreen.V26.Types.TransactionLine
migrateLegacyTransactionLine dateText datePickerModel ( group, amount, validity ) =
    { date = Nothing
    , dateText = dateText
    , datePickerModel = datePickerModel
    , secondaryDescription = ""
    , detailsExpanded = False
    , group = group
    , amount = amount
    , nameValidity = migrateNameValidity validity
    }


migratePasswordDialogModel : Evergreen.V24.Types.PasswordDialogModel -> Evergreen.V26.Types.PasswordDialogModel
migratePasswordDialogModel old =
    old


migrateAmount : Evergreen.V24.Types.Amount a_old -> Evergreen.V26.Types.Amount a_new
migrateAmount old =
    case old of
        Evergreen.V24.Types.Amount amount ->
            Evergreen.V26.Types.Amount amount


migrateGroup : Evergreen.V24.Types.Group -> Evergreen.V26.Types.Group
migrateGroup old =
    old |> Dict.map (\_ share -> migrateShare share)


migrateNameValidity : Evergreen.V24.Types.NameValidity -> Evergreen.V26.Types.NameValidity
migrateNameValidity old =
    case old of
        Evergreen.V24.Types.Complete ->
            Evergreen.V26.Types.Complete

        Evergreen.V24.Types.Incomplete ->
            Evergreen.V26.Types.Incomplete

        Evergreen.V24.Types.InvalidPrefix ->
            Evergreen.V26.Types.InvalidPrefix


migratePage : Evergreen.V24.Types.Page -> Evergreen.V26.Types.Page
migratePage old =
    case old of
        Evergreen.V24.Types.Home ->
            Evergreen.V26.Types.Home

        Evergreen.V24.Types.Json json ->
            Evergreen.V26.Types.Json json

        Evergreen.V24.Types.Import path ->
            Evergreen.V26.Types.Import path

        Evergreen.V24.Types.NotFound ->
            Evergreen.V26.Types.NotFound


migrateShare : Evergreen.V24.Types.Share -> Evergreen.V26.Types.Share
migrateShare old =
    case old of
        Evergreen.V24.Types.Share share ->
            Evergreen.V26.Types.Share share


migrateTheme : Evergreen.V24.Types.Theme -> Evergreen.V26.Types.Theme
migrateTheme old =
    case old of
        Evergreen.V24.Types.LightMode ->
            Evergreen.V26.Types.LightMode

        Evergreen.V24.Types.DarkMode ->
            Evergreen.V26.Types.DarkMode


migrateTransactionStatus : Evergreen.V24.Types.TransactionStatus -> Evergreen.V26.Types.TransactionStatus
migrateTransactionStatus old =
    case old of
        Evergreen.V24.Types.Active ->
            Evergreen.V26.Types.Active

        Evergreen.V24.Types.Deleted ->
            Evergreen.V26.Types.Deleted

        Evergreen.V24.Types.Replaced ->
            Evergreen.V26.Types.Replaced


migrateGroupCreditTotals : Dict.Dict String (Dict.Dict String (Evergreen.V24.Types.Amount Evergreen.V24.Types.Credit)) -> Dict.Dict String (Dict.Dict String (Evergreen.V26.Types.Amount Evergreen.V26.Types.Credit))
migrateGroupCreditTotals old =
    old |> Dict.map (\_ inner -> inner |> Dict.map (\_ amount -> migrateAmount amount))
