module Frontend exposing (..)

import Basics.Extra exposing (flip)
import Browser exposing (UrlRequest(..))
import Browser.Dom exposing (getViewport)
import Browser.Events exposing (onResize)
import Browser.Navigation as Nav
import Date
import DatePicker
import Dialog
import Dict exposing (Dict)
import Dict.Extra as Dict
import Element exposing (..)
import Element.Background as Background
import Element.Border as Border
import Element.Font as Font
import Element.Input as Input
import Html exposing (Html)
import Html.Attributes as Attr
import Html.Events exposing (..)
import Lamdera
import List.Extra as List
import Maybe.Extra as Maybe
import Regex
import String
import Task
import Tuple exposing (..)
import Types exposing (..)
import Url


type alias Model =
    FrontendModel


app =
    Lamdera.frontend
        { init = init
        , onUrlRequest = UrlClicked
        , onUrlChange = UrlChanged
        , update = update
        , updateFromBackend = updateFromBackend
        , subscriptions = \_ -> onResize ViewportChanged
        , view = view
        }


init : Url.Url -> Nav.Key -> ( Model, Cmd FrontendMsg )
init url key =
    let
        ( page, routingCmds ) =
            routing url
    in
    ( { page = page
      , showDialog = Nothing
      , user = ""
      , nameValidity = Incomplete
      , userGroups = Nothing
      , group = ""
      , groupValidity = Incomplete
      , groupTransactions = []
      , key = key
      , windowWidth = 1000
      , windowHeight = 1000
      , checkingAuthentication = True
      , theme = LightMode
      }
    , Cmd.batch
        [ routingCmds
        , Task.perform
            (\viewport ->
                ViewportChanged
                    (round viewport.viewport.width)
                    (round viewport.viewport.height)
            )
            getViewport
        , Lamdera.sendToBackend CheckAuthentication
        ]
    )


routing : Url.Url -> ( Page, Cmd FrontendMsg )
routing url =
    case url.path of
        "/" ->
            ( Home, Cmd.none )

        "/json" ->
            ( Json Nothing, Lamdera.sendToBackend RequestAllTransactions )

        "/import" ->
            ( Import "", Cmd.none )

        _ ->
            ( NotFound, Cmd.none )


