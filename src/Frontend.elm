module Frontend exposing (..)

import Basics.Extra exposing (flip)
import Browser exposing (UrlRequest(..))
import Browser.Navigation as Nav
import Date
import DatePicker
import Dialog
import Dict
import Dict.Extra as Dict
import Element exposing (..)
import Element.Background as Background
import Element.Border as Border
import Element.Input as Input
import Html
import Html.Attributes as Attr
import Html.Events exposing (..)
import Lamdera
import List.Extra as List
import Maybe.Extra as Maybe
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
        , subscriptions = \m -> Sub.none
        , view = view
        }


init : Url.Url -> Nav.Key -> ( Model, Cmd FrontendMsg )
init url key =
    ( { showDialog = Nothing
      , showSpendingFor = ""
      , nameValidity = Incomplete
      , spendings = Nothing
      , key = key
      }
    , Cmd.none
    )


update : FrontendMsg -> Model -> ( Model, Cmd FrontendMsg )
update msg model =
    case msg of
        UrlClicked urlRequest ->
            case urlRequest of
                Internal url ->
                    ( model
                    , Nav.pushUrl model.key (Url.toString url)
                    )

                External url ->
                    ( model
                    , Nav.load url
                    )

        UrlChanged url ->
            ( model, Cmd.none )

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

        ShowAddAccountDialog ->
            ( { model
                | showDialog =
                    Just
                        (AddAccountOrGroupDialog
                            { name = ""
                            , nameInvalid = False
                            , ownersOrMembers = []
                            , submitted = False
                            , account = True
                            }
                        )
              }
            , Cmd.none
            )

        ShowAddGroupDialog ->
            ( { model
                | showDialog =
                    Just
                        (AddAccountOrGroupDialog
                            { name = ""
                            , nameInvalid = False
                            , ownersOrMembers = []
                            , submitted = False
                            , account = False
                            }
                        )
              }
            , Cmd.none
            )

        ShowAddSpendingDialog ->
            ( { model
                | showDialog =
                    Just
                        (AddSpendingDialog
                            { description = ""
                            , date = Nothing
                            , dateText = ""
                            , datePickerModel = DatePicker.init
                            , totalSpending = ""
                            , groupSpendings = []
                            , transactions = []
                            , submitted = False
                            }
                        )
              }
            , Task.perform SetToday Date.today
            )

        SetToday today ->
            case model.showDialog of
                Just (AddSpendingDialog dialogModel) ->
                    ( { model
                        | showDialog =
                            Just
                                (AddSpendingDialog
                                    { dialogModel
                                        | datePickerModel = DatePicker.setToday today dialogModel.datePickerModel
                                    }
                                )
                      }
                    , Cmd.none
                    )

                _ ->
                    ( model, Cmd.none )

        Submit ->
            case model.showDialog of
                Just (AddPersonDialog dialogModel) ->
                    ( { model | showDialog = Just (AddPersonDialog { dialogModel | submitted = True }) }
                    , Lamdera.sendToBackend (AddPerson dialogModel.name)
                    )

                Just (AddAccountOrGroupDialog dialogModel) ->
                    let
                        ownersOrMembers =
                            dialogModel.ownersOrMembers
                                |> List.map
                                    (\( ownerOrMember, share, _ ) ->
                                        ( ownerOrMember
                                        , share
                                            |> String.toInt
                                            |> Maybe.withDefault 0
                                        )
                                    )
                                |> Dict.fromListDedupe (+)
                                |> Dict.map (\_ -> Share)
                    in
                    ( { model | showDialog = Just (AddAccountOrGroupDialog { dialogModel | submitted = True }) }
                    , if dialogModel.account then
                        Lamdera.sendToBackend (AddAccount dialogModel.name ownersOrMembers)

                      else
                        Lamdera.sendToBackend (AddGroup dialogModel.name ownersOrMembers)
                    )

                Just (AddSpendingDialog dialogModel) ->
                    let
                        groupSpendings =
                            dialogModel.groupSpendings
                                |> List.map
                                    (\( group, amount, _ ) ->
                                        ( group
                                        , amount
                                            |> String.toInt
                                            |> Maybe.withDefault 0
                                        )
                                    )
                                |> Dict.fromListDedupe (+)
                                |> Dict.map (\_ -> Amount)

                        transactions =
                            dialogModel.transactions
                                |> List.map
                                    (\( account, amount, _ ) ->
                                        ( account
                                        , amount
                                            |> String.toInt
                                            |> Maybe.withDefault 0
                                        )
                                    )
                                |> Dict.fromListDedupe (+)
                                |> Dict.map (\_ -> Amount)
                    in
                    case
                        ( dialogModel.date
                        , String.toInt dialogModel.totalSpending
                        )
                    of
                        ( Just date, Just totalSpending ) ->
                            ( { model
                                | showDialog =
                                    Just
                                        (AddSpendingDialog
                                            { dialogModel | submitted = True }
                                        )
                              }
                            , Lamdera.sendToBackend
                                (AddSpending
                                    { description = dialogModel.description
                                    , year = Date.year date
                                    , month = Date.monthNumber date
                                    , day = Date.day date
                                    , totalSpending = Amount totalSpending
                                    , groupSpendings = groupSpendings
                                    , transactions = transactions
                                    }
                                )
                            )

                        _ ->
                            ( model, Cmd.none )

                Nothing ->
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

                Just (AddAccountOrGroupDialog dialogModel) ->
                    if name == "" then
                        ( { model | showDialog = Just (AddAccountOrGroupDialog { dialogModel | name = "", nameInvalid = True }) }
                        , Cmd.none
                        )

                    else
                        ( { model | showDialog = Just (AddAccountOrGroupDialog { dialogModel | name = name, nameInvalid = False }) }
                        , Lamdera.sendToBackend (CheckValidName name)
                        )

                Just (AddSpendingDialog dialogModel) ->
                    ( { model | showDialog = Just (AddSpendingDialog { dialogModel | description = name }) }
                    , Cmd.none
                    )

                Nothing ->
                    ( { model | showSpendingFor = name, nameValidity = Incomplete }
                    , Lamdera.sendToBackend (AutocompletePerson name)
                    )

        AddOwnerOrMemberName ownerOrMember ->
            case model.showDialog of
                Just (AddAccountOrGroupDialog dialogModel) ->
                    ( { model
                        | showDialog =
                            Just
                                (AddAccountOrGroupDialog
                                    { dialogModel
                                        | ownersOrMembers =
                                            dialogModel.ownersOrMembers
                                                |> addNameInList ownerOrMember "1"
                                    }
                                )
                      }
                    , Lamdera.sendToBackend (AutocompletePerson ownerOrMember)
                    )

                _ ->
                    ( model, Cmd.none )

        UpdateOwnerOrMemberName index ownerOrMember ->
            case model.showDialog of
                Just (AddAccountOrGroupDialog dialogModel) ->
                    ( { model
                        | showDialog =
                            Just
                                (AddAccountOrGroupDialog
                                    { dialogModel
                                        | ownersOrMembers =
                                            dialogModel.ownersOrMembers
                                                |> updateNameInList
                                                    index
                                                    ownerOrMember
                                                    (\_ -> "1")
                                    }
                                )
                      }
                    , if String.length ownerOrMember > 0 then
                        Lamdera.sendToBackend (AutocompletePerson ownerOrMember)

                      else
                        Cmd.none
                    )

                _ ->
                    ( model, Cmd.none )

        UpdateOwnerOrMemberShare index share ->
            case model.showDialog of
                Just (AddAccountOrGroupDialog dialogModel) ->
                    ( { model
                        | showDialog =
                            Just
                                (AddAccountOrGroupDialog
                                    { dialogModel
                                        | ownersOrMembers =
                                            dialogModel.ownersOrMembers
                                                |> updateValueInList index share
                                    }
                                )
                      }
                    , Cmd.none
                    )

                _ ->
                    ( model, Cmd.none )

        UpdateTotalSpending totalSpending ->
            case model.showDialog of
                Just (AddSpendingDialog dialogModel) ->
                    ( { model | showDialog = Just (AddSpendingDialog { dialogModel | totalSpending = totalSpending }) }
                    , Cmd.none
                    )

                _ ->
                    ( model, Cmd.none )

        ChangeDatePicker changeEvent ->
            case model.showDialog of
                Just (AddSpendingDialog dialogModel) ->
                    ( { model
                        | showDialog =
                            Just
                                (AddSpendingDialog
                                    (case changeEvent of
                                        DatePicker.DateChanged date ->
                                            { dialogModel | date = Just date, dateText = Date.toIsoString date }

                                        DatePicker.TextChanged dateText ->
                                            { dialogModel
                                                | date =
                                                    Date.fromIsoString dateText
                                                        |> Result.toMaybe
                                                , dateText = dateText
                                            }

                                        DatePicker.PickerChanged subMsg ->
                                            { dialogModel | datePickerModel = DatePicker.update subMsg dialogModel.datePickerModel }
                                    )
                                )
                      }
                    , Cmd.none
                    )

                _ ->
                    ( model, Cmd.none )

        AddGroupName group ->
            case model.showDialog of
                Just (AddSpendingDialog dialogModel) ->
                    ( { model
                        | showDialog =
                            Just
                                (AddSpendingDialog
                                    { dialogModel
                                        | groupSpendings =
                                            dialogModel.groupSpendings
                                                |> addAccountOrGroup dialogModel group
                                    }
                                )
                      }
                    , Lamdera.sendToBackend (AutocompleteGroup group)
                    )

                _ ->
                    ( model, Cmd.none )

        UpdateGroupName index group ->
            case model.showDialog of
                Just (AddSpendingDialog dialogModel) ->
                    ( { model
                        | showDialog =
                            Just
                                (AddSpendingDialog
                                    { dialogModel
                                        | groupSpendings =
                                            dialogModel.groupSpendings
                                                |> updateNameInList
                                                    index
                                                    group
                                                    (computeRemainder dialogModel)
                                    }
                                )
                      }
                    , if String.length group > 0 then
                        Lamdera.sendToBackend (AutocompleteGroup group)

                      else
                        Cmd.none
                    )

                _ ->
                    ( model, Cmd.none )

        UpdateGroupAmount index amount ->
            case model.showDialog of
                Just (AddSpendingDialog dialogModel) ->
                    ( { model
                        | showDialog =
                            Just
                                (AddSpendingDialog
                                    { dialogModel
                                        | groupSpendings =
                                            dialogModel.groupSpendings
                                                |> updateValueInList index amount
                                    }
                                )
                      }
                    , Cmd.none
                    )

                _ ->
                    ( model, Cmd.none )

        AddAccountName account ->
            case model.showDialog of
                Just (AddSpendingDialog dialogModel) ->
                    ( { model
                        | showDialog =
                            Just
                                (AddSpendingDialog
                                    { dialogModel
                                        | transactions =
                                            dialogModel.transactions
                                                |> addAccountOrGroup dialogModel account
                                    }
                                )
                      }
                    , Lamdera.sendToBackend (AutocompleteAccount account)
                    )

                _ ->
                    ( model, Cmd.none )

        UpdateAccountName index account ->
            case model.showDialog of
                Just (AddSpendingDialog dialogModel) ->
                    ( { model
                        | showDialog =
                            Just
                                (AddSpendingDialog
                                    { dialogModel
                                        | transactions =
                                            dialogModel.transactions
                                                |> updateNameInList
                                                    index
                                                    account
                                                    (computeRemainder dialogModel)
                                    }
                                )
                      }
                    , if String.length account > 0 then
                        Lamdera.sendToBackend (AutocompleteAccount account)

                      else
                        Cmd.none
                    )

                _ ->
                    ( model, Cmd.none )

        UpdateAccountAmount index amount ->
            case model.showDialog of
                Just (AddSpendingDialog dialogModel) ->
                    ( { model
                        | showDialog =
                            Just
                                (AddSpendingDialog
                                    { dialogModel
                                        | transactions =
                                            dialogModel.transactions
                                                |> updateValueInList index amount
                                    }
                                )
                      }
                    , Cmd.none
                    )

                _ ->
                    ( model, Cmd.none )