update : FrontendMsg -> Model -> ( Model, Cmd FrontendMsg )
update msg model =
    case msg of
        UrlClicked urlRequest ->
            case urlRequest of
                Internal url ->
                    let
                        ( page, routingCmds ) =
                            routing url
                    in
                    ( { model | page = page }
                    , Cmd.batch
                        [ Nav.pushUrl model.key (Url.toString url)
                        , routingCmds
                        ]
                    )

                External url ->
                    ( model
                    , Nav.load url
                    )

        UrlChanged url ->
            let
                ( page, routingCmds ) =
                    routing url
            in
            ( { model | page = page }
            , routingCmds
            )

        NoOpFrontendMsg ->
            ( model, Cmd.none )

        ShowAddPersonDialog ->
            ( { model
                | showDialog =
                    Just
                        (AddPersonDialog
                            { name = ""
                            , nameInvalid = False
                            , submitted = False
                            }
                        )
              }
            , Cmd.none
            )

        ShowAddGroupDialog ->
            ( { model
                | showDialog =
                    Just
                        (AddGroupDialog
                            { name = ""
                            , nameInvalid = False
                            , members = []
                            , submitted = False
                            }
                        )
              }
            , Cmd.none
            )

        ShowAddSpendingDialog maybeReference ->
            case maybeReference of
                Nothing ->
                    -- Create new spending
                    ( { model
                        | showDialog =
                            Just
                                (AddSpendingDialog
                                    { spendingId = Nothing
                                    , description = ""
                                    , date = Nothing
                                    , dateText = ""
                                    , datePickerModel = DatePicker.init
                                    , total = ""
                                    , credits = []
                                    , debits = []
                                    , submitted = False
                                    }
                                )
                      }
                    , Task.perform SetToday Date.today
                    )

                Just reference ->
                    -- Edit existing transaction
                    case List.find (\t -> t.transactionId == reference.transactionId) model.groupTransactions of
                        Just transaction ->
                            let
                                date =
                                    Date.fromCalendarDate transaction.year (Date.numberToMonth transaction.month) transaction.day

                                dateText =
                                    Date.format "yyyy-MM-dd" date

                                total =
                                    transaction.total |> (\(Amount amount) -> amount) |> viewAmount
                            in
                            ( { model
                                | showDialog =
                                    Just
                                        (AddSpendingDialog
                                            { spendingId = Just reference.spendingId
                                            , description = transaction.description
                                            , date = Just date
                                            , dateText = dateText
                                            , datePickerModel = DatePicker.initWithToday date
                                            , total = total
                                            , credits = [] -- Will be populated when SpendingDetails arrives
                                            , debits = [] -- Will be populated when SpendingDetails arrives
                                            , submitted = False
                                            }
                                        )
                              }
                            , Cmd.batch
                                [ Task.perform SetToday Date.today
                                , Lamdera.sendToBackend (RequestSpendingDetails reference.spendingId)
                                ]
                            )

                        Nothing ->
                            ( model, Cmd.none )

        ShowConfirmDeleteDialog spendingId ->
            ( { model | showDialog = Just (ConfirmDeleteDialog spendingId) }, Cmd.none )

        ConfirmDeleteSpending spendingId ->
            ( { model | showDialog = Nothing }
            , Lamdera.sendToBackend (DeleteSpending spendingId)
            )

        SetToday today ->
            case model.showDialog of
                Just (AddSpendingDialog dialogModel) ->
                    let
                        spendingDate =
                            dialogModel.date |> Maybe.withDefault today

                        applyDefault =
                            applySpendingDateDefault dialogModel.date spendingDate

                        setTodayInLine line =
                            { line | datePickerModel = DatePicker.setToday today line.datePickerModel }
                    in
                    ( { model
                        | showDialog =
                            Just
                                (AddSpendingDialog
                                    (normalizeSpendingDialogLines
                                        { dialogModel
                                            | datePickerModel = DatePicker.setToday today dialogModel.datePickerModel
                                            , date = Just spendingDate
                                            , dateText =
                                                if dialogModel.dateText == "" then
                                                    Date.toIsoString spendingDate

                                                else
                                                    dialogModel.dateText
                                            , credits =
                                                dialogModel.credits
                                                    |> List.map setTodayInLine
                                                    |> applyDefault
                                            , debits =
                                                dialogModel.debits
                                                    |> List.map setTodayInLine
                                                    |> applyDefault
                                        }
                                    )
                                )
                      }
                    , Cmd.none
                    )

                _ ->
                    ( model, Cmd.none )

        Submit ->
            case model.page of
                Import "" ->
                    ( model, Cmd.none )

                Import json ->
                    ( model
                    , Lamdera.sendToBackend (ImportJson json)
                    )

                Home ->
                    case model.showDialog of
                        Just (AddPersonDialog dialogModel) ->
                            ( { model | showDialog = Just (AddPersonDialog { dialogModel | submitted = True }) }
                            , Lamdera.sendToBackend (CreatePerson dialogModel.name)
                            )

                        Just (AddGroupDialog dialogModel) ->
                            let
                                members =
                                    dialogModel.members
                                        |> List.map
                                            (\( member, share, _ ) ->
                                                ( member
                                                , share
                                                    |> String.toInt
                                                    |> Maybe.withDefault 0
                                                )
                                            )
                                        |> Dict.fromListDedupe (+)
                                        |> Dict.map (\_ -> Share)
                            in
                            ( { model | showDialog = Just (AddGroupDialog { dialogModel | submitted = True }) }
                            , Lamdera.sendToBackend (CreateGroup dialogModel.name members)
                            )

                        Just (AddSpendingDialog dialogModel) ->
                            let
                                maybeTotal =
                                    dialogModel.total |> parseAmountValue

                                transactions =
                                    dialogTransactions dialogModel
                            in
                            if List.isEmpty transactions || Maybe.isNothing maybeTotal then
                                ( model, Cmd.none )

                            else
                                ( { model
                                    | showDialog =
                                        Just
                                            (AddSpendingDialog
                                                { dialogModel | submitted = True }
                                            )
                                  }
                                , case dialogModel.spendingId of
                                    Nothing ->
                                        Lamdera.sendToBackend
                                            (CreateSpending
                                                { description = dialogModel.description
                                                , total = maybeTotal |> Maybe.withDefault 0 |> Amount
                                                , transactions = transactions
                                                }
                                            )

                                    Just spendingId ->
                                        Lamdera.sendToBackend
                                            (EditSpending
                                                { spendingId = spendingId
                                                , description = dialogModel.description
                                                , total = maybeTotal |> Maybe.withDefault 0 |> Amount
                                                , transactions = transactions
                                                }
                                            )
                                )

                        Just (ConfirmDeleteDialog _) ->
                            -- This should not happen as ConfirmDeleteDialog has its own buttons
                            ( model, Cmd.none )

                        Just (PasswordDialog dialogModel) ->
                            ( { model
                                | showDialog =
                                    Just
                                        (PasswordDialog
                                            { dialogModel | submitted = True }
                                        )
                              }
                            , Lamdera.sendToBackend (CheckPassword dialogModel.password)
                            )

                        Nothing ->
                            ( model, Cmd.none )

                _ ->
                    ( model, Cmd.none )

        Cancel ->
            ( { model | showDialog = Nothing }
            , Cmd.none
            )

        UpdateName name ->
            case model.showDialog of
                Just (AddPersonDialog dialogModel) ->
                    if name == "" then
                        ( { model | showDialog = Just (AddPersonDialog { dialogModel | name = "", nameInvalid = True }) }
                        , Cmd.none
                        )

                    else
                        ( { model | showDialog = Just (AddPersonDialog { dialogModel | name = name, nameInvalid = False }) }
                        , Lamdera.sendToBackend (CheckValidName name)
                        )

                Just (AddGroupDialog dialogModel) ->
                    if name == "" then
                        ( { model | showDialog = Just (AddGroupDialog { dialogModel | name = "", nameInvalid = True }) }
                        , Cmd.none
                        )

                    else
                        ( { model | showDialog = Just (AddGroupDialog { dialogModel | name = name, nameInvalid = False }) }
                        , Lamdera.sendToBackend (CheckValidName name)
                        )

                Just (AddSpendingDialog dialogModel) ->
                    ( { model | showDialog = Just (AddSpendingDialog { dialogModel | description = name }) }
                    , Cmd.none
                    )

                Just (ConfirmDeleteDialog _) ->
                    -- No name updates for delete confirmation dialog
                    ( model, Cmd.none )

                Just (PasswordDialog dialogModel) ->
                    ( model, Cmd.none )

                Nothing ->
                    ( { model
                        | user = name
                        , nameValidity = Incomplete
                        , userGroups = Nothing
                      }
                    , if String.length name > 0 then
                        Lamdera.sendToBackend (AutocompletePerson name)

                      else
                        Cmd.none
                    )

        UpdateGroupName name ->
            ( { model
                | group = name
                , groupValidity = Incomplete
                , groupTransactions = []
              }
            , if String.length name > 0 then
                Lamdera.sendToBackend (AutocompleteGroup name)

              else
                Cmd.none
            )

        AddMember member ->
            case model.showDialog of
                Just (AddGroupDialog dialogModel) ->
                    ( { model
                        | showDialog =
                            Just
                                (AddGroupDialog
                                    { dialogModel
                                        | members =
                                            dialogModel.members
                                                |> addNameInList member "1"
                                    }
                                )
                      }
                    , Lamdera.sendToBackend (AutocompletePerson member)
                    )

                _ ->
                    ( model, Cmd.none )

        UpdateMember index member ->
            case model.showDialog of
                Just (AddGroupDialog dialogModel) ->
                    ( { model
                        | showDialog =
                            Just
                                (AddGroupDialog
                                    { dialogModel
                                        | members =
                                            dialogModel.members
                                                |> updateNameInList
                                                    index
                                                    member
                                                    (\_ -> "1")
                                    }
                                )
                      }
                    , if String.length member > 0 then
                        Lamdera.sendToBackend (AutocompletePerson member)

                      else
                        Cmd.none
                    )

                _ ->
                    ( model, Cmd.none )

        UpdateShare index share ->
            case model.showDialog of
                Just (AddGroupDialog dialogModel) ->
                    ( { model
                        | showDialog =
                            Just
                                (AddGroupDialog
                                    { dialogModel
                                        | members =
                                            dialogModel.members
                                                |> updateValueInList index share
                                    }
                                )
                      }
                    , Cmd.none
                    )

                _ ->
                    ( model, Cmd.none )

        UpdateSpendingTotal total ->
            case model.showDialog of
                Just (AddSpendingDialog dialogModel) ->
                    ( { model
                        | showDialog =
                            Just
                                (AddSpendingDialog
                                    (normalizeSpendingDialogLines { dialogModel | total = total })
                                )
                      }
                    , Cmd.none
                    )

                _ ->
                    ( model, Cmd.none )

        UpdateSpendingDate changeEvent ->
            case model.showDialog of
                Just (AddSpendingDialog dialogModel) ->
                    ( { model
                        | showDialog =
                            Just
                                (AddSpendingDialog
                                    (updateSpendingDate changeEvent dialogModel)
                                )
                      }
                    , Cmd.none
                    )

                _ ->
                    ( model, Cmd.none )

        AddCredit ->
            case model.showDialog of
                Just (AddSpendingDialog dialogModel) ->
                    ( { model
                        | showDialog =
                            Just
                                (AddSpendingDialog
                                    (normalizeSpendingDialogLines
                                        { dialogModel
                                            | credits = addTransactionLine dialogModel.date dialogModel.total dialogModel.credits
                                        }
                                    )
                                )
                      }
                    , Cmd.none
                    )

                _ ->
                    ( model, Cmd.none )

        UpdateCreditGroup index group ->
            case model.showDialog of
                Just (AddSpendingDialog dialogModel) ->
                    ( { model
                        | showDialog =
                            Just
                                (AddSpendingDialog
                                    (normalizeSpendingDialogLines
                                        { dialogModel
                                            | credits =
                                                updateTransactionLine index
                                                    (\line -> { line | group = group, nameValidity = Incomplete })
                                                    dialogModel.credits
                                        }
                                    )
                                )
                      }
                    , if String.length group > 0 then
                        Lamdera.sendToBackend (AutocompleteGroup group)

                      else
                        Cmd.none
                    )

                _ ->
                    ( model, Cmd.none )

        UpdateCreditAmount index amount ->
            case model.showDialog of
                Just (AddSpendingDialog dialogModel) ->
                    ( { model
                        | showDialog =
                            Just
                                (AddSpendingDialog
                                    (normalizeSpendingDialogLines
                                        { dialogModel
                                            | credits =
                                                updateTransactionLine index
                                                    (\line -> { line | amount = amount })
                                                    dialogModel.credits
                                        }
                                    )
                                )
                      }
                    , Cmd.none
                    )

                _ ->
                    ( model, Cmd.none )

        RemoveCredit index ->
            case model.showDialog of
                Just (AddSpendingDialog dialogModel) ->
                    ( { model
                        | showDialog =
                            Just
                                (AddSpendingDialog
                                    (normalizeSpendingDialogLines
                                        { dialogModel
                                            | credits = removeTransactionLine index dialogModel.credits
                                        }
                                    )
                                )
                      }
                    , Cmd.none
                    )

                _ ->
                    ( model, Cmd.none )

        ToggleCreditDetails index ->
            case model.showDialog of
                Just (AddSpendingDialog dialogModel) ->
                    ( { model
                        | showDialog =
                            Just
                                (AddSpendingDialog
                                    (normalizeSpendingDialogLines
                                        { dialogModel
                                            | credits =
                                                updateTransactionLine index
                                                    (\line -> { line | detailsExpanded = not line.detailsExpanded })
                                                    dialogModel.credits
                                        }
                                    )
                                )
                      }
                    , Cmd.none
                    )

                _ ->
                    ( model, Cmd.none )

        UpdateCreditDate index changeEvent ->
            case model.showDialog of
                Just (AddSpendingDialog dialogModel) ->
                    ( { model
                        | showDialog =
                            Just
                                (AddSpendingDialog
                                    (normalizeSpendingDialogLines
                                        { dialogModel
                                            | credits = updateTransactionLineDate index changeEvent dialogModel.credits
                                        }
                                    )
                                )
                      }
                    , Cmd.none
                    )

                _ ->
                    ( model, Cmd.none )

        UpdateCreditSecondaryDescription index description ->
            case model.showDialog of
                Just (AddSpendingDialog dialogModel) ->
                    ( { model
                        | showDialog =
                            Just
                                (AddSpendingDialog
                                    (normalizeSpendingDialogLines
                                        { dialogModel
                                            | credits =
                                                updateTransactionLine index
                                                    (\line -> { line | secondaryDescription = description })
                                                    dialogModel.credits
                                        }
                                    )
                                )
                      }
                    , Cmd.none
                    )

                _ ->
                    ( model, Cmd.none )

        AddDebit ->
            case model.showDialog of
                Just (AddSpendingDialog dialogModel) ->
                    ( { model
                        | showDialog =
                            Just
                                (AddSpendingDialog
                                    (normalizeSpendingDialogLines
                                        { dialogModel
                                            | debits = addTransactionLine dialogModel.date dialogModel.total dialogModel.debits
                                        }
                                    )
                                )
                      }
                    , Cmd.none
                    )

                _ ->
                    ( model, Cmd.none )

        UpdateDebitGroup index group ->
            case model.showDialog of
                Just (AddSpendingDialog dialogModel) ->
                    ( { model
                        | showDialog =
                            Just
                                (AddSpendingDialog
                                    (normalizeSpendingDialogLines
                                        { dialogModel
                                            | debits =
                                                updateTransactionLine index
                                                    (\line -> { line | group = group, nameValidity = Incomplete })
                                                    dialogModel.debits
                                        }
                                    )
                                )
                      }
                    , if String.length group > 0 then
                        Lamdera.sendToBackend (AutocompleteGroup group)

                      else
                        Cmd.none
                    )

                _ ->
                    ( model, Cmd.none )

        UpdateDebitAmount index amount ->
            case model.showDialog of
                Just (AddSpendingDialog dialogModel) ->
                    ( { model
                        | showDialog =
                            Just
                                (AddSpendingDialog
                                    (normalizeSpendingDialogLines
                                        { dialogModel
                                            | debits =
                                                updateTransactionLine index
                                                    (\line -> { line | amount = amount })
                                                    dialogModel.debits
                                        }
                                    )
                                )
                      }
                    , Cmd.none
                    )

                _ ->
                    ( model, Cmd.none )

        UpdateDebitDate index changeEvent ->
            case model.showDialog of
                Just (AddSpendingDialog dialogModel) ->
                    ( { model
                        | showDialog =
                            Just
                                (AddSpendingDialog
                                    (normalizeSpendingDialogLines
                                        { dialogModel
                                            | debits = updateTransactionLineDate index changeEvent dialogModel.debits
                                        }
                                    )
                                )
                      }
                    , Cmd.none
                    )

                _ ->
                    ( model, Cmd.none )

        UpdateDebitSecondaryDescription index description ->
            case model.showDialog of
                Just (AddSpendingDialog dialogModel) ->
                    ( { model
                        | showDialog =
                            Just
                                (AddSpendingDialog
                                    (normalizeSpendingDialogLines
                                        { dialogModel
                                            | debits =
                                                updateTransactionLine index
                                                    (\line -> { line | secondaryDescription = description })
                                                    dialogModel.debits
                                        }
                                    )
                                )
                      }
                    , Cmd.none
                    )

                _ ->
                    ( model, Cmd.none )

        RemoveDebit index ->
            case model.showDialog of
                Just (AddSpendingDialog dialogModel) ->
                    ( { model
                        | showDialog =
                            Just
                                (AddSpendingDialog
                                    (normalizeSpendingDialogLines
                                        { dialogModel
                                            | debits = removeTransactionLine index dialogModel.debits
                                        }
                                    )
                                )
                      }
                    , Cmd.none
                    )

                _ ->
                    ( model, Cmd.none )

        ToggleDebitDetails index ->
            case model.showDialog of
                Just (AddSpendingDialog dialogModel) ->
                    ( { model
                        | showDialog =
                            Just
                                (AddSpendingDialog
                                    (normalizeSpendingDialogLines
                                        { dialogModel
                                            | debits =
                                                updateTransactionLine index
                                                    (\line -> { line | detailsExpanded = not line.detailsExpanded })
                                                    dialogModel.debits
                                        }
                                    )
                                )
                      }
                    , Cmd.none
                    )

                _ ->
                    ( model, Cmd.none )

        UpdatePassword password ->
            case model.showDialog of
                Just (PasswordDialog dialogModel) ->
                    ( { model
                        | showDialog =
                            Just
                                (PasswordDialog
                                    { dialogModel | password = password }
                                )
                      }
                    , Cmd.none
                    )

                _ ->
                    ( model, Cmd.none )

        UpdateJson json ->
            case model.page of
                Import _ ->
                    ( { model | page = Import json }
                    , Cmd.none
                    )

                _ ->
                    ( model, Cmd.none )

        ViewportChanged width height ->
            ( { model
                | windowWidth = width
                , windowHeight = height
              }
            , Cmd.none
            )

        ToggleTheme ->
            ( { model
                | theme =
                    case model.theme of
                        LightMode ->
                            DarkMode

                        DarkMode ->
                            LightMode
              }
            , Cmd.none
            )