computeRemainder { totalSpending } list =
    ((totalSpending
        |> String.toInt
        |> Maybe.withDefault 0
     )
        - (list
            |> List.filterMap (\( _, amount, _ ) -> amount |> String.toInt)
            |> List.sum
          )
    )
        |> String.fromInt


addAccountOrGroup model name list =
    addNameInList name (computeRemainder model list) list


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
            ( { model | showDialog = Nothing }
            , Cmd.none
            )

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

                Just (AddAccountOrGroupDialog dialogModel) ->
                    if dialogModel.name == name then
                        -- we reset submitted to False because this can be
                        -- an error message we get from the backend in case
                        -- of a race creating this group or account
                        ( { model
                            | showDialog =
                                Just
                                    (AddAccountOrGroupDialog
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
                Just (AddAccountOrGroupDialog dialogModel) ->
                    ( { model
                        | showDialog =
                            Just
                                (AddAccountOrGroupDialog
                                    { dialogModel
                                        | ownersOrMembers =
                                            dialogModel.ownersOrMembers
                                                |> List.map
                                                    (\( ownerOrMember, share, nameValidity ) ->
                                                        if String.startsWith prefix ownerOrMember then
                                                            ( ownerOrMember, share, InvalidPrefix )

                                                        else
                                                            ( ownerOrMember, share, nameValidity )
                                                    )
                                    }
                                )
                      }
                    , Cmd.none
                    )

                Nothing ->
                    ( if String.startsWith prefix model.showSpendingFor then
                        { model | nameValidity = InvalidPrefix }

                      else
                        model
                    , Cmd.none
                    )

                _ ->
                    ( model, Cmd.none )

        UniquePersonPrefix { prefix, name } ->
            case model.showDialog of
                Just (AddAccountOrGroupDialog dialogModel) ->
                    ( { model
                        | showDialog =
                            Just
                                (AddAccountOrGroupDialog
                                    { dialogModel
                                        | ownersOrMembers =
                                            dialogModel.ownersOrMembers
                                                |> List.map
                                                    (\( ownerOrMember, share, nameValidity ) ->
                                                        if String.startsWith prefix ownerOrMember then
                                                            ( name, share, Complete )

                                                        else
                                                            ( ownerOrMember, share, nameValidity )
                                                    )
                                    }
                                )
                      }
                    , Cmd.none
                    )

                Nothing ->
                    if String.startsWith prefix model.showSpendingFor then
                        ( { model | showSpendingFor = name, nameValidity = Complete }
                        , Cmd.none
                          -- TODO: request spendings for name
                        )

                    else
                        ( model, Cmd.none )

                _ ->
                    ( model, Cmd.none )

        CompleteNotUniquePerson name ->
            case model.showDialog of
                Just (AddAccountOrGroupDialog dialogModel) ->
                    ( { model
                        | showDialog =
                            Just
                                (AddAccountOrGroupDialog
                                    { dialogModel
                                        | ownersOrMembers =
                                            dialogModel.ownersOrMembers
                                                |> List.map
                                                    (\( ownerOrMember, share, nameValidity ) ->
                                                        if ownerOrMember == name then
                                                            ( ownerOrMember, share, Complete )

                                                        else
                                                            ( ownerOrMember, share, nameValidity )
                                                    )
                                    }
                                )
                      }
                    , Cmd.none
                    )

                Nothing ->
                    if model.showSpendingFor == name then
                        ( { model | nameValidity = Complete }
                        , Cmd.none
                          -- TODO: request spendings for name
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
                                        | groupSpendings =
                                            dialogModel.groupSpendings
                                                |> List.map
                                                    (\( group, amount, nameValidity ) ->
                                                        if String.startsWith prefix group then
                                                            ( group, amount, InvalidPrefix )

                                                        else
                                                            ( group, amount, nameValidity )
                                                    )
                                    }
                                )
                      }
                    , Cmd.none
                    )

                _ ->
                    ( model, Cmd.none )

        UniqueGroupPrefix { prefix, name } ->
            case model.showDialog of
                Just (AddSpendingDialog dialogModel) ->
                    ( { model
                        | showDialog =
                            Just
                                (AddSpendingDialog
                                    { dialogModel
                                        | groupSpendings =
                                            dialogModel.groupSpendings
                                                |> List.map
                                                    (\( group, amount, nameValidity ) ->
                                                        if String.startsWith prefix group then
                                                            ( name, amount, Complete )

                                                        else
                                                            ( group, amount, nameValidity )
                                                    )
                                    }
                                )
                      }
                    , Cmd.none
                    )

                _ ->
                    ( model, Cmd.none )

        CompleteNotUniqueGroup name ->
            case model.showDialog of
                Just (AddSpendingDialog dialogModel) ->
                    ( { model
                        | showDialog =
                            Just
                                (AddSpendingDialog
                                    { dialogModel
                                        | groupSpendings =
                                            dialogModel.groupSpendings
                                                |> List.map
                                                    (\( group, amount, nameValidity ) ->
                                                        if group == name then
                                                            ( group, amount, Complete )

                                                        else
                                                            ( group, amount, nameValidity )
                                                    )
                                    }
                                )
                      }
                    , Cmd.none
                    )

                _ ->
                    ( model, Cmd.none )

        InvalidAccountPrefix prefix ->
            case model.showDialog of
                Just (AddSpendingDialog dialogModel) ->
                    ( { model
                        | showDialog =
                            Just
                                (AddSpendingDialog
                                    { dialogModel
                                        | transactions =
                                            dialogModel.transactions
                                                |> List.map
                                                    (\( account, amount, nameValidity ) ->
                                                        if String.startsWith prefix account then
                                                            ( account, amount, InvalidPrefix )

                                                        else
                                                            ( account, amount, nameValidity )
                                                    )
                                    }
                                )
                      }
                    , Cmd.none
                    )

                _ ->
                    ( model, Cmd.none )

        UniqueAccountPrefix { prefix, name } ->
            case model.showDialog of
                Just (AddSpendingDialog dialogModel) ->
                    ( { model
                        | showDialog =
                            Just
                                (AddSpendingDialog
                                    { dialogModel
                                        | transactions =
                                            dialogModel.transactions
                                                |> List.map
                                                    (\( account, amount, nameValidity ) ->
                                                        if String.startsWith prefix account then
                                                            ( name, amount, Complete )

                                                        else
                                                            ( account, amount, nameValidity )
                                                    )
                                    }
                                )
                      }
                    , Cmd.none
                    )

                _ ->
                    ( model, Cmd.none )

        CompleteNotUniqueAccount name ->
            case model.showDialog of
                Just (AddSpendingDialog dialogModel) ->
                    ( { model
                        | showDialog =
                            Just
                                (AddSpendingDialog
                                    { dialogModel
                                        | transactions =
                                            dialogModel.transactions
                                                |> List.map
                                                    (\( account, amount, nameValidity ) ->
                                                        if account == name then
                                                            ( account, amount, Complete )

                                                        else
                                                            ( account, amount, nameValidity )
                                                    )
                                    }
                                )
                      }
                    , Cmd.none
                    )

                _ ->
                    ( model, Cmd.none )