emptySpendingDialog spendingId description total =
    normalizeSpendingDialogLines
        { spendingId = spendingId
        , description = description
        , total = total
        , date = Nothing
        , dateText = ""
        , datePickerModel = DatePicker.init
        , credits = []
        , debits = []
        , submitted = False
        }


setSpendingDateValue date dialogModel =
    { dialogModel
        | date = Just date
        , dateText = Date.toIsoString date
        , datePickerModel = DatePicker.initWithToday date
    }


defaultTransactionLine maybeDate amount =
    { date = maybeDate
    , dateText = maybeDate |> Maybe.map Date.toIsoString |> Maybe.withDefault ""
    , datePickerModel =
        maybeDate
            |> Maybe.map DatePicker.initWithToday
            |> Maybe.withDefault DatePicker.init
    , secondaryDescription = ""
    , detailsExpanded = False
    , group = ""
    , amount = amount
    , nameValidity = Incomplete
    }


remainingAmount total lines =
    ((total
        |> parseAmountValue
        |> Maybe.withDefault 0
     )
        - (lines
            |> List.filterMap (.amount >> parseAmountValue)
            |> List.sum
          )
    )
        |> formatAmountValue


addTransactionLine maybeDate total lines =
    lines ++ [ defaultTransactionLine maybeDate (defaultTransactionLineAmount total lines) ]


removeTransactionLine index lines =
    lines
        |> List.indexedMap Tuple.pair
        |> List.filter (\( currentIndex, _ ) -> currentIndex /= index)
        |> List.map Tuple.second


updateTransactionLine index updateLine lines =
    List.updateAt index updateLine lines


updateTransactionLineDate index changeEvent lines =
    updateTransactionLine index
        (\line ->
            case changeEvent of
                DatePicker.DateChanged date ->
                    { line
                        | date = Just date
                        , dateText = Date.toIsoString date
                        , datePickerModel = DatePicker.close line.datePickerModel
                    }

                DatePicker.TextChanged dateText ->
                    { line
                        | date = Date.fromIsoString dateText |> Result.toMaybe
                        , dateText = dateText
                    }

                DatePicker.PickerChanged subMsg ->
                    { line | datePickerModel = DatePicker.update subMsg line.datePickerModel }
        )
        lines


defaultTransactionLineAmount total lines =
    if String.trim total == "" then
        ""

    else
        remainingAmount total lines


transactionLineIsComplete line =
    String.trim line.group
        /= ""
        && (line.amount |> parseAmountValue |> Maybe.isJust)
        && Maybe.isJust line.date


transactionLineIsBlank spendingDate line =
    String.trim line.group
        == ""
        && String.trim line.amount
        == ""
        && not (transactionLineHasCustomDetails spendingDate line)


normalizeTransactionLines maybeDate total lines =
    let
        nonBlankLines =
            lines
                |> List.filter (transactionLineIsBlank maybeDate >> not)
    in
    if List.last nonBlankLines |> Maybe.map transactionLineIsComplete |> Maybe.withDefault True then
        nonBlankLines ++ [ defaultTransactionLine maybeDate (defaultTransactionLineAmount total nonBlankLines) ]

    else
        nonBlankLines


normalizeTransactionLinesWithoutAutofill maybeDate lines =
    let
        nonBlankLines =
            lines
                |> List.filter (transactionLineIsBlank maybeDate >> not)
    in
    if List.last nonBlankLines |> Maybe.map transactionLineIsComplete |> Maybe.withDefault True then
        nonBlankLines ++ [ defaultTransactionLine maybeDate "" ]

    else
        nonBlankLines


normalizeSpendingDialogLines dialogModel =
    { dialogModel
        | credits = normalizeTransactionLinesWithoutAutofill dialogModel.date dialogModel.credits
        , debits = normalizeTransactionLinesWithoutAutofill dialogModel.date dialogModel.debits
    }


lineUsesDefaultDate previousSpendingDate line =
    case ( previousSpendingDate, line.date ) of
        ( _, Nothing ) ->
            True

        ( Just previousDate, Just lineDate ) ->
            lineDate == previousDate

        ( Nothing, Just _ ) ->
            False


setTransactionLineDate date line =
    { line
        | date = Just date
        , dateText = Date.toIsoString date
        , datePickerModel = DatePicker.initWithToday date
    }


applySpendingDateDefault previousSpendingDate newDate =
    List.map
        (\line ->
            if lineUsesDefaultDate previousSpendingDate line then
                setTransactionLineDate newDate line

            else
                line
        )


updateSpendingDate changeEvent dialogModel =
    case changeEvent of
        DatePicker.DateChanged date ->
            let
                applyDefault =
                    applySpendingDateDefault dialogModel.date date

                updatedDialog =
                    dialogModel |> setSpendingDateValue date
            in
            normalizeSpendingDialogLines
                { updatedDialog
                    | credits = applyDefault dialogModel.credits
                    , debits = applyDefault dialogModel.debits
                }

        DatePicker.TextChanged dateText ->
            case Date.fromIsoString dateText |> Result.toMaybe of
                Just date ->
                    let
                        applyDefault =
                            applySpendingDateDefault dialogModel.date date

                        updatedDialog =
                            dialogModel |> setSpendingDateValue date
                    in
                    normalizeSpendingDialogLines
                        { updatedDialog
                            | dateText = dateText
                            , credits = applyDefault dialogModel.credits
                            , debits = applyDefault dialogModel.debits
                        }

                Nothing ->
                    { dialogModel | date = Nothing, dateText = dateText }

        DatePicker.PickerChanged subMsg ->
            { dialogModel | datePickerModel = DatePicker.update subMsg dialogModel.datePickerModel }


transactionLineFromSpendingTransaction side transaction =
    if transaction.side == side then
        case transaction.amount of
            Amount amount ->
                let
                    date =
                        Date.fromCalendarDate transaction.year (Date.numberToMonth transaction.month) transaction.day
                in
                Just
                    { date = Just date
                    , dateText = Date.toIsoString date
                    , datePickerModel = DatePicker.initWithToday date
                    , secondaryDescription = transaction.secondaryDescription
                    , detailsExpanded = False
                    , group = transaction.group
                    , amount = formatAmountValue amount
                    , nameValidity = Complete
                    }

    else
        Nothing


transactionLineToSpendingTransaction side line =
    case ( line.date, parseAmountValue line.amount ) of
        ( Just date, Just amount ) ->
            Just
                { year = Date.year date
                , month = Date.monthNumber date
                , day = Date.day date
                , secondaryDescription = line.secondaryDescription
                , group = line.group
                , amount = Amount amount
                , side = side
                }

        _ ->
            Nothing


dialogTransactions dialogModel =
    (dialogModel.debits
        |> List.filterMap (transactionLineToSpendingTransaction DebitTransaction)
    )
        ++ (dialogModel.credits
                |> List.filterMap (transactionLineToSpendingTransaction CreditTransaction)
           )


addNameInList name defaultValue list =
    ( name, defaultValue, Incomplete ) :: list


updateNameInList index name computeDefaultValue list =
    if index == 0 && name == "" then
        case list of
            [] ->
                []

            ( _, value, _ ) :: tail ->
                if value == "" || value == computeDefaultValue tail then
                    tail

                else
                    ( name, value, Incomplete ) :: tail

    else
        list
            |> List.updateAt index
                (\( _, value, _ ) ->
                    ( name, value, Incomplete )
                )


updateValueInList index value list =
    if index == 0 && value == "" then
        case list of
            [] ->
                []

            ( name, _, nameValidity ) :: tail ->
                if name == "" then
                    tail

                else
                    ( name, value, nameValidity ) :: tail

    else
        list
            |> List.updateAt index
                (\( name, _, nameValidity ) ->
                    ( name, value, nameValidity )
                )


updateFromBackend : ToFrontend -> Model -> ( Model, Cmd FrontendMsg )
updateFromBackend msg model =
    case msg of
        NoOpToFrontend ->
            ( model, Cmd.none )

        OperationSuccessful ->
            case model.page of
                Import _ ->
                    ( { model | page = Import "" }
                    , Cmd.none
                    )

                Home ->
                    ( { model | showDialog = Nothing }
                    , (++)
                        (if model.nameValidity == Complete then
                            [ Lamdera.sendToBackend (RequestUserGroups model.user) ]

                         else
                            []
                        )
                        (if model.groupValidity == Complete then
                            [ Lamdera.sendToBackend (RequestGroupTransactions model.group) ]

                         else
                            []
                        )
                        |> Cmd.batch
                    )

                _ ->
                    ( model, Cmd.none )

        NameAlreadyExists name ->
            case model.showDialog of
                Just (AddPersonDialog dialogModel) ->
                    if dialogModel.name == name then
                        -- we reset submitted to False because this can be
                        -- an error message we get from the backend in case
                        -- of a race creating this person
                        ( { model
                            | showDialog =
                                Just
                                    (AddPersonDialog
                                        { dialogModel
                                            | nameInvalid = True
                                            , submitted = False
                                        }
                                    )
                          }
                        , Cmd.none
                        )

                    else
                        ( model, Cmd.none )

                Just (AddGroupDialog dialogModel) ->
                    if dialogModel.name == name then
                        -- we reset submitted to False because this can be
                        -- an error message we get from the backend in case
                        -- of a race creating this group
                        ( { model
                            | showDialog =
                                Just
                                    (AddGroupDialog
                                        { dialogModel
                                            | nameInvalid = True
                                            , submitted = False
                                        }
                                    )
                          }
                        , Cmd.none
                        )

                    else
                        ( model, Cmd.none )

                _ ->
                    ( model, Cmd.none )

        InvalidPersonPrefix prefix ->
            case model.showDialog of
                Just (AddGroupDialog dialogModel) ->
                    ( { model
                        | showDialog =
                            Just
                                (AddGroupDialog
                                    { dialogModel
                                        | members =
                                            dialogModel.members
                                                |> markInvalidPrefix prefix
                                    }
                                )
                      }
                    , Cmd.none
                    )

                Nothing ->
                    ( if String.startsWith prefix model.user then
                        { model | nameValidity = InvalidPrefix }

                      else
                        model
                    , Cmd.none
                    )

                _ ->
                    ( model, Cmd.none )

        AutocompletePersonPrefix response ->
            case model.showDialog of
                Just (AddGroupDialog dialogModel) ->
                    ( { model
                        | showDialog =
                            Just
                                (AddGroupDialog
                                    { dialogModel
                                        | members =
                                            dialogModel.members
                                                |> completeToLongestCommonPrefix response
                                    }
                                )
                      }
                    , Cmd.none
                    )

                Nothing ->
                    let
                        userLower =
                            String.toLower model.user
                    in
                    if
                        String.startsWith response.prefixLower userLower
                            && String.startsWith userLower (String.toLower response.longestCommonPrefix)
                    then
                        ( { model
                            | user = response.longestCommonPrefix
                            , nameValidity =
                                if response.complete then
                                    Complete

                                else
                                    Incomplete
                          }
                        , if response.complete then
                            Lamdera.sendToBackend
                                (RequestUserGroups response.longestCommonPrefix)

                          else
                            Cmd.none
                        )

                    else
                        ( model, Cmd.none )

                _ ->
                    ( model, Cmd.none )

        InvalidGroupPrefix prefix ->
            case model.showDialog of
                Just (AddSpendingDialog dialogModel) ->
                    ( { model
                        | showDialog =
                            Just
                                (AddSpendingDialog
                                    { dialogModel
                                        | credits = dialogModel.credits |> markInvalidGroupPrefix prefix
                                        , debits = dialogModel.debits |> markInvalidGroupPrefix prefix
                                    }
                                )
                      }
                    , Cmd.none
                    )

                Just _ ->
                    ( model, Cmd.none )

                Nothing ->
                    ( if String.startsWith prefix model.group then
                        { model | groupValidity = InvalidPrefix }

                      else
                        model
                    , Cmd.none
                    )

        AutocompleteGroupPrefix response ->
            case model.showDialog of
                Just (AddSpendingDialog dialogModel) ->
                    ( { model
                        | showDialog =
                            Just
                                (AddSpendingDialog
                                    { dialogModel
                                        | credits = dialogModel.credits |> completeGroupPrefix response
                                        , debits = dialogModel.debits |> completeGroupPrefix response
                                    }
                                )
                      }
                    , Cmd.none
                    )

                Just _ ->
                    ( model, Cmd.none )

                Nothing ->
                    let
                        groupLower =
                            String.toLower model.group
                    in
                    if
                        String.startsWith response.prefixLower groupLower
                            && String.startsWith groupLower (String.toLower response.longestCommonPrefix)
                    then
                        ( { model
                            | group = response.longestCommonPrefix
                            , groupValidity =
                                if response.complete then
                                    Complete

                                else
                                    Incomplete
                          }
                        , if response.complete then
                            Lamdera.sendToBackend
                                (RequestGroupTransactions response.longestCommonPrefix)

                          else
                            Cmd.none
                        )

                    else
                        ( model, Cmd.none )

        ListUserGroups { user, debitors, creditors } ->
            ( if model.user == user then
                { model
                    | userGroups =
                        Just
                            { debitors = debitors
                            , creditors = creditors
                            }
                }

              else
                model
            , Cmd.none
            )

        ListGroupTransactions { group, transactions } ->
            ( if model.group == group then
                { model
                    | groupTransactions =
                        transactions
                }

              else
                model
            , Cmd.none
            )

        AuthenticationStatus isAuthenticated ->
            if isAuthenticated then
                -- Already authenticated, don't show password dialog
                ( { model | showDialog = Nothing, checkingAuthentication = False }, Cmd.none )

            else
                -- Not authenticated, show password dialog
                ( { model | showDialog = Just (PasswordDialog { password = "", submitted = False }), checkingAuthentication = False }
                , Cmd.none
                )

        JsonExport json ->
            case model.page of
                Json _ ->
                    ( { model | page = Json (Just json) }, Cmd.none )

                _ ->
                    ( model, Cmd.none )

        SpendingError _ ->
            -- TODO: Show error message to user in UI
            case model.showDialog of
                Just (AddSpendingDialog dialogModel) ->
                    ( { model
                        | showDialog =
                            Just (AddSpendingDialog { dialogModel | submitted = False })
                      }
                    , Cmd.none
                    )

                _ ->
                    ( model, Cmd.none )

        SpendingDetails { spendingId, description, total, transactions } ->
            -- Update the edit dialog with the fetched transaction details
            case model.showDialog of
                Just (AddSpendingDialog dialogModel) ->
                    if dialogModel.spendingId == Just spendingId then
                        let
                            spendingDate =
                                transactions
                                    |> List.sortBy (\transaction -> ( transaction.year, transaction.month, transaction.day ))
                                    |> List.head
                                    |> Maybe.map
                                        (\transaction ->
                                            Date.fromCalendarDate
                                                transaction.year
                                                (Date.numberToMonth transaction.month)
                                                transaction.day
                                        )

                            credits =
                                transactions
                                    |> List.filterMap (transactionLineFromSpendingTransaction CreditTransaction)

                            debits =
                                transactions
                                    |> List.filterMap (transactionLineFromSpendingTransaction DebitTransaction)
                        in
                        ( { model
                            | showDialog =
                                Just
                                    (AddSpendingDialog
                                        (normalizeSpendingDialogLines
                                            { dialogModel
                                                | description = description
                                                , total = total |> (\(Amount amount) -> formatAmountValue amount)
                                                , date =
                                                    case spendingDate of
                                                        Just spendingDateValue ->
                                                            Just spendingDateValue

                                                        Nothing ->
                                                            dialogModel.date
                                                , dateText =
                                                    spendingDate
                                                        |> Maybe.map Date.toIsoString
                                                        |> Maybe.withDefault dialogModel.dateText
                                                , datePickerModel =
                                                    spendingDate
                                                        |> Maybe.map DatePicker.initWithToday
                                                        |> Maybe.withDefault dialogModel.datePickerModel
                                                , credits = credits
                                                , debits = debits
                                            }
                                        )
                                    )
                          }
                        , Cmd.none
                        )

                    else
                        ( model, Cmd.none )

                _ ->
                    ( model, Cmd.none )