view : Model -> Browser.Document FrontendMsg
view model =
    let
        config title inputs canSubmit =
            { closeMessage = Just Cancel
            , maskAttributes = []
            , containerAttributes =
                [ Background.color (rgb 1 1 1)
                , Border.solid
                , Border.rounded 5
                , Border.width 1
                , centerX
                , centerY
                ]
            , headerAttributes =
                [ padding 20
                , Background.color green
                ]
            , bodyAttributes = [ padding 20 ]
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
                        [ Input.button redButtonStyle
                            { label = text "Cancel"
                            , onPress = Just Cancel
                            }
                        , Input.button
                            (if canSubmit then
                                greenButtonStyle

                             else
                                grayButtonStyle
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
                                    (nameInput dialogModel)
                                    (canSubmitPerson dialogModel)

                            AddAccountOrGroupDialog dialogModel ->
                                let
                                    label =
                                        if dialogModel.account then
                                            "Add Account"

                                        else
                                            "Add Group"
                                in
                                config label
                                    (addAccountOrGroupInputs dialogModel)
                                    (canSubmitAccountOrGroup dialogModel)

                            AddSpendingDialog dialogModel ->
                                config "Add Spending"
                                    (addSpendingInputs dialogModel)
                                    (canSubmitSpending dialogModel)
                    )

        showSpendingForAttributes =
            case model.nameValidity of
                InvalidPrefix ->
                    [ Background.color red ]

                _ ->
                    []
    in
    { title = "Accounting"
    , body =
        -- Elm UI body
        [ layout
            [ inFront (Dialog.view dialogConfig)
            ]
            (column [ width fill ]
                [ row [ centerX, spacing 70, padding 20 ]
                    [ Input.button greenButtonStyle
                        { label = text "Add Person"
                        , onPress = Just ShowAddPersonDialog
                        }
                    , Input.button greenButtonStyle
                        { label = text "Add Account"
                        , onPress = Just ShowAddAccountDialog
                        }
                    , Input.button greenButtonStyle
                        { label = text "Add Group"
                        , onPress = Just ShowAddGroupDialog
                        }
                    , Input.button greenButtonStyle
                        { label = text "Add Spending"
                        , onPress = Just ShowAddSpendingDialog
                        }
                    ]
                , Input.text showSpendingForAttributes
                    { label = Input.labelLeft [] (text "Show spending for")
                    , placeholder = Nothing
                    , onChange = UpdateName
                    , text = model.showSpendingFor
                    }
                ]
            )
        ]
    }


buttonStyle =
    [ spaceEvenly
    , padding 10
    , Border.solid
    , Border.rounded 5
    , Border.width 1
    ]


greenButtonStyle =
    buttonStyle ++ [ Background.color green ]


green =
    rgb255 152 251 152


redButtonStyle =
    buttonStyle ++ [ Background.color red ]


red =
    rgb 1 0.5 0.5


grayButtonStyle =
    buttonStyle ++ [ Background.color (rgb 0.8 0.8 0.8) ]


nameInput { name, nameInvalid } =
    let
        attributes =
            if nameInvalid then
                [ Background.color red ]

            else
                []
    in
    [ Input.text attributes
        { label = Input.labelLeft [] (text "Name")
        , placeholder = Nothing
        , onChange = UpdateName
        , text = name
        }
    ]


addAccountOrGroupInputs ({ ownersOrMembers, account } as model) =
    let
        label =
            if account then
                "Owner"

            else
                "Member"

        nbOwnersOrMembers =
            List.length ownersOrMembers
    in
    nameInput model
        ++ listInputs
            label
            "Share"
            AddOwnerOrMemberName
            UpdateOwnerOrMemberName
            UpdateOwnerOrMemberShare
            ownersOrMembers


addSpendingInputs { description, date, dateText, datePickerModel, totalSpending, groupSpendings, transactions } =
    [ Input.text []
        { label = Input.labelLeft [] (text "Description")
        , placeholder = Nothing
        , onChange = UpdateName
        , text = description
        }
    , DatePicker.input []
        { label = Input.labelLeft [] (text "Date")
        , placeholder = Nothing
        , onChange = ChangeDatePicker
        , selected = date
        , text = dateText
        , settings = DatePicker.defaultSettings
        , model = datePickerModel
        }
    , Input.text []
        { label = Input.labelLeft [] (text "Total Spending")
        , placeholder = Nothing
        , onChange = UpdateTotalSpending
        , text = totalSpending
        }
    , column [ spacing 20, Background.color (rgb 0.9 0.9 0.9), padding 20 ]
        ([ text "Group Spendings" ]
            ++ listInputs
                "Group"
                "Amount"
                AddGroupName
                UpdateGroupName
                UpdateGroupAmount
                groupSpendings
        )
    , column [ spacing 20, Background.color (rgb 0.9 0.9 0.9), padding 20 ]
        ([ text "Transactions" ]
            ++ listInputs
                "Account"
                "Amount"
                AddAccountName
                UpdateAccountName
                UpdateAccountAmount
                transactions
        )
    ]


listInputs nameLabel valueLabel addMsg updateNameMsg updateValueMsg items =
    let
        listSize =
            List.length items
    in
    (if List.all (\( name, _, _ ) -> String.length name > 0) items then
        [ row [ spacing 20 ]
            [ Input.text []
                { label =
                    Input.labelLeft []
                        (nameLabel
                            ++ " "
                            ++ (listSize + 1 |> String.fromInt)
                            |> text
                        )
                , placeholder = Nothing
                , onChange = addMsg
                , text = ""
                }
            , Input.text []
                { label = Input.labelLeft [] (text valueLabel)
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
                                [ Background.color red ]

                            _ ->
                                []
                in
                row [ spacing 20 ]
                    [ Input.text attributes
                        { label =
                            Input.labelLeft []
                                (nameLabel
                                    ++ " "
                                    ++ (listSize - index |> String.fromInt)
                                    |> text
                                )
                        , placeholder = Nothing
                        , onChange = updateNameMsg index
                        , text = name
                        }
                    , Input.text []
                        { label = Input.labelLeft [] (text valueLabel)
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


canSubmitAccountOrGroup { name, nameInvalid, ownersOrMembers, submitted } =
    not submitted
        && not nameInvalid
        && String.length name
        > 0
        && (ownersOrMembers
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


canSubmitSpending { description, date, totalSpending, groupSpendings, transactions, submitted } =
    not submitted
        && Maybe.isJust date
        && String.length description
        > 0
        && (totalSpending
                |> String.toInt
                |> Maybe.andThen
                    (\totalSpendingInt ->
                        Maybe.combine
                            [ groupSpendings
                                |> List.map
                                    (\( _, amount, nameValidity ) ->
                                        case nameValidity of
                                            Complete ->
                                                String.toInt amount

                                            _ ->
                                                Nothing
                                    )
                                |> Maybe.combine
                                |> Maybe.map List.sum
                                |> Maybe.map ((==) totalSpendingInt)
                            , transactions
                                |> List.map
                                    (\( _, amount, nameValidity ) ->
                                        case nameValidity of
                                            Complete ->
                                                String.toInt amount

                                            _ ->
                                                Nothing
                                    )
                                |> Maybe.combine
                                |> Maybe.map List.sum
                                |> Maybe.map ((==) totalSpendingInt)
                            ]
                    )
                |> Maybe.map (List.all identity)
                |> Maybe.withDefault False
           )