markInvalidPrefix prefix list =
    list
        |> List.map
            (\( name, value, nameValidity ) ->
                if String.startsWith prefix name then
                    ( name, value, InvalidPrefix )

                else
                    ( name, value, nameValidity )
            )


completeToLongestCommonPrefix { prefixLower, longestCommonPrefix, complete } list =
    list
        |> List.map
            (\( name, value, nameValidity ) ->
                let
                    n =
                        String.toLower name
                in
                if
                    String.startsWith prefixLower n
                        && String.startsWith n (String.toLower longestCommonPrefix)
                then
                    ( longestCommonPrefix
                    , value
                    , if complete then
                        Complete

                      else
                        Incomplete
                    )

                else
                    ( name, value, nameValidity )
            )


markInvalidGroupPrefix prefix lines =
    lines
        |> List.map
            (\line ->
                if String.startsWith prefix line.group then
                    { line | nameValidity = InvalidPrefix }

                else
                    line
            )


completeGroupPrefix { prefixLower, longestCommonPrefix, complete } lines =
    lines
        |> List.map
            (\line ->
                let
                    groupLower =
                        String.toLower line.group
                in
                if
                    String.startsWith prefixLower groupLower
                        && String.startsWith groupLower (String.toLower longestCommonPrefix)
                then
                    { line
                        | group = longestCommonPrefix
                        , nameValidity =
                            if complete then
                                Complete

                            else
                                Incomplete
                    }

                else
                    line
            )


view : Model -> Browser.Document FrontendMsg
view model =
    let
        palette =
            getPalette model.theme

        themeButton =
            Input.button
                (buttonStyle ++ [ Background.color palette.surface, Font.color palette.text, Border.color palette.text ])
                { label =
                    text
                        (case model.theme of
                            LightMode ->
                                "🌙 Dark Mode"

                            DarkMode ->
                                "☀️ Light Mode"
                        )
                , onPress = Just ToggleTheme
                }
    in
    case model.page of
        NotFound ->
            { title = "Accounting - Not Found"
            , body =
                [ layout [ Background.color palette.background, Font.color palette.text ]
                    (column [ centerX, padding 20, spacing 20 ]
                        [ row [] [ text "Page not found" ]
                        , row []
                            [ link
                                [ mouseOver [ Font.color (rgb255 255 0 0) ]
                                , Font.underline
                                ]
                                { label = text "Return home", url = "/" }
                            ]
                        ]
                    )
                ]
            }

        Json json ->
            { title = "Accounting - JSON"
            , body =
                [ layout
                    [ centerX
                    , padding 50
                    , Background.color palette.background
                    , Font.color palette.text
                    ]
                    (column
                        [ shrink |> maximum (model.windowHeight * 9 // 10) |> height
                        , scrollbarY
                        , Border.solid
                        , Border.rounded 5
                        , Border.width 1
                        , padding 5
                        ]
                        [ paragraph
                            []
                            [ case json of
                                Just jsonString ->
                                    el
                                        [ Font.family [ Font.monospace ]
                                        , Font.size 14
                                        , height fill
                                        ]
                                        (text jsonString)

                                Nothing ->
                                    text "Waiting to receive JSON export"
                            ]
                        ]
                    )
                ]
            }

        Import json ->
            { title = "Accounting - Import"
            , body =
                [ layout [ Background.color palette.background, Font.color palette.text ]
                    (column [ padding 20, spacing 20, width fill ]
                        [ el [ centerX ] (text "Import JSON")
                        , Input.multiline
                            [ width fill
                            , px (model.windowHeight * 8 // 10) |> height
                            , Font.family [ Font.monospace ]
                            , Font.size 14
                            , Background.color palette.inputBackground
                            , Font.color palette.text
                            ]
                            { text = json
                            , placeholder = Just (Input.placeholder [] (text "Paste JSON here"))
                            , onChange = UpdateJson
                            , label = Input.labelHidden "JSON"
                            , spellcheck = False
                            }
                        , el [ centerX ]
                            (Input.button (greenButtonStyle palette)
                                { label = text "Import"
                                , onPress =
                                    if String.length json > 0 then
                                        Just Submit

                                    else
                                        Nothing
                                }
                            )
                        ]
                    )
                ]
            }

        Home ->
            if model.checkingAuthentication then
                { title = "Accounting"
                , body =
                    [ layout [ Background.color palette.background, Font.color palette.text ]
                        (column [ centerX, centerY, spacing 20 ]
                            [ el [ centerX ] (text "🔄")
                            , el [ centerX ] (text "Checking authentication...")
                            ]
                        )
                    ]
                }

            else
                let
                    config title inputs canSubmit =
                        { closeMessage = Just Cancel
                        , maskAttributes = []
                        , containerAttributes =
                            [ Background.color palette.background
                            , Font.color palette.text
                            , Border.solid
                            , Border.rounded 5
                            , Border.width 1
                            , centerX
                            , centerY
                            , shrink |> maximum (model.windowHeight * 9 // 10) |> height
                            , scrollbarY
                            ]
                        , headerAttributes =
                            [ padding 20
                            , Background.color palette.accent
                            , Font.color palette.accentText
                            ]
                        , bodyAttributes =
                            [ padding 20
                            , height fill
                            ]
                        , footerAttributes =
                            [ Border.widthEach { top = 1, bottom = 0, left = 0, right = 0 }
                            , Border.solid
                            ]
                        , header = Just (text title)
                        , body =
                            Just
                                (column [ spacing 20 ]
                                    inputs
                                )
                        , footer =
                            Just
                                (row [ centerX, spacing 20, padding 20, alignRight ]
                                    [ Input.button (redButtonStyle palette)
                                        { label = text "Cancel"
                                        , onPress = Just Cancel
                                        }
                                    , Input.button
                                        (if canSubmit then
                                            greenButtonStyle palette

                                         else
                                            grayButtonStyle palette
                                        )
                                        { label = text "Submit"
                                        , onPress =
                                            if canSubmit then
                                                Just Submit

                                            else
                                                Nothing
                                        }
                                    ]
                                )
                        }

                    dialogConfig =
                        model.showDialog
                            |> Maybe.map
                                (\dialog ->
                                    case dialog of
                                        AddPersonDialog dialogModel ->
                                            config "Add Person"
                                                (nameInput palette model.windowWidth dialogModel)
                                                (canSubmitPerson dialogModel)

                                        AddGroupDialog dialogModel ->
                                            let
                                                label =
                                                    "Add Group / Account"
                                            in
                                            config label
                                                (addGroupInputs palette model.windowWidth dialogModel)
                                                (canSubmitGroup dialogModel)

                                        AddSpendingDialog dialogModel ->
                                            let
                                                title =
                                                    case dialogModel.spendingId of
                                                        Nothing ->
                                                            "Add Spending"

                                                        Just _ ->
                                                            "Edit Spending"
                                            in
                                            config title
                                                (addSpendingInputs palette model.windowWidth dialogModel)
                                                (canSubmitSpending dialogModel)

                                        ConfirmDeleteDialog spendingId ->
                                            { closeMessage = Just Cancel
                                            , maskAttributes = []
                                            , containerAttributes =
                                                [ Background.color palette.background
                                                , Font.color palette.text
                                                , Border.solid
                                                , Border.rounded 5
                                                , Border.width 1
                                                , centerX
                                                , centerY
                                                , shrink |> maximum (model.windowHeight * 9 // 10) |> height
                                                , scrollbarY
                                                ]
                                            , headerAttributes =
                                                [ padding 20
                                                , Background.color palette.accent
                                                , Font.color palette.accentText
                                                ]
                                            , bodyAttributes =
                                                [ padding 20
                                                , height fill
                                                ]
                                            , footerAttributes =
                                                [ Border.widthEach { top = 1, bottom = 0, left = 0, right = 0 }
                                                , Border.solid
                                                ]
                                            , header = Just (text "Confirm Delete")
                                            , body =
                                                Just
                                                    (column [ spacing 15 ]
                                                        [ Element.paragraph []
                                                            [ Element.text "Are you sure you want to delete this spending?" ]
                                                        ]
                                                    )
                                            , footer =
                                                Just
                                                    (row [ centerX, spacing 20, padding 20, alignRight ]
                                                        [ Input.button (redButtonStyle palette)
                                                            { label = text "Cancel"
                                                            , onPress = Just Cancel
                                                            }
                                                        , Input.button (greenButtonStyle palette)
                                                            { label = text "Delete"
                                                            , onPress = Just (ConfirmDeleteSpending spendingId)
                                                            }
                                                        ]
                                                    )
                                            }

                                        PasswordDialog dialogModel ->
                                            config "Password"
                                                [ Input.currentPassword (inputStyle palette)
                                                    { label = labelStyle model.windowWidth "Password"
                                                    , placeholder = Nothing
                                                    , onChange = UpdatePassword
                                                    , text = dialogModel.password
                                                    , show = False
                                                    }
                                                ]
                                                (String.length dialogModel.password > 0)
                                )

                    textFieldAttributes field =
                        case field model of
                            InvalidPrefix ->
                                inputStyle palette ++ [ Background.color palette.error ]

                            _ ->
                                inputStyle palette
                in
                { title = "Accounting"
                , body =
                    -- Elm UI body
                    [ layout
                        [ inFront
                            (el
                                [ alignTop
                                , width fill
                                , Background.color palette.navbar
                                , Font.color palette.text
                                , Border.shadow { offset = ( 0, 2 ), size = 1, blur = 4, color = rgba 0 0 0 0.1 }
                                ]
                                ((if model.windowWidth > 650 then
                                    row [ centerX, spacing 70, padding 20 ]

                                  else
                                    column [ centerX, spacing 20, padding 20 ]
                                 )
                                    [ Input.button (greenButtonStyle palette)
                                        { label = text "Add Person"
                                        , onPress = Just ShowAddPersonDialog
                                        }
                                    , Input.button (greenButtonStyle palette)
                                        { label = text "Add Group / Account"
                                        , onPress = Just ShowAddGroupDialog
                                        }
                                    , Input.button (greenButtonStyle palette)
                                        { label = text "Add Spending"
                                        , onPress = Just (ShowAddSpendingDialog Nothing)
                                        }
                                    , themeButton
                                    ]
                                )
                            )
                        , inFront (Dialog.view dialogConfig)
                        , Background.color palette.background
                        , Font.color palette.text
                        ]
                        (column
                            [ width fill
                            , spacing 20
                            , paddingEach
                                { top =
                                    if model.windowWidth < 650 then
                                        300

                                    else
                                        100
                                , left = 20
                                , right = 20
                                , bottom = 20
                                }
                            ]
                            ([ Input.text (textFieldAttributes .nameValidity)
                                { label = labelStyle model.windowWidth "Your name:"
                                , placeholder = Nothing
                                , onChange = UpdateName
                                , text = model.user
                                }
                             ]
                                ++ (case model.userGroups of
                                        Just { debitors, creditors } ->
                                            [ row [ width fill, spaceEvenly, padding 20 ]
                                                [ column [ spacing 10, Background.color palette.surface, padding 20 ]
                                                    [ text "Your Debitor Groups / Accounts"
                                                    , viewGroups model.user debitors
                                                    ]
                                                , column [ spacing 10, Background.color palette.surface, padding 20 ]
                                                    [ text "Your Creditor Groups / Accounts"
                                                    , viewGroups model.user creditors
                                                    ]
                                                , column [ spacing 10, Background.color palette.surface, padding 20 ]
                                                    [ text "Amounts due"
                                                    , personalAmountsDue debitors creditors
                                                        |> Dict.toList
                                                        |> viewAmountsDue
                                                    ]
                                                ]
                                            ]

                                        _ ->
                                            []
                                   )
                                ++ [ Input.text (textFieldAttributes .groupValidity)
                                        { label = labelStyle model.windowWidth "Display transactions for group / account:"
                                        , placeholder = Nothing
                                        , onChange = UpdateGroupName
                                        , text = model.group
                                        }
                                   ]
                                ++ List.map (viewTransaction palette) model.groupTransactions
                            )
                        )
                    ]
                }


labelStyle windowWidth textValue =
    if windowWidth > 650 then
        Input.labelLeft [] (text textValue)

    else
        Input.labelAbove [] (Element.paragraph [] [ text textValue ])


buttonStyle =
    [ spaceEvenly
    , padding 10
    , Border.solid
    , Border.rounded 5
    , Border.width 1
    ]


greenButtonStyle palette =
    buttonStyle ++ [ Background.color palette.accent, Font.color palette.accentText ]


redButtonStyle palette =
    buttonStyle ++ [ Background.color palette.error, Font.color palette.errorText ]


grayButtonStyle palette =
    buttonStyle ++ [ Background.color palette.disabledButton, Font.color palette.text ]


iconButtonStyle palette =
    [ Background.color palette.disabledButton
    , Font.color palette.text
    , Border.color palette.border
    , Border.width 1
    , padding 7
    , Border.rounded 999
    ]


deleteIconButtonStyle palette =
    [ Background.color palette.deleteButton
    , Font.color palette.text
    , Border.color palette.border
    , Border.width 1
    , padding 7
    , Border.rounded 999
    ]


type alias Palette =
    { background : Color
    , surface : Color
    , navbar : Color
    , text : Color
    , inputBackground : Color
    , border : Color
    , accent : Color
    , accentText : Color
    , error : Color
    , errorText : Color
    , editButton : Color
    , deleteButton : Color
    , disabledButton : Color
    }


lightPalette : Palette
lightPalette =
    { background = rgb 1 1 1
    , surface = rgb 0.9 0.9 0.9
    , navbar = rgb 1 1 1
    , text = rgb 0 0 0
    , inputBackground = rgb 1 1 1
    , border = rgb 0.75 0.75 0.75
    , accent = rgb255 152 251 152
    , accentText = rgb 0 0 0
    , error = rgb 1 0.5 0.5
    , errorText = rgb 0 0 0
    , editButton = rgb 0.8 0.8 1.0
    , deleteButton = rgb 1.0 0.8 0.8
    , disabledButton = rgb 0.8 0.8 0.8
    }


darkPalette : Palette
darkPalette =
    { background = rgb 0.13 0.13 0.13
    , surface = rgb 0.22 0.22 0.22
    , navbar = rgb 0.08 0.08 0.08
    , text = rgb 0.9 0.9 0.9
    , inputBackground = rgb 0.2 0.2 0.2
    , border = rgb 0.4 0.4 0.4
    , accent = rgb255 80 160 80
    , accentText = rgb 0.95 0.95 0.95
    , error = rgb 0.75 0.3 0.3
    , errorText = rgb 0.95 0.95 0.95
    , editButton = rgb 0.25 0.25 0.5
    , deleteButton = rgb 0.5 0.25 0.25
    , disabledButton = rgb 0.35 0.35 0.35
    }


getPalette : Theme -> Palette
getPalette theme =
    case theme of
        LightMode ->
            lightPalette

        DarkMode ->
            darkPalette


inputStyle : Palette -> List (Attribute msg)
inputStyle palette =
    [ Background.color palette.inputBackground
    , Font.color palette.text
    , Border.color palette.border
    ]


nameInput palette windowWidth { name, nameInvalid } =
    let
        attributes =
            if nameInvalid then
                inputStyle palette ++ [ Background.color palette.error ]

            else
                inputStyle palette
    in
    [ Input.text attributes
        { label = labelStyle windowWidth "Name"
        , placeholder = Nothing
        , onChange = UpdateName
        , text = name
        }
    ]


addGroupInputs palette windowWidth ({ members } as model) =
    let
        nbMembers =
            List.length members
    in
    nameInput palette windowWidth model
        ++ listInputs
            palette
            windowWidth
            "Owner"
            "Share"
            AddMember
            UpdateMember
            UpdateShare
            members


addSpendingInputs palette windowWidth { description, total, date, dateText, datePickerModel, credits, debits } =
    [ Input.text (inputStyle palette)
        { label = labelStyle windowWidth "Description"
        , placeholder = Nothing
        , onChange = UpdateName
        , text = description
        }
    , DatePicker.input (inputStyle palette)
        { label = labelStyle windowWidth "Date"
        , placeholder = Nothing
        , onChange = UpdateSpendingDate
        , selected = date
        , text = dateText
        , settings = DatePicker.defaultSettings
        , model = datePickerModel
        }
    , Input.text (inputStyle palette)
        { label = labelStyle windowWidth "Total"
        , placeholder = Nothing
        , onChange = UpdateSpendingTotal
        , text = total
        }
    , transactionLineInputs
        palette
        windowWidth
        date
        "Debitors"
        "Debitor"
        AddDebit
        RemoveDebit
        ToggleDebitDetails
        UpdateDebitDate
        UpdateDebitSecondaryDescription
        UpdateDebitGroup
        UpdateDebitAmount
        debits
    , transactionLineInputs
        palette
        windowWidth
        date
        "Creditors (payers)"
        "Creditor"
        AddCredit
        RemoveCredit
        ToggleCreditDetails
        UpdateCreditDate
        UpdateCreditSecondaryDescription
        UpdateCreditGroup
        UpdateCreditAmount
        credits
    ]


transactionLineInputs palette windowWidth spendingDate title lineLabel addMsg removeMsg toggleDetailsMsg updateDateMsg updateSecondaryDescriptionMsg updateGroupMsg updateAmountMsg lines =
    column [ spacing 15, Background.color palette.surface, padding 20, width fill ]
        ([ row [ spacing 10, width fill ]
            [ text title ]
         ]
            ++ (lines
                    |> List.indexedMap
                        (\index line ->
                            let
                                attributes =
                                    case line.nameValidity of
                                        InvalidPrefix ->
                                            inputStyle palette ++ [ Background.color palette.error ]

                                        _ ->
                                            inputStyle palette

                                detailsVisible =
                                    transactionLineDetailsVisible spendingDate line

                                showRemoveButton =
                                    List.length lines > 1 || not (transactionLineIsBlank spendingDate line)
                            in
                            column
                                [ spacing 12
                                , Background.color palette.background
                                , padding 15
                                , width fill
                                , Border.rounded 5
                                ]
                                ([ row [ spacing 10, width fill ]
                                    ([ el [ width fill ] none
                                     , transactionLineDetailsToggle palette spendingDate line (toggleDetailsMsg index)
                                     ]
                                        ++ (if showRemoveButton then
                                                [ Input.button
                                                    (deleteIconButtonStyle palette)
                                                    { label = removeIcon
                                                    , onPress = Just (removeMsg index)
                                                    }
                                                ]

                                            else
                                                []
                                           )
                                    )
                                 , wrappedRow [ spacing 15, width fill ]
                                    [ el [ width (transactionLineFlexibleFieldWidth windowWidth) ]
                                        (Input.text (attributes ++ [ width fill ])
                                            { label = labelStyle windowWidth (lineLabel ++ " " ++ String.fromInt (index + 1))
                                            , placeholder = Nothing
                                            , onChange = updateGroupMsg index
                                            , text = line.group
                                            }
                                        )
                                    , el [ width (transactionLineCompactFieldWidth windowWidth) ]
                                        (Input.text (inputStyle palette ++ [ width fill ])
                                            { label = labelStyle windowWidth "Amount"
                                            , placeholder = Nothing
                                            , onChange = updateAmountMsg index
                                            , text = line.amount
                                            }
                                        )
                                    ]
                                 ]
                                    ++ (if detailsVisible then
                                            [ wrappedRow [ spacing 15, width fill ]
                                                [ el [ width (transactionLineFlexibleFieldWidth windowWidth) ]
                                                    (Input.text (inputStyle palette ++ [ width fill ])
                                                        { label = labelStyle windowWidth "Description"
                                                        , placeholder = Nothing
                                                        , onChange = updateSecondaryDescriptionMsg index
                                                        , text = line.secondaryDescription
                                                        }
                                                    )
                                                , el [ width (transactionLineCompactFieldWidth windowWidth) ]
                                                    (DatePicker.input (inputStyle palette ++ [ width fill ])
                                                        { label = labelStyle windowWidth "Date"
                                                        , placeholder = Nothing
                                                        , onChange = updateDateMsg index
                                                        , selected = line.date
                                                        , text = line.dateText
                                                        , settings = DatePicker.defaultSettings
                                                        , model = line.datePickerModel
                                                        }
                                                    )
                                                ]
                                            ]

                                        else
                                            []
                                       )
                                )
                        )
               )
        )


transactionLineHasCustomDetails spendingDate line =
    String.trim line.secondaryDescription
        /= ""
        || not (lineUsesDefaultDate spendingDate line)


transactionLineFlexibleFieldWidth windowWidth =
    if windowWidth > 650 then
        fill

    else
        fillPortion 1


transactionLineCompactFieldWidth windowWidth =
    if windowWidth > 650 then
        px 150

    else
        fillPortion 1


transactionLineDetailsVisible spendingDate line =
    line.detailsExpanded || transactionLineHasCustomDetails spendingDate line


transactionLineDetailsToggle palette spendingDate line toggleMsg =
    if transactionLineHasCustomDetails spendingDate line then
        el (iconButtonStyle palette) detailsExpandedIcon

    else
        Input.button
            (iconButtonStyle palette)
            { label =
                if line.detailsExpanded then
                    detailsExpandedIcon

                else
                    detailsCollapsedIcon
            , onPress = Just toggleMsg
            }


detailsCollapsedIcon =
    strokedIcon "M7 5l5 5-5 5"


detailsExpandedIcon =
    strokedIcon "M5 7l5 5 5-5"


removeIcon =
    strokedIcon "M6 6l8 8M14 6l-8 8"


strokedIcon pathData =
    html <|
        Html.node "svg"
            [ Attr.attribute "viewBox" "0 0 20 20"
            , Attr.attribute "width" "16"
            , Attr.attribute "height" "16"
            , Attr.attribute "fill" "none"
            , Attr.attribute "stroke" "currentColor"
            , Attr.attribute "stroke-width" "1.75"
            , Attr.attribute "stroke-linecap" "round"
            , Attr.attribute "stroke-linejoin" "round"
            , Attr.style "display" "block"
            ]
            [ Html.node "path" [ Attr.attribute "d" pathData ] [] ]


listInputs palette windowWidth nameLabel valueLabel addMsg updateNameMsg updateValueMsg items =
    let
        listSize =
            List.length items
    in
    (if List.all (\( name, _, _ ) -> String.length name > 0) items then
        [ row [ spacing 20 ]
            [ Input.text (inputStyle palette)
                { label =
                    labelStyle windowWidth
                        (nameLabel
                            ++ " "
                            ++ (listSize + 1 |> String.fromInt)
                        )
                , placeholder = Nothing
                , onChange = addMsg
                , text = ""
                }
            , Input.text (inputStyle palette)
                { label = labelStyle windowWidth valueLabel
                , placeholder = Nothing
                , onChange = \_ -> NoOpFrontendMsg
                , text = ""
                }
            ]
        ]

     else
        []
    )
        ++ List.indexedMap
            (\index ( name, value, nameValidity ) ->
                let
                    attributes =
                        case nameValidity of
                            InvalidPrefix ->
                                inputStyle palette ++ [ Background.color palette.error ]

                            _ ->
                                inputStyle palette
                in
                row [ spacing 20 ]
                    [ Input.text attributes
                        { label =
                            labelStyle windowWidth
                                (nameLabel
                                    ++ " "
                                    ++ (listSize - index |> String.fromInt)
                                )
                        , placeholder = Nothing
                        , onChange = updateNameMsg index
                        , text = name
                        }
                    , Input.text (inputStyle palette)
                        { label = labelStyle windowWidth valueLabel
                        , placeholder = Nothing
                        , onChange = updateValueMsg index
                        , text = value
                        }
                    ]
            )
            items
        |> List.reverse


canSubmitPerson { name, nameInvalid, submitted } =
    not submitted && not nameInvalid && String.length name > 0


canSubmitGroup { name, nameInvalid, members, submitted } =
    not submitted
        && not nameInvalid
        && String.length name
        > 0
        && (members
                |> List.map
                    (\( _, share, nameValidity ) ->
                        case nameValidity of
                            Complete ->
                                String.toInt share

                            _ ->
                                Nothing
                    )
                |> Maybe.combine
                |> Maybe.map (List.sum >> (\sum -> sum > 0))
                |> Maybe.withDefault False
           )


validTransactionLines spendingDate lines =
    let
        meaningfulLines =
            lines
                |> List.filter (transactionLineIsBlank spendingDate >> not)
    in
    not (List.isEmpty meaningfulLines)
        && (meaningfulLines
                |> List.map
                    (\line ->
                        case ( line.date, parseAmountValue line.amount, line.nameValidity ) of
                            ( Just _, Just _, Complete ) ->
                                String.trim line.group /= ""

                            _ ->
                                False
                    )
                |> List.all identity
           )


canSubmitSpending { description, total, date, credits, debits, submitted } =
    not submitted
        && String.length description
        > 0
        && Maybe.isJust date
        && (total
                |> parseAmountValue
                |> Maybe.map
                    (\totalInt ->
                        totalInt
                            > 0
                            && validTransactionLines date credits
                            && validTransactionLines date debits
                    )
                |> Maybe.withDefault False
           )


viewTransaction palette transaction =
    row [ spacing 20, padding 20, Background.color palette.surface, Font.color palette.text ]
        [ String.fromInt transaction.year ++ "-" ++ String.fromInt transaction.month ++ "-" ++ String.fromInt transaction.day |> text
        , transaction.description |> text
        , transaction.share |> (\(Amount amount) -> amount) |> viewAmount |> text
        , "(Total: " ++ (transaction.total |> (\(Amount amount) -> amount) |> viewAmount) ++ ")" |> text
        , row [ spacing 10 ]
            [ Input.button [ Background.color palette.editButton, padding 5, Border.rounded 3 ]
                { onPress =
                    Just
                        (ShowAddSpendingDialog
                            (Just
                                { spendingId = transaction.spendingId
                                , transactionId = transaction.transactionId
                                }
                            )
                        )
                , label = text "Edit"
                }
            , Input.button [ Background.color palette.deleteButton, padding 5, Border.rounded 3 ]
                { onPress = Just (ShowConfirmDeleteDialog transaction.spendingId)
                , label = text "Delete"
                }
            ]
        ]


viewGroups : String -> List ( String, Group, Amount a ) -> Element FrontendMsg
viewGroups user list =
    let
        preprocessedList =
            list
                |> List.map
                    (\( name, shares, Amount totalAmount ) ->
                        let
                            userShare =
                                Dict.get user shares
                                    |> Maybe.map (\(Share share) -> share)
                                    |> Maybe.withDefault 0

                            totalShares =
                                Dict.values shares
                                    |> List.map (\(Share share) -> share)
                                    |> List.sum

                            userAmount =
                                totalAmount * userShare // totalShares
                        in
                        { name = name
                        , share =
                            String.fromInt userShare
                                ++ " out of "
                                ++ String.fromInt totalShares
                        , totalAmount = viewAmount totalAmount
                        , userAmount = userAmount
                        }
                    )

        total =
            preprocessedList
                |> List.map .userAmount
                |> List.sum
                |> (\totalUserAmount ->
                        [ { name = "Total"
                          , share = ""
                          , totalAmount = ""
                          , userAmount = totalUserAmount
                          }
                        ]
                   )
    in
    table [ Border.solid, Border.width 1, padding 20, spacing 30 ]
        { data = preprocessedList ++ total
        , columns =
            [ { header = text "Name"
              , width = fill
              , view = .name >> text
              }
            , { header = text "Your share"
              , width = fill
              , view = .share >> text
              }
            , { header = text "Total spending"
              , width = fill
              , view = .totalAmount >> text
              }
            , { header = text "Your spending"
              , width = fill
              , view = .userAmount >> viewAmount >> text
              }
            ]
        }


viewAmountsDue : List ( String, Amount Debit ) -> Element FrontendMsg
viewAmountsDue data =
    table [ Border.solid, Border.width 1, padding 20, spacing 30 ]
        { data = data
        , columns =
            [ { header = text "Name"
              , width = fill
              , view = first >> text
              }
            , { header = text "Due"
              , width = fill
              , view =
                    second
                        >> (\(Amount value) -> max 0 value)
                        >> viewAmount
                        >> text
              }
            , { header = text "Owed"
              , width = fill
              , view =
                    second
                        >> (\(Amount value) -> min 0 value)
                        >> negate
                        >> viewAmount
                        >> text
              }
            ]
        }


viewAmount amount =
    let
        sign =
            if amount < 0 then
                "-"

            else
                ""

        absAmount =
            abs amount
    in
    remainderBy 100 absAmount
        |> String.fromInt
        |> String.padLeft 2 '0'
        |> (++) "."
        |> (++) (absAmount // 100 |> String.fromInt)
        |> (++) sign


{-| Convert amount from cents (Int) to dollar string with decimal point
-}
formatAmountValue : Int -> String
formatAmountValue cents =
    let
        absolute =
            abs cents

        beforeComma =
            absolute // 100

        afterComma =
            modBy 100 absolute

        afterCommaString =
            if afterComma < 10 then
                "0" ++ String.fromInt afterComma

            else
                String.fromInt afterComma

        sign =
            if cents < 0 then
                "-"

            else
                ""
    in
    sign ++ String.fromInt beforeComma ++ "." ++ afterCommaString


parseAmountValue : String -> Maybe Int
parseAmountValue amount =
    case
        Regex.fromString "^(\\-?)([0-9]*)[.,]?([0-9]*)$"
            |> Maybe.withDefault Regex.never
            |> flip Regex.find amount
            |> List.map .submatches
    of
        [ [ Nothing, Just integer, Nothing ] ] ->
            String.toInt integer
                |> Maybe.map ((*) 100)

        [ [ Just "-", Just integer, Nothing ] ] ->
            String.toInt integer
                |> Maybe.map ((*) -100)

        [ [ Nothing, Nothing, Just decimal ] ] ->
            case String.length decimal of
                1 ->
                    String.toInt decimal
                        |> Maybe.map ((*) 10)

                2 ->
                    String.toInt decimal

                _ ->
                    Nothing

        [ [ Just "-", Nothing, Just decimal ] ] ->
            case String.length decimal of
                1 ->
                    String.toInt decimal
                        |> Maybe.map ((*) -10)

                2 ->
                    String.toInt decimal
                        |> Maybe.map negate

                _ ->
                    Nothing

        [ [ Nothing, Just integer, Just decimal ] ] ->
            case String.length decimal of
                1 ->
                    String.toInt integer
                        |> Maybe.map ((*) 100)
                        |> Maybe.andThen
                            (\integerValue ->
                                String.toInt decimal
                                    |> Maybe.map ((*) 10)
                                    |> Maybe.map ((+) integerValue)
                            )

                2 ->
                    String.toInt integer
                        |> Maybe.map ((*) 100)
                        |> Maybe.andThen
                            (\integerValue ->
                                String.toInt decimal
                                    |> Maybe.map ((+) integerValue)
                            )

                _ ->
                    Nothing

        [ [ Just "-", Just integer, Just decimal ] ] ->
            case String.length decimal of
                1 ->
                    String.toInt integer
                        |> Maybe.map ((*) 100)
                        |> Maybe.andThen
                            (\integerValue ->
                                String.toInt decimal
                                    |> Maybe.map ((*) 10)
                                    |> Maybe.map ((+) integerValue)
                            )
                        |> Maybe.map negate

                2 ->
                    String.toInt integer
                        |> Maybe.map ((*) 100)
                        |> Maybe.andThen
                            (\integerValue ->
                                String.toInt decimal
                                    |> Maybe.map ((+) integerValue)
                            )
                        |> Maybe.map negate

                _ ->
                    Nothing

        _ ->
            Nothing


personalAmounts : List ( String, Group, Amount a ) -> Dict String (Amount a)
personalAmounts list =
    list
        |> List.map
            (\( _, shares, Amount totalAmount ) ->
                let
                    totalShares =
                        Dict.values shares
                            |> List.map (\(Share share) -> share)
                            |> List.sum
                in
                Dict.map
                    (\_ (Share share) ->
                        Amount (totalAmount * share // totalShares)
                    )
                    shares
            )
        |> List.foldl addAmounts Dict.empty


personalAmountsDue : List ( String, Group, Amount Debit ) -> List ( String, Group, Amount Credit ) -> Dict String (Amount Debit)
personalAmountsDue debitorGroups creditorGroups =
    let
        debits =
            personalAmounts debitorGroups

        credits =
            personalAmounts creditorGroups
                |> Dict.map (\_ (Amount amount) -> Amount -amount)
    in
    addAmounts debits credits
